// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {BitMaps} from "./BitMaps.sol";
import {mulDiv, mulDivRoundingUp} from "./math/FullMath.sol";
import {addDelta, toInt256} from "./math/LiquidityMath.sol";
import {getRatioAtStrike, MAX_STRIKE, MIN_STRIKE, Q128} from "./math/StrikeMath.sol";
import {computeSwapStep} from "./math/SwapMath.sol";

uint8 constant NUM_SPREADS = 5;
int8 constant MAX_CONSECUTIVE = int8(NUM_SPREADS);

/// @author Robert Leifke and Kyle Scott
library Pairs {
    using BitMaps for BitMaps.BitMap;

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 ERRORS
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    error Initialized();
    error InvalidStrike();
    error InvalidSpread();
    error OutOfBounds();

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               DATA TYPES
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    struct Limit {
        uint256 liquidity0To1;
        uint256 liquidity1To0;
        uint256 liquidity0InPerLiquidity;
        uint256 liquidity1InPerLiquidity;
    }

    /// @custom:team could we make reference a bitmap
    struct Strike {
        Limit limit;
        uint256[NUM_SPREADS] totalSupply;
        uint256[NUM_SPREADS] liquidityBiDirectional;
        uint256[NUM_SPREADS] liquidityBorrowed;
        uint256 liquidityGrowthX128;
        int24 next0To1;
        int24 next1To0;
        uint8 reference0To1;
        uint8 reference1To0;
        bool settle0;
        bool settle1;
        uint8 activeSpread;
    }

    struct Pair {
        mapping(int24 => Strike) strikes;
        BitMaps.BitMap bitMap0To1;
        BitMaps.BitMap bitMap1To0;
        uint256 cachedBlock;
        uint128[NUM_SPREADS] composition;
        int24[NUM_SPREADS] strikeCurrent;
        int24 cachedStrikeCurrent;
        uint8 initialized; // 0 = unitialized, 1 = initialized
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                GET LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

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

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                              INITIALIZATION
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

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

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                   SWAP
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Struct to hold temporary data while completing a swap
    struct SwapState {
        int24[NUM_SPREADS] strikeCurrent;
        int24 cachedStrikeCurrent;
        uint256 liquiditySwap;
        uint256 liquidityTotal;
        uint256[NUM_SPREADS] liquiditySwapSpread;
        uint256[NUM_SPREADS] liquidityTotalSpread;
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
        state.strikeCurrent = pair.strikeCurrent;
        state.cachedStrikeCurrent = pair.cachedStrikeCurrent;

        // calculate liquiditySwap and liquidityTotal
        unchecked {
            for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                int24 activeStrike = isSwap0To1
                    ? state.cachedStrikeCurrent + int24(int256(i))
                    : state.cachedStrikeCurrent - int24(int256(i));
                int24 spreadStrikeCurrent = state.strikeCurrent[i - 1];

                if (activeStrike == spreadStrikeCurrent) {
                    uint256 liquidityTotal = pair.strikes[activeStrike].liquidityBiDirectional[i - 1];
                    uint256 liquiditySwap = mulDiv(
                        isSwap0To1 ? pair.composition[i - 1] : type(uint128).max - pair.composition[i - 1],
                        liquidityTotal,
                        Q128
                    );

                    state.liquidityTotalSpread[i - 1] = liquidityTotal;
                    state.liquiditySwapSpread[i - 1] = liquiditySwap;
                    state.liquidityTotal += liquidityTotal;
                    state.liquiditySwap += liquiditySwap;
                } else {
                    break;
                }
            }
        }

        while (true) {
            uint256 ratioX128 = getRatioAtStrike(state.cachedStrikeCurrent);
            uint256 amountRemaining;
            {
                uint256 amountIn;
                uint256 amountOut;
                (amountIn, amountOut, amountRemaining) =
                    computeSwapStep(ratioX128, state.liquiditySwap, isToken0, amountDesired);

                if (amountDesired > 0) {
                    amountDesired -= toInt256(amountIn);
                    state.amountA += toInt256(amountIn);
                    state.amountB -= toInt256(amountOut);
                } else {
                    amountDesired += toInt256(amountOut);
                    state.amountA -= toInt256(amountOut);
                    state.amountB += toInt256(amountIn);
                }

                // calculate and store liquidity gained from fees
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
                //                     pair.strikes[activeStrike].liquidityBiDirectional[i - 1] +=
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
                    uint128 composition = uint128(mulDiv(amountRemaining, Q128, state.liquidityTotal));

                    unchecked {
                        for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                            int24 activeStrike = state.cachedStrikeCurrent + int24(int256(i));
                            int24 spreadStrikeCurrent = state.strikeCurrent[i - 1];

                            if (activeStrike == spreadStrikeCurrent) {
                                pair.composition[i - 1] = composition;
                            } else {
                                break;
                            }
                        }
                    }
                } else {
                    uint128 composition =
                        type(uint128).max - uint128(mulDiv(amountRemaining, ratioX128, state.liquidityTotal));

                    unchecked {
                        for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                            int24 activeStrike = state.cachedStrikeCurrent - int24(int256(i));
                            int24 spreadStrikeCurrent = state.strikeCurrent[i - 1];

                            if (activeStrike == spreadStrikeCurrent) {
                                pair.composition[i - 1] = composition;
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

                // Remove strike from linked list and bit map if it has no liquidity
                // Only happens when initialized or all liquidity is removed from current strike
                if (state.liquidityTotal == 0) _removeStrike0To1(pair, strikePrev);

                // move state vars to the next strike
                state.cachedStrikeCurrent = pair.strikes[strikePrev].next0To1;
                state.liquiditySwap = 0;
                state.liquidityTotal = 0;
                unchecked {
                    for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                        int24 activeStrike = state.cachedStrikeCurrent + int24(int256(i));
                        // only update if it was active previously
                        if (state.strikeCurrent[i - 1] > activeStrike) {
                            state.strikeCurrent[i - 1] = activeStrike;

                            uint256 liquidity = pair.strikes[activeStrike].liquidityBiDirectional[i - 1];
                            state.liquidityTotal += liquidity;
                            state.liquiditySwap += liquidity;
                            state.liquidityTotalSpread[i - 1] = liquidity;
                            state.liquiditySwapSpread[i - 1] = liquidity;
                        } else if (state.strikeCurrent[i - 1] == activeStrike) {
                            uint256 liquidity = pair.strikes[activeStrike].liquidityBiDirectional[i - 1];
                            uint128 composition = pair.composition[i - 1];
                            uint256 liquiditySwap = mulDiv(liquidity, composition, Q128);

                            state.liquidityTotal += liquidity;
                            state.liquiditySwap += liquiditySwap;
                            state.liquidityTotalSpread[i - 1] = liquidity;
                            state.liquiditySwapSpread[i - 1] = liquiditySwap;
                        } else {
                            break;
                        }
                    }
                }
            } else {
                int24 strikePrev = state.cachedStrikeCurrent;
                if (strikePrev == MAX_STRIKE) revert OutOfBounds();

                // Remove strike from linked list and bit map if it has no liquidity
                // Only happens when initialized or all liquidity is removed from current strike
                if (state.liquidityTotal == 0) _removeStrike1To0(pair, strikePrev);

                // move state vars to the next strike
                state.cachedStrikeCurrent = pair.strikes[strikePrev].next1To0;
                state.liquiditySwap = 0;
                state.liquidityTotal = 0;

                unchecked {
                    for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                        int24 activeStrike = state.cachedStrikeCurrent - int24(int256(i));

                        // only update if it was active previously
                        if (state.strikeCurrent[i - 1] < activeStrike) {
                            state.strikeCurrent[i - 1] = activeStrike;

                            uint256 liquidity = pair.strikes[activeStrike].liquidityBiDirectional[i - 1];
                            state.liquidityTotal += liquidity;
                            state.liquiditySwap += liquidity;
                            state.liquidityTotalSpread[i - 1] = liquidity;
                            state.liquiditySwapSpread[i - 1] = liquidity;
                        } else if (state.strikeCurrent[i - 1] == activeStrike) {
                            uint256 liquidity = pair.strikes[activeStrike].liquidityBiDirectional[i - 1];
                            uint128 composition = type(uint128).max - pair.composition[i - 1];
                            uint256 liquiditySwap = mulDiv(liquidity, composition, Q128);

                            state.liquidityTotal += liquidity;
                            state.liquiditySwap += liquiditySwap;
                            state.liquidityTotalSpread[i - 1] = liquidity;
                            state.liquiditySwapSpread[i - 1] = liquiditySwap;
                        } else {
                            break;
                        }
                    }
                }
            }
        }

        // set spread composition and strike current
        pair.cachedStrikeCurrent = state.cachedStrikeCurrent;
        for (uint256 i = 0; i < NUM_SPREADS;) {
            pair.strikeCurrent[i] = state.strikeCurrent[i];

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

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                            LIQUIDITY LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Update a strike
    /// @param liquidity The amount of liquidity being added or removed
    /// @custom:team check strike + spread is not greater than max
    function updateStrike(Pair storage pair, int24 strike, uint8 spread, int256 balance, int256 liquidity) internal {
        _checkStrike(strike);
        _checkSpread(spread);

        uint256 existingLiquidity = pair.strikes[strike].liquidityBiDirectional[spread - 1];
        pair.strikes[strike].totalSupply[spread - 1] = addDelta(pair.strikes[strike].totalSupply[spread - 1], balance);
        pair.strikes[strike].liquidityBiDirectional[spread - 1] = addDelta(existingLiquidity, liquidity);

        unchecked {
            if (existingLiquidity == 0 && liquidity > 0) {
                int24 strike0To1 = strike - int8(spread);
                int24 strike1To0 = strike + int8(spread);

                _addStrike0To1(pair, strike0To1);
                _addStrike1To0(pair, strike1To0);
            } else if (liquidity < 0 && existingLiquidity == uint256(-liquidity)) {
                int24 strike0To1 = strike - int8(spread);
                int24 strike1To0 = strike + int8(spread);

                _removeStrike0To1(pair, strike0To1);
                _removeStrike1To0(pair, strike1To0);
            }
        }
    }

    function borrowLiquidity(Pair storage pair, int24 strike, uint256 liquidity) internal {
        Strike storage strikeObj = pair.strikes[strike];
        uint8 _activeSpread = strikeObj.activeSpread;

        while (true) {
            // TODO: should we do this
            // don't allow for borrowing the current strike
            if (pair.strikeCurrent[_activeSpread] == strike) revert();
            uint256 availableLiquidity = strikeObj.liquidityBiDirectional[_activeSpread];

            if (availableLiquidity >= liquidity) {
                strikeObj.liquidityBiDirectional[_activeSpread] = availableLiquidity - liquidity;
                strikeObj.liquidityBorrowed[_activeSpread] += liquidity;
                break;
            } else {
                _removeStrike0To1(pair, strike - int8(_activeSpread));
                _removeStrike1To0(pair, strike + int8(_activeSpread));

                strikeObj.liquidityBiDirectional[_activeSpread] = 0;
                strikeObj.liquidityBorrowed[_activeSpread] += availableLiquidity;
                liquidity -= availableLiquidity;
                _activeSpread++;
            }
        }
        // TODO: charge fee for borrowing

        strikeObj.activeSpread = _activeSpread;
    }

    function repayLiquidity(Pair storage pair, int24 strike, uint256 liquidity) internal {
        Strike storage strikeObj = pair.strikes[strike];
        int24 _cachedStrikeCurrent = pair.cachedStrikeCurrent;
        uint8 _activeSpread = strikeObj.activeSpread;

        if (_cachedStrikeCurrent == strike) _accrue(pair, strike);

        while (true) {
            uint256 borrowedLiquidity = strikeObj.liquidityBorrowed[_activeSpread];

            if (borrowedLiquidity >= liquidity) {
                strikeObj.liquidityBiDirectional[_activeSpread] += liquidity;
                strikeObj.liquidityBorrowed[_activeSpread] = borrowedLiquidity - liquidity;
                break;
            } else {
                strikeObj.liquidityBiDirectional[_activeSpread] += borrowedLiquidity;
                strikeObj.liquidityBorrowed[_activeSpread] = 0;
                liquidity -= borrowedLiquidity;
                _activeSpread--;

                _addStrike0To1(pair, strike - int8(_activeSpread));
                _addStrike1To0(pair, strike + int8(_activeSpread));
            }
        }
    }

    /// @notice accrue interest to the current strike
    function accrue(Pair storage pair) internal {
        _accrue(pair, pair.cachedStrikeCurrent);
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                             INTERNAL LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

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

    function _accrue(Pair storage pair, int24 strike) private {
        uint256 _cachedBlock = pair.cachedBlock;
        uint256 blocks = block.number - _cachedBlock;
        if (blocks == 0) return;

        uint256 _liquidityGrowthNumerator;
        uint256 _liquidityBorrowedTotal;

        for (uint256 i = 0; i < pair.strikes[strike].activeSpread; i++) {
            uint256 _liquidityBorrowed = pair.strikes[strike].liquidityBorrowed[i];

            pair.strikes[strike].liquidityBiDirectional[i] += ((i + 1) * blocks * _liquidityBorrowed) / 10_000;
            _liquidityGrowthNumerator += (i + 1) * blocks * _liquidityBorrowed;
            _liquidityBorrowedTotal += _liquidityBorrowed;
        }

        pair.strikes[strike].liquidityGrowthX128 +=
            mulDivRoundingUp(_liquidityGrowthNumerator, Q128, _liquidityBorrowedTotal);
        // TODO: same math as repay liquidity

        pair.cachedBlock = block.number;
    }

    function _addStrike0To1(Pair storage pair, int24 strike) private {
        uint8 reference0To1 = pair.strikes[strike].reference0To1;
        pair.strikes[strike].reference0To1 = reference0To1 + 1;

        if (reference0To1 == 0) {
            int24 below = -pair.bitMap0To1.nextBelow(-strike);
            int24 above = pair.strikes[below].next0To1;

            pair.strikes[strike].next0To1 = above;
            pair.strikes[below].next0To1 = strike;
            pair.bitMap0To1.set(-strike);
        }
    }

    function _addStrike1To0(Pair storage pair, int24 strike) private {
        uint8 reference1To0 = pair.strikes[strike].reference1To0;
        pair.strikes[strike].reference1To0 = reference1To0 + 1;

        if (reference1To0 == 0) {
            int24 below = pair.bitMap1To0.nextBelow(strike);
            int24 above = pair.strikes[below].next1To0;

            pair.strikes[strike].next1To0 = above;
            pair.strikes[below].next1To0 = strike;
            pair.bitMap1To0.set(strike);
        }
    }

    function _removeStrike0To1(Pair storage pair, int24 strike) private {
        uint8 reference0To1 = pair.strikes[strike].reference0To1;
        if (pair.cachedStrikeCurrent != strike) pair.strikes[strike].reference0To1 = reference0To1 - 1;

        if (reference0To1 == 1 && pair.cachedStrikeCurrent != strike) {
            int24 below = -pair.bitMap0To1.nextBelow(-strike);
            int24 above = pair.strikes[strike].next0To1;

            pair.strikes[below].next0To1 = above;
            pair.bitMap0To1.unset(-strike);

            pair.strikes[strike].next0To1 = 0;
        }
    }

    function _removeStrike1To0(Pair storage pair, int24 strike) private {
        uint8 reference1To0 = pair.strikes[strike].reference1To0;
        if (pair.cachedStrikeCurrent != strike) pair.strikes[strike].reference1To0 = reference1To0 - 1;

        if (reference1To0 == 1 && pair.cachedStrikeCurrent != strike) {
            int24 below = pair.bitMap1To0.nextBelow(strike);
            int24 above = pair.strikes[strike].next1To0;

            pair.strikes[below].next1To0 = above;
            pair.bitMap1To0.unset(strike);

            pair.strikes[strike].next1To0 = 0;
        }
    }
}
