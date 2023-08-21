// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Pairs} from "src/core/Pairs.sol";
import {BitMaps} from "src/core/BitMaps.sol";
import {MAX_STRIKE, MIN_STRIKE} from "src/core/math/StrikeMath.sol";

contract UpdateStrikeTest is Test {
    using Pairs for Pairs.Pair;
    using BitMaps for BitMaps.BitMap;

    Pairs.Pair private pair;

    /// @notice Test updating a strike that is not initialized
    function test_UpdateStrike_NotInitialized() external {
        vm.expectRevert();
        pair.updateStrike(0, 1, 1e18);
    }

    /// @notice Test updating a strike with an invalid spread
    function test_UpdateStrike_InvalidSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        vm.expectRevert();
        pair.updateStrike(0, 0, 1e18);
    }

    /// @notice Test updating a strike with an invalid strike
    function test_UpdateStrike_InvalidStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        vm.expectRevert();
        pair.updateStrike(type(int24).max, 1, 1e18);
    }

    /// @notice Test updating a completely fresh strike
    /// @dev Provides 0 to 1 liquidity to strike 1
    /// @dev Provides 1 to 0 liquidity to strike 3
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 1 -> 0 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 3 -> MAX_STRIKE
    function test_UpdateStrike_AddNewStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        pair.updateStrike(2, 1, 1e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[2].liquidityBiDirectional[0], 1e18);

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

    /// @notice Test updating a strike where one of the strikes where a swap is offered intersects with an existing
    /// strike
    /// @dev Provides 0 to 1 liquidity to strike -1 and 1
    /// @dev Provides 1 to 0 liquidity to strike 3
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 1 -> 0 -> -1 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 3 -> MAX_STRIKE
    function test_UpdateStrike_AddIntersectingStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.updateStrike(2, 1, 1e18);

        vm.resumeGasMetering();

        pair.updateStrike(1, 2, 1e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[1].liquidityBiDirectional[1], 1e18);
        assertEq(pair.strikes[2].liquidityBiDirectional[0], 1e18);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 1);
        assertEq(pair.strikes[1].next0To1, 0);
        assertEq(pair.strikes[0].next0To1, -1);

        assertEq(pair.strikes[-1].reference0To1, 1);
        assertEq(pair.strikes[1].reference0To1, 1);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(MAX_STRIKE), 1);
        assertEq(pair.bitMap0To1.nextBelow(1), 0);
        assertEq(pair.bitMap0To1.nextBelow(0), -1);

        // 1 to 0 strike order
        assertEq(pair.strikes[0].next1To0, 3);
        assertEq(pair.strikes[3].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[3].reference1To0, 2);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 3);

        vm.resumeGasMetering();
    }

    /// @notice Test updating a strike with existing liquidity
    /// @dev Provides 0 to 1 liquidity to strike  1
    /// @dev Provides 1 to 0 liquidity to strike 3
    /// @dev 0 to 1 strike order is MAX_STRIKE -> 1 -> 0 -> MIN_STRIKE
    /// @dev 1 to 0 strike order is MIN_STRIKE -> 0 -> 3 -> MAX_STRIKE
    function test_UpdateStrike_AddExistingStrike() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.updateStrike(2, 1, 1e18);

        vm.resumeGasMetering();

        pair.updateStrike(2, 1, 1e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[2].liquidityBiDirectional[0], 2e18);

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

    /// @notice Test overflow by adding too much liquidity
    function test_UpdateStrike_Overflow() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.updateStrike(2, 1, type(int128).max);
        pair.updateStrike(2, 1, type(int128).max);

        vm.resumeGasMetering();

        vm.expectRevert();
        pair.updateStrike(2, 1, 2);
    }

    /// @notice Test underflow by removing too much liquidity
    function test_UpdateStrike_Underflow() external {
        vm.expectRevert();
        pair.updateStrike(2, 1, -1);
    }

    /// @notice Test updating a strike by partially removing liquidity
    /// @dev Strike order shouldn't change
    function test_UpdateStrike_RemovePartial() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.updateStrike(2, 1, 2e18);

        vm.resumeGasMetering();

        pair.updateStrike(2, 1, -1e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[2].liquidityBiDirectional[0], 1e18);

        vm.resumeGasMetering();
    }

    /// @notice Test updating a strike by full removing liquidity
    /// @dev Return the strike order to default
    function test_UpdateStrike_RemoveFull() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.updateStrike(2, 1, 1e18);

        vm.resumeGasMetering();

        pair.updateStrike(2, 1, -1e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[2].liquidityBiDirectional[0], 0);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 0);
        assertEq(pair.strikes[0].next0To1, MIN_STRIKE);
        assertEq(pair.strikes[1].reference0To1, 0);
        assertEq(pair.strikes[1].next0To1, 0);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(0), MIN_STRIKE);

        // 1 to 0 strike order
        assertEq(pair.strikes[MIN_STRIKE].next1To0, 0);
        assertEq(pair.strikes[0].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[3].reference1To0, 0);
        assertEq(pair.strikes[3].next1To0, 0);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 0);

        vm.resumeGasMetering();
    }

    /// @notice Test updating a strike by full removing liquidity but one of the strikes where a swap is offered must be
    /// preserved
    /// @dev Return the strike order to default, making sure not to remove 0 from the order
    function test_updateStrike_RemoveFullPreserve() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.updateStrike(1, 1, 1e18);

        vm.resumeGasMetering();

        pair.updateStrike(1, 1, -1e18);

        vm.pauseGasMetering();

        assertEq(pair.strikes[1].liquidityBiDirectional[0], 0);

        // 0 to 1 strike order
        assertEq(pair.strikes[MAX_STRIKE].next0To1, 0);
        assertEq(pair.strikes[0].next0To1, MIN_STRIKE);
        assertEq(pair.strikes[1].reference0To1, 0);
        assertEq(pair.strikes[1].next0To1, 0);

        // 0 to 1 bit map
        assertEq(pair.bitMap0To1.nextBelow(0), MIN_STRIKE);

        // 1 to 0 strike order
        assertEq(pair.strikes[MIN_STRIKE].next1To0, 0);
        assertEq(pair.strikes[0].next1To0, MAX_STRIKE);
        assertEq(pair.strikes[3].reference1To0, 0);
        assertEq(pair.strikes[3].next1To0, 0);

        // 1 to 0 bit map
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 0);

        vm.resumeGasMetering();
    }
}
