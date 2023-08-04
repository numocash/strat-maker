// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {getLiquidityForAmount0} from "src/core/math/LiquidityMath.sol";
import {getRatioAtStrike, Q128} from "src/core/math/StrikeMath.sol";
import {mulDiv} from "src/core/math/FullMath.sol";

contract GetLiquidityForAmount0Test is Test {
    function test_getLiquidityForAmount0_RoundDownPriceOne() external {
        assertEq(getLiquidityForAmount0(1e18, Q128, false), 1e18, "amount0");
        assertEq(getLiquidityForAmount0(5e18, Q128, false), 5e18, "amount0");
    }

    function test_getLiquidityForAmount0_RoundDownPriceGreaterOne() external {
        assertEq(
            getLiquidityForAmount0(1e18, getRatioAtStrike(1), false), mulDiv(1e18, getRatioAtStrike(1), Q128), "amount0"
        );
        assertEq(
            getLiquidityForAmount0(5e18, getRatioAtStrike(1), false), mulDiv(5e18, getRatioAtStrike(1), Q128), "amount0"
        );
    }

    function test_getLiquidityForAmount0_RoundDownPriceLessOne() external {
        assertEq(
            getLiquidityForAmount0(1e18, getRatioAtStrike(-1), false),
            mulDiv(1e18, getRatioAtStrike(-1), Q128),
            "amount0"
        );
        assertEq(
            getLiquidityForAmount0(5e18, getRatioAtStrike(-1), false),
            mulDiv(5e18, getRatioAtStrike(-1), Q128),
            "amount0"
        );
    }

    function test_getLiquidityForAmount0_RoundUpPriceOne() external {
        assertEq(getLiquidityForAmount0(1e18, Q128, true), 1e18, "amount0");
        assertEq(getLiquidityForAmount0(5e18, Q128, true), 5e18, "amount0");
    }

    function test_getLiquidityForAmount0_RoundUpPriceGreaterOne() external {
        assertEq(
            getLiquidityForAmount0(1e18, getRatioAtStrike(1), true),
            mulDiv(1e18, getRatioAtStrike(1), Q128) + 1,
            "amount0"
        );
        assertEq(
            getLiquidityForAmount0(5e18, getRatioAtStrike(1), true),
            mulDiv(5e18, getRatioAtStrike(1), Q128) + 1,
            "amount0"
        );
    }

    function test_getLiquidityForAmount0_RoundUpPriceLessOne() external {
        assertEq(
            getLiquidityForAmount0(1e18, getRatioAtStrike(-1), true),
            mulDiv(1e18, getRatioAtStrike(-1), Q128) + 1,
            "amount0"
        );
        assertEq(
            getLiquidityForAmount0(5e18, getRatioAtStrike(-1), true),
            mulDiv(5e18, getRatioAtStrike(-1), Q128) + 1,
            "amount0"
        );
    }
}
