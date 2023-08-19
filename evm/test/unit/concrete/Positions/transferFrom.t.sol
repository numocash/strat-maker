// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions, biDirectionalID} from "src/core/Positions.sol";
import {Engine} from "src/core/Engine.sol";

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
        assertEq(Positions.transferFrom_jDUYFr.selector, bytes4(keccak256("transferFrom()")));
    }

    function test_TransferFrom_Approved() external {
        vm.pauseGasMetering();

        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);
        positions.approve_BKoIou(cuh, Positions.ILRTAApprovalDetails(true));

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            cuh,
            abi.encode(
                Positions.ILRTATransferDetails(
                    biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 1e18
                )
            )
        );

        vm.resumeGasMetering();
        vm.prank(cuh);
        positions.transferFrom_jDUYFr(
            address(this),
            cuh,
            Positions.ILRTATransferDetails(
                biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 1e18
            )
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 0);
        assertEq(data.liquidityBuffer, 0);

        data = positions.dataOf_cGJnTo(cuh, biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 1e18);
        assertEq(data.liquidityBuffer, 0);

        vm.resumeGasMetering();
    }

    function test_TransferFrom_NotApproved() external {
        vm.expectRevert();
        positions.transferFrom_jDUYFr(
            address(this), cuh, Positions.ILRTATransferDetails(0, Engine.OrderType.BiDirectional, 1)
        );
    }
}
