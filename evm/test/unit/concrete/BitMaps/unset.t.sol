// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {BitMaps} from "src/core/BitMaps.sol";

contract UnsetTest is Test {
    using BitMaps for BitMaps.BitMap;

    BitMaps.BitMap private bitmap;

    /// @notice Test turning off a bit that was on
    function test_Unset_Hot() external {
        vm.pauseGasMetering();

        bitmap.set(1); //on

        vm.resumeGasMetering();

        bitmap.unset(1); //off

        vm.pauseGasMetering();

        //assertions

        vm.expectRevert();
        bitmap.nextBelow(2);

        vm.resumeGasMetering();
    }

    /// @notice Test turning off a bit that was already off
    function test_Unset_Cold() external {

        vm.pauseGasMetering();

        bitmap.unset(1); //off

        vm.resumeGasMetering();

        bitmap.unset(1); //off

        vm.pauseGasMetering();

        //assertions

        vm.expectRevert();
        bitmap.nextBelow(2);

        vm.resumeGasMetering();
    }
}
