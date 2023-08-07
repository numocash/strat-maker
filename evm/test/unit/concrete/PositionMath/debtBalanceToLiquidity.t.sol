// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {debtBalanceToLiquidity} from "src/core/math/PositionMath.sol";

contract DebtBalanceToLiquidityeTest is Test {
    function test_DebtBalanceToLiquiditye() external {
        assertEq(debtBalanceToLiquidity(1e18, 0), 1e18);
        assertEq(debtBalanceToLiquidity(1e18, 1), 1e18);
    }

    function test_DebtBalanceToLiquiditye_Max() external {
        assertEq(debtBalanceToLiquidity(type(uint128).max, 0), type(uint128).max);
    }
}
