// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {BitMaps} from "src/core/BitMaps.sol";

contract SetTest is Test {
    using BitMaps for BitMaps.BitMap;

    BitMaps.BitMap private bitmap;

    /// @notice Test turning on a bit that was off
    function test_Set_Cold() external {
        // action you want to test

        bitmap.unset(1); //off

        vm.pauseGasMetering();

        // assertions

        bitmap.set(1); //on

        vm.resumeGasMetering();

        assertEq(bitmap.nextBelow(2), 1);

        vm.resumeGasMetering();
    }

    /// @notice Test turning on a bit that was already on
    function test_Set_Hot() external {
        vm.pauseGasMetering();

        // setup test

        bitmap.set(1);

        vm.resumeGasMetering();

        // action you want to test

        bitmap.set(1);

        vm.pauseGasMetering();

        // assertions

        assertEq(bitmap.nextBelow(2), 1);

        vm.resumeGasMetering();
    }
}
