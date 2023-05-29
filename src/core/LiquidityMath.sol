// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {priceSpacingDenominator, priceSpacingNumerator} from "./TickMath.sol";

function getAmount0Delta(int24 tickLower, int24 tickUpper, uint256 liquidity) pure returns (uint256 amount0) {
    // TODO: this is incorrect
    return liquidity * uint24(tickUpper - tickLower);
}

function getAmount1Delta(int24 tickLower, int24 tickUpper, uint256 liquidity) pure returns (uint256 amount1) {
    return liquidity * uint24(tickUpper - tickLower);
}
