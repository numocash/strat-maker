// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {computeSwapStep} from "src/core/math/SwapMath.sol";
import {mulDiv, mulDivRoundingUp} from "src/core/math/FullMath.sol";
import {mulDivOverflow, mulDivRoundingUpOverflow} from "../../utils/FullMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

import {console2} from "forge-std/console2.sol";

contract SwapMathFuzzTest is Test {
    /// @notice token 0 exact in always has a price <= ratio, 0 => 1
    function testFuzz_ComputeSwapStep_Token0ExactIn_PriceLess(
        uint256 ratioX128,
        uint256 liquidity,
        uint256 amountDesired
    )
        external
    {
        // exact in
        vm.assume(amountDesired <= uint256(type(int256).max));
        vm.assume(amountDesired > 0);
        // max amount in can fit in uint256
        vm.assume(ratioX128 != 0);
        vm.assume(!mulDivOverflow(liquidity, Q128, ratioX128));

        // amount out can fit in uint256
        vm.assume(!mulDivOverflow(amountDesired, ratioX128, Q128));
        (uint256 amountIn, uint256 amountOut,) = computeSwapStep(ratioX128, liquidity, true, int256(amountDesired));
        vm.assume(amountIn > 0);

        uint256 price = mulDivRoundingUp(amountOut, Q128, amountIn);

        assertLe(price, ratioX128);
    }

    /// @notice token 1 exact out always has a price <= ratio, 0 => 1
    function testFuzz_ComputeSwapStep_Token1ExactOut_PriceLess(
        uint256 ratioX128,
        uint256 liquidity,
        uint256 amountDesired
    )
        external
    {
        // exact in
        vm.assume(amountDesired <= uint256(type(int256).max));
        vm.assume(amountDesired > 0);
        // max amount in can fit in uint256
        vm.assume(ratioX128 != 0);

        // amount out can fit in uint256
        vm.assume(!mulDivOverflow(amountDesired, Q128, ratioX128));

        (uint256 amountIn, uint256 amountOut,) = computeSwapStep(ratioX128, liquidity, false, -int256(amountDesired));
        vm.assume(amountIn > 0);
        vm.assume(!mulDivOverflow(amountOut, Q128, amountIn));

        uint256 price = mulDivRoundingUp(amountOut, Q128, amountIn);

        assertLe(price, ratioX128);
    }

    /// @notice token 0 exact out always has a price >= ratio, 1 => 0
    function testFuzz_ComputeSwapStep_Token0ExactOut_PriceGreater(
        uint256 ratioX128,
        uint256 liquidity,
        uint256 amountDesired
    )
        external
    {
        // exact in
        vm.assume(amountDesired <= uint256(type(int256).max));
        vm.assume(amountDesired > 0);
        // max amount in can fit in uint256
        vm.assume(ratioX128 != 0);
        vm.assume(!mulDivOverflow(liquidity, Q128, ratioX128));

        // amount in can fit in uint256
        vm.assume(!mulDivRoundingUpOverflow(amountDesired, ratioX128, Q128));

        (uint256 amountIn, uint256 amountOut,) = computeSwapStep(ratioX128, liquidity, true, -int256(amountDesired));
        vm.assume(amountOut > 0);
        vm.assume(!mulDivOverflow(amountIn, Q128, amountOut));

        uint256 price = mulDiv(amountIn, Q128, amountOut);

        assertGe(price, ratioX128);
    }

    /// @notice token 1 exact in always has a price >= ratio
    function testFuzz_ComputeSwapStep_Token1ExactIn_PriceGreater(
        uint256 ratioX128,
        uint256 liquidity,
        uint256 amountDesired
    )
        external
    {
        // exact in
        vm.assume(amountDesired <= uint256(type(int256).max));
        vm.assume(amountDesired > 0);
        // max amount in can fit in uint256
        vm.assume(ratioX128 != 0);

        // amount out can fit in uint256
        vm.assume(!mulDivOverflow(amountDesired, Q128, ratioX128));

        (uint256 amountIn, uint256 amountOut,) = computeSwapStep(ratioX128, liquidity, false, int256(amountDesired));
        vm.assume(amountOut > 0);
        vm.assume(!mulDivOverflow(amountIn, Q128, amountOut));

        uint256 price = mulDiv(amountIn, Q128, amountOut);

        assertGe(price, ratioX128);
    }
}
