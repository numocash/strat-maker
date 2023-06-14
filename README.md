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

Yikes is an automated market maker (AMM) that allows for exchange between two assets by managing a pool of reserves referred to as a liquidity pool. Automated market makers are guided by an invariant, which determines whether a trade should be accepted.

Yikes is uses the invariant `Liquidity = Price * amount0 + amount1`, also referred to as **constant sum**, with price having units `Price: token1 / token0`.

### Tick (Aggregate Liquidity)

In order to allow for maximum simplicity and expressiveness, Yikes is an aggregate of up to 2^24 constant sum automated market makers. Each individual market is designated by its **tick** which is directly mapped to a price according to the formula `Price = (1.0001)^tick`, such that each tick is 1 bip away from adjacent ticks. This design is very similar to Uniswap's concentrated liquidity except that liquidity is assigned directly to a fixed price. Yikes manages swap routing so that all trades swap through the best available price.

### Fee Tiers

Yikes allows liquidity providers to impose a fee on their liquidity when used for a trade. Many popular AMM designs measure fees based on a fixed percentage of the input of every trade. Yikes takes a different approach and instead fees are described as a spread on the underlying liquidity. For example, liquidity placed at tick 10 with a spread of 1 is willing to swap 0 -> 1 (sell) at tick 11 and swap 1 -> 0 (buy) at tick 9.

This design essentially allows for fees to be encoded in ticks. Yikes has multiple fee tiers per pair, and optimally routes trades through all fee tiers.

## Architecture

### Engine (`core/Engine.sol`)

Yikes uses an engine contract that manages the creation and interaction with each pair. Contrary to many other exchanges, pairs are not seperate contracts but instead implemented as a library. Therefore, the engine smart contract holds the state of all pairs. This greatly decreases the cost of creating a new pair and also allows for more efficient multi-hop swaps.

In the `Engine.sol` contract information about different token pairs is store and retrieved in the internal mapping called `pairs`, which maps a pair identifier computed using token addresses to a `Pairs.Pair` struct. This struct contains data related to a specific token pair, such as liquidity, tick information, and position data. 

The `createPair()` function creates a new token pair and initializes it with an initial tick, `tickInitial`. 

The `addLiquidity()` function adds liquidity to a specified pair and updates the corresponding balances. It also invokes a callback function defined in the IAddLiquidityCallback interface. Similarly, the `removeLiquidity()` function removes liquidity from a pair and transfers the respective token amounts to the specified recipient.

The `swap()` function allows users to swap tokens between a given pair. It calculates the resulting token amounts and performs necessary transfers. The function also invokes a callback defined in the ISwapCallback interface. The contract also provides functions to retrieve pair information, tick data, and position information for a given pair, owner, tier, and tick.

### Pair (`core/Pair.sol`)

Each individual market, described by `token0` and `token1` is an instance of a pair.

### TickMaps (`core/TickMaps.sol`)

TickMaps is a library used in `Pairs.sol`. Its purpose is to manage and store information about initialized ticks with each tick being a fixed price on the constant sum curve. To do this, information about initialized blocks, words, and ticks is stored in the struct `TickMap`. It uses bitmaps and mappings to represent the initialization status at different levels, providing a compact and scalable solution for managing tick-related data.

### Positions (`core/Positions.sol`)

### Periphery

## Development

## Acknowledgements
