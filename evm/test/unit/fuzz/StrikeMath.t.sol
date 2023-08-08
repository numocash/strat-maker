// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {getRatioAtStrike, MIN_STRIKE, MAX_STRIKE} from "src/core/math/StrikeMath.sol";

contract StrikeMathFuzzTest is Test {
    function testFuzz_GetRatioAtStrike_NoRevert(int24 strike) external pure {
        vm.assume(strike >= MIN_STRIKE && strike <= MAX_STRIKE);
        getRatioAtStrike(strike);
    }

    function testFuzz_GetRatioAtStrike_Order(int24 strike) external {
        vm.assume(strike > MIN_STRIKE && strike < MAX_STRIKE);
        assertLt(getRatioAtStrike(strike), getRatioAtStrike(strike + 1));
        assertGt(getRatioAtStrike(strike), getRatioAtStrike(strike - 1));
    }
}
