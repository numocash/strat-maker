// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions} from "src/core/Positions.sol";

contract ApproveTest is Test {
    event Approval(address indexed owner, address indexed spender, bytes transferDetailsBytes);

    MockPositions private positions;

    address private immutable cuh;

    constructor() {
        cuh = makeAddr("cuh");
    }

    function setUp() external {
        positions = new MockPositions();
    }

    function test_Approve_True() external {
        vm.expectEmit(true, true, false, true);
        emit Approval(address(this), cuh, abi.encode(Positions.ILRTAApprovalDetails(true)));
        bool ret = positions.approve_BKoIou(cuh, Positions.ILRTAApprovalDetails(true));

        vm.pauseGasMetering();

        assertTrue(ret);

        Positions.ILRTAApprovalDetails memory allowance = positions.allowanceOf_QDmnOj(address(this), cuh, bytes32(0));

        assertTrue(allowance.approved);

        vm.resumeGasMetering();
    }

    function test_Approve_False() external {
        positions.approve_BKoIou(cuh, Positions.ILRTAApprovalDetails(true));

        vm.expectEmit(true, true, false, true);
        emit Approval(address(this), cuh, abi.encode(Positions.ILRTAApprovalDetails(false)));
        bool ret = positions.approve_BKoIou(cuh, Positions.ILRTAApprovalDetails(false));

        vm.pauseGasMetering();

        assertTrue(ret);

        Positions.ILRTAApprovalDetails memory allowance = positions.allowanceOf_QDmnOj(address(this), cuh, bytes32(0));

        assertFalse(allowance.approved);

        vm.resumeGasMetering();
    }

    function test_Approve_Selector() external {
        assertEq(Positions.approve_BKoIou.selector, bytes4(keccak256("approve()")));
    }
}
