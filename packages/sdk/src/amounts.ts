import { MAX_STRIKE, MIN_STRIKE, NUM_SPREADS, Q128 } from "./constants.js";
import {
  balanceToLiquidity,
  computeSwapStep,
  debtBalanceToLiquidity,
  debtLiquidityToBalance,
  getAmount0Delta,
  getAmount1Delta,
  getAmountsForLiquidity,
  getLiquidityDeltaAmount0,
  getLiquidityDeltaAmount1,
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
  type ERC20Amount,
  type Fraction,
  MaxUint128,
  fractionMultiply,
  fractionQuotient,
  makeAmountFromRaw,
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
        liquidityGrowth: makeFraction(0n),
        blockLast: 0n,
        totalSupply: [0n, 0n, 0n, 0n, 0n],
        liquidityBiDirectional: [0n, 0n, 0n, 0n, 0n],
        liquidityBorrowed: [0n, 0n, 0n, 0n, 0n],
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
    strikeCurrentCached: strike,
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
  amountDesired: bigint,
): {
  amount0: ERC20Amount<Pair["token0"]>;
  amount1: ERC20Amount<Pair["token1"]>;
  position: PositionData<"BiDirectional">;
} => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");

  if (pairData.strikes[strike] === undefined)
    pairData.strikes[strike] = {
      liquidityGrowth: makeFraction(0n),
      blockLast: 0n,
      totalSupply: [0n, 0n, 0n, 0n, 0n],
      liquidityBiDirectional: [0n, 0n, 0n, 0n, 0n],
      liquidityBorrowed: [0n, 0n, 0n, 0n, 0n],
      next0To1: 0,
      next1To0: 0,
      activeSpread: 0,
    };

  calculateAccrue(pairData, strike, block);

  const liquidity = amountDesired;
  const balance = liquidityToBalance(pairData, strike, spread, liquidity);
  const [amount0, amount1] = getAmountsForLiquidity(
    pairData,
    strike,
    spread,
    liquidity,
  );

  updateStrike(pairData, strike, spread, balance, liquidity);

  return {
    amount0: makeAmountFromRaw(pair.token0, amount0),
    amount1: makeAmountFromRaw(pair.token1, amount1),
    position: {
      type: "positionData",
      token: makePosition(
        "BiDirectional",
        {
          token0: pair.token0,
          token1: pair.token1,
          scalingFactor: pair.scalingFactor,
          strike,
          spread,
        },
        1,
      ),
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
  amountDesired: bigint,
): {
  amount0: ERC20Amount<Pair["token0"]>;
  amount1: ERC20Amount<Pair["token1"]>;
  position: PositionData<"BiDirectional">;
} => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");

  calculateAccrue(pairData, strike, block);

  const balance = amountDesired;
  const liquidity = balanceToLiquidity(pairData, strike, spread, balance);

  const [amount0, amount1] = getAmountsForLiquidity(
    pairData,
    strike,
    spread,
    liquidity,
  );

  updateStrike(pairData, strike, spread, -balance, -liquidity);

  return {
    amount0: makeAmountFromRaw(pair.token0, -amount0),
    amount1: makeAmountFromRaw(pair.token1, -amount1),
    position: {
      type: "positionData",
      token: makePosition(
        "BiDirectional",
        {
          token0: pair.token0,
          token1: pair.token1,
          scalingFactor: pair.scalingFactor,
          strike,
          spread,
        },
        1,
      ),
      balance: -balance,
      data: {},
    },
  };
};

export const calculateBorrowLiquidity = (
  pair: Pair,
  pairData: PairData,
  block: bigint,
  strike: Strike,
  selectorCollateral: TokenSelector,
  amountDesiredCollateral: bigint,
  amountDesiredDebt: bigint,
): {
  amount0: ERC20Amount<Pair["token0"]>;
  amount1: ERC20Amount<Pair["token1"]>;
  position: PositionData<"Debt">;
} => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");
  calculateAccrue(pairData, strike, block);

  const liquidity = amountDesiredDebt;
  const liquidityToken1 = borrowLiquidity(pairData, strike, liquidity);

  let amount0: bigint;
  let amount1: bigint;
  amount0 = -getAmount0Delta(liquidity - liquidityToken1, strike);
  amount1 = -getAmount1Delta(liquidityToken1);

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

  invariant(amountDesiredDebt < liquidityCollateral, "overcollateralization");

  const balance = debtLiquidityToBalance(
    liquidity,
    pairData.strikes[strike]!.liquidityGrowth,
  );
  const leverageRatio = makeFraction(liquidityCollateral, balance);

  return {
    amount0: makeAmountFromRaw(pair.token0, amount0),
    amount1: makeAmountFromRaw(pair.token1, amount1),
    position: {
      type: "positionData",
      token: makePosition(
        "Debt",
        {
          token0: pair.token0,
          token1: pair.token1,
          scalingFactor: pair.scalingFactor,
          strike,
          selectorCollateral,
        },
        1,
      ),
      balance,
      data: { leverageRatio },
    },
  };
};

export const calculateRepayLiquidity = (
  pair: Pair,
  pairData: PairData,
  block: bigint,
  strike: Strike,
  selectorCollateral: TokenSelector,
  leverageRatio: Fraction,
  amountDesiredDebt: bigint,
): {
  amount0: ERC20Amount<Pair["token0"]>;
  amount1: ERC20Amount<Pair["token1"]>;
  position: PositionData<"Debt">;
} => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");
  calculateAccrue(pairData, strike, block);

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
    amount0: makeAmountFromRaw(pair.token0, amount0),
    amount1: makeAmountFromRaw(pair.token1, amount1),
    position: {
      type: "positionData",
      token: makePosition(
        "Debt",
        {
          token0: pair.token0,
          token1: pair.token1,
          scalingFactor: pair.scalingFactor,
          strike,
          selectorCollateral,
        },
        1,
      ),
      balance: -balance,
      data: { leverageRatio },
    },
  };
};

// TODO: load strikes conditionally
export const calculateSwap = (
  pair: Pair,
  pairData: PairData,
  amountDesired: ERC20Amount<Pair["token0"] | Pair["token1"]>,
): {
  amount0: ERC20Amount<Pair["token0"]>;
  amount1: ERC20Amount<Pair["token1"]>;
} => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");

  const isSwap0To1 =
    amountDesired.amount > 0 === (amountDesired.token === pair.token0);

  const swapState: {
    liquiditySwap: bigint;
    liquidityTotal: bigint;
    liquiditySwapSpread: Tuple<bigint, typeof NUM_SPREADS>;
    liquidityTotalSpread: Tuple<bigint, typeof NUM_SPREADS>;
    amountA: bigint;
    amountB: bigint;
    amountDesired: ERC20Amount<Pair["token0"] | Pair["token1"]>;
  } = {
    liquiditySwap: 0n,
    liquidityTotal: 0n,
    liquiditySwapSpread: [0n, 0n, 0n, 0n, 0n],
    liquidityTotalSpread: [0n, 0n, 0n, 0n, 0n],
    amountA: 0n,
    amountB: 0n,
    amountDesired: makeAmountFromRaw(amountDesired.token, amountDesired.amount),
  };

  for (let i = 1; i <= NUM_SPREADS; i++) {
    const activeStrike = isSwap0To1
      ? pairData.strikeCurrentCached + i
      : pairData.strikeCurrentCached - i;
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
      pairData.strikeCurrentCached,
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
      pairData.strikeCurrentCached =
        pairData.strikes[pairData.strikeCurrentCached]!.next0To1;
      swapState.liquiditySwap = 0n;
      swapState.liquidityTotal = 0n;

      for (let i = 1; i <= NUM_SPREADS; i++) {
        const activeStrike = pairData.strikeCurrentCached + i;

        if (
          pairData.strikeCurrent[i - 1]! > activeStrike &&
          pairData.strikes[i - 1] !== undefined
        ) {
          pairData.strikeCurrent[i - 1] = activeStrike;
          const liquidity =
            pairData.strikes[activeStrike]!.liquidityBiDirectional[i - 1]!;

          swapState.liquiditySwap = liquidity;
          swapState.liquidityTotal = liquidity;
          swapState.liquiditySwapSpread[i - 1] = liquidity;
          swapState.liquidityTotalSpread[i - 1] = liquidity;
        } else if (
          pairData.strikeCurrent[i - 1]! === activeStrike &&
          pairData.strikes[i - 1] !== undefined
        ) {
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
      pairData.strikeCurrentCached =
        pairData.strikes[pairData.strikeCurrentCached]!.next1To0;
      swapState.liquiditySwap = 0n;
      swapState.liquidityTotal = 0n;

      for (let i = 1; i <= NUM_SPREADS; i++) {
        const activeStrike = pairData.strikeCurrentCached - i;

        if (
          pairData.strikeCurrent[i - 1]! > activeStrike &&
          pairData.strikes[i - 1] !== undefined
        ) {
          pairData.strikeCurrent[i - 1] = activeStrike;
          const liquidity =
            pairData.strikes[activeStrike]!.liquidityBiDirectional[i - 1]!;

          swapState.liquiditySwap = liquidity;
          swapState.liquidityTotal = liquidity;
          swapState.liquiditySwapSpread[i - 1] = liquidity;
          swapState.liquidityTotalSpread[i - 1] = liquidity;
        } else if (
          pairData.strikeCurrent[i - 1]! === activeStrike &&
          pairData.strikes[i - 1] !== undefined
        ) {
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

  if (amountDesired.token === pair.token0) {
    return {
      amount0: makeAmountFromRaw(pair.token0, swapState.amountA),
      amount1: makeAmountFromRaw(pair.token1, swapState.amountB),
    };
  } else {
    return {
      amount0: makeAmountFromRaw(pair.token0, swapState.amountB),
      amount1: makeAmountFromRaw(pair.token1, swapState.amountA),
    };
  }
};

export const calculateAccrue = (
  pairData: PairData,
  strike: Strike,
  blockCurrent: bigint,
) => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");

  const blocks = blockCurrent - pairData.strikes[strike]!.blockLast;
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

  pairData.strikes[strike]!.blockLast = blockCurrent;
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
): bigint => {
  let activeSpread = pairData.strikes[strike]!.activeSpread;
  let remainingLiquidity = liquidity;
  let liquidityToken1 = 0n;
  while (true) {
    if (
      pairData.strikes[strike]!.liquidityBiDirectional[activeSpread] >=
      remainingLiquidity
    ) {
      pairData.strikes[strike]!.liquidityBiDirectional[activeSpread] -=
        remainingLiquidity;
      pairData.strikes[strike]!.liquidityBorrowed[activeSpread] +=
        remainingLiquidity;

      // determine what token the liqudity was borrowed
      if (pairData.strikeCurrent[activeSpread] > strike) {
        liquidityToken1 += remainingLiquidity;
      } else {
        liquidityToken1 += fractionQuotient(
          fractionMultiply(
            pairData.composition[activeSpread],
            remainingLiquidity,
          ),
        );
      }

      break;
    } else {
      pairData.strikes[strike]!.liquidityBorrowed[activeSpread] +=
        pairData.strikes[strike]!.liquidityBiDirectional[activeSpread];
      pairData.strikes[strike]!.liquidityBiDirectional[activeSpread] = 0n;

      remainingLiquidity -=
        pairData.strikes[strike]!.liquidityBiDirectional[activeSpread];

      // determine what token the liqudity was borrowed
      if (pairData.strikeCurrent[activeSpread] > strike) {
        liquidityToken1 += remainingLiquidity;
      } else {
        liquidityToken1 += fractionQuotient(
          fractionMultiply(
            pairData.composition[activeSpread],
            remainingLiquidity,
          ),
        );
      }

      activeSpread++;
    }
  }
  pairData.strikes[strike]!.activeSpread = activeSpread;
  return liquidityToken1;
};

const repayLiquidity = (
  pairData: PairData,
  strike: Strike,
  liquidity: bigint,
) => {
  let activeSpread = pairData.strikes[strike]!.activeSpread;
  let remainingLiquidity = liquidity;
  while (true) {
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
