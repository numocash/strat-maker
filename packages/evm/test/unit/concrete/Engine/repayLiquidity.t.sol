// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {Pairs} from "src/core/Pairs.sol";
import {debtID} from "src/core/Positions.sol";

import {Q128} from "src/core/math/StrikeMath.sol";

contract RepayLiquidityTest is Test, Engine(payable(address(0))) {
    using Accounts for Accounts.Account;
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    function test_RepayLiquidity_LiquidityAccruedZero() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 1);
        pair.initialize(0);

        pair.accrue(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 0.5e18);

        vm.resumeGasMetering();

        _repayLiquidity(
            Engine.RepayLiquidityParams(
                address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, uint136(Q128), 0.5e18
            ),
            account
        );

        vm.pauseGasMetering();

        assertEq(pair.strikes[0].liquidity[0].swap, 1e18);
        assertEq(pair.strikes[0].liquidity[0].borrowed, 0);
        assertEq(pair.strikes[0].blockLast, 1);

        vm.resumeGasMetering();
    }

    function test_RepayLiquidity_LiquidityAccrued() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 1);
        pair.initialize(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 0.5e18);
        pair.strikes[0].liquidityRepayRateX128 = Q128;

        vm.resumeGasMetering();

        _repayLiquidity(
            Engine.RepayLiquidityParams(
                address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, uint136(Q128), 0.5e18
            ),
            account
        );

        vm.pauseGasMetering();

        assertEq(pair.strikes[0].liquidity[0].swap, 1e18);
        assertEq(pair.strikes[0].liquidity[0].borrowed, 0);
        assertEq(pair.strikes[0].blockLast, 1);

        vm.resumeGasMetering();
    }

    function test_RepayLiquidity_RepayLiquidityGrowthZero() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 1);
        pair.initialize(0);

        pair.accrue(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 0.5e18);

        vm.resumeGasMetering();

        _repayLiquidity(
            Engine.RepayLiquidityParams(
                address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, uint136(Q128), 0.5e18
            ),
            account
        );

        vm.pauseGasMetering();

        assertEq(pair.strikes[0].liquidity[0].swap, 1e18);
        assertEq(pair.strikes[0].liquidity[0].borrowed, 0);
        assertEq(
            account.lpData[0].id, debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, uint136(Q128))
        );
        assertEq(account.lpData[0].amountBurned, 0.5e18);

        vm.resumeGasMetering();
    }

    function test_RepayLiquidity_RepayLiquidityGrowth() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 1);
        pair.initialize(0);

        pair.accrue(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 0.5e18);
        pair.strikes[0].liquidityGrowthX128 = Q128 / 2;

        vm.resumeGasMetering();

        _repayLiquidity(
            Engine.RepayLiquidityParams(
                address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, uint136(Q128), 1e18
            ),
            account
        );

        vm.pauseGasMetering();

        assertEq(pair.strikes[0].liquidity[0].swap, 1e18);
        assertEq(pair.strikes[0].liquidity[0].borrowed, 0);
        assertEq(
            account.lpData[0].id, debtID(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, uint136(Q128))
        );
        assertEq(account.lpData[0].amountBurned, 1e18);

        vm.resumeGasMetering();
    }

    function test_RepayLiquidity_InvalidAmountDesired() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 1);
        pair.initialize(0);

        pair.accrue(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 0.5e18);

        vm.resumeGasMetering();

        vm.expectRevert(Engine.InvalidAmountDesired.selector);
        _repayLiquidity(
            Engine.RepayLiquidityParams(address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, uint136(Q128), 0),
            account
        );
    }

    function test_RepayLiquidity_CollateralAmount() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 1);
        pair.initialize(0);

        pair.accrue(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 0.5e18);

        vm.resumeGasMetering();

        _repayLiquidity(
            Engine.RepayLiquidityParams(
                address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, 2 * uint136(Q128), 0.5e18
            ),
            account
        );

        vm.pauseGasMetering();

        assertEq(account.erc20Data[1].token, address(2));
        assertEq(account.erc20Data[1].balanceDelta, -1.5e18);

        vm.resumeGasMetering();
    }

    function test_RepayLiquidity_CollateralAmountScale() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 8);
        Accounts.Account memory account = Accounts.newAccount(2, 1);
        pair.initialize(0);

        pair.accrue(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 0.5e18);

        vm.resumeGasMetering();

        _repayLiquidity(
            Engine.RepayLiquidityParams(
                address(1), address(2), 8, 0, Engine.TokenSelector.Token1, 0, 2 * uint136(Q128), 0.5e18
            ),
            account
        );

        vm.pauseGasMetering();

        assertEq(account.erc20Data[1].token, address(2));
        assertEq(account.erc20Data[1].balanceDelta, -1.5e18 << 8);

        vm.resumeGasMetering();
    }

    function test_RepayLiquidity_CollateralAmountLiquidityGrowth() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 1);
        pair.initialize(0);

        pair.accrue(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 0.5e18);
        pair.strikes[0].liquidityGrowthX128 = Q128 / 2;

        vm.resumeGasMetering();

        _repayLiquidity(
            Engine.RepayLiquidityParams(
                address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, uint136(Q128), 0.5e18
            ),
            account
        );

        vm.pauseGasMetering();

        assertEq(account.erc20Data[1].token, address(2));
        assertEq(account.erc20Data[1].balanceDelta, -0.5e18);

        vm.resumeGasMetering();
    }

    function test_RepayLiquidity_RepayAmount() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 1);
        pair.initialize(0);

        pair.accrue(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 0.5e18);

        vm.resumeGasMetering();

        _repayLiquidity(
            Engine.RepayLiquidityParams(
                address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, uint136(Q128), 0.5e18
            ),
            account
        );

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[0].balanceDelta, 0.5e18);

        vm.resumeGasMetering();
    }

    function test_RepayLiquidity_RepayAmountMultiSpread() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 1);
        pair.initialize(0);

        pair.accrue(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addSwapLiquidity(0, 2, 1e18);

        pair.addBorrowedLiquidity(0, 1.5e18);

        vm.resumeGasMetering();

        _repayLiquidity(
            Engine.RepayLiquidityParams(
                address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, uint136(Q128), 1.5e18
            ),
            account
        );

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[0].balanceDelta, 1.5e18);

        vm.resumeGasMetering();
    }

    function test_RepayLiquidity_RepayAmountEmptySpread() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(2, 1);
        pair.initialize(0);

        pair.accrue(0);

        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addSwapLiquidity(0, 3, 1e18);

        pair.addBorrowedLiquidity(0, 1.5e18);

        vm.resumeGasMetering();

        _repayLiquidity(
            Engine.RepayLiquidityParams(
                address(1), address(2), 0, 0, Engine.TokenSelector.Token1, 0, uint136(Q128), 1.5e18
            ),
            account
        );

        vm.pauseGasMetering();

        assertEq(account.erc20Data[0].token, address(1));
        assertEq(account.erc20Data[0].balanceDelta, 1.5e18);

        vm.resumeGasMetering();
    }
}
