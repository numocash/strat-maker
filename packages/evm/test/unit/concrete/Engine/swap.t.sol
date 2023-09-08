// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {Pairs} from "src/core/Pairs.sol";

import {computeSwapStep} from "src/core/math/SwapMath.sol";
import {getRatioAtStrike} from "src/core/math/StrikeMath.sol";

contract SwapTest is Test, Engine(payable(address(0))) {
    using Accounts for Accounts.Account;
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    function test_Swap_Amounts() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(2, 0);

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        pair.initialize(0);
        pair.addSwapLiquidity(-1, 1, 1e18);
        pair.strikeCurrent[0] = -1;
        pair.composition[0] = type(uint128).max;

        vm.resumeGasMetering();

        _swap(Engine.SwapParams(address(1), address(2), 0, Engine.SwapTokenSelector.Token1, 0.5e18), account);

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[1].token, address(2));

        (, uint256 amountOut,) = computeSwapStep(getRatioAtStrike(0), 1e18 - 1, false, 0.5e18);

        assertEq(account.erc20Data[0].balanceDelta, -int256(amountOut));
        assertEq(account.erc20Data[1].balanceDelta, 0.5e18);

        vm.resumeGasMetering();
    }

    function test_Swap_InvalidAmount() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(2, 0);

        vm.resumeGasMetering();

        vm.expectRevert(Engine.InvalidAmountDesired.selector);
        _swap(Engine.SwapParams(address(0), address(0), 0, Engine.SwapTokenSelector.Token1, 0), account);
    }

    function test_Swap_Account() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(2, 0);

        account.erc20Data[0].token = address(1);
        account.erc20Data[1].token = address(2);
        account.erc20Data[0].balanceDelta = 0;
        account.erc20Data[1].balanceDelta = -0.5e18;

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        pair.initialize(0);
        pair.addSwapLiquidity(-1, 1, 1e18);
        pair.strikeCurrent[0] = -1;
        pair.composition[0] = type(uint128).max;

        vm.resumeGasMetering();

        _swap(Engine.SwapParams(address(1), address(2), 0, Engine.SwapTokenSelector.Account, 1), account);

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[1].token, address(2));

        (, uint256 amountOut,) = computeSwapStep(getRatioAtStrike(0), 1e18 - 1, false, 0.5e18);

        assertEq(account.erc20Data[0].balanceDelta, -int256(amountOut));
        assertEq(account.erc20Data[1].balanceDelta, 0);

        vm.resumeGasMetering();
    }

    function test_Swap_AccountInvalidAmount() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(2, 0);

        vm.resumeGasMetering();

        vm.expectRevert(Engine.InvalidAmountDesired.selector);
        _swap(Engine.SwapParams(address(0), address(0), 0, Engine.SwapTokenSelector.Account, 1), account);
    }

    function test_Swap_AccountInvalidIndex() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(2, 0);

        vm.resumeGasMetering();

        vm.expectRevert();
        _swap(Engine.SwapParams(address(0), address(0), 0, Engine.SwapTokenSelector.Account, 2), account);
    }
}
