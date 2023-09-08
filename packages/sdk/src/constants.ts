import { createFraction } from "reverse-mirage";
import { getAddress } from "viem";

export const NUM_SPREADS = 5;
export const Q128 = 2n ** 128n;
export const MAX_STRIKE = 776_363;
export const MIN_STRIKE = -776_363;
export const MIN_MULTIPLIER = createFraction(1, 2000);

export const EngineAddress = getAddress(
  "0xe7f1725e7734ce288f8367e1bb143e90bb3f0512",
);

export const RouterAddress = getAddress(
  "0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0",
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
