// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv, mulDivRoundingUp} from "./math/FullMath.sol";
import {addDelta, calcAmountsForLiquidity} from "./math/LiquidityMath.sol";
import {computeSwapStep} from "./math/SwapMath.sol";
import {getCurrentTickForTierFromOffset, getRatioAtTick, MAX_TICK, MIN_TICK, Q128} from "./math/TickMath.sol";
import {Position} from "./Position.sol";
import {Tick} from "./Tick.sol";

/// @author Robert Leifke and Kyle Scott
library Pairs {
    using Tick for mapping(bytes32 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);

    error Initialized();
    error InvalidTick();
    error InvalidTier();

    struct Pair {
        uint128[5] compositions;
        int24 tickCurrent;
        int8 maxOffset;
        uint8 lock; // 2 == locked, 1 == unlocked, 0 == uninitialized
        mapping(bytes32 tickID => Tick.Info) ticks;
        mapping(bytes32 positionID => Position.Info) positions;
    }

    function getPair(
        mapping(bytes32 => Pair) storage pairs,
        address token0,
        address token1
    )
        internal
        view
        returns (Pair storage pair)
    {
        bytes32 pairID = keccak256(abi.encode(token0, token1));
        pair = pairs[pairID];
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function initialize(Pair storage pair, int24 tickInitial) internal {
        if (pair.lock != 0) revert Initialized();
        _checkTick(tickInitial);

        pair.tickCurrent = tickInitial;
        pair.lock = 1;
    }

    /*//////////////////////////////////////////////////////////////
                                   SWAP
    //////////////////////////////////////////////////////////////*/

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
    /// @param isToken0 True if amountDesired refers to token0
    /// @param amountDesired The desired amount change on the pool
    /// @return amount0 The delta of the balance of token0 of the pool
    /// @return amount1 The delta of the balance of token1 of the pool
    function swap(
        Pair storage pair,
        bool isToken0,
        int256 amountDesired
    )
        internal
        returns (int256 amount0, int256 amount1)
    {
        bool isExactIn = amountDesired > 0;
        bool isSwap0To1 = isToken0 == isExactIn;

        SwapState memory state;
        {
            int24 _tickCurrent = pair.tickCurrent;
            int8 _maxOffset = isSwap0To1 == (pair.maxOffset > 0) ? pair.maxOffset : int8(0);
            uint256 liquidity = 0;

            for (int8 i = 0; i <= (_maxOffset >= 0 ? _maxOffset : -_maxOffset); i++) {
                liquidity += pair.ticks.get(uint8(i), isSwap0To1 ? _tickCurrent + i : _tickCurrent - i).liquidity;
            }

            // TODO: could we cache liquidity
            // TODO: cap maxOffset to the number of tiers there are
            state = SwapState({
                liquidity: liquidity,
                composition: pair.compositions[0],
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
                state.maxOffset += 1;

                for (int8 i = 0; i < state.maxOffset; i++) {
                    state.liquidity += pair.ticks.get(uint8(i), state.tickCurrent + i).liquidity;
                }

                uint256 newLiquidity =
                    pair.ticks.get(uint8(state.maxOffset), state.tickCurrent + state.maxOffset).liquidity;
                uint256 newComposition = pair.compositions[uint8(state.maxOffset)];

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
                state.maxOffset -= 1;

                for (int8 i = 0; i < -state.maxOffset; i++) {
                    state.liquidity += pair.ticks.get(uint8(i), state.tickCurrent - i).liquidity;
                }

                // solhint-disable-next-line max-line-length
                uint256 newLiquidity =
                    pair.ticks.get(uint8(-state.maxOffset), state.tickCurrent + state.maxOffset).liquidity;
                uint256 newComposition = pair.compositions[uint8(-state.maxOffset)];

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
            pair.compositions[i] = state.composition;
        }
        pair.tickCurrent = state.tickCurrent;
        pair.maxOffset = state.maxOffset;
    }

    /*//////////////////////////////////////////////////////////////
                            UPDATE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Update a positions liquidity
    /// @param liquidity The amount of liquidity being added or removed
    function updateLiquidity(
        Pair storage pair,
        address to,
        uint8 tierID,
        int24 tick,
        int256 liquidity
    )
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        _checkTick(tick);
        _checkTier(tierID);

        // update ticks
        _updateTick(pair, tierID, tick, liquidity);

        // update position
        _updatePosition(pair, to, tierID, tick, liquidity);

        // determine amounts
        int24 tickCurrentForTier = getCurrentTickForTierFromOffset(pair.tickCurrent, pair.maxOffset, tierID);

        (amount0, amount1) = calcAmountsForLiquidity(
            tickCurrentForTier,
            pair.compositions[tierID],
            tick,
            liquidity > 0 ? uint256(liquidity) : uint256(-liquidity)
        );
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Check the validiity of ticks
    function _checkTick(int24 tick) internal pure {
        if (MIN_TICK > tick || tick > MAX_TICK) {
            revert InvalidTick();
        }
    }

    /// @notice Check the validity of the tier
    function _checkTier(uint8 tier) internal pure {
        if (tier > 5) revert InvalidTier();
    }

    /// @notice Update a tick
    /// @param liquidity The amount of liquidity being added or removed
    function _updateTick(Pair storage pair, uint8 tierID, int24 tick, int256 liquidity) internal {
        Tick.Info storage tickInfo = pair.ticks.get(tierID, tick);

        tickInfo.liquidity = addDelta(tickInfo.liquidity, liquidity);
    }

    /// @notice Update a position
    /// @param liquidity The amount of liquidity being added or removed
    function _updatePosition(Pair storage pair, address to, uint8 tierID, int24 tick, int256 liquidity) internal {
        Position.Info storage positionInfo = pair.positions.get(to, tierID, tick);

        positionInfo.liquidity = addDelta(positionInfo.liquidity, liquidity);
    }
}
