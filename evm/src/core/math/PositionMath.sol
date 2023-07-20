// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {Q128} from "./StrikeMath.sol";
import {Pairs} from "../Pairs.sol";
import {Positions} from "../Positions.sol";

function balanceToLiquidity(
    Pairs.Pair storage pair,
    int24 strike,
    uint8 spread,
    uint128 balance,
    bool roundUp
)
    view
    returns (uint128 liquidity)
{
    uint256 totalSupply = pair.strikes[strike].totalSupply[spread - 1];
    if (totalSupply == 0) {
        return balance;
    } else {
        return roundUp
            ? uint128(
                (
                    balance * pair.strikes[strike].liquidityBiDirectional[spread - 1]
                        + pair.strikes[strike].liquidityBorrowed[spread - 1]
                ) / totalSupply
            )
            : uint128(
                (
                    balance * pair.strikes[strike].liquidityBiDirectional[spread - 1]
                        + pair.strikes[strike].liquidityBorrowed[spread - 1]
                ) / totalSupply
            );
    }
}

function liquidityToBalance(
    Pairs.Pair storage pair,
    int24 strike,
    uint8 spread,
    uint128 liquidity,
    bool roundUp
)
    view
    returns (uint128 balance)
{
    uint128 totalLiquidity =
        pair.strikes[strike].liquidityBiDirectional[spread - 1] + pair.strikes[strike].liquidityBorrowed[spread - 1];
    if (totalLiquidity == 0) {
        return liquidity;
    } else {
        return roundUp
            ? uint128((liquidity * pair.strikes[strike].totalSupply[spread - 1]) / totalLiquidity)
            : uint128((liquidity * pair.strikes[strike].totalSupply[spread - 1]) / totalLiquidity);
    }
}

function debtBalanceToLiquidity(
    uint128 balance,
    uint256 liquidityGrowthX128,
    bool roundUp
)
    pure
    returns (uint128 liquidity)
{
    return uint128(
        roundUp
            ? mulDivRoundingUp(balance, Q128, liquidityGrowthX128 + Q128)
            : mulDiv(balance, Q128, liquidityGrowthX128 + Q128)
    );
}

function debtLiquidityToBalance(
    uint128 liquidity,
    uint256 liquidityGrowthX128,
    bool roundUp
)
    pure
    returns (uint128 balance)
{
    return uint128(
        roundUp
            ? mulDivRoundingUp(liquidity, liquidityGrowthX128 + Q128, Q128)
            : mulDiv(liquidity, liquidityGrowthX128 + Q128, Q128)
    );
}

function getLiquidityBorrowed(
    Pairs.Pair storage pair,
    int24 strike,
    Positions.DebtData storage debtData
)
    returns (uint256 liquidity)
{}

function getLiquidityCollateral(
    Pairs.Pair storage pair,
    int24 strike,
    Positions.DebtData storage debtData
)
    returns (uint256 liquidity)
{}

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

    return mulDiv(collateral0 + collateral1, Q128, balance0 + balance1);
}
