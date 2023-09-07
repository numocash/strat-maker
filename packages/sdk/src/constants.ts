import { createFraction } from "reverse-mirage";
import { getAddress } from "viem";

export const NUM_SPREADS = 5;
export const Q128 = 2n ** 128n;
export const MAX_STRIKE = 776_363;
export const MIN_STRIKE = -776_363;
export const MIN_MULTIPLIER = createFraction(1, 2000);

export const EngineAddress = getAddress(
  "0x124ddf9bdd2ddad012ef1d5bbd77c00f05c610da",
);

export const RouterAddress = getAddress(
  "0xe044814c9ed1e6442af956a817c161192cbae98f",
);

export const TokenSelectorEnum = {
  Token0: 0,
  Token1: 1,
} as const;

export const SwapTokenSelectorEnum = {
  Token0: 0,
  Token1: 1,
  Account: 2,
} as const;

export const OrderTypeEnum = {
  BiDirectional: 0,
  Debt: 1,
} as const;

export const CommandEnum = {
  Swap: 0,
  WrapWETH: 1,
  UnwrapWETH: 2,
  AddLiquidity: 3,
  RemoveLiquidity: 4,
  BorrowLiquidity: 5,
  RepayLiquidity: 6,
  Accrue: 7,
  CreatePair: 8,
} as const;
