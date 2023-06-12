# Yikes [![GitHub Actions][gha-badge]][gha]

[gha]: https://github.com/kyscott18/ilrta/actions
[gha-badge]: https://github.com/kyscott18/ilrta/actions/workflows/main.yml/badge.svg

An ethereum erc20 exchange protocol.

> ⚠️ Please note this is for research purposes only and lacks sufficient testing and audits necessary to be used in a production setting.

Features:

- Aggregate of constant-sum liquidity pools with spaced strike prices
- Custom fee settings within each pair with automatic routing between them
- Single contract architecture

## Benchmarking

|                   |Yikes   |Uniswap V3|LiquidityBook|Maverick|
|-------------------|--------|----------|-------------|--------|
|Loc                |        |          |             |        |
|Create new pair    |        |          |             |        |
|Fresh Add Liquidity|        |          |             |        |
|Hot Add Liqudity   |        |          |             |        |
|Small Swap         |        |          |             |        |
|Large Swap         |        |          |             |        |

## Concepts

### Automated Market Maker

Yikes is an automated market maker that allows for exchange between two assets by managing a pool of reserves referred to as a liquidity pool.

Yikes is uses the invariant `Liquidity = Price * amount0 + amount1` to determine if a trade should be rejected or accepted, with price having units `Price: token1 / token0`.

### Ticks

### Fee Tiers

## Architecture

### Engine

Yikes uses an engine contract that manages the creation and interaction with each pair. Contrary to many other exchanges, pairs are not seperate contracts but instead implemented as a library. Therefore, the engine smart contract holds the state of all pairs. This greatly decreases the cost of creating a new pair and also allows for more efficient multi-hop swaps.

### Pair

### Ticks

### Positions

### Periphery

## Development

## Acknowledgements
