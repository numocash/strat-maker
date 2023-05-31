// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";

import { getAmount0Delta, getAmount1Delta } from "src/core/LiquidityMath.sol";
import { getRatioAtTick, Q128 } from "src/core/TickMath.sol";
import { mulDiv } from "src/core/FullMath.sol";

contract LiquidityMathTest is Test {
    function testGetAmount0Delta() external {
        uint256 precision = 1e9;
        assertApproxEqRel(getAmount0Delta(0, 0, 1e18), 1e18, precision, "tick0");
        assertApproxEqRel(getAmount0Delta(0, 0, 5e18), 5e18, precision, "tick0 with more than 1 liq");
        assertApproxEqRel(
            getAmount0Delta(1, 1, 1e18), mulDiv(1e18, getRatioAtTick(1), Q128), precision, "positive tick"
        );
        assertApproxEqRel(
            getAmount0Delta(-1, -1, 1e18), mulDiv(1e18, getRatioAtTick(-1), Q128), precision, "negative tick"
        );
        assertApproxEqRel(
            getAmount0Delta(0, 1, 1e18), 1e18 + mulDiv(1e18, getRatioAtTick(1), Q128), precision, "positive ticks"
        );
        assertApproxEqRel(
            getAmount0Delta(-1, 0, 1e18), 1e18 + mulDiv(1e18, getRatioAtTick(-1), Q128), precision, "negative ticks"
        );
        assertApproxEqRel(
            getAmount0Delta(-1, 1, 1e18),
            1e18 + mulDiv(1e18, getRatioAtTick(1), Q128) + mulDiv(1e18, getRatioAtTick(-1), Q128),
            precision,
            "positive and negative ticks"
        );
    }

    function testGetAmount1Delta() external {
        assertEq(getAmount1Delta(0, 2, 1e18), 3e18);
        assertEq(getAmount1Delta(-2, 2, 1e18), 5e18);
        assertEq(getAmount1Delta(0, 0, 1e18), 1e18);
    }
}
