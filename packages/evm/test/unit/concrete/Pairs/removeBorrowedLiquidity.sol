// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Pairs} from "src/core/Pairs.sol";
import {BitMaps} from "src/core/BitMaps.sol";
import {MAX_STRIKE, MIN_STRIKE} from "src/core/math/StrikeMath.sol";

contract RemoveBorrowedLiquidityTest is Test {
    using Pairs for Pairs.Pair;
    using BitMaps for BitMaps.BitMap;

    Pairs.Pair private pair;

    /// @notice Test repaying liquidity for a pair that is not initialized
    function test_RemoveBorrowedLiquidity_NotInitialized() external {
        vm.expectRevert(Pairs.Initialized.selector);
        pair.removeBorrowedLiquidity(0, 1);
    }

    /// @notice Test repaying partial liquidity to a spread
    function test_RemoveBorrowedLiquidity_PartialSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(2, 1, 1e18);
        pair.addBorrowedLiquidity(2, 1e18);

        vm.resumeGasMetering();

        pair.removeBorrowedLiquidity(2, 0.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[2].liquidity[0].swap, 0.5e18);
        assertEq(pair.strikes[2].liquidity[0].borrowed, 0.5e18);
        assertEq(pair.strikes[2].activeSpread, 0);

        vm.resumeGasMetering();
    }

    /// @notice Test repaying full liquidity to a spread
    function test_RemoveBorrowedLiquidity_FullSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(2, 1, 1e18);
        pair.addBorrowedLiquidity(2, 1e18);

        vm.resumeGasMetering();

        pair.removeBorrowedLiquidity(2, 1e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[2].liquidity[0].swap, 1e18);
        assertEq(pair.strikes[2].liquidity[0].borrowed, 0);
        assertEq(pair.strikes[2].activeSpread, 0);

        vm.resumeGasMetering();
    }

    /// @notice Test repaying liquidity such that it needs to enter the next spread
    /// @dev Should add strike 2 from 0 to 1 strike order and strike 4 from 1 to 0 strike order
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 2 -> 1 -> 0 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 4 -> 5 -> MAX_STRIKE
    function test_RemoveBorrowedLiquidity_NextSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(3, 1, 1e18);
        pair.addSwapLiquidity(3, 2, 1e18);
        pair.addBorrowedLiquidity(3, 1.5e18);

        vm.resumeGasMetering();

        pair.removeBorrowedLiquidity(3, 1.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[3].liquidity[0].swap, 1e18);
        assertEq(pair.strikes[3].liquidity[0].borrowed, 0);

        assertEq(pair.strikes[3].liquidity[1].swap, 1e18);
        assertEq(pair.strikes[3].liquidity[1].borrowed, 0);

        assertEq(pair.strikes[3].activeSpread, 0);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 2);
        assertEq(pair.strikes[2].next0To1, 1);
        assertEq(pair.strikes[1].next0To1, 0);
        assertEq(pair.strikes[1].reference0To1, 0x2);
        assertEq(pair.strikes[2].reference0To1, 0x1);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(0), -1);
        assertEq(pair.bitMap0To1.nextBelow(-1), -2);
        assertEq(pair.bitMap0To1.nextBelow(-2), MIN_STRIKE);

        // 1 to 0 strike order
        assertEq(pair.strikes[0].next1To0, 4);
        assertEq(pair.strikes[4].next1To0, 5);
        assertEq(pair.strikes[5].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[4].reference1To0, 0x1);
        assertEq(pair.strikes[5].reference1To0, 0x2);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 5);
        assertEq(pair.bitMap1To0.nextBelow(5), 4);
        assertEq(pair.bitMap1To0.nextBelow(4), 0);

        vm.resumeGasMetering();
    }

    /// @notice Test borrowing liquidity when there is an empty spread in the middle before a spread with liquidity
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 1 -> 0 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 5 -> MAX_STRIKE
    function test_RemoveBorrowedLiquidity_NextSpreadZero() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(3, 2, 1e18);
        pair.addBorrowedLiquidity(3, 0.5e18);

        vm.resumeGasMetering();

        pair.removeBorrowedLiquidity(3, 0.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[3].liquidity[1].swap, 1e18);
        assertEq(pair.strikes[3].liquidity[1].borrowed, 0);

        assertEq(pair.strikes[3].activeSpread, 1);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 1);
        assertEq(pair.strikes[1].next0To1, 0);
        assertEq(pair.strikes[1].reference0To1, 0x2);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(0), -1);
        assertEq(pair.bitMap0To1.nextBelow(-1), MIN_STRIKE);

        // 1 to 0 strike order
        assertEq(pair.strikes[0].next1To0, 5);
        assertEq(pair.strikes[5].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[5].reference1To0, 0x2);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 5);
        assertEq(pair.bitMap1To0.nextBelow(5), 0);

        vm.resumeGasMetering();
    }

    /// @notice Test repaying liquidity such that it needs to go to the next spread, but one of the strikes where a
    /// swap is offered must be preserved
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 0 -> -1 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 2 -> 3 -> MAX_STRIKE
    function test_RemoveBorrowedLiquidity_NextSpreadPreserve() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(1, 1, 1e18);
        pair.addSwapLiquidity(1, 2, 1e18);
        pair.addBorrowedLiquidity(1, 1.5e18);

        vm.resumeGasMetering();

        pair.removeBorrowedLiquidity(1, 1.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[1].liquidity[0].swap, 1e18);
        assertEq(pair.strikes[1].liquidity[0].borrowed, 0);

        assertEq(pair.strikes[1].liquidity[1].swap, 1e18);
        assertEq(pair.strikes[1].liquidity[1].borrowed, 0);

        assertEq(pair.strikes[1].activeSpread, 0);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 0);
        assertEq(pair.strikes[0].next0To1, -1);
        assertEq(pair.strikes[-1].reference0To1, 0x2);
        assertEq(pair.strikes[0].reference0To1, 0x1);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(MAX_STRIKE), 1);
        assertEq(pair.bitMap0To1.nextBelow(1), 0);

        // 1 to 0 strike order
        assertEq(pair.strikes[0].next1To0, 2);
        assertEq(pair.strikes[2].next1To0, 3);
        assertEq(pair.strikes[3].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[2].reference1To0, 0x1);
        assertEq(pair.strikes[3].reference1To0, 0x2);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 3);
        assertEq(pair.bitMap1To0.nextBelow(3), 2);
        assertEq(pair.bitMap1To0.nextBelow(2), 0);

        vm.resumeGasMetering();
    }

    function test_RemoveBorrowedLiquidity_OutOfBounds() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        vm.expectRevert(Pairs.OutOfBounds.selector);
        pair.removeBorrowedLiquidity(1, 1);
    }
}
