// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {getRatioAtStrike, Q128} from "./StrikeMath.sol";

/// @notice Calculate amount0 delta when moving completely through the liquidity at the strike.
/// @dev Assumes inputs are valid
/// i.e. x = L/Pi
function getAmount0Delta(uint256 liquidity, int24 strike, bool roundUp) pure returns (uint256 amount0) {
    return roundUp
        ? mulDivRoundingUp(liquidity, Q128, getRatioAtStrike(strike))
        : mulDiv(liquidity, Q128, getRatioAtStrike(strike));
}

/// @notice Calculate amount1 delta when moving completely through the liquidity at the strike.
/// @dev Assumes inputs are valid
/// i.e. y = L
function getAmount1Delta(uint256 liquidity) pure returns (uint256 amount1) {
    return liquidity;
}

/// @notice Calculate amount0 in a strike for a given composition and liquidity
/// @custom:team This rounds down extra because composition is between 0 and uint128Max while ratio is scaled by
/// uint128Max + 1
function getAmount0FromComposition(
    uint128 composition,
    uint256 liquidity,
    uint256 ratioX128,
    bool roundUp
)
    pure
    returns (uint256 amount0)
{
    uint128 token0Composition;
    unchecked {
        token0Composition = type(uint128).max - composition;
    }

    return roundUp
        ? mulDivRoundingUp(liquidity, token0Composition, ratioX128)
        : mulDiv(liquidity, token0Composition, ratioX128);
}

/// @notice Calculate amount0 in a strike for a given composition and liquidity
function getAmount1FromComposition(
    uint128 composition,
    uint256 liquidity,
    bool roundUp
)
    pure
    returns (uint256 amount1)
{
    return roundUp ? mulDivRoundingUp(liquidity, composition, Q128) : mulDiv(liquidity, composition, Q128);
}

/// @notice Calculate amount{0,1} needed for the given liquidity change
function calcAmountsForLiquidity(
    int24 strikeCurrent,
    uint128 composition,
    int24 strike,
    uint256 liquidity,
    bool roundUp
)
    pure
    returns (uint256 amount0, uint256 amount1)
{
    if (strike > strikeCurrent) {
        return (getAmount0Delta(liquidity, strike, roundUp), 0);
    } else if (strike < strikeCurrent) {
        return (0, getAmount1Delta(liquidity));
    } else {
        return (
            getAmount0FromComposition(composition, liquidity, getRatioAtStrike(strike), roundUp),
            getAmount1FromComposition(composition, liquidity, roundUp)
        );
    }
}

/// @notice Calculate max liquidity received if adding the given token amounts
function calcLiquidityForAmounts(
    int24 strikeCurrent,
    uint128 composition,
    int24 strike,
    uint256 amount0,
    uint256 amount1,
    bool roundUp
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

/// @notice cast uint256 to int256, revert on overflow
function toInt256(uint256 x) pure returns (int256 z) {
    assert(x <= uint256(type(int256).max));
    z = int256(x);
}
