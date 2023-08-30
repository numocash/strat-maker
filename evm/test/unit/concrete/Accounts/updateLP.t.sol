// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";

contract UpdateLPTest is Test {
    using Accounts for Accounts.Account;

    function test_UpdateLP_Fresh() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(0, 1);

        vm.resumeGasMetering();

        account.updateLP(bytes32(uint256(1)), Engine.OrderType.BiDirectional, 1, 1);

        vm.pauseGasMetering();

        assertEq(account.lpData[0].id, bytes32(uint256(1)));
        assertTrue(account.lpData[0].orderType == Engine.OrderType.BiDirectional);
        assertEq(account.lpData[0].amountBurned, 1);
        assertEq(account.lpData[0].amountBuffer, 1);

        vm.resumeGasMetering();
    }

    function test_UpdateLP_Add() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(0, 1);
        account.updateLP(bytes32(uint256(1)), Engine.OrderType.BiDirectional, 1, 1);

        vm.resumeGasMetering();

        account.updateLP(bytes32(uint256(1)), Engine.OrderType.BiDirectional, 1, 1);

        vm.pauseGasMetering();

        assertEq(account.lpData[0].id, bytes32(uint256(1)));
        assertTrue(account.lpData[0].orderType == Engine.OrderType.BiDirectional);
        assertEq(account.lpData[0].amountBurned, 2);
        assertEq(account.lpData[0].amountBuffer, 2);

        vm.resumeGasMetering();
    }

    function test_UpdateLP_Overflow() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(0, 1);
        account.updateLP(bytes32(uint256(1)), Engine.OrderType.BiDirectional, type(uint128).max, 0);

        vm.expectRevert();
        vm.resumeGasMetering();

        account.updateLP(bytes32(uint256(1)), Engine.OrderType.BiDirectional, 1, 0);
    }

    function test_UpdateToken_InvalidLength() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(0, 1);
        account.updateLP(bytes32(uint256(1)), Engine.OrderType.BiDirectional, 1, 0);

        vm.expectRevert();
        vm.resumeGasMetering();

        account.updateLP(bytes32(uint256(2)), Engine.OrderType.BiDirectional, 1, 0);
    }
}
