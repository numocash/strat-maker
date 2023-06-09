// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Factory} from "./Factory.sol";
import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {addDelta, calcAmountsForLiquidity} from "./LiquidityMath.sol";
import {Position} from "./Position.sol";
import {computeSwapStep} from "./SwapMath.sol";
import {Tick} from "./Tick.sol";
import {getCurrentTickForTierFromOffset, getRatioAtTick, MAX_TICK, MIN_TICK, Q128} from "./TickMath.sol";

import {BalanceLib} from "src/libraries/BalaneLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IAddLiquidityCallback} from "./interfaces/IAddLiquidityCallback.sol";
import {ISwapCallback} from "./interfaces/ISwapCallback.sol";

/// @author Robert Leifke and Kyle Scott
contract Pair {
    using Tick for mapping(bytes32 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidTick();

    error InvalidTier();

    error InsufficientInput();

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    address public immutable factory;

    address public immutable token0;

    address public immutable token1;

    uint8 public constant MAX_TIERS = 5;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint128[MAX_TIERS] public compositions;
    int24 public tickCurrent;
    int8 public maxOffset;
    bool private initialized;

    mapping(bytes32 tickID => Tick.Info) public ticks;
    mapping(bytes32 positionID => Position.Info) public positions;

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

    /// @custom:team Need initialization function to set the tickCurrent

    function initialize(int24 initialTick) external onlyUninitialized {
        tickCurrent = initialTick;
        initialized = true;
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
        int8 maxOffset;
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
            int8 _maxOffset = isSwap0To1 == (maxOffset > 0) ? maxOffset : int8(0);
            uint256 liquidity = 0;

            for (int8 i = 0; i <= (_maxOffset >= 0 ? _maxOffset : -_maxOffset); i++) {
                liquidity += ticks.get(uint8(i), isSwap0To1 ? _tickCurrent + i : _tickCurrent - i).liquidity;
            }

            // TODO: could we cache liquidity
            // TODO: cap maxOffset to the number of tiers there are
            state = SwapState({
                liquidity: liquidity,
                composition: compositions[0],
                tickCurrent: _tickCurrent,
                maxOffset: _maxOffset,
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
                state.tickCurrent -= 1;
                state.liquidity = 0;
                if (state.maxOffset < int8(MAX_TIERS - 1)) state.maxOffset += 1;

                for (int8 i = 0; i < state.maxOffset; i++) {
                    state.liquidity += ticks.get(uint8(i), state.tickCurrent + i).liquidity;
                }

                uint256 newLiquidity = ticks.get(uint8(state.maxOffset), state.tickCurrent + state.maxOffset).liquidity;
                uint256 newComposition = compositions[uint8(state.maxOffset)];

                state.liquidity += newLiquidity;
                state.composition = type(uint128).max
                    - (
                        state.liquidity == 0
                            ? 0
                            : uint128(mulDiv(type(uint128).max - newComposition, newLiquidity, state.liquidity))
                    );
            } else {
                state.tickCurrent += 1;
                state.liquidity = 0;
                if (state.maxOffset > -int8(MAX_TIERS - 1)) state.maxOffset -= 1;

                for (int8 i = 0; i < -state.maxOffset; i++) {
                    state.liquidity += ticks.get(uint8(i), state.tickCurrent - i).liquidity;
                }

                // solhint-disable-next-line max-line-length
                uint256 newLiquidity = ticks.get(uint8(-state.maxOffset), state.tickCurrent + state.maxOffset).liquidity;
                uint256 newComposition = compositions[uint8(-state.maxOffset)];

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

        for (uint8 i = 0; i <= uint8(state.maxOffset >= 0 ? state.maxOffset : -state.maxOffset); i++) {
            compositions[i] = state.composition;
        }
        tickCurrent = state.tickCurrent;
        maxOffset = state.maxOffset;

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
        int24 tickCurrentForTier = getCurrentTickForTierFromOffset(tickCurrent, maxOffset, tierID);

        (amount0, amount1) = calcAmountsForLiquidity(
            tickCurrentForTier, compositions[tierID], tick, liquidity > 0 ? uint256(liquidity) : uint256(-liquidity)
        );
    }

    /// @notice Update a tick
    /// @param liquidity The amount of liquidity being added or removed
    function updateTick(uint8 tierID, int24 tick, int256 liquidity) internal {
        Tick.Info storage tickInfo = ticks.get(tierID, tick);

        tickInfo.liquidity = addDelta(tickInfo.liquidity, liquidity);
    }

    /// @notice Update a position
    /// @param liquidity The amount of liquidity being added or removed
    function updatePosition(address to, uint8 tierID, int24 tick, int256 liquidity) internal {
        Position.Info storage positionInfo = positions.get(to, tierID, tick);

        positionInfo.liquidity = addDelta(positionInfo.liquidity, liquidity);
    }
}
