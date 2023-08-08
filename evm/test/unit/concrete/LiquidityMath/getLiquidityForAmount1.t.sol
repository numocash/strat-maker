// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {getLiquidityForAmount1} from "src/core/math/LiquidityMath.sol";

contract GetLiquidityForAmount1Test is Test {
    function test_getLiquidityForAmount1() external {
        assertEq(getLiquidityForAmount1(1e18), 1e18, "amount1");
        assertEq(getLiquidityForAmount1(5e18), 5e18, "amount1");
    }
}
