// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {BitMaps} from "./BitMaps.sol";
import {mulDiv} from "./math/FullMath.sol";
import {toInt256} from "./math/LiquidityMath.sol";
import {getRatioAtStrike, MAX_STRIKE, MIN_STRIKE, Q128} from "./math/StrikeMath.sol";
import {computeSwapStep} from "./math/SwapMath.sol";

uint8 constant NUM_SPREADS = 5;

/// @title Pairs
/// @notice Library for managing a series of constant sum automated market makers with impliciting borrowing
/// @author Kyle Scott and Robert Leifke
library Pairs {
    using BitMaps for BitMaps.BitMap;

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 ERRORS
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    error Initialized();
    error InvalidSpread();
    error InvalidStrike();
    error OutOfBounds();
    error Overflow();

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               DATA TYPES
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Data for liquidity
    /// @param swap Liquidity that is available to be swapped
    /// @param borrowed Liquidity that is actively borrowed
    /// @dev Packs values into the same slot since they are commonly used together
    struct Liquidity {
        uint128 swap;
        uint128 borrowed;
    }

    /// @notice Data for liquidity repaid per unit of liquidity
    /// @dev Needed because solidity doesn't let you get storage pointers to value types
    struct LiquidityGrowth {
        uint256 liquidityGrowthX128;
    }

    /// @notice Data needed to represent a strike (constant sum automated market market with a fixed price)
    /// @param liquidityGrowthX128 Liquidity repaid per unit of borrowed liquidity
    /// @param liquidityGrowthSpreadX128 Liquidity repaid per unit of liquidty per spread
    /// @param liquidityRepayRateX128 Rate at which liquidity is repaid, summation of balance / multiplier for all
    /// positions
    /// @param liquidity Liquidity available
    /// @param blockLast The block where liquidity was accrued last
    /// @param next0To1 Strike where the next 0 to 1 swap is available, < this strike
    /// @param next1To0 Strike where the next 1 to 0 swap is available, > this strike
    /// @param reference0To1 Bitmap of spreads offering 0 to 1 swaps at the price of this strike
    /// @param reference1To0 Bitmap of spreads offering 1 to 0 swaps at the price of this strike
    /// @param activeSpread The spread index where liquidity is actively being borrowed from
    struct Strike {
        uint256 liquidityGrowthX128;
        uint256 liquidityRepayRateX128;
        LiquidityGrowth[NUM_SPREADS] liquidityGrowthSpreadX128;
        Liquidity[NUM_SPREADS] liquidity;
        uint184 blockLast;
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
    /// @param initialized True if the pair has been initialized
    struct Pair {
        mapping(int24 => Strike) strikes;
        BitMaps.BitMap bitMap0To1;
        BitMaps.BitMap bitMap1To0;
        uint128[NUM_SPREADS] composition;
        int24[NUM_SPREADS] strikeCurrent;
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

        unchecked {
            for (uint256 i = 0; i < NUM_SPREADS; i++) {
                pair.strikeCurrent[i] = strikeInitial;
            }
        }
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                   SWAP
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Intermediate data when calculating a swap
    /// @dev Needed to get rid of stack too deep errors
    /// @param liquiditySwap Amount of liquidity available to be swapped, accounting for direction
    /// @param liquidityTotal Amount of liquidity in the strikes that are being used for swapping
    /// @param liquidityRemaining Amount of liquidity remaining at the strike that wasn't used to swap
    /// @param liquiditySwapSpread Amount of liqudity per spread available to be swapped
    /// @param liquidityTotalSpread Amount of liquidity per spread being used to swap
    /// @param amountA Balance change of the token which `amountDesired` refers to
    /// @param amountB Balance change of the opposite token
    /// @param strike Swap is being offered at the price of this strike
    /// @param strikeStart First `strike` a swap was offered at
    /// @param spreadBitMap Bit map with positive representing a spread that is offering a swap at `strike`
    struct SwapState {
        uint256 liquiditySwap;
        uint256 liquidityTotal;
        uint256 liquidityRemaining;
        uint256[NUM_SPREADS] liquiditySwapSpread;
        uint256[NUM_SPREADS] liquidityTotalSpread;
        int256 amountA;
        int256 amountB;
        int24 strike;
        int24 strikeStart;
        uint8 spreadBitMap;
    }

    /// @notice Swap between the two tokens in the pair
    /// @param isToken0 True if amountDesired refers to token 0
    /// @param amountDesired The desired amount change on the pair
    /// @return amount0 The delta of the balance of token 0 of the pair
    /// @return amount1 The delta of the balance of token 1 of the pair
    /// @custom:team Account for liquidity growth
    function swap(Pair storage pair, bool isToken0, int256 amountDesired) internal returns (int256, int256) {
        if (!pair.initialized) revert Initialized();

        bool isSwap0To1 = isToken0 == (amountDesired > 0);

        // Find the closest strike offering a swap and set initial swap state
        SwapState memory state;
        unchecked {
            int24 _strikeCurrent = pair.strikeCurrent[0];
            int24 strike = isSwap0To1
                ? pair.strikes[-pair.bitMap0To1.nextBelow(-_strikeCurrent)].next0To1
                : pair.strikes[pair.bitMap1To0.nextBelow(_strikeCurrent)].next1To0;

            state.strike = strike;
            state.strikeStart = isSwap0To1 ? _strikeCurrent - 1 : _strikeCurrent + 1;
            state.spreadBitMap = isSwap0To1 ? pair.strikes[strike].reference0To1 : pair.strikes[strike].reference1To0;
        }

        unchecked {
            for (uint256 i = _lsb(state.spreadBitMap); i <= _msb(state.spreadBitMap); i++) {
                if ((state.spreadBitMap & (1 << i)) > 0) {
                    int24 spreadStrike =
                        isSwap0To1 ? state.strike + int24(uint24(i + 1)) : state.strike - int24(uint24(i + 1));

                    if (spreadStrike == pair.strikeCurrent[i]) {
                        uint256 liquidityTotal = pair.strikes[spreadStrike].liquidity[i].swap;
                        uint256 liquiditySwap = (
                            (isSwap0To1 ? type(uint128).max - pair.composition[i] : pair.composition[i])
                                * liquidityTotal
                        ) / Q128;

                        state.liquidityTotalSpread[i] = liquidityTotal;
                        state.liquiditySwapSpread[i] = liquiditySwap;
                        state.liquidityTotal += liquidityTotal;
                        state.liquiditySwap += liquiditySwap;
                    } else {
                        // mask bits below this spread
                        state.spreadBitMap &= uint8(1 << i) - 1;
                        break;
                    }
                }
            }
        }

        while (true) {
            {
                uint256 amountIn;
                uint256 amountOut;
                (amountIn, amountOut, state.liquidityRemaining) =
                    computeSwapStep(getRatioAtStrike(state.strike), state.liquiditySwap, isToken0, amountDesired);

                if (amountDesired > 0) {
                    // exact in, amountIn <= amountDesired
                    unchecked {
                        amountDesired -= int256(amountIn);
                        state.amountA += int256(amountIn);
                    }
                    state.amountB -= toInt256(amountOut);
                } else {
                    // exact out, amountOut <= -amountDesired
                    unchecked {
                        amountDesired += int256(amountOut);
                        state.amountA -= int256(amountOut);
                    }
                    state.amountB += toInt256(amountIn);
                }
            }

            // calculate and store liquidity gained from fees
            // fee is taken as a percentage of liquidity used
            unchecked {
                for (uint256 i = _lsb(state.spreadBitMap); i <= _msb(state.spreadBitMap); i++) {
                    if ((state.spreadBitMap & (1 << i)) > 0) {
                        int24 spreadStrike =
                            isSwap0To1 ? state.strike + int24(uint24(i + 1)) : state.strike - int24(uint24(i + 1));

                        uint256 _liquiditySwapSpread = state.liquiditySwapSpread[i];
                        uint256 liquidityRemainingSpread =
                            mulDiv(state.liquidityRemaining, _liquiditySwapSpread, state.liquidityTotal);
                        uint256 liquidityNew = ((i + 1) * (_liquiditySwapSpread - liquidityRemainingSpread)) / 1_000_000;

                        _updateLiqudityGrowth(
                            pair.strikes[spreadStrike].liquidityGrowthSpreadX128[i],
                            liquidityNew,
                            state.liquidityTotalSpread[i]
                        );
                    }
                }
            }

            // swap is finished
            if (amountDesired == 0) break;

            if (isSwap0To1) {
                // calculate the swap state for the next strike to the left
                int24 strikePrev = state.strike;
                if (strikePrev == MIN_STRIKE) revert OutOfBounds();

                state.strike = pair.strikes[strikePrev].next0To1;
                state.spreadBitMap = pair.strikes[state.strike].reference0To1;

                // Remove strike from linked list and bit map if it has no liquidity
                // Only happens when initialized or all liquidity is removed from current strike
                if (state.liquidityTotal == 0) {
                    int24 below = -pair.bitMap0To1.nextBelow(-strikePrev);
                    int24 above = pair.strikes[strikePrev].next0To1;

                    pair.strikes[below].next0To1 = above;
                    pair.bitMap0To1.unset(-strikePrev);

                    pair.strikes[strikePrev].next0To1 = 0;
                }

                state.liquiditySwap = 0;
                state.liquidityTotal = 0;

                unchecked {
                    for (uint256 i = _lsb(state.spreadBitMap); i <= _msb(state.spreadBitMap); i++) {
                        if ((state.spreadBitMap & (1 << i)) > 0) {
                            int24 spreadStrike = state.strike + int24(uint24(i + 1));
                            uint24 strikeDelta = uint24(state.strikeStart - state.strike);

                            if (i < strikeDelta) {
                                uint256 liquidity = pair.strikes[spreadStrike].liquidity[i].swap;

                                state.liquidityTotal += liquidity;
                                state.liquiditySwap += liquidity;
                                state.liquidityTotalSpread[i] = liquidity;
                                state.liquiditySwapSpread[i] = liquidity;
                            } else if (spreadStrike == pair.strikeCurrent[i]) {
                                uint256 composition = pair.composition[i];
                                uint256 liquidity = pair.strikes[spreadStrike].liquidity[i].swap;
                                uint256 liquiditySwap = (liquidity * composition) / Q128;

                                state.liquidityTotal += liquidity;
                                state.liquiditySwap += liquiditySwap;
                                state.liquidityTotalSpread[i] = liquidity;
                                state.liquiditySwapSpread[i] = liquiditySwap;
                            } else {
                                // mask bits below this spread
                                state.spreadBitMap &= uint8(1 << i) - 1;
                                break;
                            }
                        }
                    }
                }
            } else {
                // calculate the swap state for the next strike to the right
                int24 strikePrev = state.strike;
                if (strikePrev == MAX_STRIKE) revert OutOfBounds();

                state.strike = pair.strikes[strikePrev].next1To0;
                state.spreadBitMap = pair.strikes[state.strike].reference1To0;

                // Remove strike from linked list and bit map if it has no liquidity
                // Only happens when initialized or all liquidity is removed from current strike
                if (state.liquidityTotal == 0) {
                    int24 below = pair.bitMap1To0.nextBelow(strikePrev);
                    int24 above = pair.strikes[strikePrev].next1To0;

                    pair.strikes[below].next1To0 = above;
                    pair.bitMap1To0.unset(strikePrev);

                    pair.strikes[strikePrev].next1To0 = 0;
                }

                state.liquiditySwap = 0;
                state.liquidityTotal = 0;

                // Calculate the liquidity in the next tick and store it to state
                unchecked {
                    for (uint256 i = _lsb(state.spreadBitMap); i <= _msb(state.spreadBitMap); i++) {
                        if ((state.spreadBitMap & (1 << i)) > 0) {
                            int24 spreadStrike = state.strike - int24(uint24(i + 1));
                            uint24 strikeDelta = uint24(state.strike - state.strikeStart);

                            if (i < strikeDelta) {
                                uint256 liquidity = pair.strikes[spreadStrike].liquidity[i].swap;

                                state.liquidityTotal += liquidity;
                                state.liquiditySwap += liquidity;
                                state.liquidityTotalSpread[i] = liquidity;
                                state.liquiditySwapSpread[i] = liquidity;
                            } else if (spreadStrike == pair.strikeCurrent[i]) {
                                uint256 composition = type(uint128).max - pair.composition[i];
                                uint256 liquidity = pair.strikes[spreadStrike].liquidity[i].swap;
                                uint256 liquiditySwap = (liquidity * composition) / Q128;

                                state.liquidityTotal += liquidity;
                                state.liquiditySwap += liquiditySwap;
                                state.liquidityTotalSpread[i] = liquidity;
                                state.liquiditySwapSpread[i] = liquiditySwap;
                            } else {
                                // mask bits below this spread
                                state.spreadBitMap &= uint8(1 << i) - 1;
                                break;
                            }
                        }
                    }
                }
            }
        }

        // Save updated pair state to storage
        unchecked {
            if (isSwap0To1) {
                uint128 composition = uint128(mulDiv(state.liquidityRemaining, Q128, state.liquidityTotal));
                uint256 strikeDelta = uint24(state.strikeStart - state.strike);
                uint256 consecutiveSpreads = strikeDelta > NUM_SPREADS ? NUM_SPREADS : strikeDelta;
                uint8 msb = _msb(state.spreadBitMap);
                for (uint256 i = 0; i <= (msb > consecutiveSpreads ? msb : consecutiveSpreads); i++) {
                    pair.strikeCurrent[i] = state.strike + int24(uint24(i + 1));
                    pair.composition[i] = composition;
                }
            } else {
                uint128 composition =
                    type(uint128).max - uint128(mulDiv(state.liquidityRemaining, Q128, state.liquidityTotal));
                uint24 strikeDelta = uint24(state.strike - state.strikeStart);
                uint256 consecutiveSpreads = strikeDelta > NUM_SPREADS ? NUM_SPREADS : strikeDelta;
                uint8 msb = _msb(state.spreadBitMap);
                for (uint256 i = 0; i <= (msb > consecutiveSpreads ? msb : consecutiveSpreads); i++) {
                    pair.strikeCurrent[i] = state.strike - int24(uint24(i + 1));
                    pair.composition[i] = composition;
                }
            }
        }

        return isToken0 ? (state.amountA, state.amountB) : (state.amountB, state.amountA);
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                            LIQUIDITY LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Add liquidity to a specific strike
    /// @dev liquidity > 0
    function addSwapLiquidity(
        Pair storage pair,
        int24 strike,
        uint8 spread,
        uint128 liquidity
    )
        internal
        returns (uint128)
    {
        unchecked {
            if (!pair.initialized) revert Initialized();
            _checkSpread(spread);

            uint256 existingLiquidity = pair.strikes[strike].liquidity[spread - 1].swap;
            uint256 borrowedLiquidity = pair.strikes[strike].liquidity[spread - 1].borrowed;

            if (existingLiquidity + borrowedLiquidity + uint256(liquidity) > type(uint128).max) revert Overflow();

            if (spread - 1 < pair.strikes[strike].activeSpread) {
                pair.strikes[strike].liquidity[spread - 1].borrowed = uint128(borrowedLiquidity) + liquidity;

                return liquidity;
            } else {
                pair.strikes[strike].liquidity[spread - 1].swap = uint128(existingLiquidity) + liquidity;

                int24 strike0To1 = strike - int8(spread);
                int24 strike1To0 = strike + int8(spread);

                _checkStrike(strike0To1);
                _checkStrike(strike1To0);

                if (existingLiquidity == 0) {
                    int24 _strikeCurrent = pair.strikeCurrent[0];
                    _addStrike0To1(pair, strike0To1, spread, _strikeCurrent == strike0To1);
                    _addStrike1To0(pair, strike1To0, spread, _strikeCurrent == strike1To0);
                }

                return 0;
            }
        }
    }

    /// @notice Remove liquidity from a specific strike
    /// @dev liquidity > 0
    /// @custom:team Check removing more liquidity than is available
    function removeSwapLiquidity(
        Pair storage pair,
        int24 strike,
        uint8 spread,
        uint128 liquidity
    )
        internal
        returns (uint128)
    {
        unchecked {
            if (!pair.initialized) revert Initialized();
            _checkSpread(spread);

            uint256 _activeSpread = pair.strikes[strike].activeSpread;

            if (spread - 1 < _activeSpread) {
                // all liquidity is borrowed
                pair.strikes[strike].liquidity[spread - 1].borrowed -= liquidity;

                return liquidity;
            } else {
                uint128 existingLiquidity = pair.strikes[strike].liquidity[spread - 1].swap;

                if (liquidity < existingLiquidity) {
                    // enough liquidity to just remove swap liquiidty
                    pair.strikes[strike].liquidity[spread - 1].swap = existingLiquidity - liquidity;
                    return 0;
                } else {
                    // remove all swap liquidity first, then borrowed liquidity

                    {
                        // remove strikes from strike list
                        int24 strike0To1 = strike - int8(spread);
                        int24 strike1To0 = strike + int8(spread);

                        int24 _strikeCurrent = pair.strikeCurrent[0];
                        _removeStrike0To1(pair, strike0To1, spread, _strikeCurrent == strike0To1);
                        _removeStrike1To0(pair, strike1To0, spread, _strikeCurrent == strike1To0);
                    }

                    uint128 remainingLiquidity = liquidity - existingLiquidity;

                    pair.strikes[strike].liquidity[spread - 1].swap = 0;
                    pair.strikes[strike].liquidity[spread - 1].borrowed -= remainingLiquidity;

                    return remainingLiquidity;
                }
            }
        }
    }

    /// @notice Borrow liquidity from a specific strike
    /// @custom:team Should this lazily go to the next spread or not
    /// @custom:team Should we charge 1 block on borrowing liquidity
    function addBorrowedLiquidity(Pair storage pair, int24 strike, uint136 liquidity) internal {
        unchecked {
            if (!pair.initialized) revert Initialized();

            Strike storage strikeObj = pair.strikes[strike];
            uint8 _activeSpread = strikeObj.activeSpread;

            while (true) {
                uint128 availableLiquidity = strikeObj.liquidity[_activeSpread].swap;

                if (availableLiquidity >= liquidity) {
                    strikeObj.liquidity[_activeSpread].swap = availableLiquidity - uint128(liquidity);
                    strikeObj.liquidity[_activeSpread].borrowed += uint128(liquidity);

                    break;
                }

                if (availableLiquidity > 0) {
                    // update current spread
                    strikeObj.liquidity[_activeSpread].swap = 0;
                    strikeObj.liquidity[_activeSpread].borrowed += availableLiquidity;
                    liquidity -= availableLiquidity;

                    // remove spread from strike order
                    int24 strike0To1 = strike - int8(_activeSpread + 1);
                    int24 strike1To0 = strike + int8(_activeSpread + 1);

                    int24 _strikeCurrent = pair.strikeCurrent[0];
                    _removeStrike0To1(pair, strike0To1, _activeSpread + 1, _strikeCurrent == strike0To1);
                    _removeStrike1To0(pair, strike1To0, _activeSpread + 1, _strikeCurrent == strike1To0);
                }

                // move to next spread
                _activeSpread++;
                if (_activeSpread >= NUM_SPREADS) revert OutOfBounds();
            }

            strikeObj.activeSpread = _activeSpread;
        }
    }

    /// @notice Repay liquidity to a specific strike
    function removeBorrowedLiquidity(Pair storage pair, int24 strike, uint136 liquidity) internal {
        unchecked {
            if (!pair.initialized) revert Initialized();

            Strike storage strikeObj = pair.strikes[strike];
            uint8 _activeSpread = strikeObj.activeSpread;

            while (true) {
                uint128 borrowedLiquidity = strikeObj.liquidity[_activeSpread].borrowed;

                if (borrowedLiquidity >= liquidity) {
                    strikeObj.liquidity[_activeSpread].swap += uint128(liquidity);
                    strikeObj.liquidity[_activeSpread].borrowed = borrowedLiquidity - uint128(liquidity);

                    break;
                }

                if (borrowedLiquidity > 0) {
                    // update current spread
                    strikeObj.liquidity[_activeSpread].swap += borrowedLiquidity;
                    strikeObj.liquidity[_activeSpread].borrowed = 0;
                    liquidity -= borrowedLiquidity;

                    // add next spread into strike order
                    // subtract 1 from spread implicitly
                    int24 strike0To1 = strike - int8(_activeSpread);
                    int24 strike1To0 = strike + int8(_activeSpread);

                    int24 _strikeCurrent = pair.strikeCurrent[0];
                    _addStrike0To1(pair, strike0To1, _activeSpread, _strikeCurrent == strike0To1);
                    _addStrike1To0(pair, strike1To0, _activeSpread, _strikeCurrent == strike1To0);
                }

                // move to next spread
                if (_activeSpread == 0) revert OutOfBounds();
                _activeSpread--;
            }

            strikeObj.activeSpread = _activeSpread;
        }
    }

    /// @notice Accrue liquidity for a strike and return the amount of liquidity that must be repaid
    /// @custom:team How to handle overflow
    /// @custom:team Need to update to only accrue a maximum amount in order to cap leverage
    function accrue(Pair storage pair, int24 strike) internal returns (uint136) {
        unchecked {
            if (!pair.initialized) revert Initialized();

            uint256 _blockLast = pair.strikes[strike].blockLast;
            uint256 blocks = block.number - _blockLast;
            if (blocks == 0) return 0;
            pair.strikes[strike].blockLast = uint184(block.number);

            uint256 liquidityAccrued;
            uint256 liquidityBorrowedTotal;
            for (uint256 i = 0; i <= pair.strikes[strike].activeSpread; i++) {
                uint128 liquidityBorrowed = pair.strikes[strike].liquidity[i].borrowed;
                uint128 liquiditySwap = pair.strikes[strike].liquidity[i].swap;

                if (liquidityBorrowed > 0) {
                    // can only overflow when (i + 1) * blocks > type(uint128).max
                    uint256 fee = (i + 1) * blocks;
                    uint256 liquidityAccruedSpread =
                        fee >= 2_000_000 ? liquidityBorrowed : (fee * uint256(liquidityBorrowed)) / 2_000_000;

                    liquidityAccrued += liquidityAccruedSpread;
                    liquidityBorrowedTotal += liquidityBorrowed;

                    _updateLiqudityGrowth(
                        pair.strikes[strike].liquidityGrowthSpreadX128[i],
                        liquidityAccruedSpread,
                        liquidityBorrowed + liquiditySwap
                    );
                }
            }

            if (liquidityAccrued == 0) return 0;

            // update liqudity growth
            pair.strikes[strike].liquidityGrowthX128 += mulDiv(liquidityAccrued, Q128, liquidityBorrowedTotal);

            return uint136(mulDiv(pair.strikes[strike].liquidityRepayRateX128, liquidityAccrued, Q128));
        }
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                             INTERNAL LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    function _msb(uint8 x) private pure returns (uint8 r) {
        unchecked {
            if (x >= 0x10) {
                x >>= 4;
                r += 4;
            }
            if (x >= 0x4) {
                x >>= 2;
                r += 2;
            }
            if (x >= 0x2) r += 1;
        }
    }

    function _lsb(uint8 x) private pure returns (uint8 r) {
        unchecked {
            r = 7;

            if (x & 0xf > 0) {
                r -= 4;
            } else {
                x >>= 4;
            }
            if (x & 0x3 > 0) {
                r -= 2;
            } else {
                x >>= 2;
            }
            if (x & 0x1 > 0) r -= 1;
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
        if (spread == 0 || spread > NUM_SPREADS) revert InvalidSpread();
    }

    /// @notice Computes and stores the amount of liquidity paid per unit of liquidity
    function _updateLiqudityGrowth(
        LiquidityGrowth storage liquidityGrowth,
        uint256 liquidityPaid,
        uint256 liquidity
    )
        private
    {
        uint256 _liquidityGrowthX128 = liquidityGrowth.liquidityGrowthX128;
        if (_liquidityGrowthX128 == 0) {
            liquidityGrowth.liquidityGrowthX128 = Q128 + mulDiv(liquidityPaid, Q128, liquidity);
        } else {
            // realistically cannot overflow
            liquidityGrowth.liquidityGrowthX128 = _liquidityGrowthX128 + mulDiv(liquidityPaid, Q128, liquidity);
        }
    }

    function _addStrike0To1(Pair storage pair, int24 strike, uint8 spread, bool preserve) private {
        uint8 reference0To1 = pair.strikes[strike].reference0To1;
        unchecked {
            pair.strikes[strike].reference0To1 = reference0To1 | uint8(1 << (spread - 1));
        }

        if (!preserve && reference0To1 == 0) {
            int24 below = -pair.bitMap0To1.nextBelow(-strike);
            int24 above = pair.strikes[below].next0To1;

            pair.strikes[strike].next0To1 = above;
            pair.strikes[below].next0To1 = strike;
            pair.bitMap0To1.set(-strike);
        }
    }

    function _addStrike1To0(Pair storage pair, int24 strike, uint8 spread, bool preserve) private {
        uint8 reference1To0 = pair.strikes[strike].reference1To0;
        unchecked {
            pair.strikes[strike].reference1To0 = reference1To0 | uint8(1 << (spread - 1));
        }

        if (!preserve && reference1To0 == 0) {
            int24 below = pair.bitMap1To0.nextBelow(strike);
            int24 above = pair.strikes[below].next1To0;

            pair.strikes[strike].next1To0 = above;
            pair.strikes[below].next1To0 = strike;
            pair.bitMap1To0.set(strike);
        }
    }

    function _removeStrike0To1(Pair storage pair, int24 strike, uint8 spread, bool preserve) private {
        uint8 reference0To1 = pair.strikes[strike].reference0To1;
        unchecked {
            reference0To1 &= ~uint8(1 << (spread - 1));
            pair.strikes[strike].reference0To1 = reference0To1;
        }

        if (!preserve && reference0To1 == 0) {
            int24 below = -pair.bitMap0To1.nextBelow(-strike);
            int24 above = pair.strikes[strike].next0To1;

            pair.strikes[below].next0To1 = above;
            pair.bitMap0To1.unset(-strike);

            pair.strikes[strike].next0To1 = 0;
        }
    }

    function _removeStrike1To0(Pair storage pair, int24 strike, uint8 spread, bool preserve) private {
        uint8 reference1To0 = pair.strikes[strike].reference1To0;
        unchecked {
            reference1To0 &= ~uint8(1 << (spread - 1));
            pair.strikes[strike].reference1To0 = reference1To0;
        }

        if (!preserve && reference1To0 == 0) {
            int24 below = pair.bitMap1To0.nextBelow(strike);
            int24 above = pair.strikes[strike].next1To0;

            pair.strikes[below].next1To0 = above;
            pair.bitMap1To0.unset(strike);

            pair.strikes[strike].next1To0 = 0;
        }
    }
}
