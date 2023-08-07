// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {liquidityToBalance} from "src/core/math/PositionMath.sol";
import {Pairs} from "src/core/Pairs.sol";

contract LiquidityToBalanceTest is Test {
    Pairs.Pair private pair;

    function test_LiquidityToBalance_TotalSupplyZero() external {
        assertEq(liquidityToBalance(pair, 0, 1, 1e18), 1e18);
    }

    function test_LiquidityToBalance() external {
        // setup pair
        pair.strikes[0].totalSupply[0] = 1e18 - 1;
        pair.strikes[0].liquidityBiDirectional[0] = 0.5e18;
        pair.strikes[0].liquidityBorrowed[0] = 0.5e18;

        assertEq(liquidityToBalance(pair, 0, 1, 1e18), 1e18 - 1);

        // delete pair
        delete pair.strikes[0].totalSupply;
        delete pair.strikes[0].liquidityBiDirectional;
        delete pair.strikes[0].liquidityBorrowed;
    }

    function test_LiquidityToBalance_Max() external {
        // setup pair
        pair.strikes[0].totalSupply[0] = type(uint128).max;
        pair.strikes[0].liquidityBiDirectional[0] = type(uint128).max;

        assertEq(liquidityToBalance(pair, 0, 1, type(uint128).max), type(uint128).max);

        // delete pair
        delete pair.strikes[0].totalSupply;
        delete pair.strikes[0].liquidityBiDirectional;
    }
}
