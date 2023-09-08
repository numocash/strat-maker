// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockPositions} from "../../../mocks/MockPositions.sol";
import {Positions} from "src/core/Positions.sol";

contract MintTest is Test {
    event Transfer(address indexed from, address indexed to, bytes transferDetailsBytes);

    MockPositions private positions;

    function setUp() external {
        positions = new MockPositions();
    }

    function test_Mint_Cold() external {
        vm.pauseGasMetering();

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), abi.encode(Positions.ILRTATransferDetails(0, 1e18)));

        vm.resumeGasMetering();
        positions.mint(address(this), 0, 1e18);
        vm.pauseGasMetering();

        Positions.ILRTAData memory data = positions.dataOf_cGJnTo(address(this), 0);

        assertEq(data.balance, 1e18);

        vm.resumeGasMetering();
    }

    function test_Mint_Hot() external {
        vm.pauseGasMetering();

        positions.mint(address(this), 0, 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), abi.encode(Positions.ILRTATransferDetails(0, 1e18)));

        vm.resumeGasMetering();
        positions.mint(address(this), 0, 1e18);
        vm.pauseGasMetering();

        Positions.ILRTAData memory data = positions.dataOf_cGJnTo(address(this), 0);

        assertEq(data.balance, 2e18);

        vm.resumeGasMetering();
    }
}
