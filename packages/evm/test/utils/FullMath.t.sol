// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {mulDivOverflow, mulDivRoundingUpOverflow} from "./FullMath.sol";

contract FullMathTest is Test {
    function test_FullMath_MulDiv() external {
        assertFalse(mulDivOverflow(1e18, 1e18, 1e18));
        assertFalse(mulDivOverflow(type(uint256).max, type(uint256).max, type(uint256).max));
    }

    function test_FullMath_MulDivOverflow() external {
        assertTrue(mulDivOverflow(type(uint256).max - 1, 1e18, 1e18 - 1));
    }

    function test_FullMath_MulDivRoundingUp() external {
        assertFalse(mulDivRoundingUpOverflow(type(uint256).max, type(uint256).max, type(uint256).max));
    }

    function test_FullMath_MulDivRoundingUpOverflow() external {
        assertTrue(mulDivRoundingUpOverflow(type(uint256).max - 1, 1e18, 1e18 - 1));
    }
}
