// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PairHelper} from "./helpers/PairHelper.sol";

import {Pairs, MAX_SPREADS} from "src/core/Pairs.sol";
import {Strikes} from "src/core/Strikes.sol";
import {Positions} from "src/core/Positions.sol";
import {mulDiv} from "src/core/math/FullMath.sol";
import {getRatioAtStrike} from "src/core/math/StrikeMath.sol";
import {MAX_STRIKE, MIN_STRIKE, Q128} from "src/core/math/StrikeMath.sol";

contract InitializationTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testInitializeStrikeMaps() external {
        Strikes.Strike memory strike = pair.getStrike(0);
        assertEq(strike.next0To1, MIN_STRIKE);
        assertEq(strike.next1To0, MAX_STRIKE);

        strike = pair.getStrike(MAX_STRIKE);
        assertEq(strike.next0To1, 0);

        strike = pair.getStrike(MIN_STRIKE);
        assertEq(strike.next1To0, 0);
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

    function testLiquidityStrikes() external {
        basicAddLiquidity();

        Strikes.Strike memory strike = pair.getStrike(0);
        assertEq(strike.liquidity[0], 1e18);
    }

    function testLiquidityPosition() external {
        basicAddLiquidity();
        Positions.ILRTAData memory positionInfo = pair.getPosition(address(this), 0, 0);

        assertEq(positionInfo.liquidity, 1e18);
    }

    function testAddLiquidityStrikeMapBasic() external {
        basicAddLiquidity();

        Strikes.Strike memory strike = pair.getStrike(0);
        assertEq(strike.next0To1, MIN_STRIKE);
        assertEq(strike.next1To0, MAX_STRIKE);

        strike = pair.getStrike(MAX_STRIKE);
        assertEq(strike.next0To1, 0);

        strike = pair.getStrike(MIN_STRIKE);
        assertEq(strike.next1To0, 0);
    }

    function testAddLiquidityStrikeMapWithSpread() external {
        pair.addLiquidity(0, 1, 1e18);

        Strikes.Strike memory strike = pair.getStrike(0);
        assertEq(strike.next0To1, -1, "initial strike 0 to 1");
        assertEq(strike.next1To0, 1, "initial strike 1 to 0");

        strike = pair.getStrike(-1);
        assertEq(strike.next0To1, MIN_STRIKE, "0 to 1");

        strike = pair.getStrike(1);
        assertEq(strike.next1To0, MAX_STRIKE, "1 to 0");
    }

    function testGasAddLiquidityFreshStrikes() external {
        pair.addLiquidity(0, 1, 1e18);
    }

    function testGasAddLiquidityHotStrikes() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 1, 1e18);
        vm.resumeGasMetering();

        pair.addLiquidity(0, 1, 1e18);
    }

    function testAddLiquidityBadStrikes() external {
        vm.expectRevert(Pairs.InvalidStrike.selector);
        pair.addLiquidity(type(int24).min, 0, 1e18);

        vm.expectRevert(Pairs.InvalidStrike.selector);
        pair.addLiquidity(type(int24).max, 0, 1e18);
    }

    function testAddLiquidityBadSpread() external {
        vm.expectRevert(Pairs.InvalidSpread.selector);
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

    function testRemoveLiquidityStrikes() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        Strikes.Strike memory strike = pair.getStrike(0);
        assertEq(strike.liquidity[0], 0);
    }

    function testRemoveLiquidityPosition() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        Positions.ILRTAData memory positionInfo = pair.getPosition(address(this), 0, 0);

        assertEq(positionInfo.liquidity, 0);
    }

    function testGasRemoveLiquidityCloseStrikes() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        pair.removeLiquidity(0, 1, 1e18);
    }

    function testGasRemoveLiquidityOpenStrikes() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 1, 2e18);
        vm.resumeGasMetering();

        pair.removeLiquidity(0, 1, 1e18);
    }

    function testRemoveLiquidityStrikeMapBasic() external {
        pair.addLiquidity(0, 0, 1e18);
        pair.removeLiquidity(0, 0, 1e18);
        Strikes.Strike memory strike = pair.getStrike(0);
        assertEq(strike.next0To1, MIN_STRIKE);
        assertEq(strike.next1To0, MAX_STRIKE);

        strike = pair.getStrike(MAX_STRIKE);
        assertEq(strike.next0To1, 0);

        strike = pair.getStrike(MIN_STRIKE);
        assertEq(strike.next1To0, 0);
    }

    function testRemoveLiquidityStrikeMapCurrentStrike() external {
        pair.addLiquidity(1, 0, 1e18);
        pair.swap(false, 1e18 - 1);

        pair.removeLiquidity(1, 0, 1e18);

        Strikes.Strike memory strike = pair.getStrike(0);
        assertEq(strike.next0To1, MIN_STRIKE);
        assertEq(strike.next1To0, 0);

        strike = pair.getStrike(1);
        assertEq(strike.next0To1, 0);
        assertEq(strike.next1To0, MAX_STRIKE);

        strike = pair.getStrike(MAX_STRIKE);
        assertEq(strike.next0To1, 1);

        strike = pair.getStrike(MIN_STRIKE);
        assertEq(strike.next1To0, 1);
    }

    function testRemoveLiquidityBadStrikes() external {
        vm.expectRevert(Pairs.InvalidStrike.selector);
        pair.removeLiquidity(type(int24).min, 0, 1e18);

        vm.expectRevert(Pairs.InvalidStrike.selector);
        pair.removeLiquidity(type(int24).max, 0, 1e18);
    }

    function testRemoveLiquidityBadSpread() external {
        vm.expectRevert(Pairs.InvalidSpread.selector);
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

        (uint128[5] memory compositions, int24 strikeCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], type(uint128).max, 1e9);
        assertEq(strikeCurrent, 0);
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

        (uint128[5] memory compositions, int24 strikeCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], type(uint128).max, 1e9);
        assertEq(strikeCurrent, 0);
        assertEq(offset, 0);
    }

    function testSwapToken0ExactInBasic() external {
        pair.addLiquidity(-1, 0, 1e18);
        // 0->1
        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtStrike(-1));
        (int256 amount0, int256 amount1) = pair.swap(true, int256(amountIn));

        assertApproxEqAbs(amount0, int256(amountIn), precision, "amount0");
        assertApproxEqAbs(amount1, -1e18, precision, "amount1");

        assertApproxEqAbs(token0.balanceOf(address(this)), 0, precision);
        assertApproxEqAbs(token1.balanceOf(address(this)), 1e18, precision);

        assertApproxEqAbs(token0.balanceOf(address(pair)), amountIn, precision);
        assertApproxEqAbs(token1.balanceOf(address(pair)), 0, precision);

        (uint128[5] memory compositions, int24 strikeCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], 0, 1e9);
        assertEq(strikeCurrent, -1);
        assertEq(offset, 1);
    }

    function testSwapToken1ExactOutBasic() external {
        pair.addLiquidity(-1, 0, 1e18);
        // 0->1

        (int256 amount0, int256 amount1) = pair.swap(false, -1e18 + 1);

        uint256 amountIn = mulDiv(1e18, Q128, getRatioAtStrike(-1));

        assertApproxEqAbs(amount0, int256(amountIn), precision, "amount0");
        assertApproxEqAbs(amount1, -1e18, precision, "amount1");

        assertApproxEqAbs(token0.balanceOf(address(this)), 0, precision, "balance0");
        assertApproxEqAbs(token1.balanceOf(address(this)), 1e18, precision, "balance1");

        assertApproxEqAbs(token0.balanceOf(address(pair)), amountIn, precision, "balance0 pair");
        assertApproxEqAbs(token1.balanceOf(address(pair)), 0, precision, "balance1 pair");

        (uint128[5] memory compositions, int24 strikeCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], 0, 1e9);
        assertEq(strikeCurrent, -1);
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

    function testGasSwapSameStrike() external {
        vm.pauseGasMetering();
        basicAddLiquidity();
        vm.resumeGasMetering();

        pair.swap(false, 1e18 - 1);
    }

    function testGasSwapMulti() external {
        vm.pauseGasMetering();
        basicAddLiquidity();
        vm.resumeGasMetering();

        pair.swap(false, 0.2e18);
        pair.swap(false, 0.2e18);
    }

    function testGasSwapTwoStrikes() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 0, 1e18);
        pair.addLiquidity(1, 0, 1e18);
        vm.resumeGasMetering();

        pair.swap(false, 1.5e18);
    }

    function testGasSwapFarStrikes() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 0, 1e18);
        pair.addLiquidity(10, 0, 1e18);
        vm.resumeGasMetering();
        pair.swap(false, 1.5e18);
    }

    function testMultiSpreadDown() external {
        pair.addLiquidity(0, 0, 1e18);
        pair.addLiquidity(0, 1, 1e18);
        pair.swap(false, 1.5e18);

        (uint128[5] memory compositions, int24 strikeCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], type(uint128).max / 2, 1e14, "composition 0");
        assertApproxEqRel(compositions[1], type(uint128).max / 2, 1e14, "composition 1");
        assertEq(strikeCurrent, 1);
        assertEq(offset, -1);
    }

    function testMultiSpreadUp() external {
        pair.addLiquidity(-1, 0, 1e18);
        pair.addLiquidity(-1, 1, 1e18);
        pair.swap(true, 1.5e18);

        (uint128[5] memory compositions, int24 strikeCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], type(uint128).max / 2, 1e15, "composition 0");
        assertApproxEqRel(compositions[1], type(uint128).max / 2, 1e15, "composition 1");
        assertEq(strikeCurrent, -2);
        assertEq(offset, 2);
    }

    function testInitialLiquidity() external {
        pair.addLiquidity(0, 0, 1e18);
        pair.addLiquidity(1, 0, 1e18);

        pair.addLiquidity(0, 1, 1e18);

        pair.swap(false, 1.5e18);
        pair.swap(false, 0.4e18);

        (uint128[5] memory compositions, int24 strikeCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], (uint256(type(uint128).max) * 45) / 100, 1e15, "composition 0");
        assertApproxEqRel(compositions[1], (uint256(type(uint128).max) * 45) / 100, 1e15, "composition 1");
        assertEq(strikeCurrent, 1);
        assertEq(offset, -1);
    }

    function testSpreadComposition() external {
        pair.addLiquidity(-1, 0, 1e18);
        pair.addLiquidity(-2, 0, 1e18);

        pair.addLiquidity(0, 1, 1e18);

        pair.swap(true, 1.5e18);

        (uint128[5] memory compositions, int24 strikeCurrent, int8 offset,) = pair.getPair();

        assertApproxEqRel(compositions[0], type(uint128).max / 2, 1e15, "composition 0");
        assertApproxEqRel(compositions[1], type(uint128).max / 2, 1e15, "composition 1");
        assertEq(strikeCurrent, -2);
        assertEq(offset, 2);
    }
}
