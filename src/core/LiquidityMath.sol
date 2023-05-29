// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {priceSpacingDenominator, priceSpacingNumerator} from "./TickMath.sol";

// amount0Series > 0
// amount0Series < 0

function getAmount0Delta(int24 tickLower, int24 tickUpper, uint256 liquidity) pure returns (uint256 amount0) {
    // TODO: this is incorrect
    return liquidity * (uint24(tickUpper - tickLower) + 1);
}

function getAmount1Delta(int24 tickLower, int24 tickUpper, uint256 liquidity) pure returns (uint256 amount1) {
    return liquidity * (uint24(tickUpper - tickLower) + 1);
}
