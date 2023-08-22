// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {BitMaps} from "./BitMaps.sol";
import {mulDiv, mulDivRoundingUp} from "./math/FullMath.sol";
import {
    getLiquidityForAmount0,
    getLiquidityForAmount1,
    scaleLiquidityDown,
    addDelta,
    toInt256
} from "./math/LiquidityMath.sol";
import {getRatioAtStrike, MAX_STRIKE, MIN_STRIKE, Q128} from "./math/StrikeMath.sol";
import {computeSwapStep} from "./math/SwapMath.sol";

uint8 constant NUM_SPREADS = 5;
int8 constant MAX_CONSECUTIVE = int8(NUM_SPREADS);

/// @title Pairs
/// @notice Library for managing a concentrated liquidity, constant sum automated market maker with impliciting
/// borrowing
/// @author Robert Leifke and Kyle Scott
/// @custom:team change what strikeCurrentCached represents to better handle flip flop trades
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

    /// @notice Data needed to represent a strike (constant sum automated market market with a fixed price)
    /// @param liquidityGrowthX128 Liquidity repaid per unit of liquidty
    /// @param blockLast The block where liquidity was accrued last
    /// @param liquidityGrowthSpreadX128 Liquidity repaid per unit of liquidty per spread
    /// @param liquidityBiDirectional Liquidity available to be swapper per spread
    /// @param liquidityBorrowed Liquidity borrowed per spread
    /// @param next0To1 Strike where the next 0 to 1 swap is available, < this strike
    /// @param next1To0 Strike where the next 1 to 0 swap is available, > this strike
    /// @param reference0To1 Number of spreads offering 0 to 1 swaps referencing this strike
    /// @param reference1To0 Number of spreads offering 1 to 0 swaps referencing this strike
    /// @param activeSpread The spread index where liquidity is actively being borrowed from
    /// @custom:team could we make reference a bitmap
    struct Strike {
        uint256 liquidityGrowthX128;
        uint256 blockLast;
        uint128[NUM_SPREADS] liquidityGrowthSpreadX128;
        uint128[NUM_SPREADS] liquidityBiDirectional;
        uint128[NUM_SPREADS] liquidityBorrowed;
        int24 next0To1;
        int24 next1To0;
        uint8 reference0To1;
        uint8 reference1To0;
        uint8 activeSpread;
    }

    /// @notice Data needed to represent a pair
    /// @param strikes Strike index to `Strike`
    /// @param bitMap0To1 Bit map of strikes supporting 0 to 1 swaps
    /// @param bitMap1To0 Bit map of strikes supporting 1 to 0 swaps
    /// @param composition Percentage of liquidity held in token 1 per spread
    /// @param strikeCurrent Active strike index per spread
    /// @param strikeCurrentCached Strike index that was last used for a swap
    /// @param initialized True if the pair has been initialized
    struct Pair {
        mapping(int24 => Strike) strikes;
        BitMaps.BitMap bitMap0To1;
        BitMaps.BitMap bitMap1To0;
        uint128[NUM_SPREADS] composition;
        int24[NUM_SPREADS] strikeCurrent;
        int24 strikeCurrentCached;
        bool initialized;
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                GET LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Return the unique identfier for the described pair
    function getPairID(address token0, address token1, uint8 scalingFactor) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token0, token1, scalingFactor));
    }

    /// @notice Return the unique identifier and reference to the described pair
    function getPairAndID(
        mapping(bytes32 => Pair) storage pairs,
        address token0,
        address token1,
        uint8 scalingFactor
    )
        internal
        view
        returns (bytes32 pairID, Pair storage pair)
    {
        pairID = getPairID(token0, token1, scalingFactor);
        pair = pairs[pairID];
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                              INITIALIZATION
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Initialize the pair by setting the initial strike
    function initialize(Pair storage pair, int24 strikeInitial) internal {
        if (pair.initialized) revert Initialized();

        _checkStrike(strikeInitial);

        pair.strikeCurrentCached = strikeInitial;
        pair.initialized = true;

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
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                   SWAP
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Struct to hold temporary data while completing a swap
    struct SwapState {
        int24[NUM_SPREADS] strikeCurrent;
        int24 strikeCurrentCached;
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
    function swap(
        Pair storage pair,
        uint8 scalingFactor,
        bool isToken0,
        int256 amountDesired
    )
        internal
        returns (int256, int256)
    {
        if (!pair.initialized) revert Initialized();
        bool isSwap0To1 = isToken0 == amountDesired > 0;

        SwapState memory state;
        state.strikeCurrent = pair.strikeCurrent;
        state.strikeCurrentCached = pair.strikeCurrentCached;

        // calculate liquiditySwap and liquidityTotal
        unchecked {
            for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                int24 activeStrike = isSwap0To1
                    ? state.strikeCurrentCached + int24(int256(i))
                    : state.strikeCurrentCached - int24(int256(i));
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
            uint256 ratioX128 = getRatioAtStrike(state.strikeCurrentCached);
            {
                uint256 liquidityRemaining;
                {
                    uint256 amountIn;
                    uint256 amountOut;
                    (amountIn, amountOut, liquidityRemaining) =
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
                    unchecked {
                        if (isSwap0To1) {
                            if (state.liquiditySwap > 0) {
                                for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                                    int24 activeStrike = state.strikeCurrentCached + int24(int256(i));

                                    if (activeStrike == state.strikeCurrent[i - 1]) {
                                        uint256 liquidityNew = getLiquidityForAmount0(
                                            mulDiv(
                                                state.liquiditySwapSpread[i - 1],
                                                amountIn * i,
                                                state.liquiditySwap * 10_000
                                            ),
                                            ratioX128
                                        );
                                        pair.strikes[activeStrike].liquidityBiDirectional[i - 1] +=
                                            scaleLiquidityDown(liquidityNew, scalingFactor);
                                        state.liquidityTotal += liquidityNew;
                                    } else {
                                        break;
                                    }
                                }
                            }
                        } else {
                            if (state.liquiditySwap > 0) {
                                for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                                    int24 activeStrike = state.strikeCurrentCached - int24(int256(i));

                                    if (activeStrike == state.strikeCurrent[i - 1]) {
                                        uint256 liquidityNew = getLiquidityForAmount1(
                                            mulDiv(
                                                state.liquiditySwapSpread[i - 1],
                                                amountIn * i,
                                                state.liquiditySwap * 10_000
                                            )
                                        );
                                        pair.strikes[activeStrike].liquidityBiDirectional[i - 1] +=
                                            scaleLiquidityDown(liquidityNew, scalingFactor);
                                        state.liquidityTotal += liquidityNew;
                                    } else {
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }

                if (amountDesired == 0) {
                    if (isSwap0To1) {
                        uint128 composition = uint128(mulDiv(liquidityRemaining, Q128, state.liquidityTotal));

                        unchecked {
                            for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                                int24 activeStrike = state.strikeCurrentCached + int24(int256(i));
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
                            type(uint128).max - uint128(mulDiv(liquidityRemaining, Q128, state.liquidityTotal));

                        unchecked {
                            for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                                int24 activeStrike = state.strikeCurrentCached - int24(int256(i));
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
            }

            if (isSwap0To1) {
                int24 strikePrev = state.strikeCurrentCached;
                if (strikePrev == MIN_STRIKE) revert OutOfBounds();

                // move state vars to the next strike
                state.strikeCurrentCached = pair.strikes[strikePrev].next0To1;
                state.liquiditySwap = 0;
                state.liquidityTotal = 0;

                // Remove strike from linked list and bit map if it has no liquidity
                // Only happens when initialized or all liquidity is removed from current strike
                if (state.liquidityTotal == 0) _removeStrike0To1(pair, strikePrev, false);

                unchecked {
                    for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                        int24 activeStrike = state.strikeCurrentCached + int24(int256(i));
                        // only update if it was active previously
                        if (state.strikeCurrent[i - 1] > activeStrike) {
                            state.strikeCurrent[i - 1] = activeStrike;

                            uint256 liquidity = pair.strikes[activeStrike].liquidityBiDirectional[i - 1];

                            state.liquidityTotal += liquidity;
                            state.liquiditySwap += liquidity;
                            state.liquidityTotalSpread[i - 1] = liquidity;
                            state.liquiditySwapSpread[i - 1] = liquidity;
                            // TODO: can liquiditySpread ever have dirty bits
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
                int24 strikePrev = state.strikeCurrentCached;
                if (strikePrev == MAX_STRIKE) revert OutOfBounds();

                // move state vars to the next strike
                state.strikeCurrentCached = pair.strikes[strikePrev].next1To0;
                state.liquiditySwap = 0;
                state.liquidityTotal = 0;

                // Remove strike from linked list and bit map if it has no liquidity
                // Only happens when initialized or all liquidity is removed from current strike
                if (state.liquidityTotal == 0) _removeStrike1To0(pair, strikePrev, false);

                unchecked {
                    for (uint256 i = 1; i <= NUM_SPREADS; i++) {
                        int24 activeStrike = state.strikeCurrentCached - int24(int256(i));

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
        pair.strikeCurrentCached = state.strikeCurrentCached;
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

    /// @notice Add or remove liquidity from a specific strike
    /// @custom:team What if liquidity is added or removed below the active strike
    /// @custom:team Does liquidity need to be accrued?
    function updateStrike(Pair storage pair, int24 strike, uint8 spread, int128 liquidity) internal {
        unchecked {
            if (!pair.initialized) revert Initialized();
            _checkSpread(spread);

            int24 strike0To1 = strike - int8(spread);
            int24 strike1To0 = strike + int8(spread);

            _checkStrike(strike0To1);
            _checkStrike(strike1To0);

            uint128 existingLiquidity = pair.strikes[strike].liquidityBiDirectional[spread - 1];
            pair.strikes[strike].liquidityBiDirectional[spread - 1] = addDelta(existingLiquidity, liquidity);

            if (existingLiquidity == 0 && liquidity > 0) {
                int24 _strikeCurrentCached = pair.strikeCurrentCached;
                _addStrike0To1(pair, strike0To1, _strikeCurrentCached == strike0To1);
                _addStrike1To0(pair, strike1To0, _strikeCurrentCached == strike1To0);
            } else if (liquidity < 0 && existingLiquidity == uint128(-liquidity)) {
                int24 _strikeCurrentCached = pair.strikeCurrentCached;
                _removeStrike0To1(pair, strike0To1, _strikeCurrentCached == strike0To1);
                _removeStrike1To0(pair, strike1To0, _strikeCurrentCached == strike1To0);
            }
        }
    }

    /// @notice Borrow liquidity from a specific strike
    /// @return liquidityToken0 The amount of liquidity removed in token 0
    /// @return liquidityToken1 The amount of liquidity removed in token 1
    /// @custom:team liquidityBorrowed + liquidityBiDirectional should be less than type(uint128).max
    /// @custom:team Need to figure out the liqudity borrowed composition
    /// @custom:team What does strikeCachedCurrent represent
    /// @custom:team Should this lazily go to the next spread or not
    function borrowLiquidity(
        Pair storage pair,
        int24 strike,
        uint128 liquidity
    )
        internal
        returns (uint128 liquidityToken0, uint128 liquidityToken1)
    {
        unchecked {
            if (!pair.initialized) revert Initialized();

            Strike storage strikeObj = pair.strikes[strike];
            uint8 _activeSpread = strikeObj.activeSpread;

            while (true) {
                uint128 availableLiquidity = strikeObj.liquidityBiDirectional[_activeSpread];

                if (availableLiquidity >= liquidity) {
                    strikeObj.liquidityBiDirectional[_activeSpread] = availableLiquidity - liquidity;
                    strikeObj.liquidityBorrowed[_activeSpread] += liquidity;

                    break;
                }

                if (availableLiquidity > 0) {
                    // update current spread
                    strikeObj.liquidityBiDirectional[_activeSpread] = 0;
                    strikeObj.liquidityBorrowed[_activeSpread] += availableLiquidity;
                    liquidity -= availableLiquidity;

                    // remove spread from strike order
                    int24 strike0To1 = strike - int8(_activeSpread + 1);
                    int24 strike1To0 = strike + int8(_activeSpread + 1);

                    int24 _strikeCurrentCached = pair.strikeCurrentCached;
                    _removeStrike0To1(pair, strike0To1, _strikeCurrentCached == strike0To1);
                    _removeStrike1To0(pair, strike1To0, _strikeCurrentCached == strike1To0);
                }

                // move to next spread
                _activeSpread++;
                if (_activeSpread >= NUM_SPREADS) revert OutOfBounds();
            }

            strikeObj.activeSpread = _activeSpread;
        }
    }

    /// @notice Repay liquidity to a specific strike
    function repayLiquidity(Pair storage pair, int24 strike, uint128 liquidity) internal {
        unchecked {
            if (!pair.initialized) revert Initialized();

            Strike storage strikeObj = pair.strikes[strike];
            uint8 _activeSpread = strikeObj.activeSpread;

            while (true) {
                uint128 borrowedLiquidity = strikeObj.liquidityBorrowed[_activeSpread];

                if (borrowedLiquidity >= liquidity) {
                    strikeObj.liquidityBiDirectional[_activeSpread] += liquidity;
                    strikeObj.liquidityBorrowed[_activeSpread] = borrowedLiquidity - liquidity;

                    break;
                }

                if (borrowedLiquidity > 0) {
                    // update current spread
                    strikeObj.liquidityBiDirectional[_activeSpread] += borrowedLiquidity;
                    strikeObj.liquidityBorrowed[_activeSpread] = 0;
                    liquidity -= borrowedLiquidity;

                    // add next spread into strike order
                    // subtract 1 from spread implicitly
                    int24 strike0To1 = strike - int8(_activeSpread);
                    int24 strike1To0 = strike + int8(_activeSpread);

                    int24 _strikeCurrentCached = pair.strikeCurrentCached;
                    _addStrike0To1(pair, strike0To1, _strikeCurrentCached == strike0To1);
                    _addStrike1To0(pair, strike1To0, _strikeCurrentCached == strike1To0);
                }

                // move to next spread
                if (_activeSpread == 0) revert OutOfBounds();
                _activeSpread--;
            }

            strikeObj.activeSpread = _activeSpread;
        }
    }

    function accrue(Pair storage pair, int24 strike) internal {
        uint256 _blockLast = pair.strikes[strike].blockLast;
        uint256 blocks = block.number - _blockLast;
        if (blocks == 0) return;

        uint128 liquidityRepaid;
        uint128 liquidityBorrowedTotal;

        for (uint256 i = 0; i <= pair.strikes[strike].activeSpread; i++) {
            uint128 liquidityBorrowed = pair.strikes[strike].liquidityBorrowed[i];

            uint128 spreadGrowth = uint128(((i + 1) * blocks * liquidityBorrowed) / 10_000);

            pair.strikes[strike].liquidityBiDirectional[i] += spreadGrowth; // think this is wrong
            liquidityRepaid += spreadGrowth;
            liquidityBorrowedTotal += liquidityBorrowed;
        }

        if (liquidityRepaid == 0) return;

        // pair.strikes[strike].liquidityGrowthExpX128 = mulDivRoundingUp(
        //     pair.strikes[strike].liquidityGrowthExpX128 + Q128,
        //     liquidityBorrowedTotal,
        //     liquidityBorrowedTotal - liquidityRepaid
        // ) - Q128; // think this is wrong

        repayLiquidity(pair, strike, liquidityRepaid);
        pair.strikes[strike].blockLast = block.number;
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
        if (spread == 0 || spread > NUM_SPREADS) revert InvalidSpread();
    }

    function _addStrike0To1(Pair storage pair, int24 strike, bool preserve) private {
        uint8 reference0To1 = pair.strikes[strike].reference0To1;
        unchecked {
            pair.strikes[strike].reference0To1 = reference0To1 + 1;
        }

        if (!preserve && reference0To1 == 0) {
            int24 below = -pair.bitMap0To1.nextBelow(-strike);
            int24 above = pair.strikes[below].next0To1;

            pair.strikes[strike].next0To1 = above;
            pair.strikes[below].next0To1 = strike;
            pair.bitMap0To1.set(-strike);
        }
    }

    function _addStrike1To0(Pair storage pair, int24 strike, bool preserve) private {
        uint8 reference1To0 = pair.strikes[strike].reference1To0;
        unchecked {
            pair.strikes[strike].reference1To0 = reference1To0 + 1;
        }

        if (!preserve && reference1To0 == 0) {
            int24 below = pair.bitMap1To0.nextBelow(strike);
            int24 above = pair.strikes[below].next1To0;

            pair.strikes[strike].next1To0 = above;
            pair.strikes[below].next1To0 = strike;
            pair.bitMap1To0.set(strike);
        }
    }

    function _removeStrike0To1(Pair storage pair, int24 strike, bool preserve) private {
        uint8 reference0To1 = pair.strikes[strike].reference0To1;
        unchecked {
            pair.strikes[strike].reference0To1 = reference0To1 - 1;
        }

        if (!preserve && reference0To1 == 1) {
            int24 below = -pair.bitMap0To1.nextBelow(-strike);
            int24 above = pair.strikes[strike].next0To1;

            pair.strikes[below].next0To1 = above;
            pair.bitMap0To1.unset(-strike);

            pair.strikes[strike].next0To1 = 0;
        }
    }

    function _removeStrike1To0(Pair storage pair, int24 strike, bool preserve) private {
        uint8 reference1To0 = pair.strikes[strike].reference1To0;
        unchecked {
            pair.strikes[strike].reference1To0 = reference1To0 - 1;
        }

        if (!preserve && reference1To0 == 1) {
            int24 below = pair.bitMap1To0.nextBelow(strike);
            int24 above = pair.strikes[strike].next1To0;

            pair.strikes[below].next1To0 = above;
            pair.bitMap1To0.unset(strike);

            pair.strikes[strike].next1To0 = 0;
        }
    }
}
