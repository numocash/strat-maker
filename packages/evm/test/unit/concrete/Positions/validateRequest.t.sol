// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions} from "src/core/Positions.sol";

contract ValidateRequestTest is Test {
    MockPositions private positions;

    function setUp() external {
        positions = new MockPositions();
    }

    function test_ValidateRequest_IDMismatch() external {
        bool ret = positions.validateRequest_dUBETg(
            Positions.ILRTATransferDetails(bytes32(0), 0), Positions.ILRTATransferDetails(bytes32(uint256(1)), 0)
        );

        vm.pauseGasMetering();

        assertFalse(ret);

        vm.resumeGasMetering();
    }

    function test_ValidateRequest_AmountGT() external {
        bool ret = positions.validateRequest_dUBETg(
            Positions.ILRTATransferDetails(bytes32(0), 0), Positions.ILRTATransferDetails(bytes32(0), 1)
        );

        vm.pauseGasMetering();

        assertFalse(ret);

        vm.resumeGasMetering();
    }

    function test_ValidateRequest_True() external {
        bool ret = positions.validateRequest_dUBETg(
            Positions.ILRTATransferDetails(bytes32(0), 0), Positions.ILRTATransferDetails(bytes32(0), 0)
        );

        vm.pauseGasMetering();

        assertTrue(ret);

        vm.resumeGasMetering();
    }

    function test_ValidateRequest_Selector() external {
        assertEq(Positions.validateRequest_dUBETg.selector, bytes4(keccak256("validateRequest()")));
    }
}
