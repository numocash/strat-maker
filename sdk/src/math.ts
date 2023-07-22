import { Q128 } from "./constants.js";
import type { PositionData } from "./positions.js";
import type { Pair, PairData, Spread, Strike } from "./types.js";
import { fractionToQ128, q128ToFraction } from "./utils.js";
import {
  type CurrencyAmount,
  type Fraction,
  MaxUint128,
  MaxUint256,
  type Token,
  currencyEqualTo,
  fractionAdd,
  fractionDivide,
  fractionMultiply,
} from "reverse-mirage";
import invariant from "tiny-invariant";

export const getAmount0Delta = (liquidity: bigint, strike: Strike): bigint => {
  const ratio = getRatioAtStrike(strike);
  return (liquidity * ratio.denominator) / ratio.numerator;
};

export const getAmount1Delta = (liquidity: bigint) => liquidity;

export const getLiquidityDeltaAmount0 = (
  amount0: bigint,
  strike: Strike,
): bigint => {
  const ratio = getRatioAtStrike(strike);
  return (amount0 * ratio.numerator) / ratio.denominator;
};

export const getLiquidityDeltaAmount1 = (amount1: bigint): bigint => amount1;

export const getAmount0FromComposition = (
  composition: Fraction,
  liquidity: bigint,
  strike: Strike,
): bigint => {
  const ratio = getRatioAtStrike(strike);
  return (
    (liquidity *
      (MaxUint128 - fractionToQ128(composition)) *
      ratio.denominator) /
    (Q128 * ratio.numerator)
  );
};

export const getAmount1FromComposition = (
  composition: Fraction,
  liquidity: bigint,
  strike: Strike,
): bigint => {
  const ratio = getRatioAtStrike(strike);
  return (
    (liquidity * fractionToQ128(composition) * ratio.denominator) /
    (Q128 * ratio.numerator)
  );
};

export const getAmount0ForLiquidity = (
  pairData: PairData,
  strike: Strike,
  spread: Spread,
  liquidity: bigint,
): bigint => {
  const strikeCurrent = pairData.strikeCurrent[spread - 1]!;

  if (strike > strikeCurrent) return getAmount0Delta(liquidity, strike);
  else if (strike === strikeCurrent) {
    const composition = pairData.composition[spread - 1]!;
    return getAmount0FromComposition(composition, liquidity, strike);
  } else return 0n;
};

export const getAmount1ForLiquidity = (
  pairData: PairData,
  strike: Strike,
  spread: Spread,
  liquidity: bigint,
): bigint => {
  const strikeCurrent = pairData.strikeCurrent[spread - 1]!;

  if (strike < strikeCurrent) return getAmount1Delta(liquidity);
  else if (strike === strikeCurrent) {
    const composition = pairData.composition[spread - 1]!;
    return getAmount1FromComposition(composition, liquidity, strike);
  } else return 0n;
};

export const getAmountsForLiquidity = (
  pairData: PairData,
  strike: Strike,
  spread: Spread,
  liquidity: bigint,
): [bigint, bigint] => {
  const strikeCurrent = pairData.strikeCurrent[spread - 1]!;

  if (strike > strikeCurrent) {
    return [getAmount0Delta(liquidity, strike), 0n];
  } else if (strike < strikeCurrent) {
    return [0n, getAmount1Delta(liquidity)];
  } else {
    const composition = pairData.composition[spread - 1]!;
    return [
      getAmount0FromComposition(composition, liquidity, strike),
      getAmount1FromComposition(composition, liquidity, strike),
    ];
  }
};

export const getLiquidityForAmount0 = (
  pairData: PairData,
  strike: Strike,
  spread: Spread,
  amount0: bigint,
): bigint => {
  const strikeCurrent = pairData.strikeCurrent[spread - 1]!;

  if (strike > strikeCurrent) return getLiquidityDeltaAmount0(amount0, strike);
  else if (strike === strikeCurrent) {
    const ratio = getRatioAtStrike(strike);
    const composition = pairData.composition[spread - 1]!;
    return (
      (amount0 * ratio.numerator * Q128) /
      (ratio.denominator * (MaxUint128 - fractionToQ128(composition)))
    );
  } else return 0n;
};

export const getLiquidityForAmount1 = (
  pairData: PairData,
  strike: Strike,
  spread: Spread,
  amount1: bigint,
): bigint => {
  const strikeCurrent = pairData.strikeCurrent[spread - 1]!;

  if (strike < strikeCurrent) return getLiquidityDeltaAmount1(amount1);
  else if (strike === strikeCurrent) {
    const ratio = getRatioAtStrike(strike);
    const composition = pairData.composition[spread - 1]!;
    return (
      (amount1 * ratio.numerator * Q128) /
      (ratio.denominator * fractionToQ128(composition))
    );
  } else return 0n;
};

export const balanceToLiquidity = (
  pairData: PairData,
  strike: Strike,
  spread: Spread,
  balance: bigint,
): bigint => {
  1;
  const totalSupply = pairData.strikes[strike]!.totalSupply[spread - 1]!;
  if (totalSupply === 0n) return balance;

  const totalLiquidity =
    pairData.strikes[strike]!.liquidityBorrowed[spread - 1]! +
    pairData.strikes[strike]!.liquidityBiDirectional[spread - 1]!;

  return (balance * totalLiquidity) / totalSupply;
};

export const liquidityToBalance = (
  pairData: PairData,
  strike: Strike,
  spread: Spread,
  liquidity: bigint,
): bigint => {
  const totalSupply = pairData.strikes[strike]!.totalSupply[spread - 1]!;

  const totalLiquidity =
    pairData.strikes[strike]!.liquidityBorrowed[spread - 1]! +
    pairData.strikes[strike]!.liquidityBiDirectional[spread - 1]!;

  return (liquidity * totalSupply) / totalLiquidity;
};

export const debtBalanceToLiquidity = (
  balance: bigint,
  liquidityGrowth: Fraction,
): bigint =>
  (balance * liquidityGrowth.denominator * Q128) /
  (liquidityGrowth.numerator + Q128);

export const debtLiquidityToBalance = (
  liquidity: bigint,
  liquidityGrowth: Fraction,
): bigint =>
  (liquidity * (liquidityGrowth.numerator + Q128)) /
  (liquidityGrowth.denominator * Q128);

export const getRatioAtStrike = (strike: Strike): Fraction => {
  const x = strike < 0 ? -strike : strike;
  let ratioX128: bigint = Q128;

  if ((x & 0x1) > 0)
    ratioX128 = (ratioX128 * 0xfff97272373d413259a407b06395f90fn) >> 128n;
  if ((x & 0x2) > 0)
    ratioX128 = (ratioX128 * 0xfff2e50f5f656932ef1171c20d94409bn) >> 128n;
  if ((x & 0x4) > 0)
    ratioX128 = (ratioX128 * 0xffe5caca7e10e4e61c349d88de59ee79n) >> 128n;
  if ((x & 0x8) > 0)
    ratioX128 = (ratioX128 * 0xffcb9843d60f6159c9d84a0ffaab939bn) >> 128n;
  if ((x & 0x10) > 0)
    ratioX128 = (ratioX128 * 0xff973b41fa98c08147284cf074e387d5n) >> 128n;
  if ((x & 0x20) > 0)
    ratioX128 = (ratioX128 * 0xff2ea16466c96a3843e046662bb67727n) >> 128n;
  if ((x & 0x40) > 0)
    ratioX128 = (ratioX128 * 0xfe5dee046a99a2a811ac114ac614ac9cn) >> 128n;
  if ((x & 0x80) > 0)
    ratioX128 = (ratioX128 * 0xfcbe86c7900a88aedccf765871cd46e5n) >> 128n;
  if ((x & 0x100) > 0)
    ratioX128 = (ratioX128 * 0xf987a7253ac413176ecb9e29f4d08c52n) >> 128n;
  if ((x & 0x200) > 0)
    ratioX128 = (ratioX128 * 0xf3392b0822b7000593527a95f936c282n) >> 128n;
  if ((x & 0x400) > 0)
    ratioX128 = (ratioX128 * 0xe7159475a2c29b7442512e1cbb578357n) >> 128n;
  if ((x & 0x800) > 0)
    ratioX128 = (ratioX128 * 0xd097f3bdfd2022b881dcc82b04dd48c5n) >> 128n;
  if ((x & 0x1000) > 0)
    ratioX128 = (ratioX128 * 0xa9f746462d870fdf86560b5c522cf05fn) >> 128n;
  if ((x & 0x2000) > 0)
    ratioX128 = (ratioX128 * 0x70d869a156d2a1b88b568394a9e07f2bn) >> 128n;
  if ((x & 0x4000) > 0)
    ratioX128 = (ratioX128 * 0x31be135f97d08fd97c61d38210d0ed17n) >> 128n;
  if ((x & 0x8000) > 0)
    ratioX128 = (ratioX128 * 0x9aa508b5b7a84e1c49ed3ab387b721en) >> 128n;
  if ((x & 0x10000) > 0)
    ratioX128 = (ratioX128 * 0x5d6af8dedb811966760afd60167cf2n) >> 128n;
  if ((x & 0x20000) > 0)
    ratioX128 = (ratioX128 * 0x2216e584f5fa1ea90bf2722b93a1n) >> 128n;
  if ((x & 0x40000) > 0)
    ratioX128 = (ratioX128 * 0x48a170391f7dc423d5d34c2n) >> 128n;
  if ((x & 0x80000) > 0) ratioX128 = (ratioX128 * 0x149b34ee7ac262n) >> 128n;
  // Stop computation here since |strike| < 2**20

  // Inverse r since base = 1/1.0001
  if (strike > 0) ratioX128 = MaxUint256 / ratioX128;

  return q128ToFraction(ratioX128);
};

export const computeSwapStep = (
  pair: Pair,
  strike: Strike,
  liquidity: bigint,
  amountDesired: CurrencyAmount<Token>,
): { amountIn: bigint; amountOut: bigint; liquidityRemaining: bigint } => {
  const isExactIn = amountDesired.amount > 0;
  const isToken0 = currencyEqualTo(pair.token0, amountDesired.currency);
  const ratio = getRatioAtStrike(strike);

  if (isExactIn) {
    const maxAmountIn = isToken0
      ? getAmount0Delta(liquidity, strike)
      : getAmount1Delta(liquidity);

    const amountIn =
      amountDesired.amount > maxAmountIn ? maxAmountIn : amountDesired.amount;
    const amountOut = isToken0
      ? (amountIn * ratio.numerator) / ratio.denominator
      : (amountIn * ratio.denominator) / ratio.numerator;
    const liquidityRemaining =
      amountDesired.amount > maxAmountIn
        ? 0n
        : isToken0
        ? getLiquidityDeltaAmount0(maxAmountIn - amountDesired.amount, strike)
        : getLiquidityDeltaAmount1(maxAmountIn - amountDesired.amount);
    return { amountIn, amountOut, liquidityRemaining };
  } else {
    const maxAmountOut = isToken0
      ? getAmount0Delta(liquidity, strike)
      : getAmount1Delta(liquidity);

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
        ? getLiquidityDeltaAmount0(maxAmountOut + amountDesired.amount, strike)
        : getLiquidityDeltaAmount1(maxAmountOut + amountDesired.amount);
    return { amountIn, amountOut, liquidityRemaining };
  }
};

export const addDebtPositions = (
  position0: PositionData<"Debt">,
  position1: PositionData<"Debt">,
): PositionData<"Debt"> => {
  invariant(position0.position !== position1.position);

  const collateral0 = fractionMultiply(
    position0.data.leverageRatio,
    position0.balance,
  );
  const collateral1 = fractionMultiply(
    position1.data.leverageRatio,
    position1.balance,
  );

  return {
    balance: position0.balance + position1.balance,
    position: position0.position,
    data: {
      leverageRatio: fractionDivide(
        fractionAdd(collateral0, collateral1),
        position0.balance + position1.balance,
      ),
    },
  };
};
