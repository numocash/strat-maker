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
import {mulDivOverflow} from "../../utils/FullMath.sol";

contract PositionMathFuzzTest is Test {
    /// @notice liquidity to balance back to liquidity is always less than the original amount
    function testFuzz_Liquidity(uint128 liquidity, uint256 liquidityGrowthX128) external {
        vm.assume(liquidityGrowthX128 == 0 || liquidityGrowthX128 >= Q128);

        vm.assume(!mulDivOverflow(liquidity, liquidityGrowthX128, 1));

        assertGe(liquidity, balanceToLiquidity(liquidityToBalance(liquidity, liquidityGrowthX128), liquidityGrowthX128));
    }

    /// @notice balanceToLiquidity cannot overflow because balance >= liquidity for liquidity positions
    function testFuzz_BalanceToLiquidity_Overflow(uint128 liquidity, uint256 liquidityGrowthX128) external {
        vm.assume(liquidityGrowthX128 == 0 || liquidityGrowthX128 >= Q128);

        assertGe(liquidity, balanceToLiquidity(liquidity, liquidityGrowthX128));
    }

    /// @notice debtBalanceToLiquidity cannot overflow because balance >= liquidity of debt positions
    function testFuzz_DebtBalanceToLiquidity_Overflow(uint128 balance, uint256 liquidityGrowthX128) external {
        vm.assume(liquidityGrowthX128 <= type(uint256).max && liquidityGrowthX128 >= Q128);
        assertGe(balance, debtBalanceToLiquidity(balance, liquidityGrowthX128));
    }
}
