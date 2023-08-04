// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {getAmount0} from "src/core/math/LiquidityMath.sol";
import {getRatioAtStrike, Q128} from "src/core/math/StrikeMath.sol";
import {mulDiv} from "src/core/math/FullMath.sol";

contract GetAmount0Test is Test {
    function test_GetAmount0_RoundDownPriceOneComposition0() external {
        assertEq(getAmount0(1e18, Q128, 0, false), 1e18 - 1);
        assertEq(getAmount0(5e18, Q128, 0, false), 5e18 - 1);
    }

    function test_GetAmount0_RoundDownPriceOneComposition() external {
        assertEq(getAmount0(1e18, Q128, uint128(Q128 >> 1), false), 0.5e18 - 1);
    }

    function test_GetAmount0_RoundDownPriceOneCompositionMax() external {
        assertEq(getAmount0(1e18, Q128, type(uint128).max, false), 0);
        assertEq(getAmount0(5e18, Q128, type(uint128).max, false), 0);
    }

    function test_GetAmount0_RoundUpPriceOneComposition0() external {
        assertEq(getAmount0(1e18, Q128, 0, true), 1e18);
        assertEq(getAmount0(5e18, Q128, 0, true), 5e18);
    }

    function test_GetAmount0_RoundUpPriceOneComposition() external {
        assertEq(getAmount0(1e18, Q128, uint128(Q128 >> 1), true), 0.5e18);
    }

    function test_GetAmount0_RoundUpPriceOneCompositionMax() external {
        assertEq(getAmount0(1e18, Q128, type(uint128).max, true), 0);
        assertEq(getAmount0(5e18, Q128, type(uint128).max, true), 0);
    }

    function test_GetAmount0_PriceGreaterOne() external {
        assertEq(getAmount0(1e18, getRatioAtStrike(1), 0, false), mulDiv(1e18, Q128 - 1, getRatioAtStrike(1)));
    }

    function test_GetAmount0_PriceLessOne() external {
        assertEq(getAmount0(1e18, getRatioAtStrike(-1), 0, false), mulDiv(1e18, Q128 - 1, getRatioAtStrike(-1)));
    }
}
