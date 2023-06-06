// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PairHelper} from "./helpers/PairHelper.sol";

import {Pair} from "src/core/Pair.sol";
import {mulDiv} from "src/core/FullMath.sol";
import {getRatioAtTick} from "src/core/TickMath.sol";
import {Q128, Q96} from "src/core/TickMath.sol";

contract MintTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testMintReturnAmounts() external {
        (uint256 amount0, uint256 amount1) = basicMint();

        assertEq(amount0, 1e18);
        assertEq(amount1, 1e18);
    }

    function testMintTokenBalances() external {
        basicMint();

        assertEq(token0.balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), 0);

        assertEq(token0.balanceOf(address(pair)), 1e18);
        assertEq(token1.balanceOf(address(pair)), 1e18);
    }

    function testMintTierLiquidityInRange() external {
        basicMint();

        (uint256 liquidity) = pair.tiers(0);

        assertEq(liquidity, 1e18);
    }

    function testMintTierLiquidityOutRange() external {
        token1.mint(address(this), 1e18);
        pair.mint(address(this), 0, -1, -1, 1e18, bytes(""));

        (uint256 liquidity) = pair.tiers(0);

        assertEq(liquidity, 0);
    }

    function testMintTicks() external {
        basicMint();

        (uint256 liquidityGross, int256 liquidityNet) = pair.ticks(keccak256(abi.encodePacked(uint8(0), int24(-1))));
        assertEq(liquidityGross, 1e18);
        assertEq(liquidityNet, 1e18);

        (liquidityGross, liquidityNet) = pair.ticks(keccak256(abi.encodePacked(uint8(0), int24(0))));
        assertEq(liquidityGross, 1e18);
        assertEq(liquidityNet, -1e18);
    }

    function testMintPosition() external {
        basicMint();
        (uint256 liquidity) = pair.positions(keccak256(abi.encodePacked(address(this), uint8(0), int24(-1), int24(0))));

        assertEq(liquidity, 1e18);
    }

    function testMintBadTicks() external {
        vm.expectRevert(Pair.InvalidTick.selector);
        pair.mint(address(this), 0, type(int24).min, 0, 1e18, bytes(""));

        vm.expectRevert(Pair.InvalidTick.selector);
        pair.mint(address(this), 0, 0, type(int24).max, 1e18, bytes(""));

        vm.expectRevert(Pair.InvalidTick.selector);
        pair.mint(address(this), 0, 1, 0, 1e18, bytes(""));
    }

    function testMintBadTier() external {
        vm.expectRevert(Pair.InvalidTier.selector);
        pair.mint(address(this), 10, -1, 0, 1e18, bytes(""));
    }
}

contract BurnTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testBurnReturnAmounts() external {
        basicMint();
        (uint256 amount0, uint256 amount1) = basicBurn();

        assertEq(amount0, 1e18);
        assertEq(amount1, 1e18);
    }

    function testBurnTokenAmounts() external {
        basicMint();
        basicBurn();

        assertEq(token0.balanceOf(address(this)), 1e18);
        assertEq(token1.balanceOf(address(this)), 1e18);

        assertEq(token0.balanceOf(address(pair)), 0);
        assertEq(token1.balanceOf(address(pair)), 0);
    }

    function testTierInRange() external {
        basicMint();
        basicBurn();

        (uint256 liquidity) = pair.tiers(0);

        assertEq(liquidity, 0);
    }

    function testTierOutRange() external {
        token1.mint(address(this), 1e18);
        pair.mint(address(this), 0, -1, -1, 1e18, bytes(""));

        pair.burn(address(this), 0, -1, -1, 1e18);

        (uint256 liquidity) = pair.tiers(0);

        assertEq(liquidity, 0);
    }

    function testBurnTicks() external {
        basicMint();
        basicBurn();

        (uint256 liquidityGross, int256 liquidityNet) = pair.ticks(keccak256(abi.encodePacked(uint8(0), int24(-1))));
        assertEq(liquidityGross, 0);
        assertEq(liquidityNet, 0);

        (liquidityGross, liquidityNet) = pair.ticks(keccak256(abi.encodePacked(uint8(0), int24(0))));
        assertEq(liquidityGross, 0);
        assertEq(liquidityNet, 0);
    }

    function testBurnPosition() external {
        basicMint();
        basicBurn();

        (uint256 liquidity) = pair.positions(keccak256(abi.encodePacked(address(this), uint8(0), int24(-1), int24(0))));

        assertEq(liquidity, 0);
    }

    function testBurnBadTicks() external {
        vm.expectRevert(Pair.InvalidTick.selector);
        pair.burn(address(this), 0, type(int24).min, 0, 1e18);

        vm.expectRevert(Pair.InvalidTick.selector);
        pair.burn(address(this), 0, 0, type(int24).max, 1e18);

        vm.expectRevert(Pair.InvalidTick.selector);
        pair.burn(address(this), 0, 1, 0, 1e18);
    }

    function testBurnBadTier() external {
        vm.expectRevert(Pair.InvalidTier.selector);
        pair.burn(address(this), 10, -1, 0, 1e18);
    }
}

contract SwapTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testSwapReturnAmountsToken1ExactIn() external {
        basicMint();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), false, 1e18);

        assertEq(amount0, -1e18);
        assertEq(amount1, 1e18);
    }

    function testSwapReturnAmountsToken0ExactOut() external {
        basicMint();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), true, -1e18);

        assertEq(amount0, -1e18);
        assertEq(amount1, 1e18);
    }

    function testSwapReturnAmountsToken0ExactIn() external {
        basicMint();
        // 0->1
        (int256 amount0, int256 amount1) = pair.swap(address(this), true, 1e18);

        uint256 amountOut = mulDiv(1e18, getRatioAtTick(-1), Q128);

        assertEq(amount0, 1e18, "amount0");
        assertEq(amount1, -int256(amountOut), "amount1");
    }

    function testSwapReturnAmountsToken1ExactOut() external {
        basicMint();
        // 0->1
        (int256 amount0, int256 amount1) = pair.swap(address(this), false, -1e18);

        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));

        assertEq(amount0, int256(amountIn), "amount0");
        assertEq(amount1, -1e18, "amount1");
    }

    function testSwapPartialReturnAmountsToken1ExactIn() external {
        basicMint();
        (int256 amount0, int256 amount1) = pair.swap(address(this), false, 0.5e18);

        assertEq(amount0, -0.5e18);
        assertEq(amount1, 0.5e18);
    }

    function testSwapPartialReturnAmountsToken0ExactOut() external {
        basicMint();
        (int256 amount0, int256 amount1) = pair.swap(address(this), true, -0.5e18);

        assertEq(amount0, -0.5e18);
        assertEq(amount1, 0.5e18);
    }

    function testSwapAmount0Out() external {
        basicMint();
        pair.swap(address(this), false, 1e18);

        assertEq(token0.balanceOf(address(this)), 1e18);
        assertEq(token1.balanceOf(address(this)), 0);
    }

    function testSwapAmount1Out() external {
        basicMint();
        pair.swap(address(this), true, 1e18);

        uint256 amountOut = mulDiv(1e18, getRatioAtTick(-1), Q128);

        assertEq(token0.balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), amountOut);
    }

    function testSwapCompositionToken1ExactIn() external {
        basicMint();
        pair.swap(address(this), false, 1e18);

        assertEq(pair.composition(), type(uint96).max);
    }

    function testSwapCompositionToken0ExactOut() external {
        basicMint();
        pair.swap(address(this), true, -1e18);

        assertEq(pair.composition(), type(uint96).max);
    }

    function testSwapCompositionToken0ExactIn() external {
        basicMint();
        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));
        pair.swap(address(this), true, int256(amountIn));

        assertEq(pair.composition(), 0);
    }

    function testSwapCompositionToken1ExactOut() external {
        basicMint();
        pair.swap(address(this), false, -1e18);

        assertEq(pair.composition(), 0);
    }

    function testSwapPartialCompositionToken1ExactIn() external {
        basicMint();
        pair.swap(address(this), false, 0.5e18);

        assertEq(pair.composition(), Q96 / 2);
    }

    function testSwapPartialCompositionToken0ExactOut() external {
        basicMint();
        pair.swap(address(this), true, -0.5e18);

        assertEq(pair.composition(), Q96 / 2);
    }

    function testSwapNoChangeLiquidity() external {
        basicMint();
        pair.swap(address(this), false, 1e18);

        (uint256 liquidity) = pair.tiers(0);

        assertEq(liquidity, 1e18);
    }

    function testSwapNoChangeTick() external {
        basicMint();
        pair.swap(address(this), false, 1e18);

        assertEq(pair.tickCurrent(), 0);
    }
}
