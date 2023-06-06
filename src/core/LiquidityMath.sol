// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {getRatioAtTick, Q96, Q128, Q32} from "./TickMath.sol";
import {mulDiv} from "./FullMath.sol";

/// @notice Calculates the sum of a geometric series for positive ticks
/// @dev Use r = 1/1.0001
/// i.e. Sn = a1 (1 - r^n) / (1 - r)
/// @dev Takes advantage of the fact that getRatioAtTick(-n) == (1/1.0001)^n
function finiteGeoSeriesSumPos(uint256 a1, int24 n) pure returns (uint256 sum) {
    return 10_001 * (a1 - mulDiv(a1, getRatioAtTick(-n), Q128));
}

/// @notice Calculates the sum of a geometric series for negative ticks
/// @dev Use r = 1.0001
/// i.e. Sn = a1 (1 - r^n) / (1 - r)
/// @dev Takes advantage of the fact that getRatioAtTick(n) == 1.0001^n
function finiteGeoSeriesSumNeg(uint256 a1, int24 n) pure returns (uint256 sum) {
    return 10_000 * (mulDiv(a1, getRatioAtTick(n), Q128) - a1);
}

/// @notice Calculate amount0 delta when tick moves from tickLower to tickUpper.
/// @dev Assumes inputs are valid
/// i.e. x = ∑ L/Pi
/// @custom:team Rounding needs to be checked
function getAmount0Delta(int24 tickLower, int24 tickUpper, uint256 liquidity) pure returns (uint256 amount0) {
    if (tickLower >= 0) {
        return finiteGeoSeriesSumPos(mulDiv(liquidity, getRatioAtTick(tickLower), Q128), (tickUpper - tickLower) + 1);
    } else if (tickUpper <= 0) {
        return finiteGeoSeriesSumNeg(mulDiv(liquidity, getRatioAtTick(tickLower), Q128), (tickUpper - tickLower) + 1);
    } else {
        return finiteGeoSeriesSumPos(liquidity, tickUpper + 1) + finiteGeoSeriesSumNeg(liquidity, -tickLower + 1)
            - liquidity;
    }
}

/// @notice Calculate amount1 delta when tick moves from tickLower to tickUpper.
/// @dev Assumes inputs are valid
/// i.e. y = L
/// @custom:team Rounding needs to be checked
function getAmount1Delta(int24 tickLower, int24 tickUpper, uint256 liquidity) pure returns (uint256 amount1) {
    return liquidity * (uint24(tickUpper - tickLower) + 1);
}

/// @notice Calculate amount{0,1} needed for the given liquidity change
/// @custom:team check for overflow on amount0
function calcAmountsForLiquidity(
    int24 tickCurrent,
    uint96 composition,
    int24 tickLower,
    int24 tickUpper,
    uint256 liquidity
)
    pure
    returns (uint256 amount0, uint256 amount1)
{
    if (tickUpper < tickCurrent) {
        return (0, getAmount1Delta(tickLower, tickUpper, liquidity));
    } else if (tickLower > tickCurrent) {
        return (getAmount0Delta(tickLower, tickUpper, liquidity), 0);
    } else {
        amount0 = tickUpper != tickCurrent ? getAmount0Delta(tickCurrent + 1, tickUpper, liquidity) : 0;
        amount1 = tickLower != tickCurrent ? getAmount1Delta(tickLower, tickCurrent - 1, liquidity) : 0;

        amount0 += mulDiv(liquidity, (Q96 - composition) * Q32, getRatioAtTick(tickCurrent));
        amount1 += mulDiv(liquidity, composition, Q96);

        return (amount0, amount1);
    }
}

/// @notice Calculate max liquidity received if adding the given token amounts
function calcLiquidityForAmounts(
    int24 tickCurrent,
    uint96 composition,
    int24 tickLower,
    int24 tickUpper,
    uint256 amount0,
    uint256 amount1
)
    pure
    returns (uint256 liquidity)
{}

function addDelta(uint256 x, int256 y) pure returns (uint256 z) {
    if (y < 0) {
        require((z = x - uint256(-y)) < x, "LS");
    } else {
        require((z = x + uint256(y)) >= x, "LA");
    }
}
