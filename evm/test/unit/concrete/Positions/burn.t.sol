// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions, biDirectionalID} from "src/core/Positions.sol";
import {Engine} from "src/core/Engine.sol";

contract BurnTest is Test {
    event Transfer(address indexed from, address indexed to, bytes transferDetailsBytes);

    MockPositions private positions;

    function setUp() external {
        positions = new MockPositions();
    }

    function test_Burn_Full() external {
        vm.pauseGasMetering();

        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            address(0),
            abi.encode(
                Positions.ILRTATransferDetails(
                    biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 1e18
                )
            )
        );

        vm.resumeGasMetering();
        positions.burn(
            address(this), biDirectionalID(address(1), address(2), 0, 0, 1), 1e18, Engine.OrderType.BiDirectional
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 0);
        assertEq(data.liquidityBuffer, 0);

        vm.resumeGasMetering();
    }

    function test_Burn_Partial() external {
        vm.pauseGasMetering();

        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            address(0),
            abi.encode(
                Positions.ILRTATransferDetails(
                    biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 0.5e18
                )
            )
        );

        vm.resumeGasMetering();
        positions.burn(
            address(this), biDirectionalID(address(1), address(2), 0, 0, 1), 0.5e18, Engine.OrderType.BiDirectional
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 0.5e18);
        assertEq(data.liquidityBuffer, 0);

        vm.resumeGasMetering();
    }
}
