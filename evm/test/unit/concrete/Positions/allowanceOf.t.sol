// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions} from "src/core/Positions.sol";

contract AllowanceOfTest is Test {
    MockPositions private positions;

    address private immutable cuh;

    constructor() {
        cuh = makeAddr("cuh");
    }

    function setUp() external {
        positions = new MockPositions();
    }

    function test_AllowanceOf_Zero() external {
        Positions.ILRTAApprovalDetails memory allowance = positions.allowanceOf_QDmnOj(address(this), cuh, bytes32(0));

        vm.pauseGasMetering();

        assertEq(allowance.approved, false);

        vm.resumeGasMetering();
    }

    function test_AllowanceOf_True() external {
        vm.pauseGasMetering();

        positions.approve_BKoIou(cuh, Positions.ILRTAApprovalDetails(true));

        vm.resumeGasMetering();

        Positions.ILRTAApprovalDetails memory allowance = positions.allowanceOf_QDmnOj(address(this), cuh, bytes32(0));

        vm.pauseGasMetering();

        assertEq(allowance.approved, true);

        vm.resumeGasMetering();
    }

    function test_AllowanceOf_False() external {
        vm.pauseGasMetering();

        positions.approve_BKoIou(cuh, Positions.ILRTAApprovalDetails(true));
        positions.approve_BKoIou(cuh, Positions.ILRTAApprovalDetails(false));

        vm.resumeGasMetering();

        Positions.ILRTAApprovalDetails memory allowance = positions.allowanceOf_QDmnOj(address(this), cuh, bytes32(0));

        vm.pauseGasMetering();

        assertEq(allowance.approved, false);

        vm.resumeGasMetering();
    }

    function test_AllowanceOf_Selector() external {
        assertEq(Positions.allowanceOf_QDmnOj.selector, bytes4(keccak256("allowanceOf()")));
    }
}
