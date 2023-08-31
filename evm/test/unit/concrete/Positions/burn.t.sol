// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions, biDirectionalID, debtID} from "src/core/Positions.sol";
import {Engine} from "src/core/Engine.sol";

contract BurnTest is Test {
    event Transfer(address indexed from, address indexed to, bytes transferDetailsBytes);

    MockPositions private positions;

    function setUp() external {
        positions = new MockPositions();
    }

    function test_Burn_BiDirectionalFull() external {
        vm.pauseGasMetering();

        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            address(0),
            abi.encode(
                Positions.ILRTATransferDetails(
                    biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 1e18, 0
                )
            )
        );

        vm.resumeGasMetering();
        positions.burn(
            address(this), biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 1e18, 0
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 0);
        assertEq(data.buffer, 0);

        vm.resumeGasMetering();
    }

    function test_Burn_BiDirectionalPartial() external {
        vm.pauseGasMetering();

        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            address(0),
            abi.encode(
                Positions.ILRTATransferDetails(
                    biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 0.5e18, 0
                )
            )
        );

        vm.resumeGasMetering();
        positions.burn(
            address(this), biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 0.5e18, 0
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 0.5e18);
        assertEq(data.buffer, 0);

        vm.resumeGasMetering();
    }

    function test_Burn_DebtFull() external {
        vm.pauseGasMetering();

        positions.mintDebt(address(this), address(1), address(2), 0, 0, Engine.TokenSelector.Token0, 1e18, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            address(0),
            abi.encode(
                Positions.ILRTATransferDetails(
                    debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0), Engine.OrderType.Debt, 1e18, 1e18
                )
            )
        );

        vm.resumeGasMetering();
        positions.burn(
            address(this),
            debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0),
            Engine.OrderType.Debt,
            1e18,
            1e18
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0));

        assertEq(data.balance, 0);
        assertEq(data.buffer, 0);

        vm.resumeGasMetering();
    }

    function test_Burn_DebtPartial() external {
        vm.pauseGasMetering();

        positions.mintDebt(address(this), address(1), address(2), 0, 0, Engine.TokenSelector.Token0, 1e18, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            address(0),
            abi.encode(
                Positions.ILRTATransferDetails(
                    debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0),
                    Engine.OrderType.Debt,
                    0.5e18,
                    0.5e18
                )
            )
        );

        vm.resumeGasMetering();
        positions.burn(
            address(this),
            debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0),
            Engine.OrderType.Debt,
            0.5e18,
            0.5e18
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0));

        assertEq(data.balance, 0.5e18);
        assertEq(data.buffer, 0.5e18);

        vm.resumeGasMetering();
    }
}
