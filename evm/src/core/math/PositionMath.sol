// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {Q128} from "./StrikeMath.sol";
import {Pairs} from "../Pairs.sol";
import {Positions} from "../Positions.sol";

error Overflow();

/// @notice Convert liquidity position balance to liquidity
/// @dev Assume strike and spread are valid, rounds down
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

        if (totalSupply == 0) {
            return balance;
        } else {
            uint256 _liquidity = (
                uint256(balance)
                    * (
                        uint256(
                            pair.strikes[strike].liquidityBiDirectional[spreadIndex]
                                + pair.strikes[strike].liquidityBorrowed[spreadIndex]
                        )
                    )
            ) / totalSupply;
            if (_liquidity > type(uint128).max) revert Overflow();
            return uint128(_liquidity);
        }
    }
}

/// @notice Convert liquidity to liquidity position balance
/// @dev Assume strike and spread are valid, rounds down
/// @dev Cannot overflow because liquidity >= balance for liquidity positions
/// @dev balance = (liquidity * totalSupply) / totalLiquidity
/// @custom:team is there any assumption we can make about how much liquidity there is to potentially remove the
/// totalLiquidity zero check
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
            return
                uint128((uint256(liquidity) * uint256(pair.strikes[strike].totalSupply[spreadIndex])) / totalLiquidity);
        }
    }
}

/// @notice Convert debt position balance to liquidity
/// @dev liquidity = balance / (liquidityGrowth + 1)
/// @dev Rounds up, cannot overflow because balance >= liquidity for debt positions
/// @custom:team How to make sure liquidityGrowth doesn't overflow
function debtBalanceToLiquidity(uint128 balance, uint256 liquidityGrowthX128) pure returns (uint128) {
    return uint128(mulDivRoundingUp(balance, Q128, liquidityGrowthX128 + Q128));
}

/// @notice Convert liquidity to debt position balance
/// @dev balance = liquidity * (liquidityGrowth + 1)
/// @dev Rounds up
/// @custom:team How to make sure liquidityGrowth doesn't overflow
function debtLiquidityToBalance(uint128 liquidity, uint256 liquidityGrowthX128) pure returns (uint128) {
    uint256 balance = mulDivRoundingUp(liquidity, liquidityGrowthX128 + Q128, Q128);
    if (balance > type(uint128).max) revert Overflow();
    return uint128(balance);
}

/// @notice Combine two positions, adding together the leverage ratio
function addPositions(
    uint128 balance0,
    uint128 balance1,
    Positions.DebtData memory debtData0,
    Positions.DebtData memory debtData1
)
    pure
    returns (uint256 leverageRatioX128)
{
    uint256 collateral0 = mulDiv(balance0, debtData0.leverageRatioX128, Q128);
    uint256 collateral1 = mulDiv(balance1, debtData1.leverageRatioX128, Q128);

    return mulDiv(collateral0 + collateral1, Q128, uint256(balance0) + uint256(balance1));
}
