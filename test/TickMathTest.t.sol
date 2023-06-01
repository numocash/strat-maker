// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";

import { MIN_TICK, MAX_TICK, getRatioAtTick } from "src/core/TickMath.sol";

contract TickMathTest is Test {
    function testTickMath() external {
        assertEq(getRatioAtTick(MIN_TICK), 0);
        assertEq(getRatioAtTick(MAX_TICK), 0);
    }
}
