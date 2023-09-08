// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {scaleLiquidityUp} from "src/core/math/LiquidityMath.sol";

contract ScaleLiquidityUpTest is Test {
    function test_ScaleLiquidityUp() external {
        assertEq(scaleLiquidityUp(1e18, 0), 1e18, "scale liquidity up min");
        assertEq(scaleLiquidityUp(1e18, 32), 1e18 * 2 ** 32, "scale liquidity up");
        assertEq(
            scaleLiquidityUp(type(uint128).max, 128), uint256(type(uint128).max) * 2 ** 128, "scale liquidity up max"
        );
    }
}
