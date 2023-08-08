// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {
    liquidityToBalance,
    balanceToLiquidity,
    debtLiquidityToBalance,
    debtBalanceToLiquidity
} from "src/core/math/PositionMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";
import {Pairs} from "src/core/Pairs.sol";

contract PositionMathFuzzTest is Test {
    Pairs.Pair private pair;

    /// @notice liquidity to balance back to liquidity is always less than the original amount
    function testFuzz_Liquidity(uint128 liquidity, uint128 totalLiquidity, uint128 totalSupply) external {
        int24 strike = 0;
        uint8 spread = 1;

        vm.assume(totalLiquidity >= totalSupply);
        vm.assume(totalSupply > 0);

        pair.strikes[strike].totalSupply[spread - 1] = totalSupply;
        pair.strikes[strike].liquidityBiDirectional[spread - 1] = totalLiquidity;

        assertGe(
            liquidity, balanceToLiquidity(pair, strike, spread, liquidityToBalance(pair, strike, spread, liquidity))
        );

        delete pair.strikes[strike].totalSupply;
        delete pair.strikes[strike].liquidityBiDirectional;
    }

    /// @notice liquidityToBalance cannot overflow because liquidity >= balance for liquidity positions
    function testFuzz_LiquidityToBalance_Overflow(
        uint128 liquidity,
        uint128 totalLiquidity,
        uint128 totalSupply
    )
        external
    {
        vm.assume(totalLiquidity >= totalSupply);

        int24 strike = 0;
        uint8 spread = 1;

        pair.strikes[strike].totalSupply[spread - 1] = totalSupply;
        pair.strikes[strike].liquidityBiDirectional[spread - 1] = totalLiquidity;

        assertGe(liquidity, liquidityToBalance(pair, strike, spread, liquidity));

        delete pair.strikes[strike].totalSupply;
        delete pair.strikes[strike].liquidityBiDirectional;
    }

    /// @notice debtBalanceToLiquidity cannot overflow because balance >= liquidity of debt positions
    function testFuzz_DebtBalanceToLiquidity_Overflow(uint128 balance, uint256 liquidityGrowthX128) external {
        vm.assume(liquidityGrowthX128 <= type(uint256).max - Q128);
        assertGe(balance, debtBalanceToLiquidity(balance, liquidityGrowthX128));
    }
}
