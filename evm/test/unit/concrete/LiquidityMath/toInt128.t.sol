// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {toInt128} from "src/core/math/LiquidityMath.sol";

contract ToInt128Test is Test {
    function test_ToInt128() external {
        assertEq(toInt128(1e18), 1e18);
        assertEq(toInt128(uint128(type(int128).max)), type(int128).max);

        vm.expectRevert();
        toInt128(type(uint128).max);
    }
}
