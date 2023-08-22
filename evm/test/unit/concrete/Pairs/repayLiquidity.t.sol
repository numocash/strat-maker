// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Pairs} from "src/core/Pairs.sol";
import {BitMaps} from "src/core/BitMaps.sol";
import {MAX_STRIKE, MIN_STRIKE} from "src/core/math/StrikeMath.sol";

contract BorrowLiquidityTest is Test {
    using Pairs for Pairs.Pair;
    using BitMaps for BitMaps.BitMap;

    Pairs.Pair private pair;

    /// @notice Test repaying liquidity for a pair that is not initialized
    function test_RepayLiquidity_NotInitialized() external {
        vm.expectRevert(Pairs.Initialized.selector);
        pair.repayLiquidity(0, 1);
    }

    /// @notice Test repaying partial liquidity to a spread
    function test_RepayLiquidity_PartialSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.updateStrike(2, 1, 1e18);
        pair.borrowLiquidity(2, 1e18);

        vm.resumeGasMetering();

        pair.repayLiquidity(2, 0.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[2].liquidityBiDirectional[0], 0.5e18);
        assertEq(pair.strikes[2].liquidityBorrowed[0], 0.5e18);
        assertEq(pair.strikes[2].activeSpread, 0);

        vm.resumeGasMetering();
    }

    /// @notice Test repaying full liquidity to a spread
    function test_RepayLiquidity_FullSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.updateStrike(2, 1, 1e18);
        pair.borrowLiquidity(2, 1e18);

        vm.resumeGasMetering();

        pair.repayLiquidity(2, 1e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[2].liquidityBiDirectional[0], 1e18);
        assertEq(pair.strikes[2].liquidityBorrowed[0], 0);
        assertEq(pair.strikes[2].activeSpread, 0);

        vm.resumeGasMetering();
    }

    /// @notice Test repaying liquidity such that it needs to enter the next spread
    /// @dev Should add strike 2 from 0 to 1 strike order and strike 4 from 1 to 0 strike order
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 2 -> 1 -> 0 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 4 -> 5 -> MAX_STRIKE
    function test_RepayLiquidity_NextSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.updateStrike(3, 1, 1e18);
        pair.updateStrike(3, 2, 1e18);
        pair.borrowLiquidity(3, 1.5e18);

        vm.resumeGasMetering();

        pair.repayLiquidity(3, 1.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[3].liquidityBiDirectional[0], 1e18);
        assertEq(pair.strikes[3].liquidityBorrowed[0], 0);

        assertEq(pair.strikes[3].liquidityBiDirectional[1], 1e18);
        assertEq(pair.strikes[3].liquidityBorrowed[1], 0);

        assertEq(pair.strikes[3].activeSpread, 0);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 2);
        assertEq(pair.strikes[2].next0To1, 1);
        assertEq(pair.strikes[1].next0To1, 0);
        assertEq(pair.strikes[1].reference0To1, 1);
        assertEq(pair.strikes[2].reference0To1, 1);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(0), -1);
        assertEq(pair.bitMap0To1.nextBelow(-1), -2);
        assertEq(pair.bitMap0To1.nextBelow(-2), MIN_STRIKE);

        // 1 to 0 strike order
        assertEq(pair.strikes[0].next1To0, 4);
        assertEq(pair.strikes[4].next1To0, 5);
        assertEq(pair.strikes[5].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[4].reference1To0, 1);
        assertEq(pair.strikes[5].reference1To0, 1);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 5);
        assertEq(pair.bitMap1To0.nextBelow(5), 4);
        assertEq(pair.bitMap1To0.nextBelow(4), 0);

        vm.resumeGasMetering();
    }

    /// @notice Test borrowing liquidity when there is an empty spread in the middle before a spread with liquidity
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 1 -> 0 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 5 -> MAX_STRIKE
    function test_RepayLiquidity_NextSpreadZero() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.updateStrike(3, 2, 1e18);
        pair.borrowLiquidity(3, 0.5e18);

        vm.resumeGasMetering();

        pair.repayLiquidity(3, 0.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[3].liquidityBiDirectional[1], 1e18);
        assertEq(pair.strikes[3].liquidityBorrowed[1], 0);

        assertEq(pair.strikes[3].activeSpread, 1);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 1);
        assertEq(pair.strikes[1].next0To1, 0);
        assertEq(pair.strikes[1].reference0To1, 1);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(0), -1);
        assertEq(pair.bitMap0To1.nextBelow(-1), MIN_STRIKE);

        // 1 to 0 strike order
        assertEq(pair.strikes[0].next1To0, 5);
        assertEq(pair.strikes[5].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[5].reference1To0, 1);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 5);
        assertEq(pair.bitMap1To0.nextBelow(5), 0);

        vm.resumeGasMetering();
    }

    /// @notice Test repaying liquidity such that it needs to go to the next spread, but one of the strikes where a
    /// swap is offered must be preserved
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 0 -> -1 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 2 -> 3 -> MAX_STRIKE
    function test_RepayLiquidity_NextSpreadPreserve() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.updateStrike(1, 1, 1e18);
        pair.updateStrike(1, 2, 1e18);
        pair.borrowLiquidity(1, 1.5e18);

        vm.resumeGasMetering();

        pair.repayLiquidity(1, 1.5e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[1].liquidityBiDirectional[0], 1e18);
        assertEq(pair.strikes[1].liquidityBorrowed[0], 0);

        assertEq(pair.strikes[1].liquidityBiDirectional[1], 1e18);
        assertEq(pair.strikes[1].liquidityBorrowed[1], 0);

        assertEq(pair.strikes[1].activeSpread, 0);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 0);
        assertEq(pair.strikes[0].next0To1, -1);
        assertEq(pair.strikes[-1].reference0To1, 1);
        assertEq(pair.strikes[0].reference0To1, 1);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(MAX_STRIKE), 1);
        assertEq(pair.bitMap0To1.nextBelow(1), 0);

        // 1 to 0 strike order
        assertEq(pair.strikes[0].next1To0, 2);
        assertEq(pair.strikes[2].next1To0, 3);
        assertEq(pair.strikes[3].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[2].reference1To0, 1);
        assertEq(pair.strikes[3].reference1To0, 1);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 3);
        assertEq(pair.bitMap1To0.nextBelow(3), 2);
        assertEq(pair.bitMap1To0.nextBelow(2), 0);

        vm.resumeGasMetering();
    }

    function test_RepayLiquidity_OutOfBounds() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        vm.expectRevert(Pairs.OutOfBounds.selector);
        pair.repayLiquidity(1, 1);
    }
}
