// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";

contract NameTest is Test {
    MockPositions private positions;

    function setUp() external {
        positions = new MockPositions();
    }

    function test_Name() external {
        assertEq(positions.name(), "Numoen Dry Powder");
    }
}
