// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import { priceSpacingDenominator, priceSpacingNumerator, getRatioAtTick, Q128 } from "./TickMath.sol";
import { mulDiv } from "./FullMath.sol";

/// @dev Assuming tick is <= TickMath::MAX_TICK and > 0
function positiveSeries(int24 tick, uint256 liquidity) pure returns (uint256 amount) {
    return uint256(priceSpacingDenominator) * liquidity + liquidity + mulDiv(liquidity, getRatioAtTick(-tick), Q128);
}

function negativeSeries(int24 tick, uint256 liquidity) pure returns (uint256 amount) {
    return uint256(priceSpacingDenominator) * (mulDiv(liquidity, getRatioAtTick(int24(tick + 1)), Q128) - liquidity);
}

function getAmount0Delta(int24 tickLower, int24 tickUpper, uint256 liquidity) pure returns (uint256 amount0) {
    if (tickLower > 0) {
        return positiveSeries(tickUpper, liquidity) - positiveSeries(tickLower, liquidity);
    } else if (tickUpper < 0) {
        return negativeSeries(tickLower, liquidity) - negativeSeries(tickUpper, liquidity);
    } else {
        return positiveSeries(tickUpper, liquidity) + negativeSeries(tickLower, liquidity);
    }
}

function getAmount1Delta(int24 tickLower, int24 tickUpper, uint256 liquidity) pure returns (uint256 amount1) {
    return liquidity * (uint24(tickUpper - tickLower) + 1);
}
