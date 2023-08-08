// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {getRatioAtStrike, MIN_STRIKE, MAX_STRIKE} from "src/core/math/StrikeMath.sol";
import {console2} from "forge-std/console2.sol";

contract GetRatioAtStrikeTest is Test {
    function test_basic() external {
        uint256 ratioX128 = getRatioAtStrike(MIN_STRIKE);
        console2.log("min ratio %x", ratioX128);

        ratioX128 = getRatioAtStrike(0);

        ratioX128 = getRatioAtStrike(MAX_STRIKE);
        console2.log("max ratio %x", ratioX128);
    }
}
