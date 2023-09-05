// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv} from "./FullMath.sol";
import {Q128} from "./StrikeMath.sol";
import {Positions} from "../Positions.sol";

/// @notice Error thrown when result of a math operation is greater than maximum allowable number
error Overflow();

/// @notice Convert liquidity position balance to liquidity
/// @dev Assume strike and spread are valid, rounds down
/// @dev liquidity = balance * liquidityGrowthX128
function balanceToLiquidity(uint128 balance, uint256 liquidityGrowthX128) pure returns (uint128) {
    if (liquidityGrowthX128 == 0) return balance;
    uint256 liquidity = mulDiv(balance, liquidityGrowthX128, Q128);
    if (liquidity > type(uint128).max) revert Overflow();
    return uint128(liquidity);
}

/// @notice Convert liquidity to liquidity position balance
/// @dev Assume strike and spread are valid, rounds down
/// @dev Cannot overflow because liquidity >= balance for liquidity positions
/// @dev balance = liquidity / liquidityGrowthX128
function liquidityToBalance(uint128 liquidity, uint256 liquidityGrowthX128) pure returns (uint128) {
    if (liquidityGrowthX128 == 0) return liquidity;
    unchecked {
        return uint128((uint256(liquidity) * Q128) / liquidityGrowthX128);
    }
}

/// @notice Convert debt position balance to liquidity
/// @dev liquidity = balance * (multiplier - liquidityGrowth) / multiplier
/// @dev Rounds down, cannot overflow becuase balance >= liquidity for debt positions
function debtBalanceToLiquidity(
    uint128 balance,
    uint256 multiplierX128,
    uint256 liquidityGrowthX128
)
    pure
    returns (uint128)
{
    if (liquidityGrowthX128 == 0) return balance;
    if (liquidityGrowthX128 >= multiplierX128) return 0;
    return uint128(mulDiv(balance, multiplierX128 - liquidityGrowthX128, multiplierX128));
}
