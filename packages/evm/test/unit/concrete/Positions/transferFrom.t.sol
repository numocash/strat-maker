// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions} from "src/core/Positions.sol";

contract TransferFromTest is Test {
    event Transfer(address indexed from, address indexed to, bytes transferDetailsBytes);

    MockPositions private positions;

    address private immutable cuh;

    constructor() {
        cuh = makeAddr("cuh");
    }

    function setUp() external {
        positions = new MockPositions();
    }

    function test_TransferFrom_Selector() external {
        assertEq(Positions.transferFrom_OSclqX.selector, bytes4(keccak256("transferFrom()")));
    }

    function test_TransferFrom_Approved() external {
        vm.pauseGasMetering();

        positions.mint(address(this), 0, 1e18);
        positions.approve_BKoIou(cuh, Positions.ILRTAApprovalDetails(true));

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), cuh, abi.encode(Positions.ILRTATransferDetails(0, 1e18)));

        vm.resumeGasMetering();
        vm.prank(cuh);
        positions.transferFrom_OSclqX(address(this), cuh, Positions.ILRTATransferDetails(0, 1e18));
        vm.pauseGasMetering();

        Positions.ILRTAData memory data = positions.dataOf(address(this), 0);

        assertEq(data.balance, 0);

        data = positions.dataOf(cuh, 0);

        assertEq(data.balance, 1e18);

        vm.resumeGasMetering();
    }

    function test_TransferFrom_NotApproved() external {
        vm.expectRevert();
        positions.transferFrom_OSclqX(address(this), cuh, Positions.ILRTATransferDetails(0, 1));
    }
}
