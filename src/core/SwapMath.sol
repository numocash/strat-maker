// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {Q128, Q96, Q32} from "./TickMath.sol";

import {console2} from "forge-std/console2.sol";

/// @custom:team when do we need to round up
function computeSwapStep(
    uint256 ratioX128,
    uint96 composition,
    uint256 liquidity,
    bool isToken0,
    int256 amountDesired
)
    pure
    returns (uint256 amountIn, uint256 amountOut, uint256 amountRemaining)
{
    bool exactIn = amountDesired > 0;
    if (exactIn) {
        uint256 maxAmountIn =
            isToken0 ? mulDiv(liquidity, composition * Q32, ratioX128) : mulDiv(liquidity, (Q96 - composition), Q96);
        (amountIn, amountRemaining) = uint256(amountDesired) >= maxAmountIn
            ? (maxAmountIn, 0)
            : (uint256(amountDesired), maxAmountIn - uint256(amountDesired));

        amountOut = isToken0 ? mulDiv(amountIn, ratioX128, Q128) : mulDiv(amountIn, Q128, ratioX128);
    } else {
        uint256 maxAmountOut =
            isToken0 ? mulDiv(liquidity, (Q96 - composition) * Q32, ratioX128) : mulDiv(liquidity, composition, Q96);

        (amountOut, amountRemaining) = uint256(-amountDesired) > maxAmountOut
            ? (maxAmountOut, 0)
            : (uint256(-amountDesired), maxAmountOut - uint256(-amountDesired));
        amountIn = isToken0 ? mulDiv(amountOut, ratioX128, Q128) : mulDiv(amountOut, Q128, ratioX128);
    }
}
