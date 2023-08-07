// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {balanceToLiquidity} from "src/core/math/PositionMath.sol";
import {Pairs} from "src/core/Pairs.sol";

contract BalanceToLiquidityTest is Test {
    Pairs.Pair private pair;

    function test_BalanceToLiquidity() external {
        // setup pair
        pair.strikes[0].totalSupply[0] = 1e18;
        pair.strikes[0].liquidityBiDirectional[0] = 0.5e18;
        pair.strikes[0].liquidityBorrowed[0] = 0.5e18;

        assertEq(balanceToLiquidity(pair, 0, 1, 1e18), 1e18);

        // delete pair
        delete pair.strikes[0].totalSupply;
        delete pair.strikes[0].liquidityBiDirectional;
        delete pair.strikes[0].liquidityBorrowed;
    }

    function test_BalanceToLiquidity_Max() external {
        // setup pair
        pair.strikes[0].totalSupply[0] = type(uint128).max;
        pair.strikes[0].liquidityBiDirectional[0] = type(uint128).max;

        assertEq(balanceToLiquidity(pair, 0, 1, type(uint128).max), type(uint128).max);

        // delete pair
        delete pair.strikes[0].totalSupply;
        delete pair.strikes[0].liquidityBiDirectional;
    }

    function test_BalanceToLiquidity_Overflow() external {
        // setup pair
        pair.strikes[0].totalSupply[0] = type(uint128).max - 1;
        pair.strikes[0].liquidityBiDirectional[0] = type(uint128).max;

        vm.expectRevert();
        balanceToLiquidity(pair, 0, 1, type(uint128).max);

        // delete pair
        delete pair.strikes[0].totalSupply;
        delete pair.strikes[0].liquidityBiDirectional;
    }
}