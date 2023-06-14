// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {getAmount0Delta, getAmount1Delta} from "src/core/math/LiquidityMath.sol";
import {getRatioAtStrike, Q128} from "src/core/math/StrikeMath.sol";
import {mulDiv} from "src/core/math/FullMath.sol";

contract LiquidityMathTest is Test {
    function testGetRatioAtStrikeBasic() external {
        assertEq(getRatioAtStrike(0), Q128);
        assertGe(getRatioAtStrike(1), Q128, "positive strike greater than one");
        assertGe(Q128, getRatioAtStrike(-1), "positive strike greater than one");
    }
}
