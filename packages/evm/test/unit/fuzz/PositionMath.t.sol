// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {liquidityToBalance, balanceToLiquidity, debtBalanceToLiquidity} from "src/core/math/PositionMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";
import {mulDiv} from "src/core/math/FullMath.sol";

contract PositionMathFuzzTest is Test {
    /// @notice liquidity to balance back to liquidity is always less than the original amount
    function testFuzz_Liquidity(uint128 liquidity, uint256 liquidityGrowthX128) external {
        vm.assume(liquidityGrowthX128 == 0 || liquidityGrowthX128 >= Q128);

        vm.assume(mulDiv(liquidity, liquidityGrowthX128, Q128) <= type(uint128).max);

        assertGe(liquidity, balanceToLiquidity(liquidityToBalance(liquidity, liquidityGrowthX128), liquidityGrowthX128));
    }

    /// @notice liquidityToBalance cannot overflow because liquidity >= balance for liquidity positions
    function testFuzz_LiquidityToBalance_Overflow(uint128 liquidity, uint256 liquidityGrowthX128) external {
        vm.assume(liquidityGrowthX128 == 0 || liquidityGrowthX128 >= Q128);

        assertGe(liquidity, liquidityToBalance(liquidity, liquidityGrowthX128));
    }

    /// @notice debtBalanceToLiquidity cannot overflow because balance >= liquidity of debt positions
    function testFuzz_DebtBalanceToLiquidity_Overflow(
        uint128 balance,
        uint256 multiplierX128,
        uint256 liquidityGrowthX128
    )
        external
    {
        vm.assume(liquidityGrowthX128 == 0 || liquidityGrowthX128 >= Q128);
        assertGe(balance, debtBalanceToLiquidity(balance, multiplierX128, liquidityGrowthX128));
    }
}
