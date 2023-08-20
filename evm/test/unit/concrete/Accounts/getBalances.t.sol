// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";

contract GetBalanceTest is Test {
    using Accounts for Accounts.Account;

    function balanceOf(address owner) external returns (uint256) {
        return 10 ** 18;
    }

    function test_GetBalance_Positive() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.updateToken(address(this), 1);

        vm.resumeGasMetering();

        account.getBalances();

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].balanceBefore, 1e18);

        vm.resumeGasMetering();
    }

    function test_GetBalance_Negative() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.updateToken(address(this), -1);

        vm.resumeGasMetering();

        account.getBalances();

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].balanceBefore, 0);

        vm.resumeGasMetering();
    }

    function test_GetBalance_Multiple() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(2, 0);

        account.updateToken(address(1), -1);
        account.updateToken(address(this), 1);

        vm.resumeGasMetering();

        account.getBalances();

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].balanceBefore, 0);
        assertEq(account.erc20Data[1].balanceBefore, 1e18);

        vm.resumeGasMetering();
    }
}
