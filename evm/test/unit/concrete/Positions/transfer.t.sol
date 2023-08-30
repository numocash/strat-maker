// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions, biDirectionalID, debtID} from "src/core/Positions.sol";
import {Engine} from "src/core/Engine.sol";

contract TransferTest is Test {
    event Transfer(address indexed from, address indexed to, bytes transferDetailsBytes);

    MockPositions private positions;

    address private immutable cuh;

    constructor() {
        cuh = makeAddr("cuh");
    }

    function setUp() external {
        positions = new MockPositions();
    }

    function test_Transfer_Selector() external {
        assertEq(Positions.transfer_AjLAUd.selector, bytes4(keccak256("transfer()")));
    }

    /// @notice Transfer more tokens than you have, causing a revert
    function test_Transfer_Underflow() external {
        vm.pauseGasMetering();

        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);

        vm.expectRevert();
        vm.resumeGasMetering();
        positions.transfer_AjLAUd(
            cuh,
            Positions.ILRTATransferDetails(
                biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 1e18 + 1, 0
            )
        );
    }

    function test_Transfer_Overflow() external {
        vm.pauseGasMetering();

        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);
        positions.mintBiDirectional(cuh, address(1), address(2), 0, 0, 1, type(uint128).max);

        vm.expectRevert();
        vm.resumeGasMetering();
        positions.transfer_AjLAUd(
            cuh,
            Positions.ILRTATransferDetails(
                biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 1e18, 0
            )
        );
    }

    function test_Transfer_BiDirectionalFull() external {
        vm.pauseGasMetering();

        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            cuh,
            abi.encode(
                Positions.ILRTATransferDetails(
                    biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 1e18, 0
                )
            )
        );

        vm.resumeGasMetering();
        positions.transfer_AjLAUd(
            cuh,
            Positions.ILRTATransferDetails(
                biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 1e18, 0
            )
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 0);
        assertEq(data.buffer, 0);

        data = positions.dataOf_cGJnTo(cuh, biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 1e18);
        assertEq(data.buffer, 0);

        vm.resumeGasMetering();
    }

    function test_Transfer_BiDirectional_PartialCold() external {
        vm.pauseGasMetering();

        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            cuh,
            abi.encode(
                Positions.ILRTATransferDetails(
                    biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 0.5e18, 0
                )
            )
        );

        vm.resumeGasMetering();
        positions.transfer_AjLAUd(
            cuh,
            Positions.ILRTATransferDetails(
                biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 0.5e18, 0
            )
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 0.5e18);
        assertEq(data.buffer, 0);

        data = positions.dataOf_cGJnTo(cuh, biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 0.5e18);
        assertEq(data.buffer, 0);

        vm.resumeGasMetering();
    }

    function test_Transfer_BiDirectionalPartialHot() external {
        vm.pauseGasMetering();

        positions.mintBiDirectional(address(this), address(1), address(2), 0, 0, 1, 1e18);
        positions.mintBiDirectional(cuh, address(1), address(2), 0, 0, 1, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            cuh,
            abi.encode(
                Positions.ILRTATransferDetails(
                    biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 0.5e18, 0
                )
            )
        );

        vm.resumeGasMetering();
        positions.transfer_AjLAUd(
            cuh,
            Positions.ILRTATransferDetails(
                biDirectionalID(address(1), address(2), 0, 0, 1), Engine.OrderType.BiDirectional, 0.5e18, 0
            )
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 0.5e18);
        assertEq(data.buffer, 0);

        data = positions.dataOf_cGJnTo(cuh, biDirectionalID(address(1), address(2), 0, 0, 1));

        assertEq(data.balance, 1.5e18);
        assertEq(data.buffer, 0);

        vm.resumeGasMetering();
    }

    function test_Transfer_DebtFull() external {
        vm.pauseGasMetering();

        positions.mintDebt(address(this), address(1), address(2), 0, 0, Engine.TokenSelector.Token0, 1e18, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            cuh,
            abi.encode(
                Positions.ILRTATransferDetails(
                    debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0), Engine.OrderType.Debt, 1e18, 1e18
                )
            )
        );

        vm.resumeGasMetering();
        positions.transfer_AjLAUd(
            cuh,
            Positions.ILRTATransferDetails(
                debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0), Engine.OrderType.Debt, 1e18, 1e18
            )
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0));

        assertEq(data.balance, 0);
        assertEq(data.buffer, 0);

        data = positions.dataOf_cGJnTo(cuh, debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0));

        assertEq(data.balance, 1e18);
        assertEq(data.buffer, 1e18);

        vm.resumeGasMetering();
    }

    function test_Transfer_DebtPartialCold() external {
        vm.pauseGasMetering();

        positions.mintDebt(address(this), address(1), address(2), 0, 0, Engine.TokenSelector.Token0, 1e18, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            cuh,
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
        positions.transfer_AjLAUd(
            cuh,
            Positions.ILRTATransferDetails(
                debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0), Engine.OrderType.Debt, 0.5e18, 0.5e18
            )
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0));

        assertEq(data.balance, 0.5e18);
        assertEq(data.buffer, 0.5e18);

        data = positions.dataOf_cGJnTo(cuh, debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0));

        assertEq(data.balance, 0.5e18);
        assertEq(data.buffer, 0.5e18);

        vm.resumeGasMetering();
    }

    function test_Transfer_DebtPartialHot() external {
        vm.pauseGasMetering();

        positions.mintDebt(address(this), address(1), address(2), 0, 0, Engine.TokenSelector.Token0, 1e18, 1e18);
        positions.mintDebt(cuh, address(1), address(2), 0, 0, Engine.TokenSelector.Token0, 1e18, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(this),
            cuh,
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
        positions.transfer_AjLAUd(
            cuh,
            Positions.ILRTATransferDetails(
                debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0), Engine.OrderType.Debt, 0.5e18, 0.5e18
            )
        );
        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            positions.dataOf_cGJnTo(address(this), debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0));

        assertEq(data.balance, 0.5e18);
        assertEq(data.buffer, 0.5e18);

        data = positions.dataOf_cGJnTo(cuh, debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token0));

        assertEq(data.balance, 1.5e18);
        assertEq(data.buffer, 1.5e18);

        vm.resumeGasMetering();
    }
}
