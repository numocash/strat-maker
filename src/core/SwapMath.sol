// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {addDelta, getAmount0FromComposition, getAmount1FromComposition} from "./LiquidityMath.sol";
import {Q128} from "./TickMath.sol";

/// @notice Compoutes the result of a swap within a tick
/// @param isToken0 True if amountDesired refers to token0
/// @param amountDesired The desired amount change on the pool
/// @return amountIn The amount of tokens to be swapped in
/// @return amountOut The amount of tokens to be swapped out
/// @return amountRemaining The amount of output token still remaining in the tick
/// @custom:team when do we need to round up and when can we use unchecked math
function computeSwapStep(
    uint256 ratioX128,
    uint128 composition,
    uint256 liquidity,
    bool isToken0,
    int256 amountDesired
)
    pure
    returns (uint256 amountIn, uint256 amountOut, uint256 amountRemaining)
{
    bool isExactIn = amountDesired > 0;
    if (isExactIn) {
        uint256 maxAmountIn = isToken0
            ? getAmount0FromComposition(type(uint128).max - composition, liquidity, ratioX128)
            : getAmount1FromComposition(type(uint128).max - composition, liquidity);

        bool completeSwap = uint256(amountDesired) >= maxAmountIn;

        amountIn = completeSwap ? maxAmountIn : uint256(amountDesired);
        amountOut = isToken0 ? mulDiv(amountIn, ratioX128, Q128) : mulDiv(amountIn, Q128, ratioX128);
        amountRemaining = completeSwap ? 0 : maxAmountIn - uint256(amountDesired);
    } else {
        uint256 maxAmountOut = isToken0
            ? getAmount0FromComposition(composition, liquidity, ratioX128)
            : getAmount1FromComposition(composition, liquidity);

        bool completeSwap = uint256(-amountDesired) > maxAmountOut;

        amountOut = completeSwap ? maxAmountOut : uint256(-amountDesired);
        amountIn = isToken0 ? mulDiv(amountOut, ratioX128, Q128) : mulDiv(amountOut, Q128, ratioX128);
        amountRemaining = completeSwap ? 0 : maxAmountOut - uint256(-amountDesired);
    }
}
