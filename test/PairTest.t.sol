// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PairHelper} from "./helpers/PairHelper.sol";

import {Pairs} from "src/core/Pairs.sol";
import {Engine} from "src/core/Engine.sol";
import {Tick} from "src/core/Tick.sol";
import {Position} from "src/core/Position.sol";
import {mulDiv} from "src/core/math/FullMath.sol";
import {getRatioAtTick} from "src/core/math/TickMath.sol";
import {Q128} from "src/core/math/TickMath.sol";

contract InitializationTest is Test {
    Engine internal engine;

    function setUp() external {
        engine = new Engine();
    }

    function testInitialize() external {
        engine.createPair(address(1), address(2), 5);

        (, int24 tickCurrent,, uint8 lock) = engine.getPair(address(1), address(2));

        assertEq(tickCurrent, 5);
        assertEq(lock, 1);
    }

    function testInitializeDouble() external {
        engine.createPair(address(1), address(2), 5);
        vm.expectRevert(Pairs.Initialized.selector);
        engine.createPair(address(1), address(2), 5);
    }

    function testInitializeBadTick() external {
        vm.expectRevert(Pairs.InvalidTick.selector);
        engine.createPair(address(1), address(2), type(int24).max);
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

        assertApproxEqRel(token0.balanceOf(address(engine)), 1e18, precision);
        assertEq(token1.balanceOf(address(engine)), 0);
    }

    function testLiquidityTicks() external {
        basicAddLiquidity();

        Tick.Info memory tickInfo = engine.getTick(address(token0), address(token1), 0, 0);
        assertEq(tickInfo.liquidity, 1e18);
    }

    function testLiquidityPosition() external {
        basicAddLiquidity();
        Position.Info memory positionInfo = engine.getPosition(address(token0), address(token1), address(this), 0, 0);

        assertEq(positionInfo.liquidity, 1e18);
    }

    function testAddLiquidityBadTick() external {
        vm.expectRevert(Pairs.InvalidTick.selector);
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: type(int24).min,
                liquidity: 1e18,
                data: bytes("")
            })
        );

        vm.expectRevert(Pairs.InvalidTick.selector);
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: type(int24).max,
                liquidity: 1e18,
                data: bytes("")
            })
        );
    }

    function testAddLiquidityBadTier() external {
        vm.expectRevert(Pairs.InvalidTier.selector);
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 10,
                tick: 0,
                liquidity: 1e18,
                data: bytes("")
            })
        );
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

        assertApproxEqRel(token0.balanceOf(address(engine)), 0, precision);
        assertEq(token1.balanceOf(address(engine)), 0);
    }

    function testRemoveLiquidityTicks() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        Tick.Info memory tickInfo = engine.getTick(address(token0), address(token1), 0, 0);
        assertEq(tickInfo.liquidity, 0);
    }

    function testRemoveLiquidityPosition() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        Position.Info memory positionInfo = engine.getPosition(address(token0), address(token1), address(this), 0, 0);

        assertEq(positionInfo.liquidity, 0);
    }

    function testRemoveLiquidityBadTick() external {
        vm.expectRevert(Pairs.InvalidTick.selector);
        engine.removeLiquidity(
            Engine.RemoveLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: type(int24).min,
                liquidity: 1e18
            })
        );

        vm.expectRevert(Pairs.InvalidTick.selector);
        engine.removeLiquidity(
            Engine.RemoveLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: type(int24).max,
                liquidity: 1e18
            })
        );
    }

    function testRemoveLiquidityBadTier() external {
        vm.expectRevert(Pairs.InvalidTier.selector);
        engine.removeLiquidity(
            Engine.RemoveLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 10,
                tick: 0,
                liquidity: 1e18
            })
        );
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
        (int256 amount0, int256 amount1) = engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: false,
                amountDesired: 1e18 - 1,
                data: bytes("")
            })
        );

        assertApproxEqRel(amount0, -1e18 + 1, precision);
        assertApproxEqRel(amount1, 1e18 - 1, precision);

        assertApproxEqRel(token0.balanceOf(address(this)), 1e18, precision);
        assertApproxEqRel(token1.balanceOf(address(this)), 0, precision);

        assertApproxEqRel(token0.balanceOf(address(engine)), 0, precision);
        assertApproxEqRel(token1.balanceOf(address(engine)), 1e18, precision);

        (uint128[5] memory compositions, int24 tickCurrent, int8 maxOffset,) =
            engine.getPair(address(token0), address(token1));

        assertApproxEqRel(compositions[0], type(uint128).max, 1e9);
        assertEq(tickCurrent, 0);
        assertEq(maxOffset, 0);
    }

    function testSwapToken0ExactOutBasic() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: true,
                amountDesired: -1e18 + 1,
                data: bytes("")
            })
        );

        assertApproxEqRel(amount0, -1e18, precision);
        assertApproxEqRel(amount1, 1e18, precision);

        assertApproxEqRel(token0.balanceOf(address(this)), 1e18, precision);
        assertApproxEqRel(token1.balanceOf(address(this)), 0, precision);

        assertApproxEqRel(token0.balanceOf(address(engine)), 0, precision);
        assertApproxEqRel(token1.balanceOf(address(engine)), 1e18, precision);

        (uint128[5] memory compositions, int24 tickCurrent, int8 maxOffset,) =
            engine.getPair(address(token0), address(token1));

        assertApproxEqRel(compositions[0], type(uint128).max, 1e9);
        assertEq(tickCurrent, 0);
        assertEq(maxOffset, 0);
    }

    function testSwapToken0ExactInBasic() external {
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: -1,
                liquidity: 1e18,
                data: bytes("")
            })
        );
        // 0->1
        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));
        (int256 amount0, int256 amount1) = engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: true,
                amountDesired: int256(amountIn),
                data: bytes("")
            })
        );

        assertApproxEqAbs(amount0, int256(amountIn), precision, "amount0");
        assertApproxEqAbs(amount1, -1e18, precision, "amount1");

        assertApproxEqAbs(token0.balanceOf(address(this)), 0, precision);
        assertApproxEqAbs(token1.balanceOf(address(this)), 1e18, precision);

        assertApproxEqAbs(token0.balanceOf(address(engine)), amountIn, precision);
        assertApproxEqAbs(token1.balanceOf(address(engine)), 0, precision);

        (uint128[5] memory compositions, int24 tickCurrent, int8 maxOffset,) =
            engine.getPair(address(token0), address(token1));

        assertApproxEqRel(compositions[0], 0, 1e9);
        assertEq(tickCurrent, -1);
        assertEq(maxOffset, 1);
    }

    function testSwapToken1ExactOutBasic() external {
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: -1,
                liquidity: 1e18,
                data: bytes("")
            })
        );
        // 0->1

        (int256 amount0, int256 amount1) = engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: false,
                amountDesired: -1e18 + 1,
                data: bytes("")
            })
        );

        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtTick(-1));

        assertApproxEqAbs(amount0, int256(amountIn), precision, "amount0");
        assertApproxEqAbs(amount1, -1e18, precision, "amount1");

        assertApproxEqAbs(token0.balanceOf(address(this)), 0, precision, "balance0");
        assertApproxEqAbs(token1.balanceOf(address(this)), 1e18, precision, "balance1");

        assertApproxEqAbs(token0.balanceOf(address(engine)), amountIn, precision, "balance0 pair");
        assertApproxEqAbs(token1.balanceOf(address(engine)), 0, precision, "balance1 pair");

        (uint128[5] memory compositions, int24 tickCurrent, int8 maxOffset,) =
            engine.getPair(address(token0), address(token1));

        assertApproxEqRel(compositions[0], 0, 1e9);
        assertEq(tickCurrent, -1);
        assertEq(maxOffset, 1);
    }

    function testSwapPartial0To1() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: false,
                amountDesired: 0.5e18,
                data: bytes("")
            })
        );
        assertApproxEqAbs(amount0, -0.5e18, precision);
        assertApproxEqAbs(amount1, 0.5e18, precision);

        (uint128[5] memory compositions,,,) = engine.getPair(address(token0), address(token1));

        assertApproxEqRel(compositions[0], Q128 / 2, 1e9);
    }

    function testSwapPartial1To0() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: true,
                amountDesired: -0.5e18,
                data: bytes("")
            })
        );

        assertApproxEqAbs(amount0, -0.5e18, precision);
        assertApproxEqAbs(amount1, 0.5e18, precision);

        (uint128[5] memory compositions,,,) = engine.getPair(address(token0), address(token1));

        assertApproxEqRel(compositions[0], Q128 / 2, 1e9);
    }

    function testSwapStartPartial0To1() external {}

    function testSwapStartPartial1To0() external {}

    function testSwapGasSameTick() external {
        vm.pauseGasMetering();
        basicAddLiquidity();
        vm.resumeGasMetering();

        engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: false,
                amountDesired: 1e18 - 1,
                data: bytes("")
            })
        );
    }

    function testSwapGasMulti() external {
        vm.pauseGasMetering();
        basicAddLiquidity();
        vm.resumeGasMetering();

        engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: false,
                amountDesired: 0.2e18,
                data: bytes("")
            })
        );
        engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: false,
                amountDesired: 0.2e18,
                data: bytes("")
            })
        );
    }

    function testSwapGasTwoTicks() external {
        vm.pauseGasMetering();
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: 0,
                liquidity: 1e18,
                data: bytes("")
            })
        );
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: 1,
                liquidity: 1e18,
                data: bytes("")
            })
        );
        vm.resumeGasMetering();

        engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: false,
                amountDesired: 1.5e18,
                data: bytes("")
            })
        );
    }

    function testMultiTierDown() external {
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: 0,
                liquidity: 1e18,
                data: bytes("")
            })
        );
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 1,
                tick: 0,
                liquidity: 1e18,
                data: bytes("")
            })
        );
        engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: false,
                amountDesired: 1.5e18,
                data: bytes("")
            })
        );

        (uint128[5] memory compositions, int24 tickCurrent, int8 maxOffset,) =
            engine.getPair(address(token0), address(token1));

        assertApproxEqRel(compositions[0], type(uint128).max / 2, 1e14, "composition 0");
        assertApproxEqRel(compositions[1], type(uint128).max / 2, 1e14, "composition 1");
        assertEq(tickCurrent, 1);
        assertEq(maxOffset, -1);
    }

    function testMultiTierUp() external {
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: -1,
                liquidity: 1e18,
                data: bytes("")
            })
        );
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 1,
                tick: -1,
                liquidity: 1e18,
                data: bytes("")
            })
        );
        engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: true,
                amountDesired: 1.5e18,
                data: bytes("")
            })
        );

        (uint128[5] memory compositions, int24 tickCurrent, int8 maxOffset,) =
            engine.getPair(address(token0), address(token1));

        assertApproxEqRel(compositions[0], type(uint128).max / 2, 1e15, "composition 0");
        assertApproxEqRel(compositions[1], type(uint128).max / 2, 1e15, "composition 1");
        assertEq(tickCurrent, -2);
        assertEq(maxOffset, 2);
    }

    function testInitialLiquidity() external {
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: 0,
                liquidity: 1e18,
                data: bytes("")
            })
        );
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: 1,
                liquidity: 1e18,
                data: bytes("")
            })
        );

        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 1,
                tick: 0,
                liquidity: 1e18,
                data: bytes("")
            })
        );

        engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: false,
                amountDesired: 1.5e18,
                data: bytes("")
            })
        );
        engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: false,
                amountDesired: 0.4e18,
                data: bytes("")
            })
        );

        (uint128[5] memory compositions, int24 tickCurrent, int8 maxOffset,) =
            engine.getPair(address(token0), address(token1));

        assertApproxEqRel(compositions[0], (uint256(type(uint128).max) * 45) / 100, 1e15, "composition 0");
        assertApproxEqRel(compositions[1], (uint256(type(uint128).max) * 45) / 100, 1e15, "composition 1");
        assertEq(tickCurrent, 1);
        assertEq(maxOffset, -1);
    }

    function testTierComposition() external {
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: -1,
                liquidity: 1e18,
                data: bytes("")
            })
        );
        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 0,
                tick: -2,
                liquidity: 1e18,
                data: bytes("")
            })
        );

        engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tierID: 1,
                tick: 0,
                liquidity: 1e18,
                data: bytes("")
            })
        );

        engine.swap(
            Engine.SwapParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                isToken0: true,
                amountDesired: 1.5e18,
                data: bytes("")
            })
        );

        (uint128[5] memory compositions, int24 tickCurrent, int8 maxOffset,) =
            engine.getPair(address(token0), address(token1));

        assertApproxEqRel(compositions[0], type(uint128).max / 2, 1e15, "composition 0");
        assertApproxEqRel(compositions[1], type(uint128).max / 2, 1e15, "composition 1");
        assertEq(tickCurrent, -2);
        assertEq(maxOffset, 2);
    }
}
