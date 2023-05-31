// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";

import { getAmount0Delta, getAmount1Delta } from "src/core/LiquidityMath.sol";

contract LiquidityMathTest is Test {
    function testGetAmount0Delta() external {
        assertEq(getAmount1Delta(0, 0, 1e18), 1e18);
    }

    function testGetAmount1Delta() external {
        assertEq(getAmount1Delta(0, 2, 1e18), 3e18);
        assertEq(getAmount1Delta(-2, 2, 1e18), 5e18);
        assertEq(getAmount1Delta(0, 0, 1e18), 1e18);
    }
}
