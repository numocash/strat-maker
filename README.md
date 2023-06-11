# Yikes [![GitHub Actions][gha-badge]][gha]

[gha]: https://github.com/kyscott18/ilrta/actions
[gha-badge]: https://github.com/kyscott18/ilrta/actions/workflows/main.yml/badge.svg

An ethereum erc20 exchange protocol.

Features:

- Limit orders
- Custom fee settings within each pair

## Benchmarking

## Concepts and formulas

The protocol aims for ultimate simplicity and the expressiveness of an orderbook by using an aggregate of two asset, constant sum liquidity pools. Unlike Uniswap V3, liquidity can be precisely distributed on any fixed price rather than distributed evenly across a price range.

### Strikes 

### Offsets

### Strike Spacing

In order to create a more familiar trading experience, we opt for a different strike spacing than what was used in Uniswap V3 where ticks are each 0.01\% from each other. Instead, we use constantly-spaced ticks with a piece-wise function determining the spacing.

## Architecture

Core - `Engine.sol`
