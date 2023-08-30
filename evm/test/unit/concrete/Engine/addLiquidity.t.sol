// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {Pairs} from "src/core/Pairs.sol";
import {Positions, biDirectionalID} from "src/core/Positions.sol";

import {getAmounts} from "src/core/math/LiquidityMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

contract AddLiquidity is Test, Engine {
    using Accounts for Accounts.Account;
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    function test_AddLiquidity_InsufficientInput() external {}

    function test_AddLiquidity_LiquidityAccrued() external {}

    function test_AddLiquidity_LiquidityDisplaced() external {}

    function test_AddLiquidity_Amounts() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(1, 0);
        pair.initialize(0);

        vm.resumeGasMetering();

        _addLiquidity(address(this), Engine.AddLiquidityParams(address(1), address(2), 0, 2, 1, 1e18), account);

        vm.pauseGasMetering();

        (uint256 amount0,) = getAmounts(pair, 1e18, 2, 1, true);

        assertEq(uint256(account.erc20Data[0].balanceDelta), amount0);

        vm.resumeGasMetering();
    }

    function test_AddLiquidity_Mint_LiquidityGrowthZero() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(1, 0);
        pair.initialize(0);

        vm.resumeGasMetering();

        _addLiquidity(address(this), Engine.AddLiquidityParams(address(1), address(2), 0, 2, 1, 1e18), account);

        vm.pauseGasMetering();

        Positions.ILRTAData memory data = _dataOf[address(this)][biDirectionalID(address(1), address(2), 0, 2, 1)];

        assertEq(data.balance, 1e18);
        assertEq(data.buffer, 0);

        vm.resumeGasMetering();
    }

    function test_AddLiquidity_Mint_LiquidityGrowth() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        Accounts.Account memory account = Accounts.newAccount(1, 0);
        pair.initialize(0);
        pair.strikes[2].liquidityGrowthSpreadX128[0].liquidityGrowthX128 = 2 * Q128;

        vm.resumeGasMetering();

        _addLiquidity(address(this), Engine.AddLiquidityParams(address(1), address(2), 0, 2, 1, 1e18), account);

        vm.pauseGasMetering();

        Positions.ILRTAData memory data = _dataOf[address(this)][biDirectionalID(address(1), address(2), 0, 2, 1)];

        assertEq(data.balance, 0.5e18);
        assertEq(data.buffer, 0);

        vm.resumeGasMetering();
    }
}
