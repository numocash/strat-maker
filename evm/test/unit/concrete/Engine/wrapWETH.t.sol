// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {Pairs} from "src/core/Pairs.sol";

import {WETH} from "solmate/src/tokens/WETH.sol";

import {console2} from "forge-std/console2.sol";

contract WrapWETHTest is Test, Engine(payable(new WETH())) {
    using Accounts for Accounts.Account;
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    function test_WrapWETH_MaxValue() external {
        vm.skip(true);
    }

    function test_WrapWETH_Zero() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);

        vm.resumeGasMetering();

        _wrapWETH(account);

        vm.pauseGasMetering();

        assertEq(WETH(weth).balanceOf(address(this)), 0);
        assertEq(account.erc20Data[0].balanceDelta, 0);
        assertEq(account.erc20Data[0].token, weth);

        vm.resumeGasMetering();
    }

    function test_WrapWETH_NonZero() external payable {
        vm.skip(true);
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);

        vm.deal(address(this), 1 ether);

        console2.log(msg.value);

        vm.resumeGasMetering();

        _wrapWETH(account);

        vm.pauseGasMetering();

        assertEq(WETH(weth).balanceOf(address(this)), 0);
        assertEq(account.erc20Data[0].balanceDelta, 0);

        vm.resumeGasMetering();
    }
}
