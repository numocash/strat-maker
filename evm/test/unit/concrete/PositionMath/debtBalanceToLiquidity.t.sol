// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {debtBalanceToLiquidity} from "src/core/math/PositionMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

contract DebtBalanceToLiquidityTest is Test {
    function test_DebtBalanceToLiquidity() external {
        assertEq(debtBalanceToLiquidity(1e18, Q128, 0), 1e18);
        assertEq(debtBalanceToLiquidity(1e18, Q128, Q128 / 2), 0.5e18);
    }

    function test_DebtBalanceToLiquidity_Max() external {
        assertEq(debtBalanceToLiquidity(type(uint128).max, type(uint256).max, 0), type(uint128).max);
        assertEq(debtBalanceToLiquidity(type(uint128).max, type(uint256).max, 1), type(uint128).max - 1);
    }
}
