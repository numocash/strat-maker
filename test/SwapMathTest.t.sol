// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {computeSwapStep} from "src/core/SwapMath.sol";
import {Q128, Q96} from "src/core/TickMath.sol";

contract SwapMathTest is Test {
    function testToken0ExactInBasic() external {
        (uint256 amount0, uint256 amount1) = computeSwapStep(Q128, type(uint96).max, 1e18, true, 1e18);

        assertEq(amount0, 1e18, "amount0");
        assertEq(amount1, 1e18, "amount1");
    }

    function testToken1ExactInBasic() external {
        (uint256 amount0, uint256 amount1) = computeSwapStep(Q128, 0, 1e18, false, 1e18);

        assertEq(amount0, 1e18, "amount0");
        assertEq(amount1, 1e18, "amount1");
    }

    function testToken0ExactOutBasic() external {
        (uint256 amount0, uint256 amount1) = computeSwapStep(Q128, 0, 1e18, true, -1e18);

        assertEq(amount0, 1e18, "amount0");
        assertEq(amount1, 1e18, "amount1");
    }

    function testToken1ExactOutBasic() external {
        (uint256 amount0, uint256 amount1) = computeSwapStep(Q128, type(uint96).max, 1e18, false, -1e18);

        assertEq(amount0, 1e18, "amount0");
        assertEq(amount1, 1e18, "amount1");
    }

    function testToken0ExactInPartial() external {
        (uint256 amount0, uint256 amount1) = computeSwapStep(Q128, type(uint96).max, 1e18, true, 0.5e18);

        assertEq(amount0, 0.5e18, "amount0");
        assertEq(amount1, 0.5e18, "amount1");
    }

    function testToken1ExactInPartial() external {
        (uint256 amount0, uint256 amount1) = computeSwapStep(Q128, 0, 1e18, false, 0.5e18);

        assertEq(amount0, 0.5e18, "amount0");
        assertEq(amount1, 0.5e18, "amount1");
    }

    function testToken0ExactOutPartial() external {
        (uint256 amount0, uint256 amount1) = computeSwapStep(Q128, 0, 1e18, true, -0.5e18);

        assertEq(amount0, 0.5e18, "amount0");
        assertEq(amount1, 0.5e18, "amount1");
    }

    function testToken1ExactOutPartial() external {
        (uint256 amount0, uint256 amount1) = computeSwapStep(Q128, type(uint96).max, 1e18, false, -0.5e18);

        assertEq(amount0, 0.5e18, "amount0");
        assertEq(amount1, 0.5e18, "amount1");
    }
}
