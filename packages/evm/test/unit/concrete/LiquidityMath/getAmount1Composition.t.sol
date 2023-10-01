// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {getAmount1} from "src/core/math/LiquidityMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

contract GetAmount1Test is Test {
    function test_GetAmount1_RoundDownPriceOneComposition0() external {
        assertEq(getAmount1(1e18, 0, false), 0);
        assertEq(getAmount1(5e18, 0, false), 0);
    }

    function test_GetAmount1_RoundDownPriceOneComposition() external {
        assertEq(getAmount1(1e18, uint128(Q128 >> 1), false), 0.5e18);
    }

    function test_GetAmount1_RoundDownPriceOneCompositionMax() external {
        assertEq(getAmount1(1e18, type(uint128).max, false), 1e18 - 1);
        assertEq(getAmount1(5e18, type(uint128).max, false), 5e18 - 1);
    }

    function test_GetAmount1_RoundUpPriceOneComposition0() external {
        assertEq(getAmount1(1e18, 0, true), 0);
        assertEq(getAmount1(5e18, 0, true), 0);
    }

    function test_GetAmount1_RoundUpPriceOneComposition() external {
        assertEq(getAmount1(1e18, uint128(Q128 >> 1), true), 0.5e18);
    }

    function test_GetAmount1_RoundUpPriceOneCompositionMax() external {
        assertEq(getAmount1(1e18, type(uint128).max, true), 1e18);
        assertEq(getAmount1(5e18, type(uint128).max, true), 5e18);
    }
}
