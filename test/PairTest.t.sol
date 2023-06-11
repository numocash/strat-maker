// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PairHelper} from "./helpers/PairHelper.sol";

import {Pair} from "src/core/Pair.sol";
import {Ticks} from "src/core/Ticks.sol";
import {mulDiv} from "src/core/FullMath.sol";
import {getRatioAtTick, MAX_TICK, MIN_TICK} from "src/core/TickMath.sol";
import {Q128} from "src/core/TickMath.sol";

contract InitializeTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testInitializeTickMaps() external {
        (int24 next0To1, int24 next1To0,,) = pair.ticks(0);
        assertEq(next0To1, MIN_TICK);
        assertEq(next1To0, MAX_TICK);

        (next0To1,,,) = pair.ticks(MAX_TICK);
        assertEq(next0To1, 0);

        (, next1To0,,) = pair.ticks(MIN_TICK);
        assertEq(next1To0, 0);
    }
}

contract AddLiquidityTest is Test, PairHelper {
    uint256 precision = 1e9;

    function setUp() external {
        _setUp();
    }

    function testAddLiquidityReturnAmounts() external {
        (uint256 amount0, uint256 amount1) = basicAddLiquidity();

        assertApproxEqRel(amount0, 1e18, precision);
        assertEq(amount1, 0);
    }

    function testLiquidityTokenBalances() external {
        basicAddLiquidity();

        assertApproxEqRel(token0.balanceOf(address(this)), 0, precision);
        assertEq(token1.balanceOf(address(this)), 0);

        assertApproxEqRel(token0.balanceOf(address(pair)), 1e18, precision);
        assertEq(token1.balanceOf(address(pair)), 0);
    }

    // function testLiquidityTicks() external {
    //     basicAddLiquidity();

    //     // Ticks.getLiquidity(pair.ticks(0), 0);
    //     // (uint256 liquidity) = pair.ticks(0)(keccak256(abi.encodePacked(uint8(0), int24(0))));
    //     // assertEq(liquidity, 1e18);
    // }

    function testLiquidityPosition() external {
        basicAddLiquidity();
        (uint256 liquidity) = pair.positions(keccak256(abi.encodePacked(address(this), uint8(0), int24(0))));

        assertEq(liquidity, 1e18);
    }

    function testAddLiquidityTickMapBasic() external {
        pair.addLiquidity(address(this), 0, 0, 1e18, bytes(""));

        (int24 next0To1, int24 next1To0,,) = pair.ticks(0);
        assertEq(next0To1, MIN_TICK);
        assertEq(next1To0, MAX_TICK);

        (next0To1,,,) = pair.ticks(MAX_TICK);
        assertEq(next0To1, 0);

        (, next1To0,,) = pair.ticks(MIN_TICK);
        assertEq(next1To0, 0);
    }

    function testAddLiquidityTickMapWithTier() external {
        pair.addLiquidity(address(this), 1, 0, 1e18, bytes(""));

        (int24 next0To1, int24 next1To0,,) = pair.ticks(0);
        assertEq(next0To1, -1, "initial tick 0 to 1");
        assertEq(next1To0, 1, "initial tick 1 to 0");

        (next0To1,,,) = pair.ticks(-1);
        assertEq(next0To1, MIN_TICK, "0 to 1");

        (, next1To0,,) = pair.ticks(1);
        assertEq(next1To0, MAX_TICK, "1 to 0");
    }

    function testAddLiquidityGasFreshTicks() external {
        pair.addLiquidity(address(this), 1, 0, 1e18, bytes(""));
    }

    function testAddLiquidityGasHotTicks() external {
        vm.pauseGasMetering();
        pair.addLiquidity(address(this), 1, 0, 1e18, bytes(""));
        vm.resumeGasMetering();

        pair.addLiquidity(address(this), 1, 0, 1e18, bytes(""));
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
    uint256 precision = 1e9;

    function setUp() external {
        _setUp();
    }

    function testRemoveLiquidityReturnAmounts() external {
        basicAddLiquidity();
        (uint256 amount0, uint256 amount1) = basicRemoveLiquidity();

        assertApproxEqRel(amount0, 1e18, precision);
        assertEq(amount1, 0);
    }

    function testRemoveLiquidityTokenAmounts() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        assertApproxEqRel(token0.balanceOf(address(this)), 1e18, precision);
        assertEq(token1.balanceOf(address(this)), 0);

        assertApproxEqRel(token0.balanceOf(address(pair)), 0, precision);
        assertEq(token1.balanceOf(address(pair)), 0);
    }

    // function testRemoveLiquidityTicks() external {
    //     basicAddLiquidity();
    //     basicRemoveLiquidity();
    //     (uint256 liquidity) = pair.ticks(keccak256(abi.encodePacked(uint8(0), int24(0))));
    //     assertEq(liquidity, 0);
    // }

    function testRemoveLiquidityPosition() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        (uint256 liquidity) = pair.positions(keccak256(abi.encodePacked(address(this), uint8(0), int24(0))));

        assertEq(liquidity, 0);
    }

    function testRemoveLiquidityGasCloseTicks() external {
        vm.pauseGasMetering();
        pair.addLiquidity(address(this), 1, 0, 1e18, bytes(""));
        vm.resumeGasMetering();

        pair.removeLiquidity(address(this), 1, 0, 1e18);
    }

    function testRemoveLiquidityGasOpenTicks() external {
        vm.pauseGasMetering();
        pair.addLiquidity(address(this), 1, 0, 1e18, bytes(""));
        pair.addLiquidity(address(this), 1, 0, 1e18, bytes(""));
        vm.resumeGasMetering();

        pair.removeLiquidity(address(this), 1, 0, 1e18);
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
    uint256 precision = 10;

    function setUp() external {
        _setUp();
    }

    function testSwapToken1ExactInBasic() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), false, 1e18 - 1, bytes(""));

        assertApproxEqRel(amount0, -1e18 + 1, precision);
        assertApproxEqRel(amount1, 1e18 - 1, precision);

        assertApproxEqRel(token0.balanceOf(address(this)), 1e18, precision);
        assertApproxEqRel(token1.balanceOf(address(this)), 0, precision);

        assertApproxEqRel(token0.balanceOf(address(pair)), 0, precision);
        assertApproxEqRel(token1.balanceOf(address(pair)), 1e18, precision);

        assertApproxEqRel(pair.compositions(0), type(uint128).max, precision);
        assertEq(pair.tickCurrent(), 0);
        assertEq(pair.offset(), 0);
    }

    function testSwapToken0ExactOutBasic() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), true, -1e18 + 1, bytes(""));

        assertApproxEqRel(amount0, -1e18, precision);
        assertApproxEqRel(amount1, 1e18, precision);

        assertApproxEqRel(token0.balanceOf(address(this)), 1e18, precision);
        assertApproxEqRel(token1.balanceOf(address(this)), 0, precision);

        assertApproxEqRel(token0.balanceOf(address(pair)), 0, precision);
        assertApproxEqRel(token1.balanceOf(address(pair)), 1e18, precision);

        assertApproxEqRel(pair.compositions(0), type(uint128).max, precision);
        assertEq(pair.tickCurrent(), 0);
        assertEq(pair.offset(), 0);
    }

    function testSwapToken0ExactInBasic() external {
        pair.addLiquidity(address(this), 0, -1, 1e18, bytes(""));
        // 0->1
        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));
        (int256 amount0, int256 amount1) = pair.swap(address(this), true, int256(amountIn), bytes(""));

        assertApproxEqAbs(amount0, int256(amountIn), precision, "amount0");
        assertApproxEqAbs(amount1, -1e18, precision, "amount1");

        assertApproxEqAbs(token0.balanceOf(address(this)), 0, precision);
        assertApproxEqAbs(token1.balanceOf(address(this)), 1e18, precision);

        assertApproxEqAbs(token0.balanceOf(address(pair)), amountIn, precision);
        assertApproxEqAbs(token1.balanceOf(address(pair)), 0, precision);

        assertApproxEqRel(pair.compositions(0), 0, 1e9, "composition");
        assertEq(pair.tickCurrent(), -1, "tickCurrent");
        assertEq(pair.offset(), 1, "offset");
    }

    function testSwapToken1ExactOutBasic() external {
        pair.addLiquidity(address(this), 0, -1, 1e18, bytes(""));
        // 0->1
        (int256 amount0, int256 amount1) = pair.swap(address(this), false, -1e18 + 1, bytes(""));

        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));

        assertApproxEqAbs(amount0, int256(amountIn), precision, "amount0");
        assertApproxEqAbs(amount1, -1e18, precision, "amount1");

        assertApproxEqAbs(token0.balanceOf(address(this)), 0, precision, "balance0");
        assertApproxEqAbs(token1.balanceOf(address(this)), 1e18, precision, "balance1");

        assertApproxEqAbs(token0.balanceOf(address(pair)), amountIn, precision, "balance0 pair");
        assertApproxEqAbs(token1.balanceOf(address(pair)), 0, precision, "balance1 pair");

        assertApproxEqRel(pair.compositions(0), 0, 1e9, "composition");
        assertEq(pair.tickCurrent(), -1, "tickCurrent");
        assertEq(pair.offset(), 1, "offset");
    }

    function testSwapPartial0To1() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), false, 0.5e18, bytes(""));

        assertApproxEqAbs(amount0, -0.5e18, precision);
        assertApproxEqAbs(amount1, 0.5e18, precision);

        assertApproxEqRel(pair.compositions(0), Q128 / 2, 1e9, "composition");
    }

    function testSwapPartial1To0() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(address(this), true, -0.5e18, bytes(""));

        assertApproxEqAbs(amount0, -0.5e18, precision);
        assertApproxEqAbs(amount1, 0.5e18, precision);

        assertApproxEqRel(pair.compositions(0), Q128 / 2, 1e9);
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

    function testSwapGasFarTicks() external {
        vm.pauseGasMetering();
        pair.addLiquidity(address(this), 0, 0, 1e18, bytes(""));
        pair.addLiquidity(address(this), 0, 10, 1e18, bytes(""));
        vm.resumeGasMetering();
        pair.swap(address(this), false, 1.5e18, bytes(""));
    }

    function testMultiTierDown() external {
        pair.addLiquidity(address(this), 0, 0, 1e18, bytes(""));
        pair.addLiquidity(address(this), 1, 0, 1e18, bytes(""));

        pair.swap(address(this), false, 1.5e18, bytes(""));

        assertApproxEqRel(pair.compositions(0), type(uint128).max / 2, 1e14, "composition 0");
        assertApproxEqRel(pair.compositions(1), type(uint128).max / 2, 1e14, "composition 1");
        assertEq(pair.tickCurrent(), 1);
        assertEq(pair.offset(), -1);
    }

    function testMultiTierUp() external {
        pair.addLiquidity(address(this), 0, -1, 1e18, bytes(""));
        pair.addLiquidity(address(this), 1, -1, 1e18, bytes(""));

        pair.swap(address(this), true, 1.5e18, bytes(""));

        assertApproxEqRel(pair.compositions(0), type(uint128).max / 2, 1e15, "composition 0");
        assertApproxEqRel(pair.compositions(1), type(uint128).max / 2, 1e15, "composition 1");
        assertEq(pair.tickCurrent(), -2);
        assertEq(pair.offset(), 2);
    }

    function testInitialLiquidity() external {
        pair.addLiquidity(address(this), 0, 0, 1e18, bytes(""));
        pair.addLiquidity(address(this), 0, 1, 1e18, bytes(""));

        pair.addLiquidity(address(this), 1, 0, 1e18, bytes(""));

        pair.swap(address(this), false, 1.5e18, bytes(""));
        pair.swap(address(this), false, 0.4e18, bytes(""));

        assertApproxEqRel(pair.compositions(0), (uint256(type(uint128).max) * 45) / 100, 1e15, "composition 0");
        assertApproxEqRel(pair.compositions(1), (uint256(type(uint128).max) * 45) / 100, 1e15, "composition 1");
        assertEq(pair.tickCurrent(), 1);
        assertEq(pair.offset(), -1);
    }

    function testTierComposition() external {
        pair.addLiquidity(address(this), 0, -1, 1e18, bytes(""));
        pair.addLiquidity(address(this), 0, -2, 1e18, bytes(""));

        pair.addLiquidity(address(this), 1, 0, 1e18, bytes(""));

        pair.swap(address(this), true, 1.5e18, bytes(""));

        assertApproxEqRel(pair.compositions(0), type(uint128).max / 2, 1e15, "composition 0");
        assertApproxEqRel(pair.compositions(1), type(uint128).max / 2, 1e15, "composition 1");
        assertEq(pair.tickCurrent(), -2);
        assertEq(pair.offset(), 2);
    }
}
