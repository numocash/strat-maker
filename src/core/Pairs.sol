// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {BitMaps} from "./BitMaps.sol";
import {mulDiv, mulDivRoundingUp} from "./math/FullMath.sol";
import {addDelta, calcAmountsForLiquidity, toInt256} from "./math/LiquidityMath.sol";
import {getRatioAtStrike, MAX_STRIKE, MIN_STRIKE, Q128} from "./math/StrikeMath.sol";
import {computeSwapStep} from "./math/SwapMath.sol";

uint8 constant NUM_SPREADS = 5;
int8 constant MAX_CONSECUTIVE = int8(NUM_SPREADS);

/// @author Robert Leifke and Kyle Scott
library Pairs {
    using BitMaps for BitMaps.BitMap;

    /*<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3
                                 ERRORS
    <3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3*/

    error Initialized();
    error InvalidStrike();
    error InvalidSpread();
    error OutOfBounds();

    /*<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3
                               DATA TYPES
    <3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3*/

    struct Limit {
        uint256 liquidity0To1;
        uint256 liquidity1To0;
        uint256 liquidity0InPerLiquidity;
        uint256 liquidity1InPerLiquidity;
    }

    /// @custom:team could we make reference a bitmap
    /// @custom:team add need settle flags
    struct Strike {
        Limit limit;
        uint256[NUM_SPREADS] liquidityBiDirectional;
        uint256[NUM_SPREADS] totalSupply;
        int24 next0To1;
        int24 next1To0;
        uint8 reference0To1;
        uint8 reference1To0;
    }

    struct Pair {
        uint128[NUM_SPREADS] composition;
        int24[NUM_SPREADS] strikeCurrent;
        int24 cachedStrikeCurrent;
        uint8 initialized; // 0 = unitialized, 1 = initialized
        mapping(int24 => Strike) strikes;
        BitMaps.BitMap bitMap0To1;
        BitMaps.BitMap bitMap1To0;
    }

    /*<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3
                                GET LOGIC
    <3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3<3*/

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

    /// @notice Initialize the pair by setting the initial strike
    function initialize(Pair storage pair, int24 strikeInitial) internal {
        if (pair.initialized != 0) revert Initialized();
        _checkStrike(strikeInitial);

        pair.cachedStrikeCurrent = strikeInitial;
        pair.initialized = 1;

        for (uint256 i = 0; i < NUM_SPREADS;) {
            pair.strikeCurrent[i] = strikeInitial;

            unchecked {
                i++;
            }
        }

        // strike order when swapping 0 -> 1
        // MAX_STRIKE -> strikeInitial -> MIN_STRIKE

        // strike order when swapping 1 -> 0
        // MIN_STRIKE -> strikeInitial -> MAX_STRIKE

        pair.bitMap0To1.set(MIN_STRIKE);
        pair.bitMap1To0.set(MIN_STRIKE);
        pair.bitMap0To1.set(-strikeInitial);
        pair.bitMap1To0.set(strikeInitial);
        pair.strikes[MAX_STRIKE].next0To1 = strikeInitial;
        pair.strikes[MIN_STRIKE].next1To0 = strikeInitial;
        pair.strikes[strikeInitial].next0To1 = MIN_STRIKE;
        pair.strikes[strikeInitial].next1To0 = MAX_STRIKE;
        pair.strikes[strikeInitial].reference0To1 = 1;
        pair.strikes[strikeInitial].reference1To0 = 1;
    }

    /*//////////////////////////////////////////////////////////////
                                   SWAP
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct to hold temporary data while completing a swap
    struct SwapState {
        uint128[NUM_SPREADS] composition;
        int24[NUM_SPREADS] strikeCurrent;
        int24 cachedStrikeCurrent;
        uint256 cachedLiquidity;
        uint128 cachedComposition;
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
    /// @custom:team track available swap liquidity instead of composition
    function swap(Pair storage pair, bool isToken0, int256 amountDesired) internal returns (int256, int256) {
        if (pair.initialized != 1) revert Initialized();
        bool isSwap0To1 = isToken0 == amountDesired > 0;

        SwapState memory state;
        state.composition = pair.composition;
        state.strikeCurrent = pair.strikeCurrent;
        state.cachedStrikeCurrent = pair.cachedStrikeCurrent;

        (state.cachedLiquidity, state.cachedComposition) = _calculateActiveLiquidity(
            state.composition, state.strikeCurrent, pair.strikes, state.cachedStrikeCurrent, isSwap0To1
        );

        while (true) {
            uint256 ratioX128 = getRatioAtStrike(state.cachedStrikeCurrent);
            uint256 amountRemaining;
            {
                uint256 amountIn;
                uint256 amountOut;
                (amountIn, amountOut, amountRemaining) =
                    computeSwapStep(ratioX128, state.cachedComposition, state.cachedLiquidity, isToken0, amountDesired);

                if (amountDesired > 0) {
                    amountDesired -= toInt256(amountIn);
                    state.amountA += toInt256(amountIn);
                    state.amountB -= toInt256(amountOut);
                } else {
                    amountDesired += toInt256(amountOut);
                    state.amountA -= toInt256(amountOut);
                    state.amountB += toInt256(amountIn);
                }

                // if (isSwap0To1) {
                //     unchecked {
                //         uint256 swapLiquidityAvailable = mulDiv(
                //             type(uint256).max - state.cachedComposition,
                //             state.cachedLiquidity,
                //             type(uint256).max / ratioX128
                //         );

                //         if (swapLiquidityAvailable > 0) {
                //             for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                //                 int24 activeStrike = state.cachedStrikeCurrent + int24(int256(i));
                //                 int24 spreadStrikeCurrent = state.strikeCurrent[i - 1];

                //                 if (activeStrike == spreadStrikeCurrent) {
                //                     pair.strikes[activeStrike].liquidity0InPerLiquidity[i - 1] += mulDiv(
                //                         amountIn, type(uint256).max - state.composition[i - 1],
                // swapLiquidityAvailable
                //                     );
                //                 } else {
                //                     break;
                //                 }
                //             }
                //         }
                //     }
                // } else {
                //     unchecked {
                //         uint256 swapLiquidityAvailable = mulDiv(state.cachedComposition, state.cachedLiquidity,
                // Q128);
                //         if (swapLiquidityAvailable > 0) {
                //             for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                //                 int24 activeStrike = state.cachedStrikeCurrent - int24(int256(i));
                //                 int24 spreadStrikeCurrent = state.strikeCurrent[i - 1];

                //                 if (activeStrike == spreadStrikeCurrent) {
                //                     pair.strikes[activeStrike].liquidity1InPerLiquidity[i - 1] +=
                //                         mulDiv(amountIn, state.composition[i - 1], swapLiquidityAvailable);
                //                 } else {
                //                     break;
                //                 }
                //             }
                //         }
                //     }
                // }
            }

            if (amountDesired == 0) {
                if (isSwap0To1) {
                    uint128 composition = uint128(mulDiv(amountRemaining, Q128, state.cachedLiquidity));

                    unchecked {
                        for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                            int24 activeStrike = state.cachedStrikeCurrent + int24(int256(i));
                            int24 spreadStrikeCurrent = state.strikeCurrent[i - 1];

                            if (activeStrike == spreadStrikeCurrent) {
                                state.composition[i - 1] = composition;
                            } else {
                                break;
                            }
                        }
                    }
                } else {
                    uint128 composition =
                        type(uint128).max - uint128(mulDiv(amountRemaining, ratioX128, state.cachedLiquidity));

                    unchecked {
                        for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                            int24 activeStrike = state.cachedStrikeCurrent - int24(int256(i));
                            int24 spreadStrikeCurrent = state.strikeCurrent[i - 1];

                            if (activeStrike == spreadStrikeCurrent) {
                                state.composition[i - 1] = composition;
                            } else {
                                break;
                            }
                        }
                    }
                }

                break;
            }

            if (isSwap0To1) {
                int24 strikePrev = state.cachedStrikeCurrent;
                if (strikePrev == MIN_STRIKE) revert OutOfBounds();

                // move state vars to the next strike
                state.cachedStrikeCurrent = pair.strikes[strikePrev].next0To1;
                unchecked {
                    for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                        int24 activeStrike = state.cachedStrikeCurrent + int24(int256(i));
                        // only update if it was active previously
                        if (state.strikeCurrent[i - 1] >= activeStrike) {
                            state.composition[i - 1] = type(uint128).max;
                            state.strikeCurrent[i - 1] = activeStrike;
                        } else {
                            break;
                        }
                    }
                }

                // Remove strike from linked list and bit map if it has no liquidity
                // Only happens when initialized or all liquidity is removed from current strike
                if (state.cachedLiquidity == 0) {
                    assert(pair.strikes[strikePrev].reference0To1 == 1);

                    int24 below = -pair.bitMap0To1.nextBelow(-strikePrev);
                    int24 above = pair.strikes[strikePrev].next0To1;

                    pair.strikes[below].next0To1 = above;
                    pair.bitMap0To1.unset(-strikePrev);

                    pair.strikes[strikePrev].next0To1 = 0;
                    pair.strikes[strikePrev].reference0To1 = 0;
                }

                (state.cachedLiquidity, state.cachedComposition) = _calculateActiveLiquidity(
                    state.composition, state.strikeCurrent, pair.strikes, state.cachedStrikeCurrent, true
                );
            } else {
                int24 strikePrev = state.cachedStrikeCurrent;
                if (strikePrev == MAX_STRIKE) revert OutOfBounds();

                // move state vars to the next strike
                state.cachedStrikeCurrent = pair.strikes[strikePrev].next1To0;
                unchecked {
                    for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                        int24 activeStrike = state.cachedStrikeCurrent - int24(int256(i));
                        // only update if it was active previously
                        if (state.strikeCurrent[i - 1] <= activeStrike) {
                            state.composition[i - 1] = 0;
                            state.strikeCurrent[i - 1] = activeStrike;
                        } else {
                            break;
                        }
                    }
                }

                // Remove strike from linked list and bit map if it has no liquidity
                // Only happens when initialized or all liquidity is removed from current strike
                if (state.cachedLiquidity == 0) {
                    assert(pair.strikes[strikePrev].reference1To0 == 1);

                    int24 below = pair.bitMap1To0.nextBelow(strikePrev);
                    int24 above = pair.strikes[strikePrev].next1To0;

                    pair.strikes[below].next1To0 = above;
                    pair.bitMap1To0.unset(strikePrev);

                    pair.strikes[strikePrev].next1To0 = 0;
                    pair.strikes[strikePrev].reference1To0 = 0;
                }

                (state.cachedLiquidity, state.cachedComposition) = _calculateActiveLiquidity(
                    state.composition, state.strikeCurrent, pair.strikes, state.cachedStrikeCurrent, false
                );
            }
        }

        // set spread composition and strike current
        pair.cachedStrikeCurrent = state.cachedStrikeCurrent;
        for (uint256 i = 0; i < NUM_SPREADS;) {
            pair.strikeCurrent[i] = state.strikeCurrent[i];
            pair.composition[i] = state.composition[i];

            unchecked {
                i++;
            }
        }

        if (isToken0) {
            return (state.amountA, state.amountB);
        } else {
            return (state.amountB, state.amountA);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            UPDATE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Update a positions liquidity
    /// @param liquidity The amount of liquidity being added or removed
    function updateLiquidity(
        Pair storage pair,
        int24 strike,
        uint8 spread,
        int256 liquidity
    )
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        if (pair.initialized != 1) revert Initialized();
        _checkStrike(strike);
        _checkSpread(spread);

        _updateStrike(pair, strike, spread, liquidity);

        (amount0, amount1) = calcAmountsForLiquidity(
            pair.strikeCurrent[spread - 1],
            pair.composition[spread - 1],
            strike,
            liquidity > 0 ? uint256(liquidity) : uint256(-liquidity),
            liquidity > 0
        );
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice sum all the active liquidity
    function _calculateActiveLiquidity(
        uint128[NUM_SPREADS] memory composition,
        int24[NUM_SPREADS] memory strikeCurrent,
        mapping(int24 => Strike) storage strikes,
        int24 cachedStrikeCurrent,
        bool isSwap0To1
    )
        private
        view
        returns (uint256 cachedLiquidity, uint128 cachedComposition)
    {
        unchecked {
            for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                int24 activeStrike =
                    isSwap0To1 ? cachedStrikeCurrent + int24(int256(i)) : cachedStrikeCurrent - int24(int256(i));
                int24 spreadStrikeCurrent = strikeCurrent[i - 1];

                if (activeStrike == spreadStrikeCurrent) {
                    uint256 spreadLiquidity = strikes[activeStrike].liquidityBiDirectional[i - 1];

                    if (spreadLiquidity > 0) {
                        cachedLiquidity += spreadLiquidity;
                        // KYLE: is this rounding correctly
                        cachedComposition += uint128(mulDiv(composition[i - 1], spreadLiquidity, cachedLiquidity));
                    }
                } else {
                    // exit early because higher spreads are always farther away from the active strike
                    break;
                }
            }
        }
    }

    /// @notice Check the validiity of strikes
    function _checkStrike(int24 strike) private pure {
        if (MIN_STRIKE > strike || strike > MAX_STRIKE) {
            revert InvalidStrike();
        }
    }

    /// @notice Check the validity of the spread
    function _checkSpread(uint8 spread) private pure {
        if (spread == 0 || spread > NUM_SPREADS + 1) revert InvalidSpread();
    }

    /// @notice Update a strike
    /// @param liquidity The amount of liquidity being added or removed
    /// @custom:team check strike + spread is not greater than max
    function _updateStrike(Pair storage pair, int24 strike, uint8 spread, int256 liquidity) private {
        uint256 existingLiquidity = pair.strikes[strike].liquidityBiDirectional[spread - 1];
        pair.strikes[strike].liquidityBiDirectional[spread - 1] = addDelta(existingLiquidity, liquidity);

        unchecked {
            if (existingLiquidity == 0 && liquidity > 0) {
                int24 strike0To1 = strike - int8(spread);
                int24 strike1To0 = strike + int8(spread);
                uint8 reference0To1 = pair.strikes[strike0To1].reference0To1;
                uint8 reference1To0 = pair.strikes[strike1To0].reference1To0;

                bool add0To1 = reference0To1 == 0;
                bool add1To0 = reference1To0 == 0;
                pair.strikes[strike0To1].reference0To1 = reference0To1 + 1;
                pair.strikes[strike1To0].reference1To0 = reference1To0 + 1;

                if (add0To1) {
                    // tick0To1s are in decreasing order, double negate to reuse nextBelow function
                    int24 below = -pair.bitMap0To1.nextBelow(-strike0To1);
                    int24 above = pair.strikes[below].next0To1;

                    pair.strikes[strike0To1].next0To1 = above;
                    pair.strikes[below].next0To1 = strike0To1;
                    pair.bitMap0To1.set(-strike0To1);
                }

                if (add1To0) {
                    int24 below = pair.bitMap1To0.nextBelow(strike1To0);
                    int24 above = pair.strikes[below].next1To0;

                    pair.strikes[strike1To0].next1To0 = above;
                    pair.strikes[below].next1To0 = strike1To0;
                    pair.bitMap1To0.set(strike1To0);
                }
            } else if (liquidity < 0 && existingLiquidity == uint256(-liquidity)) {
                int24 strike0To1 = strike - int8(spread);
                int24 strike1To0 = strike + int8(spread);
                uint8 reference0To1 = pair.strikes[strike0To1].reference0To1;
                uint8 reference1To0 = pair.strikes[strike1To0].reference1To0;

                bool remove0To1 = reference0To1 == 1 && pair.cachedStrikeCurrent != strike0To1;
                bool remove1To0 = reference1To0 == 1 && pair.cachedStrikeCurrent != strike1To0;
                if (pair.cachedStrikeCurrent != strike0To1) pair.strikes[strike0To1].reference0To1 = reference0To1 - 1;
                if (pair.cachedStrikeCurrent != strike1To0) pair.strikes[strike1To0].reference1To0 = reference1To0 - 1;

                if (remove0To1) {
                    int24 below = -pair.bitMap0To1.nextBelow(-strike0To1);
                    int24 above = pair.strikes[strike0To1].next0To1;

                    pair.strikes[below].next0To1 = above;
                    pair.bitMap0To1.unset(-strike0To1);

                    pair.strikes[strike0To1].next0To1 = 0;
                }

                if (remove1To0) {
                    int24 below = pair.bitMap1To0.nextBelow(strike1To0);
                    int24 above = pair.strikes[strike1To0].next1To0;

                    pair.strikes[below].next1To0 = above;
                    pair.bitMap1To0.unset(strike1To0);

                    pair.strikes[strike1To0].next1To0 = 0;
                }
            }
        }
    }
}
