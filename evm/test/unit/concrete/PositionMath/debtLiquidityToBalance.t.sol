// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {debtLiquidityToBalance} from "src/core/math/PositionMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

contract DebtLiquidityToBalanceTest is Test {
    function test_DebtLiquidityToBalance() external {
        assertEq(debtLiquidityToBalance(1e18, 0), 1e18);
        assertEq(debtLiquidityToBalance(1e18, 1), 1e18 + 1);
    }

    function test_DebtLiquidityToBalance_Max() external {
        assertEq(debtLiquidityToBalance(type(uint128).max, 0), type(uint128).max);
    }

    function test_DebtLiquidityToBalance_Overflow() external {
        vm.expectRevert();
        debtLiquidityToBalance(type(uint128).max, Q128);
    }
}
