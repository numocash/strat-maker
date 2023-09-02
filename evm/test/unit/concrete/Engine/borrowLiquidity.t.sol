// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {Pairs} from "src/core/Pairs.sol";
import {Positions, debtID} from "src/core/Positions.sol";

import {Q128} from "src/core/math/StrikeMath.sol";

contract BorrowLiquidityTest is Test, Engine(payable(address(0))) {
    using Accounts for Accounts.Account;
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    function test_BorrowLiquidity_LiquidityAccruedZero() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 0);
        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 1e18, 0.5e18),
            account
        );

        vm.pauseGasMetering();

        assertEq(pair.strikes[0].liquidity[0].swap, 0.5e18);
        assertEq(pair.strikes[0].liquidity[0].borrowed, 0.5e18);
        assertEq(pair.strikes[0].blockLast, 1);

        vm.resumeGasMetering();
    }

    function test_BorrowLiquidity_LiquidityAccrued() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 0);
        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 0.5e18);

        vm.resumeGasMetering();

        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 1e18, 0.5e18),
            account
        );

        vm.pauseGasMetering();

        assertEq(pair.strikes[0].liquidity[0].swap, 0.5e18 / 10_000);
        assertEq(pair.strikes[0].liquidity[0].borrowed, 1e18 - 0.5e18 / 10_000);
        assertEq(pair.strikes[0].blockLast, 1);

        vm.resumeGasMetering();
    }

    function test_BorrowLiquidity_InvalidAmountDesired() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(2, 0);

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        pair.initialize(0);
        pair.accrue(0);

        vm.resumeGasMetering();

        vm.expectRevert(Engine.InvalidAmountDesired.selector);
        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 1e18, 0),
            account
        );
    }

    function test_BorrowLiquidity_UpdatePair() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(2, 0);

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        pair.initialize(0);
        pair.accrue(0);
        pair.addSwapLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 1e18, 0.5e18),
            account
        );

        vm.pauseGasMetering();

        assertEq(pair.strikes[0].liquidity[0].swap, 0.5e18);
        assertEq(pair.strikes[0].liquidity[0].borrowed, 0.5e18);
        assertEq(pair.strikes[0].activeSpread, 0);

        vm.resumeGasMetering();
    }

    function test_BorrowLiquidity_MintAmount() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 0);
        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 1e18, 0.5e18),
            account
        );

        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            _dataOf[address(this)][debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token1)];

        assertEq(data.balance, 0.5e18);
        assertEq(data.buffer, 0.5e18);

        vm.resumeGasMetering();
    }

    function test_BorrowLiquidity_MintAmountLiquidityGrowth() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 0);
        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.strikes[0].liquidityGrowthExpX128 = 2 * Q128;

        vm.resumeGasMetering();

        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 1e18, 0.5e18),
            account
        );

        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            _dataOf[address(this)][debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token1)];

        assertEq(data.balance, 1e18);
        assertEq(data.buffer, 1e18);

        vm.resumeGasMetering();
    }

    function test_BorrowLiquidity_MintAmountScale() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 8);
        Accounts.Account memory account = Accounts.newAccount(2, 0);
        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 8, 0, Engine.TokenSelector.Token1, 1e18 << 8, 0.5e18),
            account
        );

        vm.pauseGasMetering();

        Positions.ILRTAData memory data =
            _dataOf[address(this)][debtID(address(1), address(2), 8, 0, Engine.TokenSelector.Token1)];

        assertEq(data.balance, 0.5e18);
        assertEq(data.buffer, 0.5e18);

        vm.resumeGasMetering();
    }

    function test_BorrowLiquidity_Undercollateralized() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(2, 0);

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        pair.initialize(0);
        pair.accrue(0);
        pair.addSwapLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        vm.expectRevert(Engine.InvalidAmountDesired.selector);
        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0.5e18 - 1, 0.5e18),
            account
        );
    }

    function test_BorrowLiquidity_Amounts() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 0);
        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 1e18, 0.5e18),
            account
        );

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[1].token, address(2));
        assertEq(account.erc20Data[0].balanceDelta, 1 - 0.5e18);
        assertEq(account.erc20Data[1].balanceDelta, 1e18);

        vm.resumeGasMetering();
    }

    function test_BorrowLiquidity_AmountsScale() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 8);
        Accounts.Account memory account = Accounts.newAccount(2, 0);
        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 8, 0, Engine.TokenSelector.Token1, 1e18 << 8, 0.5e18),
            account
        );

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[1].token, address(2));
        assertEq(account.erc20Data[0].balanceDelta, 1 - (0.5e18 << 8));
        assertEq(account.erc20Data[1].balanceDelta, 1e18 << 8);

        vm.resumeGasMetering();
    }

    function test_BorrowLiquidity_AmountsMultiSpread() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 0);
        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addSwapLiquidity(0, 2, 1e18);

        vm.resumeGasMetering();

        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 2e18, 1.5e18),
            account
        );

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[1].token, address(2));
        assertEq(account.erc20Data[0].balanceDelta, 2 - 1.5e18);
        assertEq(account.erc20Data[1].balanceDelta, 2e18);

        vm.resumeGasMetering();
    }

    function test_BorrowLiquidity_AmountsEmptySpread() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 0);
        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addSwapLiquidity(0, 3, 1e18);

        vm.resumeGasMetering();

        _borrowLiquidity(
            address(this),
            Engine.BorrowLiquidityParams(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 2e18, 1.5e18),
            account
        );

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[1].token, address(2));
        assertEq(account.erc20Data[0].balanceDelta, 2 - 1.5e18);
        assertEq(account.erc20Data[1].balanceDelta, 2e18);

        vm.resumeGasMetering();
    }
}
