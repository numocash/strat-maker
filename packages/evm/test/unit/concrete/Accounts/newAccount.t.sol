// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";

contract NewAccountTest is Test {
    using Accounts for Accounts.Account;

    function test_Accounts_Zero() external {
        Accounts.Account memory account = Accounts.newAccount(0, 0);

        vm.pauseGasMetering();

        assertEq(account.erc20Data.length, 0);
        assertEq(account.lpData.length, 0);

        vm.resumeGasMetering();
    }

    function test_Accounts() external {
        Accounts.Account memory account = Accounts.newAccount(2, 3);

        vm.pauseGasMetering();

        assertEq(account.erc20Data.length, 2);
        assertEq(account.lpData.length, 3);

        assertEq(account.erc20Data[0].token, address(0));
        assertEq(account.erc20Data[1].token, address(0));

        assertEq(account.lpData[0].id, bytes32(uint256(0)));
        assertEq(account.lpData[1].id, bytes32(uint256(0)));
        assertEq(account.lpData[2].id, bytes32(uint256(0)));

        vm.resumeGasMetering();
    }
}
