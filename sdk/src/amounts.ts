import { MAX_STRIKE, MIN_STRIKE, NUM_SPREADS, Q128 } from "./constants.js";
import {
  balanceToLiquidity,
  computeSwapStep,
  debtBalanceToLiquidity,
  debtLiquidityToBalance,
  getAmount0Delta,
  getAmount0ForLiquidity,
  getAmount1Delta,
  getAmount1ForLiquidity,
  getAmountsForLiquidity,
  getLiquidityDeltaAmount0,
  getLiquidityDeltaAmount1,
  getLiquidityForAmount0,
  getLiquidityForAmount1,
  liquidityToBalance,
} from "./math.js";
import { type PositionData, makePosition } from "./positions.js";

import type {
  Pair,
  PairData,
  Spread,
  Strike,
  TokenSelector,
  Tuple,
} from "./types.js";
import {
  type CurrencyAmount,
  type Fraction,
  MaxUint128,
  currencyEqualTo,
  makeCurrencyAmountFromRaw,
  makeFraction,
} from "reverse-mirage";
import invariant from "tiny-invariant";

/**
 * Initialize a pair with the given initial strike
 * @param strike Initial strike
 * @returns The pair data of the new pair
 */
export const calculateInitialize = (strike: Strike): PairData => {
  checkStrike(strike);

  return {
    strikes: {
      [strike]: {
        // limitData: {
        //   liquidity0To1: 0n,
        //   liquidity1To0: 0n,
        //   liquidity0InPerLiquidity: makeFraction(0n),
        //   liquidity1InPerLiquidity: makeFraction(0n),
        // },
        totalSupply: [0n, 0n, 0n, 0n, 0n],
        liquidityBiDirectional: [0n, 0n, 0n, 0n, 0n],
        liquidityBorrowed: [0n, 0n, 0n, 0n, 0n],
        liquidityGrowth: makeFraction(0n),
        next0To1: 0,
        next1To0: 0,
        activeSpread: 0,
      },
    },
    bitMap0To1: {
      centerStrike: strike,
      words: [0n, 0n, 0n],
    },
    bitMap1To0: {
      centerStrike: strike,
      words: [0n, 0n, 0n],
    },
    composition: [
      makeFraction(0n),
      makeFraction(0n),
      makeFraction(0n),
      makeFraction(0n),
      makeFraction(0n),
    ],
    strikeCurrent: [strike, strike, strike, strike, strike],
    cachedStrikeCurrent: strike,
    cachedBlock: 0n,
    initialized: true,
  };
};

/**
 * Add liquidity to a pair
 * @param pair Immutable pair information
 * @param pairData Pair data before adding liquidity
 * @param block Current block
 * @param strike What strike to add liquidity to
 * @param spread What spread to impose on the liquidity
 * @param tokenSelector What should amount desired refer to
 * @param amountDesired The amount of the token that tokenSelector refers to that is to be added to the pair
 * @returns TODO: fill this out
 */
export const calculateAddLiquidity = (
  pair: Pair,
  pairData: PairData,
  block: bigint,
  strike: Strike,
  spread: Spread,
  tokenSelector: TokenSelector,
  amountDesired: bigint,
): {
  amount0: CurrencyAmount<Pair["token0"]>;
  amount1: CurrencyAmount<Pair["token1"]>;
  position: PositionData<"BiDirectional">;
} => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");

  pairData.cachedStrikeCurrent === strike &&
    calculateAccrue(pairData, strike, block);

  if (pairData.strikes[strike] === undefined)
    pairData.strikes[strike] = {
      // limitData: {
      //   liquidity0To1: 0n,
      //   liquidity1To0: 0n,
      //   liquidity0InPerLiquidity: makeFraction(0n),
      //   liquidity1InPerLiquidity: makeFraction(0n),
      // },
      totalSupply: [0n, 0n, 0n, 0n, 0n],
      liquidityBiDirectional: [0n, 0n, 0n, 0n, 0n],
      liquidityBorrowed: [0n, 0n, 0n, 0n, 0n],
      liquidityGrowth: makeFraction(0n),
      next0To1: 0,
      next1To0: 0,
      activeSpread: 0,
    };
  console.log(pairData.strikes);

  let balance: bigint;
  let liquidity: bigint;
  let amount0: bigint;
  let amount1: bigint;

  if (tokenSelector === "LiquidityPosition") {
    balance = amountDesired;
    liquidity = balanceToLiquidity(pairData, strike, spread, balance);
    [amount0, amount1] = getAmountsForLiquidity(
      pairData,
      strike,
      spread,
      liquidity,
    );
  } else {
    if (tokenSelector === "Token0") {
      liquidity = getLiquidityForAmount0(
        pairData,
        strike,
        spread,
        amountDesired,
      );
      amount0 = amountDesired;
      amount1 = getAmount1ForLiquidity(pairData, strike, spread, liquidity);
    } else {
      liquidity = getLiquidityForAmount1(
        pairData,
        strike,
        spread,
        amountDesired,
      );
      amount0 = getAmount0ForLiquidity(pairData, strike, spread, liquidity);
      amount1 = amountDesired;
    }

    balance = liquidityToBalance(pairData, strike, spread, liquidity);
  }

  updateStrike(pairData, strike, spread, balance, liquidity);

  return {
    amount0: makeCurrencyAmountFromRaw(pair.token0, amount0),
    amount1: makeCurrencyAmountFromRaw(pair.token1, amount1),
    position: {
      position: makePosition("BiDirectional", {
        token0: pair.token0,
        token1: pair.token1,
        scalingFactor: pair.scalingFactor,
        strike,
        spread,
      }),
      balance,
      data: {},
    },
  };
};

export const calculateRemoveLiquidity = (
  pair: Pair,
  pairData: PairData,
  block: bigint,
  strike: Strike,
  spread: Spread,
  tokenSelector: TokenSelector,
  amountDesired: bigint,
): {
  amount0: CurrencyAmount<Pair["token0"]>;
  amount1: CurrencyAmount<Pair["token1"]>;
  position: PositionData<"BiDirectional">;
} => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");

  pairData.cachedStrikeCurrent === strike &&
    calculateAccrue(pairData, strike, block);

  let balance: bigint;
  let liquidity: bigint;
  let amount0: bigint;
  let amount1: bigint;

  if (tokenSelector === "LiquidityPosition") {
    balance = amountDesired;
    liquidity = balanceToLiquidity(pairData, strike, spread, balance);
    [amount0, amount1] = getAmountsForLiquidity(
      pairData,
      strike,
      spread,
      liquidity,
    );
  } else {
    if (tokenSelector === "Token0") {
      liquidity = getLiquidityForAmount0(
        pairData,
        strike,
        spread,
        amountDesired,
      );
      amount0 = amountDesired;
      amount1 = getAmount1ForLiquidity(pairData, strike, spread, liquidity);
    } else {
      liquidity = getLiquidityForAmount1(
        pairData,
        strike,
        spread,
        amountDesired,
      );
      amount0 = getAmount0ForLiquidity(pairData, strike, spread, liquidity);
      amount1 = amountDesired;
    }

    balance = liquidityToBalance(pairData, strike, spread, liquidity);
  }

  updateStrike(pairData, strike, spread, -balance, -liquidity);

  return {
    amount0: makeCurrencyAmountFromRaw(pair.token0, -amount0),
    amount1: makeCurrencyAmountFromRaw(pair.token1, -amount1),
    position: {
      position: makePosition("BiDirectional", {
        token0: pair.token0,
        token1: pair.token1,
        scalingFactor: pair.scalingFactor,
        strike,
        spread,
      }),
      balance: -balance,
      data: {},
    },
  };
};

export const calculateBorrowLiquidity = (
  pair: Pair,
  pairData: PairData,
  strike: Strike,
  selectorCollateral: Exclude<TokenSelector, "LiquidityPosition">,
  amountDesiredCollateral: bigint,
  // selectorDebt: TokenSelector,
  amountDesiredDebt: bigint,
): {
  amount0: CurrencyAmount<Pair["token0"]>;
  amount1: CurrencyAmount<Pair["token1"]>;
  position: PositionData<"Debt">;
} => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");

  const liquidity = amountDesiredDebt;
  let amount0 = 0n;
  let amount1 = 0n;

  if (strike > pairData.cachedStrikeCurrent) {
    amount0 = -getAmount0Delta(liquidity, strike);
  } else {
    amount1 = -getAmount1Delta(liquidity);
  }

  borrowLiquidity(pairData, strike, liquidity);

  let liquidityCollateral: bigint;
  if (selectorCollateral === "Token0") {
    amount0 += amountDesiredCollateral;
    liquidityCollateral = getLiquidityDeltaAmount0(
      amountDesiredCollateral,
      strike,
    );
  } else {
    amount1 += amountDesiredCollateral;
    liquidityCollateral = getLiquidityDeltaAmount1(amountDesiredCollateral);
  }
  const balance = debtLiquidityToBalance(
    liquidity,
    pairData.strikes[strike]!.liquidityGrowth,
  );
  // TODO: is this right
  const leverageRatio = makeFraction(liquidityCollateral, balance);

  return {
    amount0: makeCurrencyAmountFromRaw(pair.token0, amount0),
    amount1: makeCurrencyAmountFromRaw(pair.token1, amount1),
    position: {
      position: makePosition("Debt", {
        token0: pair.token0,
        token1: pair.token1,
        scalingFactor: pair.scalingFactor,
        strike,
        selectorCollateral,
      }),
      balance,
      data: { leverageRatio },
    },
  };
};

export const calculateRepayLiquidity = (
  pair: Pair,
  pairData: PairData,
  strike: Strike,
  selectorCollateral: Exclude<TokenSelector, "LiquidityPosition">,
  leverageRatio: Fraction,
  // selectorDebt: TokenSelector,
  amountDesiredDebt: bigint,
): {
  amount0: CurrencyAmount<Pair["token0"]>;
  amount1: CurrencyAmount<Pair["token1"]>;
  position: PositionData<"Debt">;
} => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");

  const balance = amountDesiredDebt;
  const liquidity = debtBalanceToLiquidity(
    balance,
    pairData.strikes[strike]!.liquidityGrowth,
  );
  let amount0: bigint;
  let amount1: bigint;

  [amount0, amount1] = getAmountsForLiquidity(
    pairData,
    strike,
    (pairData.strikes[strike]!.activeSpread + 1) as Spread,
    liquidity,
  );

  repayLiquidity(pairData, strike, liquidity);

  const liquidityCollateral =
    (balance * leverageRatio.numerator) / leverageRatio.denominator -
    2n * (balance - liquidity);

  if (selectorCollateral === "Token0") {
    amount0 -= getAmount0Delta(liquidityCollateral, strike);
  } else {
    amount1 -= getAmount1Delta(liquidityCollateral);
  }

  return {
    amount0: makeCurrencyAmountFromRaw(pair.token0, amount0),
    amount1: makeCurrencyAmountFromRaw(pair.token1, amount1),
    position: {
      position: makePosition("Debt", {
        token0: pair.token0,
        token1: pair.token1,
        scalingFactor: pair.scalingFactor,
        strike,
        selectorCollateral,
      }),
      balance: -balance,
      data: { leverageRatio },
    },
  };
};

// TODO: load strikes conditionally
export const calculateSwap = (
  pair: Pair,
  pairData: PairData,
  amountDesired: CurrencyAmount<Pair["token0"] | Pair["token1"]>,
): {
  amount0: CurrencyAmount<Pair["token0"]>;
  amount1: CurrencyAmount<Pair["token1"]>;
} => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");

  const isSwap0To1 =
    amountDesired.amount > 0 ===
    currencyEqualTo(amountDesired.currency, pair.token0);

  const swapState: {
    liquiditySwap: bigint;
    liquidityTotal: bigint;
    liquiditySwapSpread: Tuple<bigint, typeof NUM_SPREADS>;
    liquidityTotalSpread: Tuple<bigint, typeof NUM_SPREADS>;
    amountA: bigint;
    amountB: bigint;
    amountDesired: CurrencyAmount<Pair["token0"] | Pair["token1"]>;
  } = {
    liquiditySwap: 0n,
    liquidityTotal: 0n,
    liquiditySwapSpread: [0n, 0n, 0n, 0n, 0n],
    liquidityTotalSpread: [0n, 0n, 0n, 0n, 0n],
    amountA: 0n,
    amountB: 0n,
    amountDesired: makeCurrencyAmountFromRaw(
      amountDesired.currency,
      amountDesired.amount,
    ),
  };

  for (let i = 1; i <= NUM_SPREADS; i++) {
    const activeStrike = isSwap0To1
      ? pairData.cachedStrikeCurrent + i
      : pairData.cachedStrikeCurrent - i;
    const spreadStrikeCurrent = pairData.strikeCurrent[i]!;

    if (activeStrike === spreadStrikeCurrent) {
      const liquidityTotal =
        pairData.strikes[activeStrike]!.liquidityBiDirectional[i - 1]!;
      const liquditySwap =
        ((isSwap0To1
          ? pairData.composition[i - 1]!.numerator
          : MaxUint128 - pairData.composition[i - 1]!.numerator) *
          liquidityTotal) /
        pairData.composition[i - 1]!.denominator;

      swapState.liquiditySwap += liquditySwap;
      swapState.liquidityTotal += liquidityTotal;
      swapState.liquiditySwapSpread[i - 1] = liquditySwap;
      swapState.liquidityTotalSpread[i - 1] = liquidityTotal;
    } else {
      break;
    }
  }

  while (true) {
    const { amountIn, amountOut } = computeSwapStep(
      pair,
      pairData.cachedStrikeCurrent,
      swapState.liquiditySwap,
      swapState.amountDesired,
    );

    if (swapState.amountDesired.amount > 0) {
      swapState.amountDesired.amount -= amountIn;
      swapState.amountA += amountIn;
      swapState.amountB -= amountOut;
    } else {
      swapState.amountDesired.amount += amountOut;
      swapState.amountA -= amountOut;
      swapState.amountB += amountIn;
    }

    // calculate fees

    if (swapState.amountDesired.amount === 0n) {
      // calculate composition
      break;
    }

    // move to next strike
    if (isSwap0To1) {
      pairData.cachedStrikeCurrent =
        pairData.strikes[pairData.cachedStrikeCurrent]!.next0To1;
      swapState.liquiditySwap = 0n;
      swapState.liquidityTotal = 0n;

      for (let i = 1; i <= NUM_SPREADS; i++) {
        const activeStrike = pairData.cachedStrikeCurrent + i;

        if (pairData.strikeCurrent[i - 1]! > activeStrike) {
          pairData.strikeCurrent[i - 1] = activeStrike;
          const liquidity =
            pairData.strikes[activeStrike]!.liquidityBiDirectional[i - 1]!;

          swapState.liquiditySwap = liquidity;
          swapState.liquidityTotal = liquidity;
          swapState.liquiditySwapSpread[i - 1] = liquidity;
          swapState.liquidityTotalSpread[i - 1] = liquidity;
        } else if (pairData.strikeCurrent[i - 1]! === activeStrike) {
          const liquidity =
            pairData.strikes[activeStrike]!.liquidityBiDirectional[i - 1]!;
          const composition = pairData.composition[i - 1]!;
          const liquiditySwap =
            (liquidity * composition.numerator) / composition.denominator;

          swapState.liquiditySwap = liquiditySwap;
          swapState.liquidityTotal = liquidity;
          swapState.liquiditySwapSpread[i - 1] = liquiditySwap;
          swapState.liquidityTotalSpread[i - 1] = liquidity;
        } else {
          break;
        }
      }
    } else {
      pairData.cachedStrikeCurrent =
        pairData.strikes[pairData.cachedStrikeCurrent]!.next1To0;
      swapState.liquiditySwap = 0n;
      swapState.liquidityTotal = 0n;

      for (let i = 1; i <= NUM_SPREADS; i++) {
        const activeStrike = pairData.cachedStrikeCurrent - i;

        if (pairData.strikeCurrent[i - 1]! > activeStrike) {
          pairData.strikeCurrent[i - 1] = activeStrike;
          const liquidity =
            pairData.strikes[activeStrike]!.liquidityBiDirectional[i - 1]!;

          swapState.liquiditySwap = liquidity;
          swapState.liquidityTotal = liquidity;
          swapState.liquiditySwapSpread[i - 1] = liquidity;
          swapState.liquidityTotalSpread[i - 1] = liquidity;
        } else if (pairData.strikeCurrent[i - 1]! === activeStrike) {
          const liquidity =
            pairData.strikes[activeStrike]!.liquidityBiDirectional[i - 1]!;
          const composition = pairData.composition[i - 1]!;
          const liquiditySwap =
            (liquidity * (Q128 - composition.numerator)) /
            composition.denominator;

          swapState.liquiditySwap = liquiditySwap;
          swapState.liquidityTotal = liquidity;
          swapState.liquiditySwapSpread[i - 1] = liquiditySwap;
          swapState.liquidityTotalSpread[i - 1] = liquidity;
        } else {
          break;
        }
      }
    }
  }

  if (currencyEqualTo(amountDesired.currency, pair.token0)) {
    return {
      amount0: makeCurrencyAmountFromRaw(pair.token0, swapState.amountA),
      amount1: makeCurrencyAmountFromRaw(pair.token1, swapState.amountB),
    };
  } else {
    return {
      amount0: makeCurrencyAmountFromRaw(pair.token0, swapState.amountB),
      amount1: makeCurrencyAmountFromRaw(pair.token1, swapState.amountA),
    };
  }
};

export const calculateAccrue = (
  pairData: PairData,
  strike: Strike,
  blockCurrent: bigint,
) => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");

  const blocks = blockCurrent - pairData.cachedBlock;
  if (blocks === 0n) return;

  let liquidityRepaid = 0n;
  let liquidityBorrowedTotal = 0n;

  for (let i = 0; i <= pairData.strikes[strike]!.activeSpread; i++) {
    const liquidityBorrowed = pairData.strikes[strike]!.liquidityBorrowed[i]!;
    const spreadGrowth =
      ((BigInt(i) + 1n) * blocks * liquidityBorrowed) / 10000n;

    pairData.strikes[i]!.liquidityBiDirectional[i] += spreadGrowth;

    liquidityRepaid += spreadGrowth;
    liquidityBorrowedTotal += liquidityBorrowed;
  }

  if (liquidityRepaid === 0n) return;

  pairData.strikes[strike]!.liquidityGrowth = makeFraction(
    (pairData.strikes[strike]!.liquidityGrowth.numerator + Q128) *
      liquidityBorrowedTotal -
      Q128,
    pairData.strikes[strike]!.liquidityGrowth.denominator *
      (liquidityBorrowedTotal - liquidityRepaid),
  );

  repayLiquidity(pairData, strike, liquidityRepaid);

  pairData.cachedBlock = blockCurrent;
};

// collateral and debt amount

const updateStrike = (
  pairData: PairData,
  strike: Strike,
  spread: Spread,
  balance: bigint,
  liquidity: bigint,
) => {
  checkStrike(strike - spread);
  checkStrike(strike + spread);

  pairData.strikes[strike]!.liquidityBiDirectional[spread - 1] += liquidity;
  pairData.strikes[strike]!.totalSupply[spread - 1] += balance;

  // TODO: update bitmap
};

const borrowLiquidity = (
  pairData: PairData,
  strike: Strike,
  liquidity: bigint,
) => {
  let activeSpread = pairData.strikes[strike]!.activeSpread;
  let remainingLiquidity = liquidity;
  while (true) {
    invariant(pairData.strikeCurrent[activeSpread] !== strike);

    if (
      pairData.strikes[strike]!.liquidityBiDirectional[activeSpread] >=
      remainingLiquidity
    ) {
      pairData.strikes[strike]!.liquidityBiDirectional[activeSpread] -=
        remainingLiquidity;
      pairData.strikes[strike]!.liquidityBorrowed[activeSpread] +=
        remainingLiquidity;
      break;
    } else {
      pairData.strikes[strike]!.liquidityBorrowed[activeSpread] +=
        pairData.strikes[strike]!.liquidityBiDirectional[activeSpread];
      pairData.strikes[strike]!.liquidityBiDirectional[activeSpread] = 0n;

      remainingLiquidity -=
        pairData.strikes[strike]!.liquidityBiDirectional[activeSpread];
      activeSpread++;
    }
  }
  pairData.strikes[strike]!.activeSpread = activeSpread;
};

const repayLiquidity = (
  pairData: PairData,
  strike: Strike,
  liquidity: bigint,
) => {
  let activeSpread = pairData.strikes[strike]!.activeSpread;
  let remainingLiquidity = liquidity;
  while (true) {
    invariant(pairData.strikeCurrent[activeSpread] !== strike);

    if (
      pairData.strikes[strike]!.liquidityBorrowed[activeSpread] >=
      remainingLiquidity
    ) {
      pairData.strikes[strike]!.liquidityBiDirectional[activeSpread] +=
        remainingLiquidity;
      pairData.strikes[strike]!.liquidityBorrowed[activeSpread] -=
        remainingLiquidity;
      break;
    } else {
      pairData.strikes[strike]!.liquidityBiDirectional[activeSpread] +=
        pairData.strikes[strike]!.liquidityBorrowed[activeSpread];
      pairData.strikes[strike]!.liquidityBorrowed[activeSpread] = 0n;

      remainingLiquidity -=
        pairData.strikes[strike]!.liquidityBorrowed[activeSpread];
      activeSpread--;
    }
  }
  pairData.strikes[strike]!.activeSpread = activeSpread;
};

const checkStrike = (strike: Strike) => {
  invariant(
    strike < MAX_STRIKE && strike > MIN_STRIKE,
    "Dry Powder SDK: strike is above maximum or below minimum",
  );
};
