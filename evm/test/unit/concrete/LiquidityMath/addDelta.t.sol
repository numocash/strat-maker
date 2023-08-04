// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {addDelta} from "src/core/math/LiquidityMath.sol";

contract AddDeltaTest is Test {
    function test_AddDelta_Positive() external {
        assertEq(addDelta(2e18, 0), 2e18);
        assertEq(addDelta(2e18, 1e18), 3e18);
        assertEq(addDelta(type(uint128).max - 1, 1), type(uint128).max, "max values");

        vm.expectRevert();
        addDelta(type(uint128).max, 1);
    }

    function test_AddDelta_Negative() external {
        assertEq(addDelta(2e18, -1e18), 1e18);
        assertEq(addDelta(2e18, -2e18), 0);
        assertEq(addDelta(type(uint128).max, -type(int128).max), 2 ** 127, "max values");

        vm.expectRevert();
        addDelta(1e18, -2e18);
    }
}
