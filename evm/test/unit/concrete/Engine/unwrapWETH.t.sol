// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {Pairs} from "src/core/Pairs.sol";

import {WETH} from "solmate/src/tokens/WETH.sol";

contract UnwrapWETHTest is Test, Engine(payable(new WETH())) {
    using Accounts for Accounts.Account;
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    address private cuh;

    function setUp() external {
        cuh = makeAddr("cuh");
    }

    function test_WrapWETH_InvalidWETHIndex() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);

        vm.resumeGasMetering();

        vm.expectRevert();
        _unwrapWETH(cuh, Engine.UnwrapWETHParams(0), account);
    }

    function test_WrapWETH_Positive() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.erc20Data[0].token = weth;
        account.erc20Data[0].balanceDelta = 1e18;

        uint256 balanceBefore = address(this).balance;

        vm.resumeGasMetering();

        _unwrapWETH(address(cuh), Engine.UnwrapWETHParams(0), account);

        vm.pauseGasMetering();

        assertEq(address(this).balance, balanceBefore);
        assertEq(cuh.balance, 0);
        assertEq(WETH(weth).balanceOf(address(this)), 0);
        assertEq(account.erc20Data[0].balanceDelta, 1e18);

        vm.resumeGasMetering();
    }

    function test_WrapWETH_Negative() external payable {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.erc20Data[0].token = weth;
        account.erc20Data[0].balanceDelta = -1e18;

        vm.deal(address(this), 1e18);
        WETH(weth).deposit{value: 1e18}();

        uint256 balanceBefore = address(this).balance;

        vm.resumeGasMetering();

        _unwrapWETH(address(cuh), Engine.UnwrapWETHParams(0), account);

        vm.pauseGasMetering();

        assertEq(address(this).balance, balanceBefore);
        assertEq(cuh.balance, 1e18);
        assertEq(WETH(weth).balanceOf(address(this)), 0);
        assertEq(account.erc20Data[0].balanceDelta, 0);

        vm.resumeGasMetering();
    }
}
