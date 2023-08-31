// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {getRatioAtStrike, Q128} from "./StrikeMath.sol";
import {Pairs} from "../Pairs.sol";

/// @notice scale liquidity up by a scaling factor
/// @dev scaling factor must be <=128, >128 loses precision unnecessarily
function scaleLiquidityUp(uint128 liquidity, uint8 scalingFactor) pure returns (uint256) {
    return uint256(liquidity) << scalingFactor;
}

/// @notice scale liquidity down by a scaling factor
/// @dev scaling factor must be <=128, >128 loses precision unnecessarily
/// @custom:team Should we be rounding up at any point?
/// @custom:team Should we check for overflow on the top end?
function scaleLiquidityDown(uint256 liquidity, uint8 scalingFactor) pure returns (uint128) {
    return uint128(liquidity >> scalingFactor);
}

/// @notice Calculate the amount of token 0 for `liquidity` units of liquidity for strike with ratio `ratioX128`.
/// @dev x = L / Pi
function getAmount0(uint256 liquidity, uint256 ratioX128, bool roundUp) pure returns (uint256 amount0) {
    return roundUp ? mulDivRoundingUp(liquidity, Q128, ratioX128) : mulDiv(liquidity, Q128, ratioX128);
}

/// @notice Calculate the amount of token 1 for `liquidity` units of liquidity.
/// @dev y = L
function getAmount1(uint256 liquidity) pure returns (uint256 amount1) {
    return liquidity;
}

/// @notice Calculate the amount of liquidity for `amount0` token 0 for strike with ratio `ratioX128`.
/// @dev L = x * Pi
/// @dev Rounds down
function getLiquidityForAmount0(uint256 amount0, uint256 ratioX128) pure returns (uint256 liquidity) {
    return mulDiv(amount0, ratioX128, Q128);
}

/// @notice Calculate the amount of liquidity for `amount1` token 1.
/// @dev L = y
function getLiquidityForAmount1(uint256 amount1) pure returns (uint256 liquidity) {
    return amount1;
}

/// @notice Calculate the amount of token 0 for `liquidity` units of liquidity for `strike` with `composition`%
/// of liquidity held in token 1.
/// @custom:team This rounds down extra because composition is between 0 and uint128Max while ratio is scaled by
/// uint128Max + 1
function getAmount0(
    uint256 liquidity,
    uint256 ratioX128,
    uint128 composition,
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

/// @notice Calculate the amount of token 1 for `liquidity` units of liquidity with `composition`%
/// of liquidity held in token 1.
function getAmount1(uint256 liquidity, uint128 composition, bool roundUp) pure returns (uint256 amount1) {
    return roundUp ? mulDivRoundingUp(liquidity, composition, Q128) : mulDiv(liquidity, composition, Q128);
}

/// @notice Calculate the amount of token 0 and token 1 for `liquidity` units of liquidity with `pair`
/// @param pair Storage pointer to a pair struct, used to conditionally sload composition
/// @dev Assumes spread is valid
function getAmounts(
    Pairs.Pair storage pair,
    uint256 liquidity,
    int24 strike,
    uint8 spread,
    bool roundUp
)
    view
    returns (uint256 amount0, uint256 amount1)
{
    unchecked {
        int24 _strikeCurrent = pair.strikeCurrent[spread - 1];

        if (strike > _strikeCurrent) {
            return (getAmount0(liquidity, getRatioAtStrike(strike), roundUp), 0);
        } else if (strike < _strikeCurrent) {
            return (0, getAmount1(liquidity));
        } else {
            uint128 composition = pair.composition[spread - 1];
            return (
                getAmount0(liquidity, getRatioAtStrike(strike), composition, roundUp),
                getAmount1(liquidity, composition, roundUp)
            );
        }
    }
}

/// @notice cast uint256 to int256, revert on overflow
function toInt256(uint256 x) pure returns (int256 z) {
    assert(x <= uint256(type(int256).max));
    z = int256(x);
}
