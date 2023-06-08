// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {getAmount0Delta, getAmount1Delta, calcAmountsForLiquidity} from "src/core/LiquidityMath.sol";
import {getRatioAtTick, Q128} from "src/core/TickMath.sol";
import {mulDiv} from "src/core/FullMath.sol";

contract LiquidityMathTest is Test {
    function testGetAmount0DeltaBasic() external {
        uint256 precision = 1e9;
        assertApproxEqRel(getAmount0Delta(1e18, 0), 1e18, precision, "tick0");
        assertApproxEqRel(getAmount0Delta(5e18, 0), 5e18, precision, "tick0 with more than 1 liq");
        assertApproxEqRel(getAmount0Delta(1e18, 1), mulDiv(1e18, Q128, getRatioAtTick(1)), precision, "positive tick");
        // solhint-disable-next-line max-line-length
        assertApproxEqRel(getAmount0Delta(1e18, -1), mulDiv(1e18, Q128, getRatioAtTick(-1)), precision, "negative tick");
    }

    function testGetAmount1DeltaBasic() external {
        assertEq(getAmount1Delta(1e18), 1e18);
        assertEq(getAmount1Delta(5e18), 5e18);
    }

    function testCalcAmountsForLiquidityUnderCurrentTick() external {
        int24 tick = 2;
        int24 tickCurrent = 4;

        uint256 liquidity = 1e18;

        (uint256 amount0, uint256 amount1) = calcAmountsForLiquidity(tickCurrent, 0, tick, liquidity);
        assertEq(amount0, 0);
        assertEq(amount1, getAmount1Delta(liquidity));
    }

    function testCalcAmountsForLiquidityOverCurrentTick() external {
        int24 tick = 0;
        int24 tickCurrent = -4;

        uint256 liquidity = 1e18;

        (uint256 amount0, uint256 amount1) = calcAmountsForLiquidity(tickCurrent, 0, tick, liquidity);
        assertEq(amount0, getAmount0Delta(liquidity, tick));
        assertEq(amount1, 0);
    }

    function testCalcAmountsForLiquidityAtCurrentTick() external {
        int24 tick = 3;
        int24 tickCurrent = 3;
        uint128 composition = uint128(Q128 / 4);

        uint256 liquidity = 1e18;
        (uint256 amount0, uint256 amount1) = calcAmountsForLiquidity(tickCurrent, composition, tick, liquidity);
        assertEq(amount0, mulDiv(liquidity, (type(uint128).max - composition), getRatioAtTick(3)));
        assertEq(amount1, mulDiv(liquidity, composition, Q128));
    }
}
