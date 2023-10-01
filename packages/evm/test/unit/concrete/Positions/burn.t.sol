// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions} from "src/core/Positions.sol";

contract BurnTest is Test {
    event Transfer(address indexed from, address indexed to, bytes transferDetailsBytes);

    MockPositions private positions;

    function setUp() external {
        positions = new MockPositions();
    }

    function test_Burn_Full() external {
        vm.pauseGasMetering();

        positions.mint(address(this), 0, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), address(0), abi.encode(Positions.ILRTATransferDetails(0, 1e18)));

        vm.resumeGasMetering();

        positions.burn(address(this), 0, 1e18);

        vm.pauseGasMetering();

        Positions.ILRTAData memory data = positions.dataOf(address(this), 0);

        assertEq(data.balance, 0);

        vm.resumeGasMetering();
    }

    function test_Burn_Partial() external {
        vm.pauseGasMetering();

        positions.mint(address(this), 0, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), address(0), abi.encode(Positions.ILRTATransferDetails(0, 0.5e18)));

        vm.resumeGasMetering();

        positions.burn(address(this), 0, 0.5e18);

        vm.pauseGasMetering();

        Positions.ILRTAData memory data = positions.dataOf(address(this), 0);

        assertEq(data.balance, 0.5e18);

        vm.resumeGasMetering();
    }
}
