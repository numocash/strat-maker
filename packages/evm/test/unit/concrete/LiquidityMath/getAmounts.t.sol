// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {getAmounts, getAmount0, getAmount1} from "src/core/math/LiquidityMath.sol";
import {getRatioAtStrike} from "src/core/math/StrikeMath.sol";
import {Pairs} from "src/core/Pairs.sol";

contract GetAmountsTest is Test {
    Pairs.Pair private pair;

    function test_GetAmounts_StrikeLess() external {
        (uint256 amount0, uint256 amount1) = getAmounts(pair, 1e18, -1, 1, false);

        assertEq(amount0, 0);
        assertEq(amount1, getAmount1(1e18));
    }

    function test_GetAmounts_StrikeGreater() external {
        (uint256 amount0, uint256 amount1) = getAmounts(pair, 1e18, 1, 1, false);

        assertEq(amount0, getAmount0(1e18, getRatioAtStrike(1), false));
        assertEq(amount1, 0);
    }

    function test_GetAmounts_StrikeEqual() external {
        (uint256 amount0, uint256 amount1) = getAmounts(pair, 1e18, 0, 1, false);
        assertEq(amount0, getAmount0(1e18, getRatioAtStrike(0), 0, false));
        assertEq(amount1, getAmount1(1e18, 0, false));
    }
}
