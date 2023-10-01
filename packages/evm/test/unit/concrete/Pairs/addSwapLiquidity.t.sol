// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Pairs} from "src/core/Pairs.sol";
import {BitMaps} from "src/core/BitMaps.sol";
import {MAX_STRIKE, MIN_STRIKE} from "src/core/math/StrikeMath.sol";

contract AddSwapLiquidityTest is Test {
    using Pairs for Pairs.Pair;
    using BitMaps for BitMaps.BitMap;

    Pairs.Pair private pair;

    /// @notice Test adding to a strike that is not initialized
    function test_AddSwapLiquidity_NotInitialized() external {
        vm.expectRevert();
        pair.addSwapLiquidity(0, 1, 1e18);
    }

    /// @notice Test adding to a strike with an invalid spread
    function test_AddSwapLiquidity_InvalidSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        vm.expectRevert();
        pair.addSwapLiquidity(0, 0, 1e18);
    }

    /// @notice Test updating a strike with an invalid strike
    function test_AddSwapLiquidity_InvalidStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        vm.expectRevert();
        pair.addSwapLiquidity(type(int24).max, 1, 1e18);
    }

    /// @notice Test adding to a completely fresh strike
    /// @dev Provides 0 to 1 liquidity to strike 1
    /// @dev Provides 1 to 0 liquidity to strike 3
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 1 -> 0 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 3 -> MAX_STRIKE
    function test_AddSwapLiquidity_NewStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        uint128 displacedLiquidity = pair.addSwapLiquidity(2, 1, 1e18);

        vm.pauseGasMetering();

        assertEq(displacedLiquidity, 0);
        assertEq(pair.strikes[2].liquidity[0].swap, 1e18);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 1);
        assertEq(pair.strikes[1].next0To1, 0);
        assertEq(pair.strikes[1].reference0To1, 0x1);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(0), -1);

        // 1 to 0 strike order
        assertEq(pair.strikes[0].next1To0, 3);
        assertEq(pair.strikes[3].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[3].reference1To0, 0x1);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 3);

        vm.resumeGasMetering();
    }

    /// @notice Test adding to a strike where one of the strikes where a swap is offered intersects with an existing
    /// strike
    /// @dev Provides 0 to 1 liquidity to strike -1 and 1
    /// @dev Provides 1 to 0 liquidity to strike 3
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 1 -> 0 -> -1 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 3 -> MAX_STRIKE
    function test_AddSwapLiquidity_IntersectingStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(2, 1, 1e18);

        vm.resumeGasMetering();

        pair.addSwapLiquidity(1, 2, 1e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[1].liquidity[1].swap, 1e18);
        assertEq(pair.strikes[2].liquidity[0].swap, 1e18);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 1);
        assertEq(pair.strikes[1].next0To1, 0);
        assertEq(pair.strikes[0].next0To1, -1);

        assertEq(pair.strikes[-1].reference0To1, 0x2);
        assertEq(pair.strikes[1].reference0To1, 0x1);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(MAX_STRIKE), 1);
        assertEq(pair.bitMap0To1.nextBelow(1), 0);
        assertEq(pair.bitMap0To1.nextBelow(0), -1);

        // 1 to 0 strike order
        assertEq(pair.strikes[0].next1To0, 3);
        assertEq(pair.strikes[3].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[3].reference1To0, 0x3);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 3);

        vm.resumeGasMetering();
    }

    /// @notice Test adding to a strike with existing liquidity
    /// @dev Provides 0 to 1 liquidity to strike  1
    /// @dev Provides 1 to 0 liquidity to strike 3
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 1 -> 0 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 3 -> MAX_STRIKE
    function test_AddSwapLiquidity_ExistingStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(2, 1, 1e18);

        vm.resumeGasMetering();

        uint128 displacedLiquidity = pair.addSwapLiquidity(2, 1, 1e18);

        vm.pauseGasMetering();

        assertEq(displacedLiquidity, 0);
        assertEq(pair.strikes[2].liquidity[0].swap, 2e18);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 1);
        assertEq(pair.strikes[1].next0To1, 0);
        assertEq(pair.strikes[1].reference0To1, 1);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(0), -1);

        // 1 to 0 strike order
        assertEq(pair.strikes[0].next1To0, 3);
        assertEq(pair.strikes[3].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[3].reference1To0, 1);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 3);

        vm.resumeGasMetering();
    }

    /// @notice Test updating a strike by adding liquidity but one of the strikes where a swap is offered must be
    /// preserved
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 0 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 2 -> MAX_STRIKE
    function test_AddSwapLiquidity_StrikePreserve() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        pair.addSwapLiquidity(1, 1, 1e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[1].liquidity[0].swap, 1e18);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 0);
        assertEq(pair.strikes[0].next0To1, MIN_STRIKE);
        assertEq(pair.strikes[0].reference0To1, 1);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(MAX_STRIKE), 0);
        assertEq(pair.bitMap0To1.nextBelow(0), MIN_STRIKE);

        // 1 to 0 strike order
        assertEq(pair.strikes[0].next1To0, 2);
        assertEq(pair.strikes[2].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[0].reference1To0, 0);
        assertEq(pair.strikes[2].reference1To0, 1);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 2);

        vm.resumeGasMetering();
    }

    /// @notice Test overflow by adding too much liquidity
    function test_AddSwapLiquidity_Overflow() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(2, 1, type(uint128).max);

        vm.resumeGasMetering();

        vm.expectRevert(Pairs.Overflow.selector);
        pair.addSwapLiquidity(2, 1, 1);
    }

    /// @notice Test adding swap liquidity under the current active spread;
    function test_AddSwapLiquidity_UnderActiveSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.strikes[2].activeSpread = 1;

        vm.resumeGasMetering();

        uint128 displacedLiquidity = pair.addSwapLiquidity(2, 1, 1e18);

        vm.pauseGasMetering();

        assertEq(displacedLiquidity, 1e18);
        assertEq(pair.strikes[2].liquidity[0].borrowed, 1e18);

        vm.resumeGasMetering();
    }
}
