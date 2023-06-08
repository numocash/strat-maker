// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PairHelper} from "./helpers/PairHelper.sol";

import {Pair} from "src/core/Pair.sol";
import {mulDiv} from "src/core/FullMath.sol";
import {getRatioAtTick} from "src/core/TickMath.sol";
import {Q128} from "src/core/TickMath.sol";

contract AddLiquidityTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testAddLiquidityReturnAmounts() external {
        (uint256 amount0, uint256 amount1) = basicAddLiquidity();

        assertEq(amount0, 1e18);
        assertEq(amount1, 0);
    }

    function testLiqudityTokenBalances() external {
        basicAddLiquidity();

        assertEq(token0.balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), 0);

        assertEq(token0.balanceOf(address(pair)), 1e18);
        assertEq(token1.balanceOf(address(pair)), 0);
    }

    function testLiquidityTicks() external {
        basicAddLiquidity();

        (uint256 liquidity) = pair.ticks(keccak256(abi.encodePacked(uint8(0), int24(0))));
        assertEq(liquidity, 1e18);
    }

    function testLiquidityPosition() external {
        basicAddLiquidity();
        (uint256 liquidity) = pair.positions(keccak256(abi.encodePacked(address(this), uint8(0), int24(0))));

        assertEq(liquidity, 1e18);
    }

    function testAddLiquidityBadTicks() external {
        vm.expectRevert(Pair.InvalidTick.selector);
        pair.addLiquidity(address(this), 0, type(int24).min, 1e18, bytes(""));

        vm.expectRevert(Pair.InvalidTick.selector);
        pair.addLiquidity(address(this), 0, type(int24).max, 1e18, bytes(""));
    }

    function testAddLiquidityBadTier() external {
        vm.expectRevert(Pair.InvalidTier.selector);
        pair.addLiquidity(address(this), 10, 0, 1e18, bytes(""));
    }
}

contract RemoveLiquidityTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testRemoveLiquidityReturnAmounts() external {
        basicAddLiquidity();
        (uint256 amount0, uint256 amount1) = basicRemoveLiquidity();

        assertEq(amount0, 1e18);
        assertEq(amount1, 0);
    }

    function testRemoveLiquidityTokenAmounts() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        assertEq(token0.balanceOf(address(this)), 1e18);
        assertEq(token1.balanceOf(address(this)), 0);

        assertEq(token0.balanceOf(address(pair)), 0);
        assertEq(token1.balanceOf(address(pair)), 0);
    }

    function testRemoveLiquidityTicks() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        (uint256 liquidity) = pair.ticks(keccak256(abi.encodePacked(uint8(0), int24(0))));
        assertEq(liquidity, 0);
    }

    function testRemoveLiquidityPosition() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        (uint256 liquidity) = pair.positions(keccak256(abi.encodePacked(address(this), uint8(0), int24(0))));

        assertEq(liquidity, 0);
    }

    function testRemoveLiquidityBadTicks() external {
        vm.expectRevert(Pair.InvalidTick.selector);
        pair.removeLiquidity(address(this), 0, type(int24).min, 1e18);

        vm.expectRevert(Pair.InvalidTick.selector);
        pair.removeLiquidity(address(this), 0, type(int24).max, 1e18);
    }

    function testRemoveLiquidityBadTier() external {
        vm.expectRevert(Pair.InvalidTier.selector);
        pair.removeLiquidity(address(this), 10, 0, 1e18);
    }
}

contract SwapTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testSwapReturnAmountsToken1ExactIn() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), false, 1e18 - 1, bytes(""));

        assertEq(amount0, -1e18 + 1);
        assertEq(amount1, 1e18 - 1);
    }

    function testSwapReturnAmountsToken0ExactOut() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), true, -1e18 + 1, bytes(""));

        assertEq(amount0, -1e18);
        assertEq(amount1, 1e18);
    }

    // function testSwapReturnAmountsToken0ExactIn() external {
    //     basicAddLiquidity();
    //     // 0->1
    //     (int256 amount0, int256 amount1) = pair.swap(address(this), true, 1e18, bytes(""));

    //     uint256 amountOut = mulDiv(1e18, getRatioAtTick(-1), Q128);

    //     assertEq(amount0, 1e18, "amount0");
    //     assertEq(amount1, -int256(amountOut), "amount1");
    // }

    // function testSwapReturnAmountsToken1ExactOut() external {
    //     basicMint();
    //     // 0->1
    //     (int256 amount0, int256 amount1) = pair.swap(address(this), false, -0.5e18);

    //     uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));

    //     assertEq(amount0, int256(amountIn), "amount0");
    //     assertEq(amount1, -1e18, "amount1");
    // }

    function testSwapPartialReturnAmountsToken1ExactIn() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), false, 0.5e18, bytes(""));

        assertEq(amount0, -0.5e18);
        assertEq(amount1, 0.5e18);
    }

    function testSwapPartialReturnAmountsToken0ExactOut() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), true, -0.5e18, bytes(""));

        assertEq(amount0, -0.5e18);
        assertEq(amount1, 0.5e18);
    }

    function testSwapAmount0Out() external {
        basicAddLiquidity();
        // 1->0
        pair.swap(address(this), false, 1e18 - 1, bytes(""));

        assertEq(token0.balanceOf(address(this)), 1e18);
        assertEq(token1.balanceOf(address(this)), 0);
    }

    // function testSwapAmount1Out() external {
    //     basicAddLiquidity();
    //     // 1->0
    //     pair.swap(address(this), true, 1e18 - 1, bytes(""));

    //     uint256 amountOut = mulDiv(1e18, getRatioAtTick(-1), Q128);

    //     assertEq(token0.balanceOf(address(this)), 0);
    //     assertEq(token1.balanceOf(address(this)), amountOut);
    // }

    function testSwapCompositionToken1ExactIn() external {
        basicAddLiquidity();
        // 1->0
        pair.swap(address(this), false, 1e18 - 1, bytes(""));

        assertEq(pair.compositions(0), type(uint96).max);
    }

    function testSwapCompositionToken0ExactOut() external {
        basicAddLiquidity();
        //1->0
        pair.swap(address(this), true, -1e18 + 1, bytes(""));

        assertEq(pair.compositions(0), type(uint96).max);
    }

    // function testSwapCompositionToken0ExactIn() external {
    //     basicAddLiquidity();

    //     uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));
    //     pair.swap(address(this), true, int256(amountIn), bytes(""));

    //     assertEq(pair.compositions(0), 0);
    // }

    // function testSwapCompositionToken1ExactOut() external {
    //     basicAddLiquidity();
    //     pair.swap(address(this), false, -1e18);

    //     assertEq(pair.composition(), 0);
    // }

    function testSwapPartialCompositionToken1ExactIn() external {
        basicAddLiquidity();
        pair.swap(address(this), false, 0.5e18, bytes(""));

        assertEq(pair.compositions(0), Q128 / 2);
    }

    function testSwapPartialCompositionToken0ExactOut() external {
        basicAddLiquidity();

        pair.swap(address(this), true, -0.5e18, bytes(""));

        assertEq(pair.compositions(0), Q128 / 2);
    }

    function testSwapNoChangeTick() external {
        basicAddLiquidity();
        pair.swap(address(this), false, 1e18 - 1, bytes(""));

        assertEq(pair.tickCurrent(), 0);
    }
}
