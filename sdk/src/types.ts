import {
  CommandEnum,
  NUM_SPREADS,
  OrderTypeEnum,
  TokenSelectorEnum,
} from "./constants.js";
import type { AbiTypeToPrimitiveType } from "abitype";
import type { CurrencyAmount, Fraction, Token } from "reverse-mirage";

/**
 * A tuple of length `N` with elements of type `T`.
 * @see https://github.com/saber-hq/saber-common/blob/master/packages/tuple-utils/src/tuple.ts
 */
export type Tuple<T, N extends number> = N extends N
  ? number extends N
    ? T[]
    : _TupleOf<T, N, []>
  : never;
type _TupleOf<T, N extends number, R extends T[]> = R["length"] extends N
  ? R
  : _TupleOf<T, N, [T, ...R]>;

export type Pair = { token0: Token; token1: Token; scalingFactor: number };

export type Strike = AbiTypeToPrimitiveType<"int24">;

export type Spread = 1 | 2 | 3 | 4 | 5;

// export type LimitData = {
//   liquidity0To1: bigint;
//   liquidity1To0: bigint;
//   liquidity0InPerLiquidity: Fraction;
//   liquidity1InPerLiquidity: Fraction;
// };

export type StrikeData = {
  // limitData: LimitData;
  totalSupply: Tuple<bigint, typeof NUM_SPREADS>;
  liquidityBiDirectional: Tuple<bigint, typeof NUM_SPREADS>;
  liquidityBorrowed: Tuple<bigint, typeof NUM_SPREADS>;
  liquidityGrowth: Fraction;
  next0To1: Strike;
  next1To0: Strike;
  activeSpread: 0 | 1 | 2 | 3 | 4;
};

export type BitMap = {
  centerStrike: Strike;
  words: Tuple<bigint, 3>;
};

export type PairData = {
  strikes: { [strike: Strike]: StrikeData };
  bitMap0To1: BitMap;
  bitMap1To0: BitMap;
  composition: Tuple<Fraction, typeof NUM_SPREADS>;
  strikeCurrent: Tuple<Strike, typeof NUM_SPREADS>;
  cachedStrikeCurrent: Strike;
  cachedBlock: bigint;
  initialized: boolean;
};

export type TokenSelector = keyof typeof TokenSelectorEnum;

export type OrderType = keyof typeof OrderTypeEnum;

type CommandType<
  TCommand extends keyof typeof CommandEnum,
  TInput extends object,
> = { command: TCommand; inputs: TInput };

export type CreatePairCommand = CommandType<
  "CreatePair",
  {
    pair: Pair;
    strike: Strike;
  }
>;

export type AddLiquidityCommand = CommandType<
  "AddLiquidity",
  {
    pair: Pair;
    strike: Strike;
    spread: Spread;
    tokenSelector: TokenSelector;
    amountDesired: bigint;
  }
>;

export type RemoveLiquidityCommands = CommandType<
  "RemoveLiquidity",
  {
    pair: Pair;
    strike: Strike;
    spread: Spread;
    tokenSelector: TokenSelector;
    amountDesired: bigint;
  }
>;

export type BorrowLiquidityCommand = CommandType<
  "BorrowLiquidity",
  {
    pair: Pair;
    strike: Strike;
    selectorCollateral: Exclude<TokenSelector, "LiquidityPosition">;
    amountDesiredCollateral: bigint;
    // selectorDebt: TokenSelector;
    amountDesiredDebt: bigint;
  }
>;

export type RepayLiquidityCommand = CommandType<
  "RepayLiquidity",
  {
    pair: Pair;
    strike: Strike;
    selectorCollateral: Exclude<TokenSelector, "LiquidityPosition">;
    leverageRatio: Fraction;
    // selectorDebt: TokenSelector;
    amountDesiredDebt: bigint;
  }
>;

export type SwapCommand = CommandType<
  "Swap",
  {
    pair: Pair;
    amountDesired: CurrencyAmount<Pair["token0"] | Pair["token1"]>;
  }
>;

export type AccrueCommand = CommandType<
  "Accrue",
  {
    pair: Pair;
  }
>;

export type Command =
  | CreatePairCommand
  | AddLiquidityCommand
  | RemoveLiquidityCommands
  | BorrowLiquidityCommand
  | RepayLiquidityCommand
  | SwapCommand
  | AccrueCommand;
