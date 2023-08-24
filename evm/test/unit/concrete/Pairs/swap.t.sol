// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Pairs} from "src/core/Pairs.sol";
import {BitMaps} from "src/core/BitMaps.sol";
import {computeSwapStep} from "src/core/math/SwapMath.sol";
import {getRatioAtStrike, Q128, MAX_STRIKE, MIN_STRIKE} from "src/core/math/StrikeMath.sol";

import {console2} from "forge-std/console2.sol";

contract SwapTest is Test {
    using Pairs for Pairs.Pair;
    using BitMaps for BitMaps.BitMap;

    Pairs.Pair private pair;

    /// @notice Test swapping a pair that isn't initialized
    function test_Swap_NotInitialized() external {
        vm.expectRevert(Pairs.Initialized.selector);
        pair.swap(false, 0);
    }

    function test_Swap_Token1ExactIn() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        (int256 amount0, int256 amount1) = pair.swap(false, 0.5e18);

        vm.pauseGasMetering();

        (, uint256 _amountOut, uint256 _liquidityRemaining) =
            computeSwapStep(getRatioAtStrike(1), 1e18 - 1, false, 0.5e18);

        // amounts
        assertEq(amount0, -int256(_amountOut));
        assertEq(amount1, 0.5e18);

        uint256 liquidityNew = (1e18 - _liquidityRemaining - 1) / 10_000;
        uint256 liquidityGrowth = Q128 + (liquidityNew * Q128) / (1e18);
        uint256 composition = type(uint128).max - (_liquidityRemaining * Q128) / (1e18);

        // pair state
        assertEq(pair.strikes[0].liquidityGrowthSpreadX128[0].liquidityGrowthX128, liquidityGrowth);
        assertEq(pair.strikeCurrentCached, 0);
        assertEq(pair.strikeCurrent[0], 0);
        assertEq(pair.composition[0], composition);
        assertEq(pair.minSpreadLastUsedIndex, 0);

        vm.resumeGasMetering();
    }

    function test_Swap_Token0ExactOut() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        (int256 amount0, int256 amount1) = pair.swap(true, -0.5e18);

        vm.pauseGasMetering();

        (uint256 _amountIn,, uint256 _liquidityRemaining) =
            computeSwapStep(getRatioAtStrike(1), 1e18 - 1, true, -0.5e18);

        // amounts
        assertEq(amount0, -0.5e18, "amount 0");
        assertEq(amount1, int256(_amountIn), "amount 1");

        uint256 liquidityNew = (1e18 - _liquidityRemaining - 1) / 10_000;
        uint256 liquidityGrowth = Q128 + (liquidityNew * Q128) / (1e18);
        uint256 composition = type(uint128).max - (_liquidityRemaining * Q128) / (1e18);

        // pair state
        assertEq(pair.strikes[0].liquidityGrowthSpreadX128[0].liquidityGrowthX128, liquidityGrowth);
        assertEq(pair.strikeCurrentCached, 0);
        assertEq(pair.strikeCurrent[0], 0);
        assertEq(pair.composition[0], composition);
        assertEq(pair.minSpreadLastUsedIndex, 0);

        vm.resumeGasMetering();
    }

    function test_Swap_Token0ExactIn() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(0, 1, 1e18);
        pair.swap(false, 1e18 - 1);

        uint256 liquidityGrowthSpreadBefore = pair.strikes[0].liquidityGrowthSpreadX128[0].liquidityGrowthX128;

        vm.resumeGasMetering();

        (int256 amount0, int256 amount1) = pair.swap(true, 0.5e18);

        vm.pauseGasMetering();

        (, uint256 _amountOut, uint256 _liquidityRemaining) =
            computeSwapStep(getRatioAtStrike(-1), 1e18 - 1, true, 0.5e18);

        // amounts
        assertEq(amount0, 0.5e18);
        assertEq(amount1, -int256(_amountOut));

        uint256 liquidityNew = (1e18 - _liquidityRemaining - 1) / 10_000;
        uint256 liquidityGrowth = liquidityGrowthSpreadBefore + (liquidityNew * Q128) / (1e18);
        uint256 composition = (_liquidityRemaining * Q128) / (1e18);

        // pair state
        assertEq(pair.strikes[0].liquidityGrowthSpreadX128[0].liquidityGrowthX128, liquidityGrowth);
        assertEq(pair.strikeCurrentCached, 0);
        assertEq(pair.strikeCurrent[0], 0);
        assertEq(pair.composition[0], composition);
        assertEq(pair.minSpreadLastUsedIndex, 0);

        vm.resumeGasMetering();
    }

    function test_Swap_Token1ExactOut() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(0, 1, 1e18);
        pair.swap(false, 1e18 - 1);

        uint256 liquidityGrowthSpreadBefore = pair.strikes[0].liquidityGrowthSpreadX128[0].liquidityGrowthX128;

        vm.resumeGasMetering();

        (int256 amount0, int256 amount1) = pair.swap(false, -0.5e18);

        vm.pauseGasMetering();

        (uint256 _amountIn,, uint256 _liquidityRemaining) =
            computeSwapStep(getRatioAtStrike(-1), 1e18 - 1, false, -0.5e18);

        // amounts
        assertEq(amount0, int256(_amountIn));
        assertEq(amount1, -0.5e18);

        uint256 liquidityNew = (1e18 - _liquidityRemaining - 1) / 10_000;
        uint256 liquidityGrowth = liquidityGrowthSpreadBefore + (liquidityNew * Q128) / (1e18);
        uint256 composition = (_liquidityRemaining * Q128) / (1e18);

        // pair state
        assertEq(pair.strikes[0].liquidityGrowthSpreadX128[0].liquidityGrowthX128, liquidityGrowth);
        assertEq(pair.strikeCurrentCached, 0);
        assertEq(pair.strikeCurrent[0], 0);
        assertEq(pair.composition[0], composition);
        assertEq(pair.minSpreadLastUsedIndex, 0);

        vm.resumeGasMetering();
    }
}
