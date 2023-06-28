# Yikes [![GitHub Actions][gha-badge]][gha]

[gha]: https://github.com/numoen/dry-powder/actions
[gha-badge]: https://github.com/numoen/dry-powder/actions/workflows/main.yml/badge.svg

An ERC20 exchange protocol on the Ethereum Virtual Machine.

> ⚠️ Please note this is for research purposes only and lacks sufficient testing and audits necessary to be used in a production setting.

Features:

- Aggregate of constant-sum liquidity pools with spaced strike prices
- Custom fee settings within each pair with automatic routing between them
- Single contract architecture

## Benchmarking

|                   |Dry Powder|Uniswap V3|LiquidityBook|Maverick|
|-------------------|----------|----------|-------------|--------|
|Loc                |          |          |             |        |
|Create new pair    |          |          |             |        |
|Add Liqudity       |          |          |             |        |
|Small Swap         |          |          |             |        |
|Large Swap         |          |          |             |        |

## Concepts

### Automated Market Maker

Dry Powder is an automated market maker (AMM) that allows for exchange between two assets by managing a pool of reserves referred to as a liquidity pool. Automated market makers are guided by an invariant, which determines whether a trade should be accepted.

Yikes is uses the invariant `Liquidity = Price * amount0 + amount1`, also referred to as **constant sum**, with price having units `Price: token1 / token0`.

Simply put, automated market makers create a market between two classes of users. Traders want to swap token0 to token1 or vice versa, presumably because they believe it will benefit them in someway. Liquidity providers lend out combination of token0 and token1, that is used to facilitate traders. They are rewarded for this with a portion of all traders trades. This market aims to connect traders and liquidity providers in a way that leaves them both satisfied with the outcome.

### Strikes (Aggregate Liquidity)

In order to allow for maximum simplicity and expressiveness, Yikes is an aggregate of up to 2^24 constant sum automated market makers. Each individual market is designated by its **strike** which is directly mapped to a price according to the formula `Price = (1.0001)^strike`, such that each strike is 1 bip away from adjacent strikes. This design is very similar to Uniswap's concentrated liquidity except that liquidity is assigned directly to a fixed price, because of the constant sum invariant. Yikes manages swap routing so that all trades swap through the best available price.

### Spreads

Yikes allows liquidity providers to impose a fee on their liquidity when used for a trade. Many popular AMM designs measure fees based on a fixed percentage of the input of every trade. Yikes takes a different approach and instead fees are described as a spread on the underlying liquidity. For example, liquidity placed at strike 10 with a spread of 1 is willing to swap 0 -> 1 (sell) at strike 11 and swap 1 -> 0 (buy) at strike 9.

This design essentially allows for fees to be encoded in strikes for more efficient storage and optimal on-chain routing. Yikes has multiple spread tiers per pair.

It is important to note that with a larger spread, pricing is less exact. For example, a liquidity position that is willing to trade token0 to token1 at strike -10 and trade token 1 to token0 at strike -3 will not be used while the global market price is anywhere between strike -10 and -3. Liquidity providers must find the correct balance for them of high fees and high volume.

### Limit orders

Yikes allows liquidity providers to only allow for their liquidity to be used in one direction, equivalent to a limit order. This is done without any keepers or third parties, instead natively available on any pair.

## Architecture

### Engine (`core/Engine.sol`)

Yikes uses an engine contract that manages the creation and interaction with each pair. Contrary to many other exchanges, pairs are not seperate contracts but instead implemented as a library. Therefore, the engine smart contract holds the state of all pairs. This greatly decreases the cost of creating a new pair and also allows for more efficient multi-hop swaps.

In the `Engine.sol` contract, information about different token pairs are stored and retrieved in the internal mapping called `pairs`, which maps a pair identifier computed using token addresses to a `Pairs.Pair` struct. This struct contains data related to a specific token pair, such as where liquidity is provided and what spread is imposed on that liquidity.

The Engine accepts an array of commands and an equal length array of inputs. Each command is an action that can be taken on a specific pair, such as `createPair()`, `addLiquidity()`, `removeLiquidity()`, or `swap()`. Each input is a bytes array that can be decoded into the inputs to each command. In a loop, commands are executed on the specified pair, and the effects are stored for later use.

After all commands have been executed, the gross outputs are transferred to the specified recipient. A callback is called, and after the gross inputs are expected to be received. This architecture allows for every command to use flash accounting, where outputs are transferred out first then arbitrary actions can be run before expecting the inputs.

### Pair (`core/Pairs.sol`)

Each individual market, described by `token0` and `token1` is an instance of a pair. Pairs contains all accounting logic.

Pairs have several state variables including:

- `composition`, and `strikeCurrent`: Information for each spread. Composition represents the portion of the liquidity that is held in `token1`. The current strike is the last strike that was used for a swap for that specific spread.
- `cachedStrikeCurrent`: The last strike that was traded through for the entire pair. This save computation and can lead to less storage writes elsewhere.
- `strikes`: Information for each strike. BiDirectional liquidity is the type of liquidity that is conventially stored in an AMM. Yikes also implements limit orders, or directional orders that are automatically closed out after being used to facilitate a trade. Limit orders need to store liquidity information as well as variables that can be used to determine if a specific limit order is closed. Strikes also contains two, singley-linked lists. These lists relate adjacent strikes together. This is needed because looping to find the next active adjacent strike is infeasible with 2**24 possible strikes.

Pairs also contain two functions to manage the state variables:

- `swap()`: Swap from one token to another, routing through the best priced liquidity.
- `updateLiquidity()`: Either add or remove liquidity from the pair.

### BitMaps (`core/BitMaps.sol`)

BitMaps is a library used in `Pairs.sol`. Its purpose is to manage and store information about initialized strikes. This is used when inserting a new node into the previously mentioned singley-linked lists in sub-linear time.

### Positions (`core/Positions.sol`)

Positions stores users liquidity positions in yikes. Positions implements a standard called `ILRTA`, which supports transferability with and without signatures.

### Router (`periphery/Router.sol`)

A router is used to interact with the Engine. Router uses a signature based token transfer scheme, `Permit3`, to pay for the inputs for command sent to the Engine. Liquidity positions can also be transferred by signature. This makes the router hold no state, including approvals. Router can therefore be seamlessly replaced at no cost to users.

## Development

## Acknowledgements
