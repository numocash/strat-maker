// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {BitMaps} from "src/core/BitMaps.sol";
import {MIN_STRIKE} from "src/core/math/StrikeMath.sol";

contract NextBelowTest is Test {
    using BitMaps for BitMaps.BitMap;

    BitMaps.BitMap private bitmap;

    /// @notice Test `nextBelow` when there is nothing below, should throw an error
    function test_NextBelow_Nothing() external {
        vm.expectRevert();
        bitmap.nextBelow(0);
    }

    /// @notice Test `nextBelow` when there is a flipped bit on the same level 2
    function test_NextBelow_SameLevel2() external {
        vm.pauseGasMetering();

        bitmap.set(MIN_STRIKE);

        vm.resumeGasMetering();

        int24 strike = bitmap.nextBelow(1 + MIN_STRIKE);

        vm.pauseGasMetering();

        assertEq(strike, MIN_STRIKE);

        vm.resumeGasMetering();
    }

    /// @notice Test `nextBelow` when there is a flipped bit on the same level 1
    function test_NextBelow_SameLevel1() external {
        vm.pauseGasMetering();

        bitmap.set(MIN_STRIKE);

        vm.resumeGasMetering();

        int24 strike = bitmap.nextBelow(2 ** 8 + MIN_STRIKE);

        vm.pauseGasMetering();

        assertEq(strike, MIN_STRIKE);

        vm.resumeGasMetering();
    }

    /// @notice Test `nextBelow` when there is a flipped bit on the same level 0
    function test_NextBelow_SameLevel0() external {
        vm.pauseGasMetering();

        bitmap.set(MIN_STRIKE);

        vm.resumeGasMetering();

        int24 strike = bitmap.nextBelow(2 ** 16 + MIN_STRIKE);

        vm.pauseGasMetering();

        assertEq(strike, MIN_STRIKE);

        vm.resumeGasMetering();
    }

    /// @notice Test `nextBelow` when there are higher bits that need to be masked on level 2
    function test_NextBelow_MaskLevel2() external {
        vm.pauseGasMetering();

        bitmap.set(MIN_STRIKE);
        bitmap.set(1 + MIN_STRIKE);

        vm.resumeGasMetering();

        int24 strike = bitmap.nextBelow(1 + MIN_STRIKE);

        vm.pauseGasMetering();

        assertEq(strike, MIN_STRIKE);

        vm.resumeGasMetering();
    }

    /// @notice Test `nextBelow` when there are higher bits that need to be masked on level 1
    function test_NextBelow_MaskLevel1() external {
        vm.pauseGasMetering();

        bitmap.set(MIN_STRIKE);
        bitmap.set(2 ** 8 + MIN_STRIKE);

        vm.resumeGasMetering();

        int24 strike = bitmap.nextBelow(2 ** 8 + MIN_STRIKE);

        vm.pauseGasMetering();

        assertEq(strike, MIN_STRIKE);

        vm.resumeGasMetering();
    }
    /// @notice Test `nextBelow` when there are higher bits that need to be masked on level 0

    function test_NextBelow_MaskLevel0() external {
        vm.pauseGasMetering();

        bitmap.set(MIN_STRIKE);
        bitmap.set(2 ** 16 + MIN_STRIKE);

        vm.resumeGasMetering();

        int24 strike = bitmap.nextBelow(2 ** 16 + MIN_STRIKE);

        vm.pauseGasMetering();

        assertEq(strike, MIN_STRIKE);

        vm.resumeGasMetering();
    }

    /// @notice Test `nextBelow` when there are lower bits that are less significant than the next below on level 2
    function test_NextBelow_MSBLevel2() external {
        vm.pauseGasMetering();

        bitmap.set(MIN_STRIKE);
        bitmap.set(1 + MIN_STRIKE);

        vm.resumeGasMetering();

        int24 strike = bitmap.nextBelow(2 + MIN_STRIKE);

        vm.pauseGasMetering();

        assertEq(strike, 1 + MIN_STRIKE);

        vm.resumeGasMetering();
    }

    /// @notice Test `nextBelow` when there are lower bits that are less significant than the next below on level 1
    function test_NextBelow_MSBLevel1() external {
        vm.pauseGasMetering();

        bitmap.set(MIN_STRIKE);
        bitmap.set(2 ** 8 + MIN_STRIKE);

        vm.resumeGasMetering();

        int24 strike = bitmap.nextBelow(2 ** 9 + MIN_STRIKE);

        vm.pauseGasMetering();

        assertEq(strike, 2 ** 8 + MIN_STRIKE);

        vm.resumeGasMetering();
    }

    /// @notice Test `nextBelow` when there are lower bits that are less significant than the next below on level 0
    function test_NextBelow_MSBLevel0() external {
        vm.pauseGasMetering();

        bitmap.set(MIN_STRIKE);
        bitmap.set(2 ** 16 + MIN_STRIKE);

        vm.resumeGasMetering();

        int24 strike = bitmap.nextBelow(2 ** 17 + MIN_STRIKE);

        vm.pauseGasMetering();

        assertEq(strike, 2 ** 16 + MIN_STRIKE);

        vm.resumeGasMetering();
    }
}
