// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PairHelper} from "./helpers/PairHelper.sol";

import {Pairs, NUM_SPREADS} from "src/core/Pairs.sol";
import {Engine} from "src/core/Engine.sol";
import {mulDiv, mulDivRoundingUp} from "src/core/math/FullMath.sol";
import {getRatioAtStrike} from "src/core/math/StrikeMath.sol";
import {MAX_STRIKE, MIN_STRIKE, Q128} from "src/core/math/StrikeMath.sol";

contract InitializationTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testInitializeStrikeMaps() external {
        Pairs.Strike memory strike = pair.getStrike(0);
        assertEq(strike.next0To1, MIN_STRIKE);
        assertEq(strike.next1To0, MAX_STRIKE);

        strike = pair.getStrike(MAX_STRIKE);
        assertEq(strike.next0To1, 0);

        strike = pair.getStrike(MIN_STRIKE);
        assertEq(strike.next1To0, 0);
    }
}

contract AddLiquidityTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testAddLiquidityReturnAmounts() external {
        (uint256 amount0, uint256 amount1) = basicAddLiquidity();

        assertEq(amount0, 1e18);
        assertEq(amount1, 0);

        assertEq(token0.balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), 0);

        assertEq(token0.balanceOf(address(pair)), 1e18);
        assertEq(token1.balanceOf(address(pair)), 0);
    }

    function testLiquidityStrikes() external {
        basicAddLiquidity();

        Pairs.Strike memory strike = pair.getStrike(0);
        assertEq(strike.liquidityBiDirectional[0], 1e18);
    }

    function testLiquidityPosition() external {
        basicAddLiquidity();

        assertEq(pair.getPositionBiDirectional(address(this), 0, 1), 1e18);
    }

    function testAddLiquidityStrikeMapBasic() external {
        basicAddLiquidity();

        Pairs.Strike memory strike = pair.getStrike(0);
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
        vm.expectRevert();
        pair.addLiquidity(type(int24).min, 0, 1e18);

        vm.expectRevert();
        pair.addLiquidity(type(int24).max, 0, 1e18);
    }

    function testAddLiquidityBadSpread() external {
        vm.expectRevert();
        pair.addLiquidity(0, 0, 1e18);

        vm.expectRevert();
        pair.addLiquidity(0, 10, 1e18);
    }

    function testAddLiquidityAfterAccrue() external {
        pair.addLiquidity(0, 1, 1e18);
        pair.addLiquidity(1, 1, 1e18);
        pair.borrowLiquidity(1, Engine.TokenSelector.Token0, 1.5e18, 0.5e18);
        pair.swap(false, 0.1e18);

        vm.roll(10);
        (uint256 amount0, uint256 amount1) = pair.addLiquidity(1, 1, 1e18);

        assertEq(amount0, mulDivRoundingUp(Q128, (1e18 + 0.5e15), getRatioAtStrike(1)));
        assertEq(amount1, 0);
    }
}

contract RemoveLiquidityTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testRemoveLiquidityReturnAmounts() external {
        basicAddLiquidity();
        (uint256 amount0, uint256 amount1) = basicRemoveLiquidity();

        assertEq(amount0, 1e18 - 1, "amount0");
        assertEq(amount1, 0, "amount1");

        assertEq(token0.balanceOf(address(this)), 1e18 - 1);
        assertEq(token1.balanceOf(address(this)), 0);

        assertEq(token0.balanceOf(address(pair)), 1);
        assertEq(token1.balanceOf(address(pair)), 0);
    }

    function testRemoveLiquidityStrikes() external {
        basicAddLiquidity();
        basicRemoveLiquidity();
        Pairs.Strike memory strike = pair.getStrike(0);
        assertEq(strike.liquidityBiDirectional[0], 0);
    }

    function testRemoveLiquidityPosition() external {
        basicAddLiquidity();
        basicRemoveLiquidity();

        assertEq(pair.getPositionBiDirectional(address(this), 0, 1), 0);
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

    // function testRemoveLiquidityStrikeMapBasic() external {
    //     pair.addLiquidity(0, 0, 1e18);
    //     pair.removeLiquidity(0, 0, 1e18);
    //     Strikes.Strike memory strike = pair.getStrike(0);
    //     assertEq(strike.next0To1, MIN_STRIKE);
    //     assertEq(strike.next1To0, MAX_STRIKE);

    //     strike = pair.getStrike(MAX_STRIKE);
    //     assertEq(strike.next0To1, 0);

    //     strike = pair.getStrike(MIN_STRIKE);
    //     assertEq(strike.next1To0, 0);
    // }

    // function testRemoveLiquidityStrikeMapCurrentStrike() external {
    //     pair.addLiquidity(1, 0, 1e18);
    //     pair.swap(false, 1e18 - 1);

    //     pair.removeLiquidity(1, 0, 1e18);

    //     Strikes.Strike memory strike = pair.getStrike(0);
    //     assertEq(strike.next0To1, MIN_STRIKE);
    //     assertEq(strike.next1To0, 0);

    //     strike = pair.getStrike(1);
    //     assertEq(strike.next0To1, 0);
    //     assertEq(strike.next1To0, MAX_STRIKE);

    //     strike = pair.getStrike(MAX_STRIKE);
    //     assertEq(strike.next0To1, 1);

    //     strike = pair.getStrike(MIN_STRIKE);
    //     assertEq(strike.next1To0, 1);
    // }

    function testRemoveLiquidityBadStrikes() external {
        vm.expectRevert();
        pair.removeLiquidity(type(int24).min, 1, 1e18);

        vm.expectRevert();
        pair.removeLiquidity(type(int24).max, 1, 1e18);
    }

    function testRemoveLiquidityBadSpread() external {
        vm.expectRevert();
        pair.removeLiquidity(0, 0, 1e18);

        vm.expectRevert();
        pair.removeLiquidity(0, 10, 1e18);
    }

    function testRemoveLiquidityPartialAfterAccrue() external {
        pair.addLiquidity(0, 1, 1e18);
        pair.addLiquidity(1, 1, 1e18);
        pair.borrowLiquidity(1, Engine.TokenSelector.Token0, 1.5e18, 0.5e18);
        pair.swap(false, 0.1e18);

        vm.roll(10);
        (uint256 amount0, uint256 amount1) = pair.removeLiquidity(1, 1, 0.25e18);

        assertEq(amount0, mulDiv(Q128, (0.25e18 + 0.125e15), getRatioAtStrike(1)));
        assertEq(amount1, 0);
    }

    function testRemoveLiquidityFullAfterAccrue() external {
        pair.addLiquidity(0, 1, 1e18);
        pair.addLiquidity(1, 1, 1e18);
        pair.borrowLiquidity(1, Engine.TokenSelector.Token0, 1.5e18, 0.5e18);
        pair.swap(false, 0.1e18);

        vm.roll(10);
        (uint256 amount0, uint256 amount1) = pair.removeLiquidity(1, 1, 0.5e18);

        assertEq(amount0, mulDiv(Q128, (0.5e18 + 0.25e15), getRatioAtStrike(1)));
        assertEq(amount1, 0);
    }
}

contract SwapTest is Test, PairHelper {
    uint256 private precision = 1e9;

    function setUp() external {
        _setUp();
    }

    function testSwapToken1ExactInBasic() external {
        basicAddLiquidity();
        // 1->0
        (int256 amount0, int256 amount1) = pair.swap(false, 1e18 - 1);

        uint256 amountOut = mulDiv(1e18 - 1, Q128, getRatioAtStrike(1));

        assertEq(amount0, -int256(amountOut));
        assertEq(amount1, 1e18 - 1);

        assertEq(token0.balanceOf(address(this)), amountOut);
        assertEq(token1.balanceOf(address(this)), 0);

        assertEq(token0.balanceOf(address(pair)), 1e18 - amountOut);
        assertEq(token1.balanceOf(address(pair)), 1e18 - 1);

        (uint128[NUM_SPREADS] memory composition, int24[NUM_SPREADS] memory strikeCurrent, int24 cachedStrikeCurrent,) =
            pair.getPair();

        assertEq(composition[0], type(uint128).max);
        assertEq(strikeCurrent[0], 0);
        assertEq(cachedStrikeCurrent, 1);
    }

    function testSwapToken0ExactOutBasic() external {
        basicAddLiquidity();
        // 1->0
        uint256 amountOut = mulDiv(1e18 - 1, Q128, getRatioAtStrike(1));

        (int256 amount0, int256 amount1) = pair.swap(true, -int256(amountOut));

        assertEq(amount0, -int256(amountOut));
        assertEq(amount1, 1e18 - 1);

        assertEq(token0.balanceOf(address(this)), amountOut);
        assertEq(token1.balanceOf(address(this)), 0);

        assertEq(token0.balanceOf(address(pair)), 1e18 - amountOut);
        assertEq(token1.balanceOf(address(pair)), 1e18 - 1);

        (uint128[NUM_SPREADS] memory composition, int24[NUM_SPREADS] memory strikeCurrent, int24 cachedStrikeCurrent,) =
            pair.getPair();

        assertEq(composition[0], type(uint128).max);
        assertEq(strikeCurrent[0], 0);
        assertEq(cachedStrikeCurrent, 1);
    }

    function testSwapToken0ExactInBasic() external {
        pair.addLiquidity(-1, 1, 1e18);
        // 0->1
        uint256 amountIn = mulDiv(1e18 + 1, Q128, getRatioAtStrike(-2));
        (int256 amount0, int256 amount1) = pair.swap(true, int256(amountIn));

        assertEq(amount0, int256(amountIn), "amount0");
        assertEq(amount1, -1e18, "amount1");

        assertEq(token0.balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), 1e18);

        assertEq(token0.balanceOf(address(pair)), amountIn);
        assertEq(token1.balanceOf(address(pair)), 0);

        (uint128[NUM_SPREADS] memory composition, int24[NUM_SPREADS] memory strikeCurrent, int24 cachedStrikeCurrent,) =
            pair.getPair();

        assertEq(composition[0], 0);
        assertEq(strikeCurrent[0], -1);
        assertEq(cachedStrikeCurrent, -2);
    }

    function testSwapToken1ExactOutBasic() external {
        pair.addLiquidity(-1, 1, 1e18);
        // 0->1

        (int256 amount0, int256 amount1) = pair.swap(false, -1e18);

        uint256 amountIn = mulDivRoundingUp(1e18, Q128, getRatioAtStrike(-2));

        assertEq(amount0, int256(amountIn), "amount0");
        assertEq(amount1, -1e18, "amount1");

        assertEq(token0.balanceOf(address(this)), 0, "balance0");
        assertEq(token1.balanceOf(address(this)), 1e18, "balance1");

        assertEq(token0.balanceOf(address(pair)), amountIn, "balance0 pair");
        assertEq(token1.balanceOf(address(pair)), 0, "balance1 pair");

        (uint128[NUM_SPREADS] memory composition, int24[NUM_SPREADS] memory strikeCurrent, int24 cachedStrikeCurrent,) =
            pair.getPair();

        assertEq(composition[0], 0);
        assertEq(strikeCurrent[0], -1);
        assertEq(cachedStrikeCurrent, -2);
    }

    // function testSwapPartial0To1() external {
    //     basicAddLiquidity();
    //     // 1->0
    //     (int256 amount0, int256 amount1) = pair.swap(false, 0.5e18);
    //     assertEq(amount0, -0.5e18);
    //     assertEq(amount1, 0.5e18);

    //     (Pairs.Spread[NUM_SPREADS] memory spreads,,) = pair.getPair();

    //     assertApproxEqRel(spreads[0].composition, Q128 / 2, precision);
    // }

    // function testSwapPartial1To0() external {
    //     basicAddLiquidity();
    //     // 1->0
    //     (int256 amount0, int256 amount1) = pair.swap(true, -0.5e18);

    //     assertEq(amount0, -0.5e18);
    //     assertEq(amount1, 0.5e18);

    //     (uint128[5] memory compositions,,,) = pair.getPair();

    //     assertApproxEqRel(compositions[0], Q128 / 2, precision);
    // }

    function testSwapStartPartial0To1() external {}

    function testSwapStartPartial1To0() external {}

    function testGasSwapHot() external {
        vm.pauseGasMetering();
        basicAddLiquidity();
        pair.swap(false, 0.2e18);
        vm.resumeGasMetering();

        pair.swap(false, 0.2e18);
    }

    function testGasSwapTwoStrikes() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 1, 1e18);
        pair.addLiquidity(1, 1, 1e18);
        pair.swap(false, 0.2e18);
        vm.resumeGasMetering();

        pair.swap(false, 1.5e18);
    }

    function testGasSwapFarStrikes() external {
        vm.pauseGasMetering();
        pair.addLiquidity(0, 1, 1e18);
        pair.addLiquidity(100, 1, 1e18);
        pair.swap(false, 0.2e18);
        vm.resumeGasMetering();

        pair.swap(false, 1e18);
    }

    //     function testInitialLiquidity() external {
    //         pair.addLiquidity(0, 0, 1e18);
    //         pair.addLiquidity(1, 0, 1e18);

    //         pair.addLiquidity(0, 1, 1e18);

    //         pair.swap(false, 1.5e18);
    //         pair.swap(false, 0.4e18);

    //         (, int24 strikeCurrent, int8 offset,) = pair.getPair();

    //         // assertEq(compositions[0], (uint256(type(uint128).max) * 45) / 100, "composition 0");
    //         // assertEq(compositions[1], (uint256(type(uint128).max) * 45) / 100, "composition 1");
    //         assertEq(strikeCurrent, 1);
    //         assertEq(offset, -1);
    //     }

    //     function testSpreadComposition() external {
    //         pair.addLiquidity(-1, 0, 1e18);
    //         pair.addLiquidity(-2, 0, 1e18);

    //         pair.addLiquidity(0, 1, 1e18);

    //         pair.swap(true, 1.5e18);

    //         (, int24 strikeCurrent, int8 offset,) = pair.getPair();

    //         // assertEq(compositions[0], type(uint128).max / 2, "composition 0");
    //         // assertEq(compositions[1], type(uint128).max / 2, "composition 1");
    //         assertEq(strikeCurrent, -2);
    //         assertEq(offset, 2);
    //     }
}

contract BorrowTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testBorrowAmounts() external {
        pair.addLiquidity(1, 1, 1e18);
        (int256 amount0, int256 amount1) = pair.borrowLiquidity(1, Engine.TokenSelector.Token0, 1.5e18, 0.5e18);

        assertEq(uint256(amount0), 1.5e18 - mulDiv(0.5e18, Q128, getRatioAtStrike(1)));
        assertEq(amount1, 0);

        assertEq(token0.balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), 0);

        assertEq(token0.balanceOf(address(pair)), mulDivRoundingUp(1e18, Q128, getRatioAtStrike(1)) + uint256(amount0));
        assertEq(token1.balanceOf(address(pair)), 0);

        (uint256 balance, uint256 leverageRatioX128) =
            pair.getPositionDebt(address(this), 1, Engine.TokenSelector.Token0);

        assertEq(balance, 0.5e18);
        assertEq(leverageRatioX128, mulDiv(mulDiv(1.5e18, getRatioAtStrike(1), Q128), Q128, 0.5e18));

        Pairs.Strike memory strike = pair.getStrike(1);

        assertEq(strike.activeSpread, 0);
        assertEq(strike.liquidityGrowthX128, 0);
        assertEq(strike.liquidityBiDirectional[0], 0.5e18);
        assertEq(strike.liquidityBorrowed[0], 0.5e18);
        assertEq(strike.totalSupply[0], 1e18);
    }

    function testAccrual() external {
        pair.addLiquidity(0, 1, 1e18);
        pair.addLiquidity(1, 1, 1e18);
        pair.borrowLiquidity(1, Engine.TokenSelector.Token0, 1.5e18, 0.5e18);
        pair.swap(false, 0.1e18);

        (,, int24 cachedStrikeCurrent,) = pair.getPair();
        assertEq(cachedStrikeCurrent, 1);

        vm.roll(10);
        pair.accrue();

        Pairs.Strike memory strike = pair.getStrike(1);

        assertEq(strike.activeSpread, 0);
        assertEq(strike.liquidityGrowthX128, mulDivRoundingUp(Q128, 0.5e18, 0.5e18 - 0.5e15) - Q128);
        assertEq(strike.liquidityBiDirectional[0], 0.5e18 + 1e15);
        assertEq(strike.liquidityBorrowed[0], 0.5e18 - 0.5e15);
        assertEq(strike.totalSupply[0], 1e18);
    }

    function testBorrowAfterAccrue() external {
        pair.addLiquidity(0, 1, 1e18);
        pair.addLiquidity(1, 1, 1e18);
        pair.borrowLiquidity(1, Engine.TokenSelector.Token0, 1.5e18, 0.5e18);
        pair.swap(false, 0.1e18);

        vm.roll(10);
        pair.borrowLiquidity(1, Engine.TokenSelector.Token0, 1.5e18, 0.1e18);

        (uint256 balance, uint256 leverageRatioX128) =
            pair.getPositionDebt(address(this), 1, Engine.TokenSelector.Token0);

        assertEq(balance, 0.5e18 + mulDiv(0.1e18, mulDivRoundingUp(Q128, 0.5e18, 0.5e18 - 0.5e15), Q128));

        // uint256 balanceCollateral = mulDiv(balance, leverageRatioX128, Q128) + liquidity - balance;
        // assertEq(leverageRatioX128, mulDiv(balanceCollateral, Q128, balance));

        Pairs.Strike memory strike = pair.getStrike(1);

        assertEq(strike.activeSpread, 0);
        assertEq(strike.liquidityGrowthX128, mulDivRoundingUp(Q128, 0.5e18, 0.5e18 - 0.5e15) - Q128);
        assertEq(strike.liquidityBiDirectional[0], 0.4e18 + 1e15);
        assertEq(strike.liquidityBorrowed[0], 0.6e18 - 0.5e15);
        assertEq(strike.totalSupply[0], 1e18);
    }
}

contract RepayTest is Test, PairHelper {
    function setUp() external {
        _setUp();
    }

    function testRepayAmounts() external {
        pair.addLiquidity(1, 1, 1e18);
        pair.borrowLiquidity(1, Engine.TokenSelector.Token0, 1.5e18, 0.5e18);
        (, uint256 leverageRatioX128) = pair.getPositionDebt(address(this), 1, Engine.TokenSelector.Token0);
        (int256 amount0, int256 amount1) =
            pair.repayLiquidity(1, Engine.TokenSelector.Token0, leverageRatioX128, 0.5e18);

        uint256 tokens0Owed = mulDivRoundingUp(0.5e18, Q128, getRatioAtStrike(1));
        uint256 tokens0Collateral = mulDiv((mulDiv(0.5e18, leverageRatioX128, Q128)), Q128, getRatioAtStrike(1));

        assertEq(amount0, int256(tokens0Owed) - int256(tokens0Collateral));
        assertEq(amount1, 0);

        assertEq(token0.balanceOf(address(this)), tokens0Collateral - tokens0Owed);
        assertEq(token1.balanceOf(address(this)), 0);

        // assertEq(token0.balanceOf(address(pair)), mulDivRoundingUp(1e18, Q128, getRatioAtStrike(1)));
        assertEq(token1.balanceOf(address(pair)), 0);
    }

    function testRepayAfterAccrue() external {
        pair.addLiquidity(0, 1, 1e18);
        pair.addLiquidity(1, 1, 1e18);
        pair.borrowLiquidity(1, Engine.TokenSelector.Token0, 1.5e18, 0.5e18);
        pair.swap(false, 0.1e18);

        (, uint256 leverageRatioX128) = pair.getPositionDebt(address(this), 1, Engine.TokenSelector.Token0);

        vm.roll(10);
        (int256 amount0, int256 amount1) =
            pair.repayLiquidity(1, Engine.TokenSelector.Token0, leverageRatioX128, 0.5e18);

        uint256 tokens0Owed = mulDivRoundingUp(0.5e18 - 0.5e15, Q128, getRatioAtStrike(1));

        assertEq(
            amount0,
            int256(tokens0Owed)
                - int256(mulDiv(mulDiv(0.5e18, leverageRatioX128, Q128) - 0.5e15, Q128, getRatioAtStrike(1)))
        );
        assertEq(amount1, 0);

        Pairs.Strike memory strike = pair.getStrike(1);

        assertEq(strike.activeSpread, 0);
        assertEq(strike.liquidityGrowthX128, mulDivRoundingUp(Q128, 0.5e18, 0.5e18 - 0.5e15) - Q128);
        assertEq(strike.liquidityBiDirectional[0], 1e18 + 0.5e15);
        assertEq(strike.liquidityBorrowed[0], 0);
        assertEq(strike.totalSupply[0], 1e18);
    }
}
