// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {computeSwapStep} from "src/core/math/SwapMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

contract ComputeSwapStepTest is Test {
    // Token 0 exact in

    function test_ComputeSwapStep_Token0ExactInPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, true, 0.5e18);

        assertEq(amountIn, 0.5e18);
        assertEq(amountOut, 0.5e18);
        assertEq(liquidityRemaining, 0.5e18);
    }

    function test_ComputeSwapStep_Token0ExactInAmountOutRoundDown() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) =
            computeSwapStep(Q128 - 1, 1e18, true, 0.5e18);

        assertEq(amountIn, 0.5e18);
        assertEq(amountOut, 0.5e18 - 1);
        assertEq(liquidityRemaining, 0.5e18);
    }

    function test_ComputeSwapStep_Token0ExactInFull() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, true, 1e18);

        assertEq(amountIn, 1e18);
        assertEq(amountOut, 1e18);
        assertEq(liquidityRemaining, 0);
    }

    function test_ComputeSwapStep_Token0ExactInOver() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, true, 1.5e18);

        assertEq(amountIn, 1e18);
        assertEq(amountOut, 1e18);
        assertEq(liquidityRemaining, 0);
    }

    // Token 1 exact in

    function test_ComputeSwapStep_Token1ExactInPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, false, 0.5e18);

        assertEq(amountIn, 0.5e18);
        assertEq(amountOut, 0.5e18);
        assertEq(liquidityRemaining, 0.5e18);
    }

    function test_ComputeSwapStep_Token1ExactInAmountOutRoundDown() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) =
            computeSwapStep(Q128 + 1, 1e18, false, 0.5e18);

        assertEq(amountIn, 0.5e18);
        assertEq(amountOut, 0.5e18 - 1);
        assertEq(liquidityRemaining, 0.5e18);
    }

    function test_ComputeSwapStep_Token1ExactInFull() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, false, 1e18);

        assertEq(amountIn, 1e18);
        assertEq(amountOut, 1e18);
        assertEq(liquidityRemaining, 0);
    }

    function test_ComputeSwapStep_Token1ExactInOver() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, false, 1.5e18);

        assertEq(amountIn, 1e18);
        assertEq(amountOut, 1e18);
        assertEq(liquidityRemaining, 0);
    }

    // Token 0 exact out

    function test_ComputeSwapStep_Token0ExactOutPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, true, -0.5e18);

        assertEq(amountIn, 0.5e18);
        assertEq(amountOut, 0.5e18);
        assertEq(liquidityRemaining, 0.5e18);
    }

    function test_ComputeSwapStep_Token0ExactOutAmountInRoundUp() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) =
            computeSwapStep(Q128 - 1, 1e18, true, -0.5e18);

        assertEq(amountIn, 0.5e18);
        assertEq(amountOut, 0.5e18);
        assertEq(liquidityRemaining, 0.5e18 - 1, "liquidity remaining");
    }

    function test_ComputeSwapStep_Token0ExactOutFull() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, true, -1e18);

        assertEq(amountIn, 1e18);
        assertEq(amountOut, 1e18);
        assertEq(liquidityRemaining, 0);
    }

    function test_ComputeSwapStep_Token0ExactOutOver() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, true, -1.5e18);

        assertEq(amountIn, 1e18);
        assertEq(amountOut, 1e18);
        assertEq(liquidityRemaining, 0);
    }

    // Token 1 exact out

    function test_ComputeSwapStep_Token1ExactOutPartial() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, false, -0.5e18);

        assertEq(amountIn, 0.5e18);
        assertEq(amountOut, 0.5e18);
        assertEq(liquidityRemaining, 0.5e18);
    }

    function test_ComputeSwapStep_Token1ExactOutAmountInRoundUp() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) =
            computeSwapStep(Q128 + 1, 1e18, false, -0.5e18);

        assertEq(amountIn, 0.5e18);
        assertEq(amountOut, 0.5e18);
        assertEq(liquidityRemaining, 0.5e18, "liquidity remaining");
    }

    function test_ComputeSwapStep_Token1ExactOutFull() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, false, -1e18);

        assertEq(amountIn, 1e18);
        assertEq(amountOut, 1e18);
        assertEq(liquidityRemaining, 0);
    }

    function test_ComputeSwapStep_Token1ExactOutOver() external {
        (uint256 amountIn, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(Q128, 1e18, false, -1.5e18);

        assertEq(amountIn, 1e18);
        assertEq(amountOut, 1e18);
        assertEq(liquidityRemaining, 0);
    }
}
