// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {liquidityToBalance} from "src/core/math/PositionMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

contract LiquidityToBalanceTest is Test {
    function test_LiquidityToBalance() external {
        assertEq(liquidityToBalance(1e18, 0), 1e18);
        assertEq(liquidityToBalance(1e18, Q128), 1e18);
        assertEq(liquidityToBalance(1e18, Q128 - 1), 1e18);
    }

    function test_LiquidityToBalance_Max() external {
        assertEq(liquidityToBalance(type(uint128).max, 0), type(uint128).max);
        assertEq(liquidityToBalance(type(uint128).max, Q128), type(uint128).max);
    }
}
