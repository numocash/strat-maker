// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv, mulDivRoundingUp} from "./math/FullMath.sol";
import {addDelta, calcAmountsForLiquidity} from "./math/LiquidityMath.sol";
import {computeSwapStep} from "./math/SwapMath.sol";
import {getCurrentTickForTierFromOffset, getRatioAtTick, MAX_TICK, MIN_TICK, Q128} from "./math/TickMath.sol";
import {Ticks} from "./Ticks.sol";
import {TickMaps} from "./TickMaps.sol";

uint8 constant MAX_TIERS = 5;
int8 constant MAX_OFFSET = int8(MAX_TIERS) - 1;

/// @author Robert Leifke and Kyle Scott
library Pairs {
    using Ticks for Ticks.Tick;
    using TickMaps for TickMaps.TickMap;

    error Initialized();
    error InvalidTick();
    error InvalidTier();
    error OutOfBounds();

    struct Pair {
        uint128[MAX_TIERS] compositions;
        int24 tickCurrent;
        int8 offset;
        uint8 lock; // 2 == locked, 1 == unlocked, 0 == uninitialized
        mapping(int24 => Ticks.Tick) ticks;
        TickMaps.TickMap tickMap0To1;
        TickMaps.TickMap tickMap1To0;
    }

    function getPairID(address token0, address token1) internal pure returns (bytes32 pairID) {
        return keccak256(abi.encodePacked(token0, token1));
    }

    function getPairAndID(
        mapping(bytes32 => Pair) storage pairs,
        address token0,
        address token1
    )
        internal
        view
        returns (bytes32 pairID, Pair storage pair)
    {
        pairID = getPairID(token0, token1);
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

        pair.tickMap0To1.set(MIN_TICK);
        pair.tickMap1To0.set(MIN_TICK);
        pair.tickMap0To1.set(-tickInitial);
        pair.tickMap1To0.set(tickInitial);
        pair.ticks[MAX_TICK].next0To1 = tickInitial;
        pair.ticks[MIN_TICK].next1To0 = tickInitial;
        pair.ticks[tickInitial].next0To1 = MIN_TICK;
        pair.ticks[tickInitial].next1To0 = MAX_TICK;
        pair.ticks[tickInitial].reference0To1 = 1;
        pair.ticks[tickInitial].reference1To0 = 1;
    }

    /*//////////////////////////////////////////////////////////////
                                   SWAP
    //////////////////////////////////////////////////////////////*/

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
    /// @param isToken0 True if amountDesired refers to token0
    /// @param amountDesired The desired amount change on the pair
    /// @return amount0 The delta of the balance of token0 of the pair
    /// @return amount1 The delta of the balance of token1 of the pair
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
            int8 _offset = isSwap0To1 == (pair.offset > 0) ? pair.offset : int8(0);
            uint256 liquidity = 0;

            for (int8 i = 0; i <= (_offset >= 0 ? _offset : -_offset); i++) {
                liquidity += pair.ticks[isSwap0To1 ? _tickCurrent + i : _tickCurrent - i].getLiquidity(uint8(i));
            }

            // TODO: could we cache liquidity
            state = SwapState({
                liquidity: liquidity,
                composition: pair.compositions[0],
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
                state.tickCurrent = pair.ticks[tickPrev].next0To1;

                state.liquidity = 0;
                if (state.offset < MAX_OFFSET) {
                    int24 jump = tickPrev - state.tickCurrent;
                    state.offset = int24(state.offset) + jump >= MAX_OFFSET ? MAX_OFFSET : int8(state.offset + jump);
                }

                for (int8 i = 0; i < state.offset; i++) {
                    state.liquidity += pair.ticks[state.tickCurrent + i].getLiquidity(uint8(i));
                }

                uint256 newLiquidity = pair.ticks[state.tickCurrent + state.offset].getLiquidity(uint8(state.offset));
                uint256 newComposition = pair.compositions[uint8(state.offset)];

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
                state.tickCurrent = pair.ticks[tickPrev].next1To0;

                state.liquidity = 0;
                if (state.offset > -MAX_OFFSET) {
                    int24 jump = state.tickCurrent - tickPrev;
                    state.offset = int24(state.offset) - jump <= -MAX_OFFSET ? -MAX_OFFSET : int8(state.offset - jump);
                }

                for (int8 i = 0; i < -state.offset; i++) {
                    state.liquidity += pair.ticks[state.tickCurrent - i].getLiquidity(uint8(i));
                }

                // solhint-disable-next-line max-line-length
                uint256 newLiquidity = pair.ticks[state.tickCurrent + state.offset].getLiquidity(uint8(-state.offset));
                uint256 newComposition = pair.compositions[uint8(-state.offset)];

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
            pair.compositions[i] = state.composition;
        }
        pair.tickCurrent = state.tickCurrent;
        pair.offset = state.offset;
    }

    /*//////////////////////////////////////////////////////////////
                            UPDATE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Update a positions liquidity
    /// @param liquidity The amount of liquidity being added or removed
    function updateLiquidity(
        Pair storage pair,
        int24 tick,
        uint8 tier,
        int256 liquidity
    )
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        _checkTick(tick);
        _checkTier(tier);

        // update ticks
        _updateTick(pair, tick, tier, liquidity);

        // determine amounts
        int24 tickCurrentForTier = getCurrentTickForTierFromOffset(pair.tickCurrent, pair.offset, tier);

        (amount0, amount1) = calcAmountsForLiquidity(
            tickCurrentForTier, pair.compositions[tier], tick, liquidity > 0 ? uint256(liquidity) : uint256(-liquidity)
        );
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Check the validiity of ticks
    function _checkTick(int24 tick) private pure {
        if (MIN_TICK > tick || tick > MAX_TICK) {
            revert InvalidTick();
        }
    }

    /// @notice Check the validity of the tier
    function _checkTier(uint8 tier) private pure {
        if (tier > MAX_TIERS) revert InvalidTier();
    }

    /// @notice Update a tick
    /// @param liquidity The amount of liquidity being added or removed
    function _updateTick(Pair storage pair, int24 tick, uint8 tier, int256 liquidity) private {
        uint256 existingLiquidity = pair.ticks[tick].getLiquidity(tier);
        pair.ticks[tick].liquidity[tier] = addDelta(existingLiquidity, liquidity);

        if (existingLiquidity == 0 && liquidity > 0) {
            int24 tick0To1 = tick - int8(tier);
            int24 tick1To0 = tick + int8(tier);
            uint8 reference0To1 = pair.ticks[tick0To1].reference0To1;
            uint8 reference1To0 = pair.ticks[tick1To0].reference1To0;

            bool add0To1 = reference0To1 == 0;
            bool add1To0 = reference1To0 == 0;
            pair.ticks[tick0To1].reference0To1 = reference0To1 + 1;
            pair.ticks[tick1To0].reference1To0 = reference1To0 + 1;

            if (add0To1) {
                int24 below = -pair.tickMap0To1.nextBelow(-tick0To1);
                int24 above = pair.ticks[below].next0To1;

                pair.ticks[tick0To1].next0To1 = above;
                pair.ticks[below].next0To1 = tick0To1;
                pair.tickMap0To1.set(-tick0To1);
            }

            if (add1To0) {
                int24 below = pair.tickMap1To0.nextBelow(tick1To0);
                int24 above = pair.ticks[below].next1To0;

                pair.ticks[tick1To0].next1To0 = above;
                pair.ticks[below].next1To0 = tick1To0;
                pair.tickMap1To0.set(tick1To0);
            }
        } else if (liquidity < 0 && existingLiquidity == uint256(-liquidity)) {
            int24 tick0To1 = tick - int8(tier);
            int24 tick1To0 = tick + int8(tier);
            uint8 reference0To1 = pair.ticks[tick0To1].reference0To1;
            uint8 reference1To0 = pair.ticks[tick1To0].reference1To0;

            bool remove0To1 = reference0To1 == 1;
            bool remove1To0 = reference1To0 == 1;
            pair.ticks[tick0To1].reference0To1 = reference0To1 - 1;
            pair.ticks[tick1To0].reference1To0 = reference1To0 - 1;

            if (remove0To1) {
                int24 below = -pair.tickMap0To1.nextBelow(-tick0To1);
                int24 above = pair.ticks[tick0To1].next0To1;

                pair.ticks[below].next0To1 = above;
                pair.tickMap0To1.unset(-tick0To1);
            }

            if (remove1To0) {
                int24 below = pair.tickMap1To0.nextBelow(tick1To0);
                int24 above = pair.ticks[tick1To0].next1To0;

                // TODO: when to clear out with delete
                pair.ticks[below].next1To0 = above;
                pair.tickMap1To0.unset(tick1To0);
            }
        }
    }
}
