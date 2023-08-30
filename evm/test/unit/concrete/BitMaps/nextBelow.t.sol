// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {BitMaps} from "src/core/BitMaps.sol";

contract NextBelowTest is Test {
    using BitMaps for BitMaps.BitMap;

    BitMaps.BitMap private bitmap;

    /// @notice Test `nextBelow` when there is nothing below, should throw an error
    function test_NextBelow_Nothing() external {}

    /// @notice Test `nextBelow` when there is a flipped bit on the same level 2
    function test_NextBelow_SameLevel2() external {}

    /// @notice Test `nextBelow` when there is a flipped bit on the same level 1
    function test_NextBelow_SameLevel1() external {}

    /// @notice Test `nextBelow` when there is a flipped bit on the same level 0
    function test_NextBelow_SameLevel0() external {}

    /// @notice Test `nextBelow` when there are higher bits that need to be masked on level 2
    function test_NextBelow_MaskLevel2() external {}

    /// @notice Test `nextBelow` when there are higher bits that need to be masked on level 1
    function test_NextBelow_MaskLevel1() external {}

    /// @notice Test `nextBelow` when there are higher bits that need to be masked on level 0
    function test_NextBelow_MaskLevel0() external {}

    /// @notice Test `nextBelow` when there are lower bits that are less significant than the next below on level 2
    function test_NextBelow_MSBLevel2() external {}

    /// @notice Test `nextBelow` when there are lower bits that are less significant than the next below on level 1
    function test_NextBelow_MSBLevel1() external {}

    /// @notice Test `nextBelow` when there are lower bits that are less significant than the next below on level 0
    function test_NextBelow_MSBLevel0() external {}
}
