// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {Pairs} from "../Pairs.sol";

function balanceToLiquidity(
    Pairs.Pair storage pair,
    int24 strike,
    uint8 spread,
    uint256 balance,
    bool roundUp
)
    view
    returns (uint256 liquidity)
{
    uint256 totalSupply = pair.strikes[strike].totalSupply[spread - 1];
    if (totalSupply == 0) {
        return balance;
    } else {
        return roundUp
            ? mulDivRoundingUp(balance, pair.strikes[strike].liquidityBiDirectional[spread - 1], totalSupply)
            : mulDiv(balance, pair.strikes[strike].liquidityBiDirectional[spread - 1], totalSupply);
    }
}

function liquidityToBalance(
    Pairs.Pair storage pair,
    int24 strike,
    uint8 spread,
    uint256 liquidity,
    bool roundUp
)
    view
    returns (uint256 balance)
{
    uint256 totalLiquidity = pair.strikes[strike].liquidityBiDirectional[spread - 1];
    if (totalLiquidity == 0) {
        return liquidity;
    } else {
        return roundUp
            ? mulDivRoundingUp(liquidity, pair.strikes[strike].totalSupply[spread - 1], totalLiquidity)
            : mulDiv(liquidity, pair.strikes[strike].totalSupply[spread - 1], totalLiquidity);
    }
}
