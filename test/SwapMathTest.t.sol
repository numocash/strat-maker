// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {computeSwapStep} from "src/core/SwapMath.sol";
import {Q128} from "src/core/TickMath.sol";

contract SwapMathTest is Test {
    uint256 precision = 1e9;

    function testToken0ExactInBasic() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) =
            computeSwapStep(Q128, type(uint128).max, 1e18, true, 1e18);

        assertApproxEqRel(amountIn, 1e18, precision, "amountIn");
        assertApproxEqRel(amountOut, 1e18, precision, "amountOut");
        assertApproxEqRel(amountRemaining, 0, precision, "amountRemaining");
    }

    function testToken1ExactInBasic() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) = computeSwapStep(Q128, 0, 1e18, false, 1e18);

        assertApproxEqRel(amountIn, 1e18, precision, "amountIn");
        assertApproxEqRel(amountOut, 1e18, precision, "amountOut");
        assertApproxEqRel(amountRemaining, 0, precision, "amountRemaining");
    }

    function testToken0ExactOutBasic() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) = computeSwapStep(Q128, 0, 1e18, true, -1e18);

        assertApproxEqRel(amountIn, 1e18, precision, "amountIn");
        assertApproxEqRel(amountOut, 1e18, precision, "amountOut");
        assertApproxEqRel(amountRemaining, 0, precision, "amountRemaining");
    }

    function testToken1ExactOutBasic() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) =
            computeSwapStep(Q128, type(uint128).max, 1e18, false, -1e18);

        assertApproxEqRel(amountIn, 1e18, precision, "amountIn");
        assertApproxEqRel(amountOut, 1e18, precision, "amountOut");
        assertApproxEqRel(amountRemaining, 0, precision, "amountRemaining");
    }

    function testToken0ExactInPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) =
            computeSwapStep(Q128, type(uint128).max, 1e18, true, 0.5e18);

        assertApproxEqRel(amountIn, 0.5e18, precision, "amountIn");
        assertApproxEqRel(amountOut, 0.5e18, precision, "amountOut");
        assertApproxEqRel(amountRemaining, 0.5e18, precision, "amountRemaining");
    }

    function testToken1ExactInPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) = computeSwapStep(Q128, 0, 1e18, false, 0.5e18);

        assertApproxEqRel(amountIn, 0.5e18, precision, "amountIn");
        assertApproxEqRel(amountOut, 0.5e18, precision, "amountOut");
        assertApproxEqRel(amountRemaining, 0.5e18, precision, "amountRemaining");
    }

    function testToken0ExactOutPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) = computeSwapStep(Q128, 0, 1e18, true, -0.5e18);

        assertApproxEqRel(amountIn, 0.5e18, precision, "amountIn");
        assertApproxEqRel(amountOut, 0.5e18, precision, "amountOut");
        assertApproxEqRel(amountRemaining, 0.5e18, precision, "amountRemaining");
    }

    function testToken1ExactOutPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) =
            computeSwapStep(Q128, type(uint128).max, 1e18, false, -0.5e18);

        assertApproxEqRel(amountIn, 0.5e18, precision, "amountIn");
        assertApproxEqRel(amountOut, 0.5e18, precision, "amountOut");
        assertApproxEqRel(amountRemaining, 0.5e18, precision, "amountRemaining");
    }
}
