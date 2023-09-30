// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Pairs} from "src/core/Pairs.sol";
import {BitMaps} from "src/core/BitMaps.sol";
import {MAX_STRIKE, MIN_STRIKE} from "src/core/math/StrikeMath.sol";

contract RemoveSwapLiquidityTest is Test {
    using Pairs for Pairs.Pair;
    using BitMaps for BitMaps.BitMap;

    Pairs.Pair private pair;

    /// @notice Test updating a strike that is not initialized
    function test_RemoveSwapLiquidity_NotInitialized() external {
        vm.expectRevert();
        pair.removeSwapLiquidity(0, 1, 1e18);
    }

    /// @notice Test updating a strike with an invalid spread
    function test_RemoveSwapLiquidity_InvalidSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        vm.expectRevert();
        pair.removeSwapLiquidity(0, 0, 1e18);
    }

    /// @notice Test updating a strike by partially removing liquidity
    /// @dev Strike order shouldn't change
    function test_RemoveSwapLiquidity_Partial() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(2, 1, 2e18);

        vm.resumeGasMetering();

        uint128 displacedLiquidity = pair.removeSwapLiquidity(2, 1, 1e18);

        vm.pauseGasMetering();

        assertEq(displacedLiquidity, 0);
        assertEq(pair.strikes[2].liquidity[0].swap, 1e18);

        vm.resumeGasMetering();
    }

    /// @notice Test updating a strike by full removing liquidity
    /// @dev Return the strike order to default
    function test_RemoveSwapLiquidity_Full() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(2, 1, 1e18);

        vm.resumeGasMetering();

        uint128 displacedLiquidity = pair.removeSwapLiquidity(2, 1, 1e18);

        vm.pauseGasMetering();

        assertEq(displacedLiquidity, 0);
        assertEq(pair.strikes[2].liquidity[0].swap, 0);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 0);
        assertEq(pair.strikes[0].next0To1, MIN_STRIKE);
        assertEq(pair.strikes[1].reference0To1, 0, "reference");
        assertEq(pair.strikes[1].next0To1, 0);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(0), MIN_STRIKE);

        // 1 to 0 strike order
        assertEq(pair.strikes[MIN_STRIKE].next1To0, 0);
        assertEq(pair.strikes[0].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[3].reference1To0, 0, "reference");
        assertEq(pair.strikes[3].next1To0, 0);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 0);

        vm.resumeGasMetering();
    }

    /// @notice Test removing swap liquidity such that it displaces some borrowed liquidity
    function test_RemoveSwapLiquidity_Displaced() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        pair.addSwapLiquidity(2, 1, 0.5e18);

        pair.strikes[2].liquidity[0].borrowed = 0.5e18;

        vm.resumeGasMetering();

        uint128 displacedLiquidity = pair.removeSwapLiquidity(2, 1, 1e18);

        vm.pauseGasMetering();

        assertEq(displacedLiquidity, 0.5e18);
        assertEq(pair.strikes[2].liquidity[0].swap, 0);
        assertEq(pair.strikes[2].liquidity[0].borrowed, 0);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 0);
        assertEq(pair.strikes[0].next0To1, MIN_STRIKE);
        assertEq(pair.strikes[1].reference0To1, 0, "reference");
        assertEq(pair.strikes[1].next0To1, 0);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(0), MIN_STRIKE);

        // 1 to 0 strike order
        assertEq(pair.strikes[MIN_STRIKE].next1To0, 0);
        assertEq(pair.strikes[0].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[3].reference1To0, 0, "reference");
        assertEq(pair.strikes[3].next1To0, 0);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 0);

        vm.resumeGasMetering();
    }

    /// @notice Test updating a strike by full removing liquidity but one of the strikes where a swap is offered must be
    /// preserved
    /// @dev Return the strike order to default, making sure not to remove 0 from the order
    function test_RemoveSwapLiquidity_FullPreserve() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(1, 1, 1e18);

        vm.resumeGasMetering();

        pair.removeSwapLiquidity(1, 1, 1e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[1].liquidity[0].swap, 0);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 0);
        assertEq(pair.strikes[0].next0To1, MIN_STRIKE);
        assertEq(pair.strikes[0].reference0To1, 0);
        assertEq(pair.strikes[1].reference0To1, 0);
        assertEq(pair.strikes[1].next0To1, 0);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(0), MIN_STRIKE);

        // 1 to 0 strike order
        assertEq(pair.strikes[MIN_STRIKE].next1To0, 0);
        assertEq(pair.strikes[0].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[0].reference0To1, 0);
        assertEq(pair.strikes[3].reference1To0, 0);
        assertEq(pair.strikes[3].next1To0, 0);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 0);

        vm.resumeGasMetering();
    }

    /// @notice Test removing swap liquidity under the active spread
    function test_RemoveSwapLiquidity_UnderActiveSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.strikes[2].activeSpread = 1;
        pair.addSwapLiquidity(2, 1, 1e18);

        vm.resumeGasMetering();

        uint128 displacedLiquidity = pair.removeSwapLiquidity(2, 1, 1e18);

        vm.pauseGasMetering();

        assertEq(displacedLiquidity, 1e18, "displaced liquidity");
        assertEq(pair.strikes[2].liquidity[0].borrowed, 0, "borrowed liquidity");

        vm.resumeGasMetering();
    }

    /// @notice Test removing swap liquidity over the active spread
    function test_RemoveSwapLiquidity_OverActiveSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(3, 2, 1e18);

        vm.resumeGasMetering();

        uint128 displacedLiquidity = pair.removeSwapLiquidity(3, 2, 1e18);

        vm.pauseGasMetering();

        assertEq(displacedLiquidity, 0, "displaced liquidity");
        assertEq(pair.strikes[2].liquidity[0].swap, 0, "swap liquidity");

        vm.resumeGasMetering();
    }
}
