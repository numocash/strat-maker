// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {getRatioAtStrike, Q128} from "./StrikeMath.sol";
import {Pairs} from "../Pairs.sol";

/// @notice Calculate amount0 delta when moving completely through the liquidity at the strike.
/// i.e. x = L / Pi
function getAmount0Delta(uint256 liquidity, int24 strike, bool roundUp) pure returns (uint256 amount0) {
    return roundUp
        ? mulDivRoundingUp(liquidity, Q128, getRatioAtStrike(strike))
        : mulDiv(liquidity, Q128, getRatioAtStrike(strike));
}

/// @notice Calculate amount1 delta when moving completely through the liquidity at the strike.
/// i.e. y = L
function getAmount1Delta(uint256 liquidity) pure returns (uint256 amount1) {
    return liquidity;
}

/// @notice Calculate liquidity for amount0
/// i.e. L = x * Pi
function getLiquidityDeltaAmount0(uint256 amount0, int24 strike, bool roundUp) pure returns (uint256 liquidity) {
    return roundUp
        ? mulDivRoundingUp(amount0, getRatioAtStrike(strike), Q128)
        : mulDiv(amount0, getRatioAtStrike(strike), Q128);
}

/// @notice Calculate liquidity for amount1
/// i.e. L = y
function getLiquidityDeltaAmount1(uint256 amount1) pure returns (uint256 liquidity) {
    return amount1;
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
function getAmountsForLiquidity(
    Pairs.Pair storage pair,
    int24 strike,
    uint8 spread,
    uint256 liquidity,
    bool roundUp
)
    view
    returns (uint256 amount0, uint256 amount1)
{
    int24 _strikeCurrent = pair.strikeCurrent[spread - 1];

    if (strike > _strikeCurrent) {
        return (getAmount0Delta(liquidity, strike, roundUp), 0);
    } else if (strike < _strikeCurrent) {
        return (0, getAmount1Delta(liquidity));
    } else {
        uint128 composition = pair.composition[spread - 1];
        return (
            getAmount0FromComposition(composition, liquidity, getRatioAtStrike(strike), roundUp),
            getAmount1FromComposition(composition, liquidity, roundUp)
        );
    }
}

/// @notice Calculate max liquidity received if adding the given amount0
function getLiquidityForAmount0(
    Pairs.Pair storage pair,
    int24 strike,
    uint8 spread,
    uint256 amount0,
    bool roundUp
)
    view
    returns (uint256 liquidity)
{
    int24 _strikeCurrent = pair.strikeCurrent[spread - 1];

    if (strike > _strikeCurrent) {
        return getLiquidityDeltaAmount0(amount0, strike, roundUp);
    } else if (strike == _strikeCurrent) {
        uint128 composition = pair.composition[spread - 1];
        uint128 token0Composition;
        unchecked {
            token0Composition = type(uint128).max - composition;
        }

        return roundUp
            ? mulDivRoundingUp(amount0, getRatioAtStrike(_strikeCurrent), token0Composition)
            : mulDiv(amount0, getRatioAtStrike(_strikeCurrent), token0Composition);
    } else {
        return 0;
    }
}

/// @notice Calculate max liquidity received if adding the given amount1
function getLiquidityForAmount1(
    Pairs.Pair storage pair,
    int24 strike,
    uint8 spread,
    uint256 amount1,
    bool roundUp
)
    view
    returns (uint256 liquidity)
{
    int24 _strikeCurrent = pair.strikeCurrent[spread - 1];

    if (strike < _strikeCurrent) {
        return getLiquidityDeltaAmount1(amount1);
    } else if (strike == _strikeCurrent) {
        uint256 composition = pair.composition[spread - 1];
        return roundUp ? mulDivRoundingUp(amount1, composition, Q128) : mulDiv(amount1, composition, Q128);
    } else {
        return 0;
    }
}

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
