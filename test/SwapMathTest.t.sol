// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {computeSwapStep} from "src/core/math/SwapMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

contract SwapMathTest is Test {
    function testToken0ExactInBasic() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) =
            computeSwapStep(Q128, type(uint128).max, 1e18, true, 1e18);

        assertEq(amountIn, 1e18, "amountIn");
        assertEq(amountOut, 1e18, "amountOut");
        assertEq(amountRemaining, 0, "amountRemaining");
    }

    function testToken1ExactInBasic() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) = computeSwapStep(Q128, 0, 1e18, false, 1e18);

        assertEq(amountIn, 1e18, "amountIn");
        assertEq(amountOut, 1e18, "amountOut");
        assertEq(amountRemaining, 0, "amountRemaining");
    }

    function testToken0ExactOutBasic() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) = computeSwapStep(Q128, 0, 1e18, true, -1e18);

        assertEq(amountIn, 1e18 - 1, "amountIn");
        assertEq(amountOut, 1e18 - 1, "amountOut");
        assertEq(amountRemaining, 0, "amountRemaining");
    }

    function testToken1ExactOutBasic() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) =
            computeSwapStep(Q128, type(uint128).max, 1e18, false, -1e18);

        assertEq(amountIn, 1e18 - 1, "amountIn");
        assertEq(amountOut, 1e18 - 1, "amountOut");
        assertEq(amountRemaining, 0, "amountRemaining");
    }

    function testToken0ExactInPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) =
            computeSwapStep(Q128, type(uint128).max, 1e18, true, 0.5e18);

        assertEq(amountIn, 0.5e18, "amountIn");
        assertEq(amountOut, 0.5e18, "amountOut");
        assertEq(amountRemaining, 0.5e18, "amountRemaining");
    }

    function testToken1ExactInPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) = computeSwapStep(Q128, 0, 1e18, false, 0.5e18);

        assertEq(amountIn, 0.5e18, "amountIn");
        assertEq(amountOut, 0.5e18, "amountOut");
        assertEq(amountRemaining, 0.5e18, "amountRemaining");
    }

    function testToken0ExactOutPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) = computeSwapStep(Q128, 0, 1e18, true, -0.5e18);

        assertEq(amountIn, 0.5e18, "amountIn");
        assertEq(amountOut, 0.5e18, "amountOut");
        assertEq(amountRemaining, 0.5e18 - 1, "amountRemaining");
    }

    function testToken1ExactOutPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 amountRemaining) =
            computeSwapStep(Q128, type(uint128).max, 1e18, false, -0.5e18);

        assertEq(amountIn, 0.5e18, "amountIn");
        assertEq(amountOut, 0.5e18, "amountOut");
        assertEq(amountRemaining, 0.5e18 - 1, "amountRemaining");
    }
}
