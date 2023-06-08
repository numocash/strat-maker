// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv} from "./FullMath.sol";
import {getRatioAtTick, Q128} from "./TickMath.sol";

/// @notice Calculate amount0 delta when moving completely through the liquidity at the tick.
/// @dev Assumes inputs are valid
/// i.e. x = L/Pi
/// @custom:team Rounding needs to be checked
function getAmount0Delta(uint256 liquidity, int24 tick) pure returns (uint256 amount0) {
    return mulDiv(liquidity, Q128, getRatioAtTick(tick));
}

/// @notice Calculate amount1 delta when moving completely through the liquidity at the tick.
/// @dev Assumes inputs are valid
/// i.e. y = L
/// @custom:team Rounding needs to be checked
function getAmount1Delta(uint256 liquidity) pure returns (uint256 amount1) {
    return liquidity;
}

/// @notice Calculate amount0 in a tick for a given composition and liquidity
/// @custom:team check for overflow
function getAmount0FromComposition(
    uint128 composition,
    uint256 liquidity,
    uint256 ratioX128
)
    pure
    returns (uint256 amount0)
{
    return mulDiv(liquidity, (type(uint128).max - composition), ratioX128);
}

/// @notice Calculate amount0 in a tick for a given composition and liquidity
function getAmount1FromComposition(uint128 composition, uint256 liquidity) pure returns (uint256 amount1) {
    return mulDiv(liquidity, composition, Q128);
}

/// @notice Calculate amount{0,1} needed for the given liquidity change
/// @custom:team check for overflow on amount0
/// @custom:team check when we can use unchecked math
function calcAmountsForLiquidity(
    int24 tickCurrent,
    uint128 composition,
    int24 tick,
    uint256 liquidity
)
    pure
    returns (uint256 amount0, uint256 amount1)
{
    if (tick > tickCurrent) {
        return (getAmount0Delta(liquidity, tick), 0);
    } else if (tick < tickCurrent) {
        return (getAmount1Delta(liquidity), 0);
    } else {
        return (
            getAmount0FromComposition(composition, liquidity, getRatioAtTick(tick)),
            getAmount1FromComposition(composition, liquidity)
        );
    }
}

/// @notice Calculate max liquidity received if adding the given token amounts
function calcLiquidityForAmounts(
    int24 tickCurrent,
    uint128 composition,
    int24 tickLower,
    int24 tickUpper,
    uint256 amount0,
    uint256 amount1
)
    pure
    returns (uint256 liquidity)
{}

/// @notice Add signed liquidity delta to liquidity
function addDelta(uint256 x, int256 y) pure returns (uint256 z) {
    if (y < 0) {
        return x - uint256(-y);
    } else {
        return x + uint256(y);
    }
}
