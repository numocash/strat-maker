# Dry Powder [![GitHub Actions][gha-badge]][gha]

[gha]: https://github.com/numoen/dry-powder/actions
[gha-badge]: https://github.com/numoen/dry-powder/actions/workflows/main.yml/badge.svg

An ERC20 exchange protocol built for the Ethereum Virtual Machine.

Features:

- Aggregate of constant-sum liquidity pools with spaced strike prices
- Reserve the right to swap on liquidity with built in, overcollateralized, liquidation-free lending
- Custom fee settings within each pair with inherent, optimal, on-chain routing between them
- Liquidity can be constricted to one trading direction (partial fill limit order)
- Auto-compounding fees
- Single contract architecture

## Benchmarking

|                   |Dry Powder|Uniswap V3|LiquidityBook|Maverick|
|-------------------|----------|----------|-------------|--------|
|Loc                |          |          |             |        |
|Create new pair    |          |          |             |        |
|Add Liqudity       |          |          |             |        |
|Small Swap         |          |          |             |        |
|Large Swap         |          |          |             |        |
|Borrow Liquidity   |          |          |             |        |

## Concepts

### Automated Market Maker

Dry Powder is an automated market maker (AMM) that allows for exchange between two assets by managing a pool of reserves referred to as a liquidity pool. Automated market makers are guided by an invariant, which determines whether a trade should be accepted.

Dry Powder is uses the invariant `Liquidity = Price * amount0 + amount1`, also referred to as **constant sum**, with price having units `Price: token1 / token0`.

Simply put, automated market makers create a market between two classes of users. Traders want to swap token0 to token1 or vice versa, presumably because they believe it will benefit them in someway. Liquidity providers lend out a combination of token0 and token1, that is used to facilitate traders. They are rewarded for this with a portion of all traders trades. This market aims to connect traders and liquidity providers in a way that leaves them both satisfied with the opportunity.

### Reserving Rights to Swap (Creating Convex Derivatives)

First implemented in Numoen's Power Market Maker Protocol is the ability to reserve the rights to swap by borrowing liquidity. To do this, users post collateral that they know will always be more valuable than the value of the liquidity they want to borrow. With this collateral, a user would borrow liquidity and immeadiately withdraw it in hopes that they can repay the liquidiity for a cheaper price in the future.

For example, let's assume the price of ether is currently $1000. Alice borrows 1 unit of liquidity at a strike price of $1500 that contains 1 ether or 1500 usdc, but because the market price is below the strike price, it is redeemable for 1 ether currently. As collateral, alice uses the 1 ether that was redeemed plus .1 ether of her own. The market price then moves to $2000 per ether. Alice sells the 1.1 ether for 2200 usdc, uses 1500 of the usdc to mint a liquidity token and payback her debt, profiting 700 usdc from a 100% price move with $100 of principal.

Obviously, users must pay for the ability to acheive asymmetric exposure. In this protocol, positions that are borrowing liquidity active liquidity are slowly liquidated by having their collateral seized and being forgiven of their debt. Interest is accrued per block and, explained in more detail in the next section, borrow rates are proportional to swap fees which are related to volatility and block times.

This has drastic impacts on the low level economics of AMMs. The profitablity of popular exchange protocols is debated because liquidity providers suffer from a phenomenom known as Loss Versus Rebalancing (LVR pronounced lever). This is essentially a cost to liquidity providers that comes from external arbitrageurs having more informed market information than the protocol. These protocols are able to remain profitable by uninformed retail traders using them as a means of exchange, but this approach isn't sustainable. Two undesireable outcomes are the fact that:

1. Arbitrageurs never lose money, they simply won't take any action if the trade is unprofitable.
2. When arbitrageurs are bidding against eachother, their payment goes to validators instead of liquidity providers.

Reserving the rights to swap or borrowing liquidty solves these problems. Actors who were previously profiting on the volatility of assets are now able to borrow liquidity and arbitrage when the market price moves. Arbitrageurs now are unprofitable when the cost of borrowing is more than the arbitrage profit. We do not attempt to "solve" LVR, but instead make sure it is appropriately priced by allowing the other side of the trade or "gain versus rebalancing". This protocol takes the more conservative assumption that all traders are more informed than the current market.

### Options Pricing

In this section we relate the cost of swapping and borrowing liquidity to market wide metrics such as implied volatility.

### Strikes (Aggregate Liquidity)

In order to allow for maximum simplicity and expressiveness, Dry Powder is an aggregate of up to 2^24 constant sum automated market makers. Each individual market is designated by its **strike** which is directly mapped to a price according to the formula `Price = (1.0001)^strike`, such that each strike is 1 bip away from adjacent strikes. This design is very similar to Uniswap's concentrated liquidity except that liquidity is assigned directly to a fixed price, because of the constant sum invariant. Dry Powder manages swap routing so that all trades swap through the best available price.

### Spreads

Dry Powder allows liquidity providers to impose a fee on their liquidity when used for a trade. Many popular AMM designs measure fees based on a fixed percentage of the input of every trade. Dry Powder takes a different approach and instead fees are described as a spread on the underlying liquidity. For example, liquidity placed at strike 10 with a spread of 1 is willing to swap 0 -> 1 (sell) at strike 11 and swap 1 -> 0 (buy) at strike 9.

This design essentially allows for fees to be encoded in strikes for more efficient storage and optimal on-chain routing. Dry Powder has multiple spread tiers per pair.

It is important to note that with a larger spread, pricing is less exact. For example, a liquidity position that is willing to trade token0 to token1 at strike -10 and trade token 1 to token0 at strike -3 will not be used while the global market price is anywhere between strike -10 and -3. Liquidity providers must find the correct balance for them of high fees and high volume.

### Limit orders

Dry Powder allows liquidity providers to only allow for their liquidity to be used in one direction, equivalent to a limit order. This is done without any keepers or third parties, instead natively available on any pair. The limit orders implemented in Dry Powder are of the "partial fill" type, meaning they may not be fully swapped at once.

## Architecture

### Engine (`core/Engine.sol`)

Dry Powder uses an engine contract that manages the creation and interaction with each pair. Contrary to many other exchanges, pairs are not seperate contracts but instead implemented as a library. Therefore, the engine smart contract holds the state of all pairs. This greatly decreases the cost of creating a new pair and also allows for more efficient multi-hop swaps.

In the `Engine.sol` contract, information about different token pairs are stored and retrieved in the internal mapping called `pairs`, which maps a pair identifier computed using token addresses to a `Pairs.Pair` struct. This struct contains data related to a specific token pair, such as where liquidity is provided and what spread is imposed on that liquidity.

The Engine accepts an array of commands and an equal length array of inputs. Each command is an action that can be taken on a specific pair, such as `createPair()`, `addLiquidity()`, `removeLiquidity()`, or `swap()`. Each input is a bytes array that can be decoded into the inputs to each command. In a loop, commands are executed on the specified pair, and the effects are stored for later use.

After all commands have been executed, the gross outputs are transferred to the specified recipient. A callback is called, and after the gross inputs are expected to be received. This architecture allows for every command to use flash accounting, where outputs are transferred out first then arbitrary actions can be run before expecting the inputs.

### Pair (`core/Pairs.sol`)

Each individual market, described by `token0` and `token1` is an instance of a pair. Pairs contains all accounting logic.

Pairs have several state variables including:

- `composition`, and `strikeCurrent`: Information for each spread. Composition represents the portion of the liquidity that is held in `token1`. The current strike is the last strike that was used for a swap for that specific spread.
- `cachedStrikeCurrent`: The last strike that was traded through for the entire pair. This save computation and can lead to less storage writes elsewhere.
- `strikes`: Information for each strike. BiDirectional liquidity is the type of liquidity that is conventially stored in an AMM. Dry Powder also implements limit orders, or directional orders that are automatically closed out after being used to facilitate a trade. Limit orders need to store liquidity information as well as variables that can be used to determine if a specific limit order is closed. Strikes also contains two, singley-linked lists. These lists relate adjacent strikes together. This is needed because looping to find the next active adjacent strike is infeasible with 2**24 possible strikes.

Pairs also contain two functions to manage the state variables:

- `swap()`: Swap from one token to another, routing through the best priced liquidity.
- `updateLiquidity()`: Either add or remove liquidity from the pair.

### BitMaps (`core/BitMaps.sol`)

BitMaps is a library used in `Pairs.sol`. Its purpose is to manage and store information about initialized strikes. This is used when inserting a new node into the previously mentioned singley-linked lists in sub-linear time.

### Positions (`core/Positions.sol`)

Positions stores users liquidity positions in Dry Powder. Positions implements a standard called `ILRTA`, which supports transferability with and without signatures.

### Router (`periphery/Router.sol`)

A router is used to interact with the Engine. Router uses a signature based token transfer scheme, `Permit3`, to pay for the inputs for command sent to the Engine. Liquidity positions can also be transferred by signature. This makes the router hold no state, including approvals. Router can therefore be seamlessly replaced at no cost to users.

## Development

## Acknowledgements
