// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {getAmount1} from "src/core/math/LiquidityMath.sol";

contract GetAmount1Test is Test {
    function test_getAmount1() external {
        assertEq(getAmount1(1e18), 1e18, "amount1");
        assertEq(getAmount1(5e18), 5e18, "amount1");
    }
}
