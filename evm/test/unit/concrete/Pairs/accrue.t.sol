// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Pairs} from "src/core/Pairs.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

contract AccrueTest is Test {
    using Pairs for Pairs.Pair;

    Pairs.Pair private pair;

    /// @notice Test accruing a pair that isn't initialized
    function test_Accrue_NotInitialized() external {
        vm.expectRevert(Pairs.Initialized.selector);
        pair.accrue(0);
    }

    /// @notice Test accruing a pair with zero blocks passed since last update
    function test_Accrue_ZeroBlocks() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.accrue(0);

        vm.resumeGasMetering();

        uint136 liquidity = pair.accrue(0);

        vm.pauseGasMetering();

        assertEq(liquidity, 0);

        vm.resumeGasMetering();
    }

    /// @notice Test accruing a pair with no liquidity borrowed
    function test_Accrue_NoLiquidityBorrowed() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        uint136 liquidity = pair.accrue(0);

        vm.pauseGasMetering();

        assertEq(liquidity, 0);

        vm.resumeGasMetering();
    }

    /// @notice Test accruing a pair and generating liquidty to be repaid
    function test_Accrue_LiquidityRepaid() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.accrue(0);
        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 1e18);

        vm.roll(block.number + 1);

        vm.resumeGasMetering();

        uint136 liquidity = pair.accrue(0);

        vm.pauseGasMetering();

        assertEq(liquidity, 1e18 / 10_000);
        assertEq(pair.strikes[0].liquidityGrowthSpreadX128[0].liquidityGrowthX128, Q128 + Q128 / 10_000);
        assertEq(pair.strikes[0].liquidityGrowthX128.liquidityGrowthX128, Q128 + Q128 / 10_000);

        vm.resumeGasMetering();
    }

    /// @notice Test accruing a pair and accruing the maximum amount of interest
    function test_Accrue_LiquidityRepaidMax() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.accrue(0);
        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 1e18);

        vm.roll(block.number + 10_001);

        vm.resumeGasMetering();

        uint136 liquidity = pair.accrue(0);

        vm.pauseGasMetering();

        assertEq(liquidity, 1e18);
        assertEq(pair.strikes[0].liquidityGrowthSpreadX128[0].liquidityGrowthX128, Q128 * 2);
        assertEq(pair.strikes[0].liquidityGrowthX128.liquidityGrowthX128, Q128 * 2);

        vm.resumeGasMetering();
    }

    /// @notice Test accruing a pair when the liquidity growth is not zero
    function test_Accrue_LiquidityGrowthNotZero() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 1e18);

        pair.accrue(0);

        vm.roll(block.number + 1);

        vm.resumeGasMetering();

        uint136 liquidity = pair.accrue(0);

        vm.pauseGasMetering();

        vm.pauseGasMetering();

        assertEq(liquidity, 1e18 / 10_000);
        assertEq(pair.strikes[0].liquidityGrowthSpreadX128[0].liquidityGrowthX128, Q128 + 2 * (Q128 / 10_000));
        assertEq(pair.strikes[0].liquidityGrowthX128.liquidityGrowthX128, Q128 + 2 * (Q128 / 10_000));

        vm.resumeGasMetering();
    }

    /// @notice Test accruing a pair when liquidity is borrowed across two spreads
    function test_Accrue_MultiSpread() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.accrue(0);
        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addSwapLiquidity(0, 2, 1e18);

        pair.addBorrowedLiquidity(0, 1.5e18);

        vm.roll(block.number + 1);

        vm.resumeGasMetering();

        uint136 liquidity = pair.accrue(0);

        vm.pauseGasMetering();

        assertEq(liquidity, 1e18 / 5000);
        assertEq(pair.strikes[0].liquidityGrowthSpreadX128[0].liquidityGrowthX128, Q128 + Q128 / 10_000);
        assertEq(pair.strikes[0].liquidityGrowthSpreadX128[1].liquidityGrowthX128, Q128 + Q128 / 5000);
        assertEq(pair.strikes[0].liquidityGrowthX128.liquidityGrowthX128, Q128 + (Q128 * (1e18 / 5000)) / 1.5e18);

        vm.resumeGasMetering();
    }

    /// @notice Test accruing a pair when liquidity borrowed for one spread is zero before the active spread
    function test_Accrue_SpreadZero() external {
        vm.pauseGasMetering();

        pair.initialize(0);
        pair.accrue(0);
        pair.addSwapLiquidity(0, 2, 1e18);
        pair.addBorrowedLiquidity(0, 1e18);

        vm.roll(block.number + 1);

        vm.resumeGasMetering();

        uint136 liquidity = pair.accrue(0);

        vm.pauseGasMetering();

        assertEq(liquidity, 1e18 / 5000);
        assertEq(pair.strikes[0].liquidityGrowthSpreadX128[1].liquidityGrowthX128, Q128 + Q128 / 5000);
        assertEq(pair.strikes[0].liquidityGrowthX128.liquidityGrowthX128, Q128 + Q128 / 5000);

        vm.resumeGasMetering();
    }
}
