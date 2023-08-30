// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions, debtID} from "src/core/Positions.sol";
import {Engine} from "src/core/Engine.sol";

contract MintDebtTest is Test {
    event Transfer(address indexed from, address indexed to, bytes transferDetailsBytes);

    MockPositions private positions;

    function setUp() external {
        positions = new MockPositions();
    }

    function test_MintDebt_Cold() external {
        vm.pauseGasMetering();

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(0),
            address(this),
            abi.encode(
                Positions.ILRTATransferDetails(
                    debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0), Engine.OrderType.Debt, 1e18, 1e18
                )
            )
        );

        vm.resumeGasMetering();
        positions.mintDebt(address(this), address(1), address(2), 0, 0, Engine.TokenSelector.Token0, 1e18, 1e18);
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0));

        assertEq(data.balance, 1e18);
        assertEq(data.buffer, 1e18);

        vm.resumeGasMetering();
    }

    function test_MintDebt_Hot() external {
        vm.pauseGasMetering();

        positions.mintDebt(address(this), address(1), address(2), 0, 0, Engine.TokenSelector.Token0, 1e18, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(0),
            address(this),
            abi.encode(
                Positions.ILRTATransferDetails(
                    debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0), Engine.OrderType.Debt, 1e18, 1e18
                )
            )
        );

        vm.resumeGasMetering();
        positions.mintDebt(address(this), address(1), address(2), 0, 0, Engine.TokenSelector.Token0, 1e18, 1e18);
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0));

        assertEq(data.balance, 2e18);
        assertEq(data.buffer, 2e18);

        vm.resumeGasMetering();
    }
}
