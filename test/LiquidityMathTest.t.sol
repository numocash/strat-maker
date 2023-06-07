// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {getAmount0Delta, getAmount1Delta, calcAmountsForLiquidity} from "src/core/LiquidityMath.sol";
import {getRatioAtTick, Q96, Q128} from "src/core/TickMath.sol";
import {mulDiv} from "src/core/FullMath.sol";

contract LiquidityMathTest is Test {
    function testGetAmount0DeltaBasic() external {
        uint256 precision = 1e9;
        assertApproxEqRel(getAmount0Delta(0, 1, 1e18), 1e18, precision, "tick0");
        assertApproxEqRel(getAmount0Delta(0, 1, 5e18), 5e18, precision, "tick0 with more than 1 liq");
        assertApproxEqRel(
            getAmount0Delta(1, 2, 1e18), mulDiv(1e18, getRatioAtTick(1), Q128), precision, "positive tick"
        );
        assertApproxEqRel(
            getAmount0Delta(-1, 0, 1e18), mulDiv(1e18, getRatioAtTick(-1), Q128), precision, "negative tick"
        );
        assertApproxEqRel(
            getAmount0Delta(0, 2, 1e18), 1e18 + mulDiv(1e18, getRatioAtTick(1), Q128), precision, "positive ticks"
        );
        assertApproxEqRel(
            getAmount0Delta(-1, 1, 1e18), 1e18 + mulDiv(1e18, getRatioAtTick(-1), Q128), precision, "negative ticks"
        );
        assertApproxEqRel(
            getAmount0Delta(-1, 2, 1e18),
            1e18 + mulDiv(1e18, getRatioAtTick(1), Q128) + mulDiv(1e18, getRatioAtTick(-1), Q128),
            precision,
            "positive and negative ticks"
        );
    }

    function testGetAmount1DeltaBasic() external {
        assertEq(getAmount1Delta(0, 3, 1e18), 3e18);
        assertEq(getAmount1Delta(-2, 3, 1e18), 5e18);
        assertEq(getAmount1Delta(0, 1, 1e18), 1e18);
    }

    function testCalcAmountsForLiquidityUnderCurrentTick() external {
        int24 tickLower = 0;
        int24 tickUpper = 3;
        int24 tickCurrent = 4;

        uint256 liquidity = 1e18;

        (uint256 amount0, uint256 amount1) = calcAmountsForLiquidity(tickCurrent, 0, tickLower, tickUpper, liquidity);
        assertEq(amount0, 0);
        assertEq(amount1, getAmount1Delta(tickLower, tickUpper, liquidity));
    }

    function testCalcAmountsForLiquidityOverCurrentTick() external {
        int24 tickLower = -2;
        int24 tickUpper = 0;
        int24 tickCurrent = -4;

        uint256 liquidity = 1e18;

        (uint256 amount0, uint256 amount1) = calcAmountsForLiquidity(tickCurrent, 0, tickLower, tickUpper, liquidity);
        assertEq(amount0, getAmount0Delta(tickLower, tickUpper, liquidity));
        assertEq(amount1, 0);
    }

    function testCalcAmountsForLiquidityInRange() external {
        int24 tickLower = -2;
        int24 tickUpper = 1;
        int24 tickCurrent = 0;

        uint256 liquidity = 1e18;
        (uint256 amount0, uint256 amount1) = calcAmountsForLiquidity(tickCurrent, 0, tickLower, tickUpper, liquidity);
        assertEq(amount0, 1e18);
        assertEq(amount1, 2e18);
    }

    function testCalcAmountsForLiquidityWithCompositionBasic() external {
        int24 tickLower = 0;
        int24 tickUpper = 1;
        int24 tickCurrent = 0;

        uint256 liquidity = 1e18;

        (uint256 amount0, uint256 amount1) =
            calcAmountsForLiquidity(tickCurrent, uint96(Q96 / 2), tickLower, tickUpper, liquidity);
        assertEq(amount0, mulDiv(liquidity, Q96 / 2, Q96));
        assertEq(amount1, mulDiv(liquidity, Q96 / 2, Q96));
    }

    function testCalcAmountsForLiquidityWithComposition() external {
        int24 tickLower = 1;
        int24 tickUpper = 2;
        int24 tickCurrent = 1;
        uint96 composition = uint96(Q96 / 4);

        uint256 liquidity = 1e18;

        (uint256 amount0, uint256 amount1) =
            calcAmountsForLiquidity(tickCurrent, composition, tickLower, tickUpper, liquidity);
        assertEq(amount0, mulDiv(liquidity, (Q96 - composition) * Q128, getRatioAtTick(1) * Q96));
        assertEq(amount1, mulDiv(liquidity, composition, Q96));
    }

    function testCalcAmountsForLiquidityMultipleTicksBasic() external {
        int24 tickLower = 0;
        int24 tickUpper = 3;
        int24 tickCurrent = 1;
        uint96 composition = uint96(Q96 / 4);

        uint256 liquidity = 1e18;

        (uint256 amount0, uint256 amount1) =
            calcAmountsForLiquidity(tickCurrent, composition, tickLower, tickUpper, liquidity);
        assertEq(
            amount0,
            mulDiv(liquidity, (Q96 - composition) * Q128, getRatioAtTick(1) * Q96)
                + mulDiv(liquidity, Q128, getRatioAtTick(2))
        );
        assertEq(amount1, mulDiv(liquidity, composition, Q96) + liquidity);
    }
}
