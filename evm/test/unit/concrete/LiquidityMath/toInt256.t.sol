// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {toInt256} from "src/core/math/LiquidityMath.sol";

contract ToInt256Test is Test {
    function test_ToInt256() external {
        assertEq(toInt256(1e18), 1e18);
        assertEq(toInt256(uint256(type(int256).max)), type(int256).max);

        vm.expectRevert();
        toInt256(type(uint256).max);
    }
}
