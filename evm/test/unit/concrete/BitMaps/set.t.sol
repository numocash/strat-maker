// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {BitMaps} from "src/core/BitMaps.sol";

contract SetTest is Test {
    using BitMaps for BitMaps.BitMap;

    BitMaps.BitMap private bitmap;

    /// @notice Test turning on a bit that was off
    function test_Set_Cold() external {}

    /// @notice Test turning on a bit that was already on
    function test_Set_Hot() external {}
}
