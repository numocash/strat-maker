// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Pairs} from "../Pairs.sol";

function balanceToLiquidity(
    Pairs.Pair storage pair,
    int24 strike,
    uint8 spread,
    uint256 balance
)
    returns (uint256 liquidity)
{
    return balance;
}

function liquidityToBalance(
    Pairs.Pair storage pair,
    int24 strike,
    uint8 spread,
    uint256 liquidity
)
    returns (uint256 balance)
{
    return liquidity;
}
