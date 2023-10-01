// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {BitMaps} from "src/core/BitMaps.sol";

contract SetTest is Test {
    using BitMaps for BitMaps.BitMap;

    BitMaps.BitMap private bitmap;

    /// @notice Test turning on a bit that was off
    function test_Set_Cold() external {
        bitmap.set(0);

        vm.pauseGasMetering();

        assertEq(bitmap.nextBelow(1), 0);

        vm.resumeGasMetering();
    }

    /// @notice Test turning on a bit that was already on
    function test_Set_Hot() external {
        vm.pauseGasMetering();

        bitmap.set(0);

        vm.resumeGasMetering();

        bitmap.set(0);

        vm.pauseGasMetering();

        assertEq(bitmap.nextBelow(1), 0);

        vm.resumeGasMetering();
    }
}
