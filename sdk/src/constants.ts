import { getAddress } from "viem";

export const NUM_SPREADS = 5;
export const Q128 = 2n ** 128n;
export const MAX_STRIKE = 887_272;
export const MIN_STRIKE = -887_272;

export const EngineAddress = getAddress(
  "0x124ddf9bdd2ddad012ef1d5bbd77c00f05c610da",
);

export const RouterAddress = getAddress(
  "0xe044814c9ed1e6442af956a817c161192cbae98f",
);

export const TokenSelectorEnum = {
  Token0: 0,
  Token1: 1,
  LiquidityPosition: 2,
} as const;

export const OrderTypeEnum = {
  BiDirectional: 0,
  // Limit: 1,
  Debt: 1,
} as const;

export const CommandEnum = {
  Swap: 0,
  AddLiquidity: 1,
  BorrowLiquidity: 2,
  RepayLiquidity: 3,
  RemoveLiquidity: 4,
  Accrue: 5,
  CreatePair: 6,
} as const;
