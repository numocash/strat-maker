// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {
    getAmount0Delta,
    getAmount1Delta,
    getAmount0FromComposition,
    getAmount1FromComposition,
    getLiquidityForAmount0,
    getLiquidityForAmount1,
    getAmountsForLiquidity
} from "src/core/math/LiquidityMath.sol";
import {getRatioAtStrike, Q128} from "src/core/math/StrikeMath.sol";
import {mulDiv} from "src/core/math/FullMath.sol";

contract LiquidityMathTest is Test {
    function testGetAmount0Delta() external {
        assertEq(getAmount0Delta(1e18, 0, false), 1e18, "strike0");
        assertEq(getAmount0Delta(1e18, 0, true), 1e18, "strike0 round up");

        assertEq(getAmount0Delta(5e18, 0, false), 5e18, "strike0 with more than 1 liq");
        assertEq(getAmount0Delta(5e18, 0, true), 5e18, "strike0 with more than 1 liq round up");

        assertEq(getAmount0Delta(1e18, 1, false), mulDiv(1e18, Q128, getRatioAtStrike(1)), "positive strike");
        assertEq(
            getAmount0Delta(1e18, 1, true), mulDiv(1e18, Q128, getRatioAtStrike(1)) + 1, "positive strike round up"
        );

        assertEq(
            getAmount0Delta(1e18, -1, true), mulDiv(1e18, Q128, getRatioAtStrike(-1)) + 1, "negative strike round up"
        );
    }

    function testGetAmount1Delta() external {
        assertEq(getAmount1Delta(1e18), 1e18);
        assertEq(getAmount1Delta(5e18), 5e18);
    }

    function testGetAmount0FromComposition() external {
        assertEq(getAmount0FromComposition(0, 1e18, getRatioAtStrike(0), false), 1e18 - 1);
        assertEq(getAmount0FromComposition(0, 1e18, getRatioAtStrike(0), true), 1e18);

        assertEq(getAmount0FromComposition(uint128(Q128 >> 1), 1e18, getRatioAtStrike(0), false), 0.5e18 - 1);
        assertEq(getAmount0FromComposition(uint128(Q128 >> 1), 1e18, getRatioAtStrike(0), true), 0.5e18);

        assertEq(getAmount0FromComposition(type(uint128).max, 1e18, getRatioAtStrike(0), false), 0);
        assertEq(getAmount0FromComposition(type(uint128).max, 1e18, getRatioAtStrike(0), true), 0);
    }

    function testGetAmount1FromComposition() external {
        assertEq(getAmount1FromComposition(0, 1e18, false), 0);
        assertEq(getAmount1FromComposition(0, 1e18, true), 0);

        assertEq(getAmount1FromComposition(uint128(Q128 >> 1), 1e18, false), 0.5e18);
        assertEq(getAmount1FromComposition(uint128(Q128 >> 1), 1e18, true), 0.5e18);

        assertEq(getAmount1FromComposition(type(uint128).max, 1e18, false), 1e18 - 1);
        assertEq(getAmount1FromComposition(type(uint128).max, 1e18, true), 1e18);
    }

    // function testgetAmountsForLiquidityUnderCurrentStrike() external {
    //     int24 strike = 2;
    //     int24 strikeCurrent = 4;

    //     uint256 liquidity = 1e18;

    //     (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(strikeCurrent, 0, strike, liquidity, false);
    //     assertEq(amount0, 0);
    //     assertEq(amount1, getAmount1Delta(liquidity));
    // }

    // function testgetAmountsForLiquidityOverCurrentStrike() external {
    //     int24 strike = 0;
    //     int24 strikeCurrent = -4;

    //     uint256 liquidity = 1e18;

    //     (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(strikeCurrent, 0, strike, liquidity, false);
    //     assertEq(amount0, getAmount0Delta(liquidity, strike, false));
    //     assertEq(amount1, 0);
    // }

    // function testgetAmountsForLiquidityAtCurrentStrike() external {
    //     int24 strike = 3;
    //     int24 strikeCurrent = 3;
    //     uint128 composition = uint128(Q128 / 4);

    //     uint256 liquidity = 1e18;
    //     (uint256 amount0, uint256 amount1) =
    //         getAmountsForLiquidity(strikeCurrent, composition, strike, liquidity, false);
    //     assertEq(amount0, mulDiv(liquidity, type(uint128).max - composition, getRatioAtStrike(3)));
    //     assertEq(amount1, mulDiv(liquidity, composition, Q128));
    // }

    // function testGetLiquidityFromAmount0() external {
    //     assertEq(getLiquidityForAmount0(1, 0, 0, 1e18, false), 0);
    //     assertEq(getLiquidityForAmount0(1, 0, 0, 1e18, true), 0);

    //     assertEq(getLiquidityForAmount0(0, 0, 0, 1e18, false), 1e18);
    //     assertEq(getLiquidityForAmount0(0, 0, 0, 1e18, true), 1e18 + 1);

    //     assertEq(getLiquidityForAmount0(0, 0, 1, mulDiv(1e18, Q128, getRatioAtStrike(1)) + 1, false), 1e18);
    //     assertEq(getLiquidityForAmount0(0, 0, 1, mulDiv(1e18, Q128, getRatioAtStrike(1)), true), 1e18);
    // }

    // function testGetLiquidityFromAmount1() external {
    //     assertEq(getLiquidityForAmount1(1, 0, 0, 1e18, false), 1e18);
    //     assertEq(getLiquidityForAmount1(1, 0, 0, 1e18, true), 1e18);

    //     assertEq(getLiquidityForAmount1(0, type(uint128).max, 0, 1e18, false), 1e18 - 1);
    //     assertEq(getLiquidityForAmount1(0, type(uint128).max, 0, 1e18, true), 1e18);

    //     assertEq(getLiquidityForAmount1(0, 0, 1, 1e18, false), 0);
    //     assertEq(getLiquidityForAmount1(0, 0, 1, 1e18, true), 0);
    // }
}
