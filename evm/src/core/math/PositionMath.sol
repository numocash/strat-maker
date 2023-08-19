// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {Q128} from "./StrikeMath.sol";
import {Pairs} from "../Pairs.sol";
import {Positions} from "../Positions.sol";

/// @notice Error thrown when result of a math operation is greater than maximum allowable number
error Overflow();

/// @notice Convert liquidity position balance to liquidity
/// @dev Assume strike and spread are valid, rounds down, totalSupply > 0
/// @dev liquidity = (balance * totalLiquidity) / totalSupply
function balanceToLiquidity(
    Pairs.Pair storage pair,
    int24 strike,
    uint8 spread,
    uint128 balance
)
    view
    returns (uint128)
{
    unchecked {
        uint8 spreadIndex = spread - 1;
        uint256 totalSupply = pair.strikes[strike].totalSupply[spreadIndex];
        uint256 totalLiquidity = pair.strikes[strike].liquidityBiDirectional[spreadIndex]
            + pair.strikes[strike].liquidityBorrowed[spreadIndex];

        uint256 _liquidity = (uint256(balance) * totalLiquidity) / totalSupply;
        if (_liquidity > type(uint128).max) revert Overflow();
        return uint128(_liquidity);
    }
}

/// @notice Convert liquidity to liquidity position balance
/// @dev Assume strike and spread are valid, rounds down
/// @dev Cannot overflow because liquidity >= balance for liquidity positions
/// @dev balance = (liquidity * totalSupply) / totalLiquidity
function liquidityToBalance(
    Pairs.Pair storage pair,
    int24 strike,
    uint8 spread,
    uint128 liquidity
)
    view
    returns (uint128)
{
    unchecked {
        uint8 spreadIndex = spread - 1;
        uint256 totalLiquidity = pair.strikes[strike].liquidityBiDirectional[spreadIndex]
            + pair.strikes[strike].liquidityBorrowed[spreadIndex];

        if (totalLiquidity == 0) {
            return liquidity;
        } else {
            uint256 totalSupply = pair.strikes[strike].totalSupply[spreadIndex];

            return uint128((uint256(liquidity) * totalSupply) / totalLiquidity);
        }
    }
}

/// @notice Convert debt position balance to liquidity
/// @dev liquidity = balance / liquidityGrowthExp
/// @dev Rounds up, cannot overflow because balance >= liquidity for debt positions
function debtBalanceToLiquidity(uint128 balance, uint256 liquidityGrowthExpX128) pure returns (uint128) {
    unchecked {
        uint256 numerator = uint256(balance) * Q128;
        return numerator % liquidityGrowthExpX128 == 0
            ? uint128(numerator / liquidityGrowthExpX128)
            : uint128(numerator / liquidityGrowthExpX128) + 1;
    }
}

/// @notice Convert liquidity to debt position balance
/// @dev balance = liquidity * liquidityGrowthExp
/// @dev Rounds up
function debtLiquidityToBalance(uint128 liquidity, uint256 liquidityGrowthExpX128) pure returns (uint128) {
    uint256 balance = mulDivRoundingUp(liquidity, liquidityGrowthExpX128, Q128);
    if (balance > type(uint128).max) revert Overflow();
    return uint128(balance);
}
