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

    function testSwapToken1ExactInBasic() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), false, 1e18 - 1, bytes(""));

        assertEq(amount0, -1e18 + 1);
        assertEq(amount1, 1e18 - 1);

        assertEq(token0.balanceOf(address(this)), 1e18);
        assertEq(token1.balanceOf(address(this)), 0);

        assertEq(token0.balanceOf(address(pair)), 0);
        assertEq(token1.balanceOf(address(pair)), 1e18);

        assertEq(pair.compositions(0), type(uint128).max);
        assertEq(pair.tickCurrent(), 0);
        assertEq(pair.maxOffset(), 0);
    }

    function testSwapToken0ExactOutBasic() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), true, -1e18 + 1, bytes(""));

        assertEq(amount0, -1e18);
        assertEq(amount1, 1e18);

        assertEq(token0.balanceOf(address(this)), 1e18);
        assertEq(token1.balanceOf(address(this)), 0);

        assertEq(token0.balanceOf(address(pair)), 0);
        assertEq(token1.balanceOf(address(pair)), 1e18);

        assertEq(pair.compositions(0), type(uint128).max);
        assertEq(pair.tickCurrent(), 0);
        assertEq(pair.maxOffset(), 0);
    }

    function testSwapToken0ExactInBasic() external {
        pair.addLiquidity(address(this), 0, -1, 1e18, bytes(""));
        // 0->1
        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));
        (int256 amount0, int256 amount1) = pair.swap(address(this), true, int256(amountIn), bytes(""));

        assertEq(amount0, int256(amountIn), "amount0");
        assertEq(amount1, 1e18, "amount1");

        assertEq(token0.balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), 1e18);

        assertEq(token0.balanceOf(address(pair)), amountIn);
        assertEq(token1.balanceOf(address(pair)), 0);

        assertEq(pair.compositions(0), 0, "composition");
        assertEq(pair.tickCurrent(), -1, "tickCurrent");
        assertEq(pair.maxOffset(), 1, "maxOffset");
    }

    function testSwapToken1ExactOutBasic() external {
        pair.addLiquidity(address(this), 0, -1, 1e18, bytes(""));
        // 0->1
        (int256 amount0, int256 amount1) = pair.swap(address(this), false, -1e18 + 1, bytes(""));

        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));

        assertEq(amount0, int256(amountIn), "amount0");
        assertEq(amount1, 1e18, "amount1");

        assertEq(token0.balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), 1e18);

        assertEq(token0.balanceOf(address(pair)), amountIn);
        assertEq(token1.balanceOf(address(pair)), 0);

        assertEq(pair.compositions(0), 0, "composition");
        assertEq(pair.tickCurrent(), -1, "tickCurrent");
        assertEq(pair.maxOffset(), 1, "maxOffset");
    }

    function testSwapPartial0To1() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), false, 0.5e18, bytes(""));

        assertEq(amount0, -0.5e18);
        assertEq(amount1, 0.5e18);

        assertEq(pair.compositions(0), Q128 / 2, "composition");
    }

    function testSwapPartial1To0() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), true, -0.5e18, bytes(""));

        assertEq(amount0, -0.5e18);
        assertEq(amount1, 0.5e18);

        assertEq(pair.compositions(0), Q128 / 2);
    }

    function testSwapStartPartial0To1() external {}

    function testSwapStartPartial1To0() external {}

    function testSwapGasSameTick() external {
        vm.pauseGasMetering();
        basicAddLiquidity();
        vm.resumeGasMetering();

        pair.swap(address(this), false, 1e18 - 1, bytes(""));
    }

    function testSwapGasMulti() external {
        vm.pauseGasMetering();
        basicAddLiquidity();
        vm.resumeGasMetering();

        pair.swap(address(this), false, 0.2e18, bytes(""));
        pair.swap(address(this), false, 0.2e18, bytes(""));
    }

    function testSwapGasTwoTicks() external {
        vm.pauseGasMetering();
        pair.addLiquidity(address(this), 0, 0, 1e18, bytes(""));
        pair.addLiquidity(address(this), 0, 1, 1e18, bytes(""));
        vm.resumeGasMetering();
        pair.swap(address(this), false, 1.5e18, bytes(""));
    }

    // test multi tiers and specifically maxOffset
}
