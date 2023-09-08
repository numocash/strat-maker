import type { AbiTypeToPrimitiveType } from "abitype";
import type { ERC20, ERC20Amount, Fraction } from "reverse-mirage";
import {
  CommandEnum,
  NUM_SPREADS,
  OrderTypeEnum,
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
  liquidityRepayRate: Fraction;
  liquidityGrowthSpread: Tuple<Fraction, typeof NUM_SPREADS>;
  liquidity: Tuple<{ swap: bigint; borrowed: bigint }, typeof NUM_SPREADS>;
  blockLast: bigint;
  next0To1: Strike;
  next1To0: Strike;
  // reference0To1: Set<Spread>;
  // reference1To0: Set<Spread>;
  activeSpread: 0 | 1 | 2 | 3 | 4;
};

export type BitMap = {
  centerStrike: Strike;
  words: Tuple<bigint, 3>;
};

export type PairData = {
  strikes: { [strike: Strike]: StrikeData };
  // bitMap0To1: BitMap;
  // bitMap1To0: BitMap;
  composition: Tuple<Fraction, typeof NUM_SPREADS>;
  strikeCurrent: Tuple<Strike, typeof NUM_SPREADS>;
  initialized: boolean;
};

export type TokenSelector = keyof typeof TokenSelectorEnum;

export type OrderType = keyof typeof OrderTypeEnum;

type CommandType<
  TCommand extends keyof typeof CommandEnum,
  TInput extends object,
> = { command: TCommand; inputs: TInput };

export type SwapCommand<TPair extends Pair = Pair> = CommandType<
  "Swap",
  {
    pair: TPair;
    amountDesired:
      | ERC20Amount<TPair["token0"] | TPair["token1"]>
      | "Token0Account"
      | "Token1Account";
  }
>;

export type WrapWETHCommand = CommandType<"WrapWETH", {}>;

export type UnwrapWETHCommand = CommandType<"UnwrapWETH", {}>;

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
    amountDesiredCollateral: ERC20Amount<Pair["token0"] | Pair["token1"]>;
    amountDesiredDebt: bigint;
  }
>;

export type RepayLiquidityCommand = CommandType<
  "RepayLiquidity",
  {
    pair: Pair;
    strike: Strike;
    selectorCollateral: TokenSelector;
    liquidityGrowthLast: Fraction;
    multiplier: Fraction;
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

export type CreatePairCommand = CommandType<
  "CreatePair",
  {
    pair: Pair;
    strike: Strike;
  }
>;

export type Command =
  | SwapCommand
  // | WrapWETHCommand
  // | UnwrapWETHCommand
  | AddLiquidityCommand
  | RemoveLiquidityCommands
  | BorrowLiquidityCommand
  | RepayLiquidityCommand
  | AccrueCommand
  | CreatePairCommand;
