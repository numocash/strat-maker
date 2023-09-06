import type { AbiTypeToPrimitiveType } from "abitype";
import type { ERC20, Fraction } from "reverse-mirage";
import {
  CommandEnum,
  NUM_SPREADS,
  OrderTypeEnum,
  SwapTokenSelectorEnum,
  TokenSelectorEnum,
} from "./constants.js";

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

export type Pair = { token0: ERC20; token1: ERC20; scalingFactor: number };

export type Strike = AbiTypeToPrimitiveType<"int24">;

export type Spread = 1 | 2 | 3 | 4 | 5;

export type StrikeData = {
  liquidityGrowth: Fraction;
  blockLast: bigint;
  totalSupply: Tuple<bigint, typeof NUM_SPREADS>;
  liquidityBiDirectional: Tuple<bigint, typeof NUM_SPREADS>;
  liquidityBorrowed: Tuple<bigint, typeof NUM_SPREADS>;
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
  strikeCurrentCached: Strike;
  initialized: boolean;
};

export type TokenSelector = keyof typeof TokenSelectorEnum;

export type SwapTokenSelector = keyof typeof SwapTokenSelectorEnum;

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
    amountDesired: bigint;
  }
>;

export type RemoveLiquidityCommands = CommandType<
  "RemoveLiquidity",
  {
    pair: Pair;
    strike: Strike;
    spread: Spread;
    amountDesired: bigint;
  }
>;

export type BorrowLiquidityCommand = CommandType<
  "BorrowLiquidity",
  {
    pair: Pair;
    strike: Strike;
    selectorCollateral: TokenSelector;
    amountDesiredCollateral: bigint;
    amountDesiredDebt: bigint;
  }
>;

export type RepayLiquidityCommand = CommandType<
  "RepayLiquidity",
  {
    pair: Pair;
    strike: Strike;
    selectorCollateral: TokenSelector;
    leverageRatio: Fraction;
    amountDesiredDebt: bigint;
  }
>;

export type SwapCommand = CommandType<
  "Swap",
  {
    pair: Pair;
    selector: SwapTokenSelector;
    amountDesired: bigint;
  }
>;

export type AccrueCommand = CommandType<
  "Accrue",
  {
    pair: Pair;
    strike: Strike;
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
