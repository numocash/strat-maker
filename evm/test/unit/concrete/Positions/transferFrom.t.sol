// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions} from "src/core/Positions.sol";

contract TransferFromTest is Test {
    MockPositions private positions;

    function setUp() external {
        positions = new MockPositions();
    }

    function test_TransferFrom_Selector() external {
        assertEq(Positions.transferFrom_jDUYFr.selector, bytes4(keccak256("transferFrom()")));
    }
}
