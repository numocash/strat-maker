// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {scaleLiquidityDown} from "src/core/math/LiquidityMath.sol";

contract ScaleLiquidityDownTest is Test {
    function test_ScaleLiquidityDown() external {
        assertEq(scaleLiquidityDown(1e18, 0), 1e18, "scale liquidity down min");
        assertEq(scaleLiquidityDown(1e18, 32), uint128(1e18) / 2 ** 32, "scale liquidity down");
        assertEq(scaleLiquidityDown(type(uint256).max, 128), type(uint256).max / 2 ** 128, "scale liquidity down max");
    }
}
