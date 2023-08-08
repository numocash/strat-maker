// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {getAmount0, getAmount1, getLiquidityForAmount0, getLiquidityForAmount1} from "./LiquidityMath.sol";
import {Q128} from "./StrikeMath.sol";

/// @notice Computes the result of a swap within a strike
/// @param liquidity Amount of liquidity in the direction of the swap
/// @param isToken0 True if amountDesired refers to token0
/// @param amountDesired The desired amount change on the pool
/// @return amountIn The amount of tokens to be swapped in
/// @return amountOut The amount of tokens to be swapped out
/// @return liquidityRemaining The amount of swappable liquidity still remaining in the strike
/// @custom:team How to round liquidity remaining
function computeSwapStep(
    uint256 ratioX128,
    uint256 liquidity,
    bool isToken0,
    int256 amountDesired
)
    pure
    returns (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining)
{
    bool isExactIn = amountDesired > 0;
    if (isExactIn) {
        uint256 maxAmountIn = isToken0 ? getAmount0(liquidity, ratioX128, true) : getAmount1(liquidity);

        bool allLiquiditySwapped = uint256(amountDesired) >= maxAmountIn;

        amountIn = allLiquiditySwapped ? maxAmountIn : uint256(amountDesired);
        amountOut = isToken0 ? mulDiv(amountIn, ratioX128, Q128) : mulDiv(amountIn, Q128, ratioX128);

        unchecked {
            liquidityRemaining = allLiquiditySwapped
                ? 0
                : isToken0
                    ? getLiquidityForAmount0(maxAmountIn - uint256(amountDesired), ratioX128)
                    : getLiquidityForAmount1(maxAmountIn - uint256(amountDesired));
        }
    } else {
        uint256 maxAmountOut = isToken0 ? getAmount0(liquidity, ratioX128, false) : getAmount1(liquidity);

        bool allLiquiditySwapped = uint256(-amountDesired) >= maxAmountOut;

        amountOut = allLiquiditySwapped ? maxAmountOut : uint256(-amountDesired);
        amountIn =
            isToken0 ? mulDivRoundingUp(amountOut, ratioX128, Q128) : mulDivRoundingUp(amountOut, Q128, ratioX128);

        unchecked {
            liquidityRemaining = allLiquiditySwapped
                ? 0
                : isToken0
                    ? getLiquidityForAmount0(maxAmountOut - uint256(-amountDesired), ratioX128)
                    : getLiquidityForAmount1(maxAmountOut - uint256(-amountDesired));
        }
    }
}
