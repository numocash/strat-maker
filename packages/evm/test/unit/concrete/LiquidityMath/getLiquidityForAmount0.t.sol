// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {getLiquidityForAmount0} from "src/core/math/LiquidityMath.sol";
import {getRatioAtStrike, Q128} from "src/core/math/StrikeMath.sol";
import {mulDiv} from "src/core/math/FullMath.sol";

contract GetLiquidityForAmount0Test is Test {
    function test_getLiquidityForAmount0_PriceOne() external {
        assertEq(getLiquidityForAmount0(1e18, Q128), 1e18, "amount0");
        assertEq(getLiquidityForAmount0(5e18, Q128), 5e18, "amount0");
    }

    function test_getLiquidityForAmount0_PriceGreaterOne() external {
        assertEq(getLiquidityForAmount0(1e18, getRatioAtStrike(1)), mulDiv(1e18, getRatioAtStrike(1), Q128), "amount0");
        assertEq(getLiquidityForAmount0(5e18, getRatioAtStrike(1)), mulDiv(5e18, getRatioAtStrike(1), Q128), "amount0");
    }

    function test_getLiquidityForAmount0_PriceLessOne() external {
        assertEq(
            getLiquidityForAmount0(1e18, getRatioAtStrike(-1)), mulDiv(1e18, getRatioAtStrike(-1), Q128), "amount0"
        );
        assertEq(
            getLiquidityForAmount0(5e18, getRatioAtStrike(-1)), mulDiv(5e18, getRatioAtStrike(-1), Q128), "amount0"
        );
    }
}
