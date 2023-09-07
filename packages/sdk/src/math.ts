import {
  type ERC20,
  type ERC20Amount,
  type Fraction,
  MaxUint128,
  MaxUint256,
  fractionDivide,
  fractionMultiply,
  fractionQuotient,
  fractionSubtract,
} from "reverse-mirage";
import invariant from "tiny-invariant";
import { Q128 } from "./constants.js";
import type { Pair, PairData, Spread, Strike } from "./types.js";
import { fractionToQ128, q128ToFraction } from "./utils.js";

export const scaleLiquidityUp = (liquidity: bigint, scalingFactor: number) =>
  liquidity << BigInt(scalingFactor);

export const scaleLiquidityDown = (liquidity: bigint, scalingFactor: number) =>
  liquidity >> BigInt(scalingFactor);

export const getAmount0 = (
  liquidity: bigint,
  strike: Strike,
  roundUp: boolean,
): bigint => {
  const ratio = getRatioAtStrike(strike);
  const numerator = liquidity * ratio.denominator;
  return roundUp
    ? numerator % ratio.numerator !== 0n
      ? numerator / ratio.numerator + 1n
      : numerator / ratio.numerator
    : numerator / ratio.numerator;
};

export const getAmount1 = (liquidity: bigint) => liquidity;

export const getLiquidityForAmount0 = (
  amount0: bigint,
  strike: Strike,
): bigint => {
  const ratio = getRatioAtStrike(strike);
  return (amount0 * ratio.numerator) / ratio.denominator;
};

export const getLiquidityForAmount1 = (amount1: bigint): bigint => amount1;

export const getAmount0Composition = (
  composition: Fraction,
  liquidity: bigint,
  strike: Strike,
  roundUp: boolean,
): bigint => {
  const ratio = getRatioAtStrike(strike);

  const numerator =
    liquidity * (MaxUint128 - fractionToQ128(composition)) * ratio.denominator;
  const denominator = Q128 * ratio.numerator;

  return roundUp
    ? numerator % denominator !== 0n
      ? numerator / denominator + 1n
      : numerator / denominator
    : numerator / denominator;
};

export const getAmount1Composition = (
  composition: Fraction,
  liquidity: bigint,
  strike: Strike,
  roundUp: boolean,
): bigint => {
  const ratio = getRatioAtStrike(strike);

  const numerator = liquidity * fractionToQ128(composition) * ratio.numerator;
  const denominator = Q128 * ratio.numerator;

  return roundUp
    ? numerator % denominator !== 0n
      ? numerator / denominator + 1n
      : numerator / denominator
    : numerator / denominator;
};

export const getAmounts = (
  pairData: PairData,
  strike: Strike,
  spread: Spread,
  liquidity: bigint,
  roundUp: boolean,
): [bigint, bigint] => {
  const strikeCurrent = pairData.strikeCurrent[spread - 1]!;

  if (strike > strikeCurrent) {
    return [getAmount0(liquidity, strike, roundUp), 0n];
  } else if (strike < strikeCurrent) {
    return [0n, getAmount1(liquidity)];
  } else {
    const composition = pairData.composition[spread - 1]!;
    return [
      getAmount0Composition(composition, liquidity, strike, roundUp),
      getAmount1Composition(composition, liquidity, strike, roundUp),
    ];
  }
};

export const balanceToLiquidity = (
  balance: bigint,
  liquidityGrowth: Fraction,
): bigint => {
  const liquidity = fractionQuotient(
    fractionMultiply(liquidityGrowth, balance),
  );
  invariant(liquidity <= MaxUint128, "Overflow");
  return liquidity;
};

export const liquidityToBalance = (
  liquidity: bigint,
  liquidityGrowth: Fraction,
): bigint =>
  (liquidity * liquidityGrowth.denominator) / liquidityGrowth.numerator;

export const debtBalanceToLiquidity = (
  balance: bigint,
  multiplier: Fraction,
  liquidityGrowth: Fraction,
): bigint =>
  fractionQuotient(
    fractionMultiply(
      fractionDivide(fractionSubtract(multiplier, liquidityGrowth), multiplier),
      balance,
    ),
  );

export const getRatioAtStrike = (strike: Strike): Fraction => {
  const x = strike < 0 ? -strike : strike;
  let ratioX128: bigint = Q128;

  if ((x & 0x1) > 0)
    ratioX128 = (ratioX128 * 0xfffcb933bd6fad37aa2d162d1a594001n) >> 128n;
  if ((x & 0x2) > 0)
    ratioX128 = (ratioX128 * 0xfff97272373d413259a46990580e213an) >> 128n;
  if ((x & 0x4) > 0)
    ratioX128 = (ratioX128 * 0xfff2e50f5f656932ef12357cf3c7fdccn) >> 128n;
  if ((x & 0x8) > 0)
    ratioX128 = (ratioX128 * 0xffe5caca7e10e4e61c3624eaa0941cd0n) >> 128n;
  if ((x & 0x10) > 0)
    ratioX128 = (ratioX128 * 0xffcb9843d60f6159c9db58835c926644n) >> 128n;
  if ((x & 0x20) > 0)
    ratioX128 = (ratioX128 * 0xff973b41fa98c081472e6896dfb254c0n) >> 128n;
  if ((x & 0x40) > 0)
    ratioX128 = (ratioX128 * 0xff2ea16466c96a3843ec78b326b52861n) >> 128n;
  if ((x & 0x80) > 0)
    ratioX128 = (ratioX128 * 0xfe5dee046a99a2a811c461f1969c3053n) >> 128n;
  if ((x & 0x100) > 0)
    ratioX128 = (ratioX128 * 0xfcbe86c7900a88aedcffc83b479aa3a4n) >> 128n;
  if ((x & 0x200) > 0)
    ratioX128 = (ratioX128 * 0xf987a7253ac413176f2b074cf7815e54n) >> 128n;
  if ((x & 0x400) > 0)
    ratioX128 = (ratioX128 * 0xf3392b0822b70005940c7a398e4b70f3n) >> 128n;
  if ((x & 0x800) > 0)
    ratioX128 = (ratioX128 * 0xe7159475a2c29b7443b29c7fa6e889d9n) >> 128n;
  if ((x & 0x1000) > 0)
    ratioX128 = (ratioX128 * 0xd097f3bdfd2022b8845ad8f792aa5825n) >> 128n;
  if ((x & 0x2000) > 0)
    ratioX128 = (ratioX128 * 0xa9f746462d870fdf8a65dc1f90e061e5n) >> 128n;
  if ((x & 0x4000) > 0)
    ratioX128 = (ratioX128 * 0x70d869a156d2a1b890bb3df62baf32f7n) >> 128n;
  if ((x & 0x8000) > 0)
    ratioX128 = (ratioX128 * 0x31be135f97d08fd981231505542fcfa6n) >> 128n;
  if ((x & 0x10000) > 0)
    ratioX128 = (ratioX128 * 0x9aa508b5b7a84e1c677de54f3e99bc9n) >> 128n;
  if ((x & 0x20000) > 0)
    ratioX128 = (ratioX128 * 0x5d6af8dedb81196699c329225ee604n) >> 128n;
  if ((x & 0x40000) > 0)
    ratioX128 = (ratioX128 * 0x2216e584f5fa1ea926041bedfe98n) >> 128n;
  if ((x & 0x80000) > 0)
    ratioX128 = (ratioX128 * 0x48a170391f7dc42444e8fa2n) >> 128n;
  // Stop computation here since |strike| < 2**20

  // Inverse r since base = 1/1.0001
  ratioX128 = (ratioX128 * ratioX128) / Q128;
  if (strike > 0) ratioX128 = MaxUint256 / ratioX128;

  return q128ToFraction(ratioX128);
};

export const computeSwapStep = (
  pair: Pair,
  strike: Strike,
  liquidity: bigint,
  amountDesired: ERC20Amount<ERC20>,
): { amountIn: bigint; amountOut: bigint; liquidityRemaining: bigint } => {
  const isExactIn = amountDesired.amount > 0;
  const isToken0 = pair.token0 === amountDesired.token;
  const ratio = getRatioAtStrike(strike);

  if (isExactIn) {
    const maxAmountIn = isToken0
      ? getAmount0(liquidity, strike, true)
      : getAmount1(liquidity);

    const amountIn =
      amountDesired.amount > maxAmountIn ? maxAmountIn : amountDesired.amount;
    const amountOut = isToken0
      ? (amountIn * ratio.numerator) / ratio.denominator
      : (amountIn * ratio.denominator) / ratio.numerator;
    const liquidityRemaining =
      amountDesired.amount > maxAmountIn
        ? 0n
        : isToken0
        ? getLiquidityForAmount0(maxAmountIn - amountDesired.amount, strike)
        : getLiquidityForAmount1(maxAmountIn - amountDesired.amount);
    return { amountIn, amountOut, liquidityRemaining };
  } else {
    const maxAmountOut = isToken0
      ? getAmount0(liquidity, strike, false)
      : getAmount1(liquidity);

    const amountOut =
      -amountDesired.amount > maxAmountOut
        ? maxAmountOut
        : -amountDesired.amount;
    const amountIn = isToken0
      ? (amountOut * ratio.numerator) / ratio.denominator
      : (amountOut * ratio.denominator) / ratio.numerator;
    const liquidityRemaining =
      -amountDesired.amount > maxAmountOut
        ? 0n
        : isToken0
        ? getLiquidityForAmount0(maxAmountOut + amountDesired.amount, strike)
        : getLiquidityForAmount1(maxAmountOut + amountDesired.amount);
    return { amountIn, amountOut, liquidityRemaining };
  }
};
