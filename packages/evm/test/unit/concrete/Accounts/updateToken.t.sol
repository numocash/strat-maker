// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";

contract UpdateTokenTest is Test {
    using Accounts for Accounts.Account;

    function test_UpdateToken_Fresh() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);

        vm.resumeGasMetering();

        account.updateToken(address(1), 1);

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[0].balanceDelta, 1);

        vm.resumeGasMetering();
    }

    function test_UpdateToken_Add() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.updateToken(address(1), 1);

        vm.resumeGasMetering();

        account.updateToken(address(1), 1);

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[0].balanceDelta, 2);

        vm.resumeGasMetering();
    }

    function test_UpdateToken_Subtract() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.updateToken(address(1), 1);

        vm.resumeGasMetering();

        account.updateToken(address(1), -2);

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[0].balanceDelta, -1);

        vm.resumeGasMetering();
    }

    function test_UpdateToken_Overflow() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.updateToken(address(1), type(int256).max);

        vm.expectRevert();
        vm.resumeGasMetering();

        account.updateToken(address(1), 1);
    }

    function test_UpdateToken_InvalidLength() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.updateToken(address(1), 1);

        vm.expectRevert();
        vm.resumeGasMetering();

        account.updateToken(address(2), 1);
    }
}
