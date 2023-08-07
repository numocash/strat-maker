// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {
    scaleLiquidityDown,
    scaleLiquidityUp,
    getAmount0,
    getAmount1,
    getLiquidityForAmount0,
    getLiquidityForAmount1
} from "src/core/math/LiquidityMath.sol";

contract LiquidityMathFuzzTest is Test {
    function testFuzz_ScaleLiqudity(uint128 liquidity, uint8 scalingFactor) external {
        vm.assume(scalingFactor <= 128);

        assertEq(scaleLiquidityDown(scaleLiquidityUp(liquidity, scalingFactor), scalingFactor), liquidity);
    }

    /// @notice amount 0 should always decrease after converting to liquidity and back
    function testFuzz_Liquidity0(uint256 amount0, uint256 ratioX128) external {
        // vm.assume(ratioX128 != 0);
        // assertLe(getAmount0(getLiquidityForAmount0(amount0, ratioX128, false), ratioX128, false), amount0);
    }

    /// @notice amount 1 should always be equal after converting to liquidity and back
    function testFuzz_Liquidity1(uint256 amount1) external {
        assertEq(getAmount1(getLiquidityForAmount1(amount1)), amount1);
    }

    // TODO: fuzz test amounts
}
