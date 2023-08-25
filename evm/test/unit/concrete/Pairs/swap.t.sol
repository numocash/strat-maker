// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Pairs} from "src/core/Pairs.sol";
import {BitMaps} from "src/core/BitMaps.sol";
import {computeSwapStep} from "src/core/math/SwapMath.sol";
import {getRatioAtStrike, Q128, MAX_STRIKE, MIN_STRIKE} from "src/core/math/StrikeMath.sol";

contract SwapTest is Test {
    using Pairs for Pairs.Pair;
    using BitMaps for BitMaps.BitMap;

    Pairs.Pair private pair;

    /// @notice Test swapping a pair that isn't initialized
    function test_Swap_NotInitialized() external {
        vm.expectRevert(Pairs.Initialized.selector);
        pair.swap(false, 0);
    }

    /// @notice Test swapping 0 to 1 so that strike 0 is cleaned up because there is not an available swap on that
    /// strike
    /// @dev 0 to 1 strike order is MAX_STRIKE -> -1 -> MIN_STRIKE
    function test_Swap_0To1RemoveEmptyStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(0, 1, 1e18);
        pair.composition[0] = type(uint128).max;

        vm.resumeGasMetering();

        pair.swap(true, 0.5e18);

        vm.pauseGasMetering();

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, -1);
        assertEq(pair.strikes[-1].next0To1, MIN_STRIKE);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(MAX_STRIKE), 1);
        assertEq(pair.bitMap0To1.nextBelow(1), MIN_STRIKE);

        vm.resumeGasMetering();
    }

    /// @notice Test swapping 1 to 0 so that strike 0 is cleaned up because there is not an available swap on that
    /// strike
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 1 -> MAX_STRIKE
    function test_Swap_1To0RemoveEmptyStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        pair.swap(false, 0.5e18);

        vm.pauseGasMetering();

        // 1 to 0 strike order
        assertEq(pair.strikes[MIN_STRIKE].next1To0, 1);
        assertEq(pair.strikes[1].next1To0, MAX_STRIKE);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 1);
        assertEq(pair.bitMap1To0.nextBelow(1), MIN_STRIKE);

        vm.resumeGasMetering();
    }

    /// @notice Test finding the next strike offering a trade
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 0 -> -5 -> MIN_STRIKE
    function test_Swap_FindClosestStrike0To1() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(-4, 1, 1e18);
        pair.strikeCurrent[0] = -4;
        pair.strikeCurrentCached = -2;

        vm.resumeGasMetering();

        pair.swap(true, 0.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikeCurrentCached, -4);
        assertEq(pair.strikeCurrent[0], -4);

        vm.resumeGasMetering();
    }

    /// @notice Test finding the next strike offering a trade
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 5 -> MAX_STRIKE
    function test_Swap_FindClosestStrike1To0() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(4, 1, 1e18);
        pair.strikeCurrent[0] = 4;
        pair.composition[0] = type(uint128).max;
        pair.strikeCurrentCached = 3;

        vm.resumeGasMetering();

        pair.swap(false, 0.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikeCurrentCached, 4);
        assertEq(pair.strikeCurrent[0], 4);

        vm.resumeGasMetering();
    }

    /// @notice Test finding intial liquidity for a 1 to 0 swap
    /// @dev Swap takes palce on strike 0
    function test_Swap_InitialLiquidity0To1() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(1, 1, 1e18);
        pair.strikeCurrent[0] = 1;
        pair.strikeCurrentCached = 1;

        vm.resumeGasMetering();

        pair.swap(true, 0.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikeCurrentCached, 1);
        assertEq(pair.strikeCurrent[0], 1);

        vm.resumeGasMetering();
    }

    /// @notice Test finding intial liquidity for a 1 to 0 swap
    /// @dev Swap takes place on strike 2
    function test_Swap_InitialLiquidity1To0() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(1, 1, 1e18);
        pair.strikeCurrent[0] = 1;
        pair.composition[0] = type(uint128).max;
        pair.strikeCurrentCached = 1;

        vm.resumeGasMetering();

        pair.swap(false, 0.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikeCurrentCached, 1);
        assertEq(pair.strikeCurrent[0], 1);

        vm.resumeGasMetering();
    }

    /// @notice Test finding intial liquidity for a trade with multiple spreads
    /// @dev 1 to 0 trade taking place on strike 0
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> MAX_STRIKE
    function test_Swap_InitialLiquidityMultiSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(-1, 1, 1e18);
        pair.addSwapLiquidity(-2, 2, 1e18);

        pair.strikeCurrent[0] = -1;
        pair.strikeCurrent[1] = -2;

        pair.composition[0] = type(uint128).max;
        pair.composition[1] = type(uint128).max;

        pair.strikeCurrentCached = -1;

        vm.resumeGasMetering();

        pair.swap(false, 1.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikeCurrentCached, -1);
        assertEq(pair.strikeCurrent[0], -1);
        assertEq(pair.strikeCurrent[1], -2);

        assertEq(pair.composition[0], pair.composition[1]);

        vm.resumeGasMetering();
    }

    /// @notice Test invalidating spreads that aren't offering trades at the same strike as the lower spread
    function test_Swap_InitialMaskHigherSpreads() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(-1, 1, 1e18);
        pair.addSwapLiquidity(-2, 2, 1e18);

        pair.strikeCurrent[0] = -1;
        pair.strikeCurrent[1] = -1;

        pair.composition[0] = type(uint128).max;
        pair.composition[1] = type(uint128).max;

        pair.strikeCurrentCached = -1;

        vm.resumeGasMetering();

        vm.expectRevert(Pairs.OutOfBounds.selector);
        pair.swap(false, 1.5e18);
    }

    /// @notice Test accounting fees for a 0 to 1 swap
    function test_Swap_Fees0To1() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(1, 1, 1e18);
        pair.strikeCurrent[0] = 1;
        pair.strikeCurrentCached = 1;

        vm.resumeGasMetering();

        pair.swap(true, 0.5e18);

        vm.pauseGasMetering();

        (,, uint256 liquidityRemaining) = computeSwapStep(getRatioAtStrike(0), 1e18 - 1, true, 0.5e18);

        uint256 liquidityNew = uint256(1e18 - liquidityRemaining - 1) / 10_000;
        uint256 liquidityGrowth = Q128 + (liquidityNew * Q128) / (1e18);
        assertEq(pair.strikes[1].liquidityGrowthSpreadX128[0].liquidityGrowthX128, liquidityGrowth);

        vm.resumeGasMetering();
    }

    /// @notice Test accounting fees for a 1 to 0 swap
    function test_Swap_Fees1To0() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(1, 1, 1e18);
        pair.strikeCurrent[0] = 1;
        pair.composition[0] = type(uint128).max;
        pair.strikeCurrentCached = 1;

        vm.resumeGasMetering();

        pair.swap(false, 0.5e18);

        vm.pauseGasMetering();

        (,, uint256 liquidityRemaining) = computeSwapStep(getRatioAtStrike(0), 1e18 - 1, false, 0.5e18);

        uint256 liquidityNew = uint256(1e18 - liquidityRemaining - 1) / 10_000;
        uint256 liquidityGrowth = Q128 + (liquidityNew * Q128) / (1e18);
        assertEq(pair.strikes[1].liquidityGrowthSpreadX128[0].liquidityGrowthX128, liquidityGrowth);

        vm.resumeGasMetering();
    }

    /// @notice Test accounting fees for trades that use one multiple
    function test_Swap_FeesMultiSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(-1, 1, 1e18);
        pair.addSwapLiquidity(-2, 2, 1e18);

        pair.strikeCurrent[0] = -1;
        pair.strikeCurrent[1] = -2;

        pair.composition[0] = type(uint128).max;
        pair.composition[1] = type(uint128).max;

        pair.strikeCurrentCached = -1;

        vm.resumeGasMetering();

        pair.swap(false, 1.5e18);

        vm.pauseGasMetering();

        (,, uint256 liquidityRemaining) = computeSwapStep(getRatioAtStrike(0), 1e18 - 1, false, 0.5e18);

        uint256 liquidityNew = uint256(1e18 - (liquidityRemaining / 2) - 1) / 10_000;
        uint256 liquidityGrowth = Q128 + (liquidityNew * Q128) / (1e18);
        assertEq(pair.strikes[-1].liquidityGrowthSpreadX128[0].liquidityGrowthX128, liquidityGrowth);

        liquidityNew = uint256(1e18 - (liquidityRemaining / 2) - 1) / 5000;
        liquidityGrowth = Q128 + (liquidityNew * Q128) / (1e18);
        assertEq(pair.strikes[-2].liquidityGrowthSpreadX128[1].liquidityGrowthX128, liquidityGrowth);

        vm.resumeGasMetering();
    }

    /// @notice Test swapping token 0 exact in
    /// @dev 0 => 1 swap, offered at strike 0
    function test_Swap_Token0ExactInAmounts() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(1, 1, 1e18);
        pair.strikeCurrent[0] = 1;
        pair.strikeCurrentCached = 1;

        vm.resumeGasMetering();

        (int256 amount0, int256 amount1) = pair.swap(true, 0.5e18);

        vm.pauseGasMetering();

        (, uint256 amountOut, uint256 liquidityRemaining) = computeSwapStep(getRatioAtStrike(0), 1e18 - 1, true, 0.5e18);

        // amounts
        assertEq(amount0, 0.5e18);
        assertEq(amount1, -int256(amountOut));

        uint256 composition = (liquidityRemaining * Q128) / (1e18);
        assertEq(pair.composition[0], composition);

        vm.resumeGasMetering();
    }

    /// @notice Test swapping token 1 exact out
    /// @dev 0 => 1 swap, offered at strike 0
    function test_Swap_Token1ExactOutAmounts() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(1, 1, 1e18);
        pair.strikeCurrent[0] = 1;
        pair.strikeCurrentCached = 1;

        vm.resumeGasMetering();

        (int256 amount0, int256 amount1) = pair.swap(false, -0.5e18);

        vm.pauseGasMetering();

        (uint256 amountIn,, uint256 liquidityRemaining) = computeSwapStep(getRatioAtStrike(0), 1e18 - 1, false, -0.5e18);

        // amounts
        assertEq(amount0, int256(amountIn));
        assertEq(amount1, -0.5e18);

        uint256 composition = (liquidityRemaining * Q128) / (1e18);
        assertEq(pair.composition[0], composition);

        vm.resumeGasMetering();
    }

    /// @notice Test swapping token 1 exact in
    /// @dev 1 => 0 swap, offered at strike 0
    function test_Swap_Token1ExactInAmounts() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(-1, 1, 1e18);
        pair.strikeCurrent[0] = -1;
        pair.strikeCurrentCached = -1;
        pair.composition[0] = type(uint128).max;

        vm.resumeGasMetering();

        (int256 amount0, int256 amount1) = pair.swap(false, 0.5e18);

        vm.pauseGasMetering();

        (, uint256 amountOut, uint256 liquidityRemaining) =
            computeSwapStep(getRatioAtStrike(0), 1e18 - 1, false, 0.5e18);

        // amounts
        assertEq(amount0, -int256(amountOut));
        assertEq(amount1, 0.5e18);

        uint256 composition = type(uint128).max - (liquidityRemaining * Q128) / (1e18);
        assertEq(pair.composition[0], composition);

        vm.resumeGasMetering();
    }

    /// @notice Test swapping token 0 exact out
    /// @dev 1 => 0 swap, offered at strike 0
    function test_Swap_Token0ExactOutAmounts() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(-1, 1, 1e18);
        pair.strikeCurrent[0] = -1;
        pair.strikeCurrentCached = -1;
        pair.composition[0] = type(uint128).max;

        vm.resumeGasMetering();

        (int256 amount0, int256 amount1) = pair.swap(true, -0.5e18);

        vm.pauseGasMetering();

        (uint256 amountIn,, uint256 liquidityRemaining) = computeSwapStep(getRatioAtStrike(0), 1e18 - 1, true, -0.5e18);

        // amounts
        assertEq(amount0, -0.5e18, "amount 0");
        assertEq(amount1, int256(amountIn), "amount 1");

        uint256 composition = type(uint128).max - (liquidityRemaining * Q128) / (1e18);
        assertEq(pair.composition[0], composition);

        vm.resumeGasMetering();
    }

    /// @notice Test swapping 0 to 1 with the swap having to move between multiple strikes in a row
    function test_Swap_0To1ConsecutiveStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addSwapLiquidity(-1, 1, 1e18);

        pair.composition[0] = type(uint128).max;

        vm.resumeGasMetering();

        pair.swap(true, 1.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikeCurrentCached, -1);
        assertEq(pair.strikeCurrent[0], -1);

        vm.resumeGasMetering();
    }

    /// @notice Test swapping 1 to 0 with the swap having to move between multiple strikes in a row
    function test_Swap_1To0ConsecutiveStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addSwapLiquidity(1, 1, 1e18);

        vm.resumeGasMetering();

        pair.swap(false, 1.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikeCurrentCached, 1);
        assertEq(pair.strikeCurrent[0], 1);

        vm.resumeGasMetering();
    }

    /// @notice Test including a spread that has the correct strike current
    function test_Swap_0To1NextStrikeCurrent() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addSwapLiquidity(0, 2, 1e18);
        pair.addSwapLiquidity(-1, 1, 1e18);

        pair.composition[0] = type(uint128).max;
        pair.composition[1] = type(uint128).max;

        vm.resumeGasMetering();

        pair.swap(true, 2.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikeCurrentCached, -1);
        assertEq(pair.strikeCurrent[0], -1);
        assertEq(pair.strikeCurrent[1], 0);

        vm.resumeGasMetering();
    }

    /// @notice Test including a spread that has the correct strike current
    function test_Swap_1To0NextStrikeCurrent() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addSwapLiquidity(0, 2, 1e18);
        pair.addSwapLiquidity(1, 1, 1e18);

        vm.resumeGasMetering();

        pair.swap(false, 2.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikeCurrentCached, 1);
        assertEq(pair.strikeCurrent[0], 1);
        assertEq(pair.strikeCurrent[1], 0);

        vm.resumeGasMetering();
    }

    /// @notice Test invalidating spreads that aren't offering trades at the same strike as the lower spread
    function test_Swap_0To1MaskHigherSpreads() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addSwapLiquidity(0, 2, 1e18);
        pair.addSwapLiquidity(-1, 1, 1e18);

        pair.composition[0] = type(uint128).max;
        pair.composition[1] = type(uint128).max;

        pair.strikeCurrent[1] = -1;

        vm.resumeGasMetering();

        vm.expectRevert();
        pair.swap(true, 2.5e18);
    }

    /// @notice Test invalidating spreads that aren't offering trades at the same strike as the lower spread
    function test_Swap_1To0MaskHigherSpreads() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addSwapLiquidity(0, 2, 1e18);
        pair.addSwapLiquidity(1, 1, 1e18);

        pair.strikeCurrent[1] = 1;

        vm.resumeGasMetering();

        vm.expectRevert();
        pair.swap(false, 2.5e18);
    }

    /// @notice Test swapping with the first available spread being non-zero
    function test_Swap_Spread0Empty() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(0, 2, 1e18);

        vm.resumeGasMetering();

        pair.swap(false, 0.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikeCurrentCached, 0);
        assertEq(pair.strikeCurrent[0], 1);
        assertEq(pair.strikeCurrent[1], 0);
        assertEq(pair.strikeCurrent[2], 0);

        vm.resumeGasMetering();
    }

    /// @notice Test swapping with a spread between the lowest and highest being zero
    function test_Swap_MiddleSpreadEmpty() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(1, 1, 1e18);
        pair.addSwapLiquidity(3, 3, 1e18);

        pair.strikeCurrentCached = 1;

        pair.strikeCurrent[0] = 1;
        pair.strikeCurrent[2] = 3;

        vm.resumeGasMetering();

        pair.swap(true, 1.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikeCurrentCached, 1);
        assertEq(pair.strikeCurrent[0], 1);
        assertEq(pair.strikeCurrent[1], 2);
        assertEq(pair.strikeCurrent[2], 3);
        assertEq(pair.strikeCurrent[3], 0);

        vm.resumeGasMetering();
    }
}
