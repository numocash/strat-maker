// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Factory} from "./Factory.sol";
import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {addDelta, calcAmountsForLiquidity} from "./LiquidityMath.sol";
import {Positions} from "./Positions.sol";
import {computeSwapStep} from "./SwapMath.sol";
import {Ticks} from "./Ticks.sol";
import {TickMaps} from "./TickMaps.sol";
import {getCurrentTickForTierFromOffset, getRatioAtTick, MAX_TICK, MIN_TICK, Q128} from "./TickMath.sol";

import {BalanceLib} from "src/libraries/BalaneLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IAddLiquidityCallback} from "./interfaces/IAddLiquidityCallback.sol";
import {ISwapCallback} from "./interfaces/ISwapCallback.sol";

/// @author Robert Leifke and Kyle Scott
contract Pair {
    using Ticks for Ticks.Tick;
    using TickMaps for TickMaps.TickMap;
    using Positions for Positions.Position;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidTick();

    error InvalidTier();

    error InsufficientInput();

    error OutOfBounds();

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    address public immutable factory;

    address public immutable token0;

    address public immutable token1;

    uint8 private constant MAX_TIERS = 5;
    int8 private constant MAX_OFFSET = int8(MAX_TIERS) - 1;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint128[MAX_TIERS] public compositions;
    int24 public tickCurrent;
    int8 public offset;
    bool private initialized;

    mapping(int24 => Ticks.Tick) public ticks;
    mapping(bytes32 positionID => Positions.Position) public positions;
    TickMaps.TickMap public tickMap0To1;
    TickMaps.TickMap public tickMap1To0;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        factory = msg.sender;
        (token0, token1) = Factory(msg.sender).parameters();
    }

    modifier onlyUninitialized() {
        require(!initialized, "Contract is already initialized");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                  LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @custom:team Decision between always having initial tick as an extra step in the linked-lists or requiring
    /// depositing liquidity on initialization
    function initialize(int24 initialTick) external onlyUninitialized {
        tickCurrent = initialTick;
        initialized = true;

        tickMap0To1.set(MIN_TICK);
        tickMap1To0.set(MIN_TICK);
        tickMap0To1.set(-initialTick);
        tickMap1To0.set(initialTick);
        ticks[MAX_TICK].next0To1 = initialTick;
        ticks[MIN_TICK].next1To0 = initialTick;
        ticks[initialTick].next0To1 = MIN_TICK;
        ticks[initialTick].next1To0 = MAX_TICK;
        ticks[initialTick].reference0To1 = 1;
        ticks[initialTick].reference1To0 = 1;
    }

    function addLiquidity(
        address to,
        uint8 tierID,
        int24 tick,
        uint256 liquidity,
        bytes calldata data
    )
        external
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = updateLiquidity(to, tierID, tick, int256(liquidity));

        uint256 balance0 = BalanceLib.getBalance(token0);
        uint256 balance1 = BalanceLib.getBalance(token1);
        IAddLiquidityCallback(msg.sender).addLiquidityCallback(amount0, amount1, data);
        if (BalanceLib.getBalance(token0) < balance0 + amount0) revert InsufficientInput();
        if (BalanceLib.getBalance(token1) < balance1 + amount1) revert InsufficientInput();

        // emit
    }

    function removeLiquidity(
        address to,
        uint8 tierID,
        int24 tick,
        uint256 liquidity
    )
        external
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = updateLiquidity(to, tierID, tick, -int256(liquidity));

        SafeTransferLib.safeTransfer(token0, to, amount0);
        SafeTransferLib.safeTransfer(token1, to, amount1);

        // emit
    }

    /// @notice Struct to hold temporary data while completing a swap
    struct SwapState {
        uint256 liquidity;
        uint128 composition;
        int24 tickCurrent;
        int8 offset;
        int256 amountDesired;
        // pool's balance change of the token which "amountDesired" refers to
        int256 amountA;
        // pool's balance change of the opposite token
        int256 amountB;
    }

    /// @notice Swap between the two tokens in the pair
    /// @param to Recipient of the output of the swap
    /// @param isToken0 True if amountDesired refers to token0
    /// @param amountDesired The desired amount change on the pool
    /// @param data Extra data passed back to the caller
    /// @return amount0 The delta of the balance of token0 of the pool
    /// @return amount1 The delta of the balance of token1 of the pool
    function swap(
        address to,
        bool isToken0,
        int256 amountDesired,
        bytes calldata data
    )
        external
        returns (int256 amount0, int256 amount1)
    {
        bool isExactIn = amountDesired > 0;
        bool isSwap0To1 = isToken0 == isExactIn;

        SwapState memory state;
        {
            int24 _tickCurrent = tickCurrent;
            int8 _offset = isSwap0To1 == (offset > 0) ? offset : int8(0);
            uint256 liquidity = 0;

            for (int8 i = 0; i <= (_offset >= 0 ? _offset : -_offset); i++) {
                liquidity += ticks[isSwap0To1 ? _tickCurrent + i : _tickCurrent - i].getLiquidity(uint8(i));
            }

            // TODO: could we cache liquidity
            state = SwapState({
                liquidity: liquidity,
                composition: compositions[0],
                tickCurrent: _tickCurrent,
                offset: _offset,
                amountDesired: amountDesired,
                amountA: 0,
                amountB: 0
            });
        }

        while (true) {
            uint256 ratioX128 = getRatioAtTick(state.tickCurrent);

            (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) =
                computeSwapStep(ratioX128, state.composition, state.liquidity, isToken0, state.amountDesired);

            if (isExactIn) {
                state.amountDesired = state.amountDesired - int256(amountIn);
                state.amountA = state.amountA + int256(amountIn);
                state.amountB = state.amountB - int256(amountOut);
            } else {
                state.amountDesired = state.amountDesired + int256(amountOut);
                state.amountA = state.amountA - int256(amountOut);
                state.amountB = state.amountB + int256(amountIn);
            }

            if (state.amountDesired == 0) {
                if (isSwap0To1) {
                    state.composition = uint128(mulDiv(amountRemaining, Q128, state.liquidity));
                } else {
                    // solhint-disable-next-line max-line-length
                    state.composition = type(uint128).max - uint128(mulDiv(amountRemaining, ratioX128, state.liquidity));
                }
                break;
            }

            if (isSwap0To1) {
                int24 tickPrev = state.tickCurrent;
                if (tickPrev == MIN_TICK) revert OutOfBounds();
                state.tickCurrent = ticks[tickPrev].next0To1;

                state.liquidity = 0;
                if (state.offset < MAX_OFFSET) {
                    int24 jump = tickPrev - state.tickCurrent;
                    state.offset = int24(state.offset) + jump >= MAX_OFFSET ? MAX_OFFSET : int8(state.offset + jump);
                }

                for (int8 i = 0; i < state.offset; i++) {
                    state.liquidity += ticks[state.tickCurrent + i].getLiquidity(uint8(i));
                }

                uint256 newLiquidity = ticks[state.tickCurrent + state.offset].getLiquidity(uint8(state.offset));
                uint256 newComposition = compositions[uint8(state.offset)];

                state.liquidity += newLiquidity;
                state.composition = type(uint128).max
                    - (
                        state.liquidity == 0
                            ? 0
                            : uint128(mulDiv(type(uint128).max - newComposition, newLiquidity, state.liquidity))
                    );
            } else {
                int24 tickPrev = state.tickCurrent;
                if (tickPrev == MAX_TICK) revert OutOfBounds();
                state.tickCurrent = ticks[tickPrev].next1To0;

                state.liquidity = 0;
                if (state.offset > -MAX_OFFSET) {
                    int24 jump = state.tickCurrent - tickPrev;
                    state.offset = int24(state.offset) - jump <= -MAX_OFFSET ? -MAX_OFFSET : int8(state.offset - jump);
                }

                for (int8 i = 0; i < -state.offset; i++) {
                    state.liquidity += ticks[state.tickCurrent - i].getLiquidity(uint8(i));
                }

                // solhint-disable-next-line max-line-length
                uint256 newLiquidity = ticks[state.tickCurrent + state.offset].getLiquidity(uint8(-state.offset));
                uint256 newComposition = compositions[uint8(-state.offset)];

                state.liquidity += newLiquidity;
                state.composition =
                    state.liquidity == 0 ? 0 : uint128(mulDiv(newComposition, newLiquidity, state.liquidity));
            }
        }

        if (isToken0) {
            amount0 = state.amountA;
            amount1 = state.amountB;
        } else {
            amount0 = state.amountB;
            amount1 = state.amountA;
        }

        for (uint8 i = 0; i <= uint8(state.offset >= 0 ? state.offset : -state.offset); i++) {
            compositions[i] = state.composition;
        }
        tickCurrent = state.tickCurrent;
        offset = state.offset;

        // pay out
        if (isToken0 == isExactIn) {
            if (amount1 < 0) SafeTransferLib.safeTransfer(token1, to, uint256(-amount1));
            uint256 balance0 = BalanceLib.getBalance(token0);
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);
            if (BalanceLib.getBalance(token0) < balance0 + uint256(amount0)) revert InsufficientInput();
        } else {
            if (amount0 < 0) SafeTransferLib.safeTransfer(token0, to, uint256(-amount0));
            uint256 balance1 = BalanceLib.getBalance(token1);
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);
            if (BalanceLib.getBalance(token1) < balance1 + uint256(amount1)) revert InsufficientInput();
        }

        // emit
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Check the validiity of ticks
    function checkTickInput(int24 tick) internal pure {
        if (MIN_TICK > tick || tick > MAX_TICK) {
            revert InvalidTick();
        }
    }

    /// @notice Check the validity of the tier
    function checkTier(uint8 tier) internal pure {
        if (tier > MAX_TIERS) revert InvalidTier();
    }

    /// @notice Update a positions liquidity
    /// @param liquidity The amount of liquidity being added or removed
    function updateLiquidity(
        address to,
        uint8 tierID,
        int24 tick,
        int256 liquidity
    )
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        checkTickInput(tick);
        checkTier(tierID);

        // update ticks
        updateTick(tierID, tick, liquidity);

        // update position
        updatePosition(to, tierID, tick, liquidity);

        // determine amounts
        int24 tickCurrentForTier = getCurrentTickForTierFromOffset(tickCurrent, offset, tierID);

        (amount0, amount1) = calcAmountsForLiquidity(
            tickCurrentForTier, compositions[tierID], tick, liquidity > 0 ? uint256(liquidity) : uint256(-liquidity)
        );
    }

    /// @notice Update a tick
    /// @param liquidity The amount of liquidity being added or removed
    /// @custom:team Entirely removing the current tick is an edge case
    function updateTick(uint8 tier, int24 tick, int256 liquidity) internal {
        uint256 existingLiquidity = ticks[tick].tierLiquidity[tier];
        ticks[tick].tierLiquidity[tier] = addDelta(existingLiquidity, liquidity);

        if (existingLiquidity == 0 && liquidity > 0) {
            int24 tick0To1 = tick - int8(tier);
            int24 tick1To0 = tick + int8(tier);
            uint8 reference0To1 = ticks[tick0To1].reference0To1;
            uint8 reference1To0 = ticks[tick1To0].reference1To0;

            bool add0To1 = reference0To1 == 0;
            bool add1To0 = reference1To0 == 0;
            ticks[tick0To1].reference0To1 = reference0To1 + 1;
            ticks[tick1To0].reference1To0 = reference1To0 + 1;

            if (add0To1) {
                int24 below = -tickMap0To1.nextBelow(-tick0To1);
                int24 above = ticks[below].next0To1;

                ticks[tick0To1].next0To1 = above;
                ticks[below].next0To1 = tick0To1;
                tickMap0To1.set(-tick0To1);
            }

            if (add1To0) {
                int24 below = tickMap1To0.nextBelow(tick1To0);
                int24 above = ticks[below].next1To0;

                ticks[tick1To0].next1To0 = above;
                ticks[below].next1To0 = tick1To0;
                tickMap1To0.set(tick1To0);
            }
        } else if (liquidity < 0 && existingLiquidity == uint256(-liquidity)) {
            int24 tick0To1 = tick - int8(tier);
            int24 tick1To0 = tick + int8(tier);
            uint8 reference0To1 = ticks[tick0To1].reference0To1;
            uint8 reference1To0 = ticks[tick1To0].reference1To0;

            bool remove0To1 = reference0To1 == 1;
            bool remove1To0 = reference1To0 == 1;
            ticks[tick0To1].reference0To1 = reference0To1 - 1;
            ticks[tick1To0].reference1To0 = reference1To0 - 1;

            if (remove0To1) {
                int24 below = -tickMap0To1.nextBelow(-tick0To1);
                int24 above = ticks[tick0To1].next0To1;

                ticks[below].next0To1 = above;
                tickMap0To1.unset(-tick0To1);
            }

            if (remove1To0) {
                int24 below = tickMap1To0.nextBelow(tick1To0);
                int24 above = ticks[tick1To0].next1To0;

                // TODO: when to clear out with delete
                ticks[below].next1To0 = above;
                tickMap1To0.unset(tick1To0);
            }
        }
    }

    /// @notice Update a position
    /// @param liquidity The amount of liquidity being added or removed
    function updatePosition(address to, uint8 tierID, int24 tick, int256 liquidity) internal {
        Positions.Position storage positionInfo = Positions.get(positions, to, tierID, tick);

        positionInfo.liquidity = addDelta(positionInfo.liquidity, liquidity);
    }
}
