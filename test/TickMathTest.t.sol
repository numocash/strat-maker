// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {getAmount0Delta, getAmount1Delta} from "src/core/math/LiquidityMath.sol";
import {getRatioAtTick, Q128} from "src/core/math/TickMath.sol";
import {mulDiv} from "src/core/math/FullMath.sol";

contract LiquidityMathTest is Test {
    function testGetRatioAtTickBasic() external {
        assertEq(getRatioAtTick(0), Q128);
        assertGe(getRatioAtTick(1), Q128, "positive tick greater than one");
        assertGe(Q128, getRatioAtTick(-1), "positive tick greater than one");
    }
}
