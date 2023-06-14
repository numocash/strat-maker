// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {getAmount0Delta, getAmount1Delta, calcAmountsForLiquidity} from "src/core/math/LiquidityMath.sol";
import {getRatioAtStrike, Q128} from "src/core/math/StrikeMath.sol";
import {mulDiv} from "src/core/math/FullMath.sol";

contract LiquidityMathTest is Test {
    function testGetAmount0DeltaBasic() external {
        uint256 precision = 1e9;
        assertApproxEqRel(getAmount0Delta(1e18, 0), 1e18, precision, "strike0");
        assertApproxEqRel(getAmount0Delta(5e18, 0), 5e18, precision, "strike0 with more than 1 liq");
        assertApproxEqRel(
            getAmount0Delta(1e18, 1), mulDiv(1e18, Q128, getRatioAtStrike(1)), precision, "positive strike"
        );
        // solhint-disable-next-line max-line-length
        assertApproxEqRel(
            getAmount0Delta(1e18, -1), mulDiv(1e18, Q128, getRatioAtStrike(-1)), precision, "negative strike"
        );
    }

    function testGetAmount1DeltaBasic() external {
        assertEq(getAmount1Delta(1e18), 1e18);
        assertEq(getAmount1Delta(5e18), 5e18);
    }

    function testCalcAmountsForLiquidityUnderCurrentStrike() external {
        int24 strike = 2;
        int24 strikeCurrent = 4;

        uint256 liquidity = 1e18;

        (uint256 amount0, uint256 amount1) = calcAmountsForLiquidity(strikeCurrent, 0, strike, liquidity);
        assertEq(amount0, 0);
        assertEq(amount1, getAmount1Delta(liquidity));
    }

    function testCalcAmountsForLiquidityOverCurrentStrike() external {
        int24 strike = 0;
        int24 strikeCurrent = -4;

        uint256 liquidity = 1e18;

        (uint256 amount0, uint256 amount1) = calcAmountsForLiquidity(strikeCurrent, 0, strike, liquidity);
        assertEq(amount0, getAmount0Delta(liquidity, strike));
        assertEq(amount1, 0);
    }

    function testCalcAmountsForLiquidityAtCurrentStrike() external {
        int24 strike = 3;
        int24 strikeCurrent = 3;
        uint128 composition = uint128(Q128 / 4);

        uint256 liquidity = 1e18;
        (uint256 amount0, uint256 amount1) = calcAmountsForLiquidity(strikeCurrent, composition, strike, liquidity);
        assertEq(amount0, mulDiv(liquidity, (type(uint128).max - composition), getRatioAtStrike(3)));
        assertEq(amount1, mulDiv(liquidity, composition, Q128));
    }
}
