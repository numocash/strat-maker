// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions, biDirectionalID} from "src/core/Positions.sol";
import {Engine} from "src/core/Engine.sol";

contract MintBiDirectionalTest is Test {
    event Transfer(address indexed from, address indexed to, bytes transferDetailsBytes);

    MockPositions private positions;

    function setUp() external {
        positions = new MockPositions();
    }

    function test_MintBiDirectional_Cold() external {
        vm.pauseGasMetering();

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(0),
            address(this),
            abi.encode(
                Positions.ILRTATransferDetails(
                    biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 1e18
                )
            )
        );

        vm.resumeGasMetering();
        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 1e18);
        assertEq(data.liquidityBuffer, 0);

        vm.resumeGasMetering();
    }

    function test_MintBiDirectional_Hot() external {
        vm.pauseGasMetering();

        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(0),
            address(this),
            abi.encode(
                Positions.ILRTATransferDetails(
                    biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 1e18
                )
            )
        );

        vm.resumeGasMetering();
        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 2e18);
        assertEq(data.liquidityBuffer, 0);

        vm.resumeGasMetering();
    }
}
