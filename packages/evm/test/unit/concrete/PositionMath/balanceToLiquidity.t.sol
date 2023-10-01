// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {balanceToLiquidity} from "src/core/math/PositionMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

contract BalanceToLiquidityTest is Test {
    function test_BalanceToLiquidity() external {
        assertEq(balanceToLiquidity(1e18, 0), 1e18);
        assertEq(balanceToLiquidity(1e18, Q128), 1e18);
        assertEq(balanceToLiquidity(1e18, Q128 + 1), 1e18);
    }

    function test_BalanceToLiquidity_Max() external {
        assertEq(balanceToLiquidity(type(uint128).max, 0), type(uint128).max);
        assertEq(balanceToLiquidity(type(uint128).max, Q128), type(uint128).max);
    }

    function test_BalanceToLiquidity_Overflow() external {
        vm.expectRevert();
        balanceToLiquidity(type(uint128).max, Q128 * 2);
    }
}
