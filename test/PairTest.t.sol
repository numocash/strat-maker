// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PairHelper} from "./helpers/PairHelper.sol";

import {Pairs, MAX_TIERS} from "src/core/Pairs.sol";
import {Ticks} from "src/core/Ticks.sol";
import {Positions} from "src/core/Positions.sol";
import {mulDiv} from "src/core/math/FullMath.sol";
import {getRatioAtTick} from "src/core/math/TickMath.sol";
import {MAX_TICK, MIN_TICK, Q128} from "src/core/math/TickMath.sol";

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

    function testLiquidityTicks() external {
        basicAddLiquidity();

        Ticks.Tick memory tick = pair.getTick(0);
        assertEq(tick.liquidity[0], 1e18);
    }

    function testLiquidityPosition() external {
        basicAddLiquidity();
        Positions.ILRTAData memory positionInfo = pair.getPosition(address(this), 0, 0);

        assertEq(positionInfo.liquidity, 1e18);
    }

    function testAddLiquidityTickMapBasic() external {
        basicAddLiquidity();

        Ticks.Tick memory tick = pair.getTick(0);
        assertEq(tick.next0To1, MIN_TICK);
        assertEq(tick.next1To0, MAX_TICK);

        tick = pair.getTick(MAX_TICK);
        assertEq(tick.next0To1, 0);

        tick = pair.getTick(MIN_TICK);
        assertEq(tick.next1To0, 0);
    }

    function testAddLiquidityTickMapWithTier() external {
        pair.addLiquidity(0, 1, 1e18);

        Ticks.Tick memory tick = pair.getTick(0);
        assertEq(tick.next0To1, -1, "initial tick 0 to 1");
        assertEq(tick.next1To0, 1, "initial tick 1 to 0");

        tick = pair.getTick(-1);
        assertEq(tick.next0To1, MIN_TICK, "0 to 1");

        tick = pair.getTick(1);
        assertEq(tick.next1To0, MAX_TICK, "1 to 0");
    }

    function testAddLiquidityGasFreshTicks() external {
        pair.addLiquidity(0, 1, 1e18);
    }

    function testAddLiquidityGasHotTicks() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 1, 1e18);
        vm.resumeGasMetering();

        pair.addLiquidity(0, 1, 1e18);
    }

    function testAddLiquidityBadTicks() external {
        vm.expectRevert(Pairs.InvalidTick.selector);
        pair.addLiquidity(type(int24).min, 0, 1e18);

        vm.expectRevert(Pairs.InvalidTick.selector);
        pair.addLiquidity(type(int24).max, 0, 1e18);
    }

    function testAddLiquidityBadTier() external {
        vm.expectRevert(Pairs.InvalidTier.selector);
        pair.addLiquidity(0, 10, 1e18);
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

    function testRemoveLiquidityTicks() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        Ticks.Tick memory tick = pair.getTick(0);
        assertEq(tick.liquidity[0], 0);
    }

    function testRemoveLiquidityPosition() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        Positions.ILRTAData memory positionInfo = pair.getPosition(address(this), 0, 0);

        assertEq(positionInfo.liquidity, 0);
    }

    function testRemoveLiquidityGasCloseTicks() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        pair.removeLiquidity(0, 1, 1e18);
    }

    function testRemoveLiquidityGasOpenTicks() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 1, 2e18);
        vm.resumeGasMetering();

        pair.removeLiquidity(0, 1, 1e18);
    }

    function testRemoveLiquidityTickMapBasic() external {
        pair.addLiquidity(0, 0, 1e18);
        pair.removeLiquidity(0, 0, 1e18);
        Ticks.Tick memory tick = pair.getTick(0);
        assertEq(tick.next0To1, MIN_TICK);
        assertEq(tick.next1To0, MAX_TICK);

        tick = pair.getTick(MAX_TICK);
        assertEq(tick.next0To1, 0);

        tick = pair.getTick(MIN_TICK);
        assertEq(tick.next1To0, 0);
    }

    function testRemoveLiquidityTickMapCurrentTick() external {
        pair.addLiquidity(0, 1, 1e18);
        pair.swap(false, 1e18 - 1);

        pair.removeLiquidity(0, 1, 1e18);

        Ticks.Tick memory tick = pair.getTick(0);
        assertEq(tick.next0To1, MIN_TICK);
        assertEq(tick.next1To0, MAX_TICK);

        tick = pair.getTick(MAX_TICK);
        assertEq(tick.next0To1, 0);

        tick = pair.getTick(MIN_TICK);
        assertEq(tick.next1To0, 0);
    }

    function testRemoveLiquidityBadTicks() external {
        vm.expectRevert(Pairs.InvalidTick.selector);
        pair.removeLiquidity(type(int24).min, 0, 1e18);

        vm.expectRevert(Pairs.InvalidTick.selector);
        pair.removeLiquidity(type(int24).max, 0, 1e18);
    }

    function testRemoveLiquidityBadTier() external {
        vm.expectRevert(Pairs.InvalidTier.selector);
        pair.removeLiquidity(0, 10, 1e18);
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
        (int256 amount0, int256 amount1) = pair.swap(false, 1e18 - 1);

        assertApproxEqRel(amount0, -1e18 + 1, precision);
        assertApproxEqRel(amount1, 1e18 - 1, precision);

        assertApproxEqRel(token0.balanceOf(address(this)), 1e18, precision);
        assertApproxEqRel(token1.balanceOf(address(this)), 0, precision);

        assertApproxEqRel(token0.balanceOf(address(pair)), 0, precision);
        assertApproxEqRel(token1.balanceOf(address(pair)), 1e18, precision);

        (uint128[5] memory compositions, int24 tickCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], type(uint128).max, 1e9);
        assertEq(tickCurrent, 0);
        assertEq(offset, 0);
    }

    function testSwapToken0ExactOutBasic() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(true, -1e18 + 1);

        assertApproxEqRel(amount0, -1e18, precision);
        assertApproxEqRel(amount1, 1e18, precision);

        assertApproxEqRel(token0.balanceOf(address(this)), 1e18, precision);
        assertApproxEqRel(token1.balanceOf(address(this)), 0, precision);

        assertApproxEqRel(token0.balanceOf(address(pair)), 0, precision);
        assertApproxEqRel(token1.balanceOf(address(pair)), 1e18, precision);

        (uint128[5] memory compositions, int24 tickCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], type(uint128).max, 1e9);
        assertEq(tickCurrent, 0);
        assertEq(offset, 0);
    }

    function testSwapToken0ExactInBasic() external {
        pair.addLiquidity(-1, 0, 1e18);
        // 0->1
        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));
        (int256 amount0, int256 amount1) = pair.swap(true, int256(amountIn));

        assertApproxEqAbs(amount0, int256(amountIn), precision, "amount0");
        assertApproxEqAbs(amount1, -1e18, precision, "amount1");

        assertApproxEqAbs(token0.balanceOf(address(this)), 0, precision);
        assertApproxEqAbs(token1.balanceOf(address(this)), 1e18, precision);

        assertApproxEqAbs(token0.balanceOf(address(pair)), amountIn, precision);
        assertApproxEqAbs(token1.balanceOf(address(pair)), 0, precision);

        (uint128[5] memory compositions, int24 tickCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], 0, 1e9);
        assertEq(tickCurrent, -1);
        assertEq(offset, 1);
    }

    function testSwapToken1ExactOutBasic() external {
        pair.addLiquidity(-1, 0, 1e18);
        // 0->1

        (int256 amount0, int256 amount1) = pair.swap(false, -1e18 + 1);

        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));

        assertApproxEqAbs(amount0, int256(amountIn), precision, "amount0");
        assertApproxEqAbs(amount1, -1e18, precision, "amount1");

        assertApproxEqAbs(token0.balanceOf(address(this)), 0, precision, "balance0");
        assertApproxEqAbs(token1.balanceOf(address(this)), 1e18, precision, "balance1");

        assertApproxEqAbs(token0.balanceOf(address(pair)), amountIn, precision, "balance0 pair");
        assertApproxEqAbs(token1.balanceOf(address(pair)), 0, precision, "balance1 pair");

        (uint128[5] memory compositions, int24 tickCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], 0, 1e9);
        assertEq(tickCurrent, -1);
        assertEq(offset, 1);
    }

    function testSwapPartial0To1() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(false, 0.5e18);
        assertApproxEqAbs(amount0, -0.5e18, precision);
        assertApproxEqAbs(amount1, 0.5e18, precision);

        (uint128[5] memory compositions,,,) = pair.getPair();

        assertApproxEqRel(compositions[0], Q128 / 2, 1e9);
    }

    function testSwapPartial1To0() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(true, -0.5e18);

        assertApproxEqAbs(amount0, -0.5e18, precision);
        assertApproxEqAbs(amount1, 0.5e18, precision);

        (uint128[5] memory compositions,,,) = pair.getPair();

        assertApproxEqRel(compositions[0], Q128 / 2, 1e9);
    }

    function testSwapStartPartial0To1() external {}

    function testSwapStartPartial1To0() external {}

    function testSwapGasSameTick() external {
        vm.pauseGasMetering();
        basicAddLiquidity();
        vm.resumeGasMetering();

        pair.swap(false, 1e18 - 1);
    }

    function testSwapGasMulti() external {
        vm.pauseGasMetering();
        basicAddLiquidity();
        vm.resumeGasMetering();

        pair.swap(false, 0.2e18);
        pair.swap(false, 0.2e18);
    }

    function testSwapGasTwoTicks() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 0, 1e18);
        pair.addLiquidity(1, 0, 1e18);
        vm.resumeGasMetering();

        pair.swap(false, 1.5e18);
    }

    function testSwapGasFarTicks() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 0, 1e18);
        pair.addLiquidity(10, 0, 1e18);
        vm.resumeGasMetering();
        pair.swap(false, 1.5e18);
    }

    function testMultiTierDown() external {
        pair.addLiquidity(0, 0, 1e18);
        pair.addLiquidity(0, 1, 1e18);
        pair.swap(false, 1.5e18);

        (uint128[5] memory compositions, int24 tickCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], type(uint128).max / 2, 1e14, "composition 0");
        assertApproxEqRel(compositions[1], type(uint128).max / 2, 1e14, "composition 1");
        assertEq(tickCurrent, 1);
        assertEq(offset, -1);
    }

    function testMultiTierUp() external {
        pair.addLiquidity(-1, 0, 1e18);
        pair.addLiquidity(-1, 1, 1e18);
        pair.swap(true, 1.5e18);

        (uint128[5] memory compositions, int24 tickCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], type(uint128).max / 2, 1e15, "composition 0");
        assertApproxEqRel(compositions[1], type(uint128).max / 2, 1e15, "composition 1");
        assertEq(tickCurrent, -2);
        assertEq(offset, 2);
    }

    function testInitialLiquidity() external {
        pair.addLiquidity(0, 0, 1e18);
        pair.addLiquidity(1, 0, 1e18);

        pair.addLiquidity(0, 1, 1e18);

        pair.swap(false, 1.5e18);
        pair.swap(false, 0.4e18);

        (uint128[5] memory compositions, int24 tickCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], (uint256(type(uint128).max) * 45) / 100, 1e15, "composition 0");
        assertApproxEqRel(compositions[1], (uint256(type(uint128).max) * 45) / 100, 1e15, "composition 1");
        assertEq(tickCurrent, 1);
        assertEq(offset, -1);
    }

    function testTierComposition() external {
        pair.addLiquidity(-1, 0, 1e18);
        pair.addLiquidity(-2, 0, 1e18);

        pair.addLiquidity(0, 1, 1e18);

        pair.swap(true, 1.5e18);

        (uint128[5] memory compositions, int24 tickCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], type(uint128).max / 2, 1e15, "composition 0");
        assertApproxEqRel(compositions[1], type(uint128).max / 2, 1e15, "composition 1");
        assertEq(tickCurrent, -2);
        assertEq(offset, 2);
    }
}
