import {
  type ERC20Amount,
  type Fraction,
  MaxUint128,
  createAmountFromRaw,
  createFraction,
  fractionAdd,
  fractionInvert,
  fractionLessThan,
  fractionMultiply,
  fractionQuotient,
  fractionSubtract,
} from "reverse-mirage";
import invariant from "tiny-invariant";
import {
  MAX_STRIKE,
  MIN_MULTIPLIER,
  MIN_STRIKE,
  NUM_SPREADS,
  Q128,
} from "./constants.js";
import {
  balanceToLiquidity,
  computeSwapStep,
  debtBalanceToLiquidity,
  getAmount0,
  getAmount1,
  getAmounts,
  getLiquidityForAmount0,
  getLiquidityForAmount1,
  liquidityToBalance,
} from "./math.js";
import { type PositionData, createPosition } from "./positions.js";
import type {
  Pair,
  PairData,
  Spread,
  Strike,
  TokenSelector,
  Tuple,
} from "./types.js";
import { fractionToQ128, q128ToFraction } from "./utils.js";

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
        liquidityGrowth: createFraction(0n),
        liquidityRepayRate: createFraction(0n),
        liquidityGrowthSpread: [
          createFraction(1),
          createFraction(1),
          createFraction(1),
          createFraction(1),
          createFraction(1),
        ],
        blockLast: 0n,
        liquidity: [
          { swap: 0n, borrowed: 0n },
          { swap: 0n, borrowed: 0n },
          { swap: 0n, borrowed: 0n },
          { swap: 0n, borrowed: 0n },
          { swap: 0n, borrowed: 0n },
        ],
        next0To1: 0,
        next1To0: 0,
        // reference0To1: new Set<Spread>(),
        // reference1To0: new Set<Spread>(),
        activeSpread: 0,
      },
    },
    composition: [
      createFraction(0n),
      createFraction(0n),
      createFraction(0n),
      createFraction(0n),
      createFraction(0n),
    ],
    strikeCurrent: [strike, strike, strike, strike, strike],
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
// TODO: scale liquidity
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
  invariant(
    amountDesired > 0n,
    "Dry Powder SDK: Invalid amount desired when adding liquidity",
  );

  const liquidityAccrued = _accrue(pairData, block, strike);
  if (liquidityAccrued > 0)
    _removeBorrowedLiquidity(pairData, strike, liquidityAccrued);

  const liquidityDisplaced = _addSwapLiquidity(
    pairData,
    strike,
    spread,
    amountDesired,
  );
  if (liquidityDisplaced > 0)
    _removeBorrowedLiquidity(pairData, strike, liquidityDisplaced);

  const [amount0, amount1] = getAmounts(
    pairData,
    strike,
    spread,
    amountDesired,
    true,
  );

  const balance = liquidityToBalance(
    amountDesired,
    pairData.strikes[strike]!.liquidityGrowthSpread[spread - 1]!,
  );

  return {
    amount0: createAmountFromRaw(pair.token0, amount0),
    amount1: createAmountFromRaw(pair.token1, amount1),
    position: {
      type: "positionData",
      token: createPosition(
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
    },
  };
};

// TODO: scale liquidity
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
  invariant(
    amountDesired > 0n,
    "Dry Powder SDK: Invalid balance when removing liquidity",
  );

  const liquidityAccrued = _accrue(pairData, block, strike);
  if (liquidityAccrued > 0)
    _removeBorrowedLiquidity(pairData, strike, liquidityAccrued);

  const liquidity = balanceToLiquidity(
    amountDesired,
    pairData.strikes[strike]!.liquidityGrowthSpread[spread - 1]!,
  );

  invariant(
    liquidity !== 0n,
    "Dry Powder SDK: Invalid liquidity when removing liquidity",
  );

  const liquidityDisplaced = _removeSwapLiquidity(
    pairData,
    strike,
    spread,
    liquidity,
  );
  if (liquidityDisplaced > 0n)
    _addBorrowedLiquidity(pairData, strike, liquidityDisplaced);

  const [amount0, amount1] = getAmounts(
    pairData,
    strike,
    spread,
    liquidity,
    false,
  );

  return {
    amount0: createAmountFromRaw(pair.token0, -amount0),
    amount1: createAmountFromRaw(pair.token1, -amount1),
    position: {
      type: "positionData",
      token: createPosition(
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
      balance: -amountDesired,
    },
  };
};

// TODO: scale liquidity
export const calculateBorrowLiquidity = (
  pair: Pair,
  pairData: PairData,
  block: bigint,
  strike: Strike,
  amountDesiredCollateral: ERC20Amount<Pair["token0"] | Pair["token1"]>,
  amountDesiredDebt: bigint,
): {
  amount0: ERC20Amount<Pair["token0"]>;
  amount1: ERC20Amount<Pair["token1"]>;
  position: PositionData<"Debt">;
} => {
  invariant(
    amountDesiredDebt > 0n,
    "Dry Powder SDK: Invalid balance when removing liquidity",
  );

  const liquidityAccrued = _accrue(pairData, block, strike);
  if (liquidityAccrued > 0)
    _removeBorrowedLiquidity(pairData, strike, liquidityAccrued);

  _addBorrowedLiquidity(pairData, strike, amountDesiredDebt);

  let amount0 = 0n;
  let amount1 = 0n;

  let activeSpread = pairData.strikes[strike]!.activeSpread;
  let liquidity = amountDesiredDebt;

  while (true) {
    if (
      pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed >= liquidity
    ) {
      const [_amount0, _amount1] = getAmounts(
        pairData,
        strike,
        (activeSpread + 1) as Spread,
        liquidity,
        false,
      );

      amount0 -= _amount0;
      amount1 -= _amount1;

      break;
    }

    if (pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed > 0n) {
      const [_amount0, _amount1] = getAmounts(
        pairData,
        strike,
        (activeSpread + 1) as Spread,
        pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed,
        false,
      );

      amount0 -= _amount0;
      amount1 -= _amount1;

      liquidity -= pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed;
    }

    activeSpread--;
  }

  const liquidityCollateral =
    amountDesiredCollateral.token === pair.token0
      ? getLiquidityForAmount0(amountDesiredCollateral.amount, strike)
      : getLiquidityForAmount1(amountDesiredCollateral.amount);

  if (amountDesiredCollateral.token === pair.token0) {
    amount0 += amountDesiredCollateral.amount;
  } else {
    amount1 += amountDesiredCollateral.amount;
  }

  invariant(
    liquidityCollateral >= amountDesiredDebt,
    "Dry Powder SDK: collateral is more than debt",
  );
  const multiplier = createFraction(
    liquidityCollateral - amountDesiredDebt,
    amountDesiredDebt,
  );

  invariant(
    fractionToQ128(multiplier) <= 2n ** 136n - 1n &&
      !fractionLessThan(multiplier, MIN_MULTIPLIER),
  );

  pairData.strikes[strike]!.liquidityRepayRate = fractionAdd(
    pairData.strikes[strike]!.liquidityRepayRate,
    fractionMultiply(fractionInvert(multiplier), amountDesiredDebt),
  );

  return {
    amount0: createAmountFromRaw(pair.token0, amount0),
    amount1: createAmountFromRaw(pair.token1, amount1),
    position: {
      type: "positionData",
      token: createPosition(
        "Debt",
        {
          token0: pair.token0,
          token1: pair.token1,
          scalingFactor: pair.scalingFactor,
          strike,
          selectorCollateral:
            amountDesiredCollateral.token === pair.token0 ? "Token0" : "Token1",
          liquidityGrowthLast: pairData.strikes[strike]!.liquidityGrowth,
          multiplier,
        },
        1,
      ),
      balance: amountDesiredDebt,
    },
  };
};

// TODO: scale liquidity
export const calculateRepayLiquidity = (
  pair: Pair,
  pairData: PairData,
  block: bigint,
  strike: Strike,
  selectorCollateral: TokenSelector,
  liquidityGrowthLast: Fraction,
  multiplier: Fraction,
  amountDesired: bigint,
): {
  amount0: ERC20Amount<Pair["token0"]>;
  amount1: ERC20Amount<Pair["token1"]>;
  position: PositionData<"Debt">;
} => {
  invariant(
    amountDesired > 0n,
    "Dry Powder SDK: Invalid balance when removing liquidity",
  );

  const liquidityAccrued = _accrue(pairData, block, strike);
  if (liquidityAccrued > 0)
    _removeBorrowedLiquidity(pairData, strike, liquidityAccrued);

  const liquidityDebt = debtBalanceToLiquidity(
    amountDesired,
    multiplier,
    fractionSubtract(
      pairData.strikes[strike]!.liquidityGrowth,
      liquidityGrowthLast,
    ),
  );

  _removeBorrowedLiquidity(pairData, strike, liquidityDebt);

  let amount0 = 0n;
  let amount1 = 0n;

  let activeSpread = pairData.strikes[strike]!.activeSpread;
  let liquidity = amountDesired;

  while (true) {
    if (pairData.strikes[strike]!.liquidity[activeSpread]!.swap >= liquidity) {
      const [_amount0, _amount1] = getAmounts(
        pairData,
        strike,
        (activeSpread + 1) as Spread,
        liquidity,
        true,
      );

      amount0 += _amount0;
      amount1 += _amount1;

      break;
    }

    if (pairData.strikes[strike]!.liquidity[activeSpread]!.swap > 0n) {
      const [_amount0, _amount1] = getAmounts(
        pairData,
        strike,
        (activeSpread + 1) as Spread,
        pairData.strikes[strike]!.liquidity[activeSpread]!.swap,
        true,
      );

      amount0 += _amount0;
      amount1 += _amount1;

      liquidity -= pairData.strikes[strike]!.liquidity[activeSpread]!.swap;
    }

    activeSpread++;
  }

  const liquidityCollateral =
    liquidityDebt +
    fractionQuotient(fractionMultiply(multiplier, liquidityDebt));

  if (selectorCollateral === "Token0") {
    amount0 -= getAmount0(liquidityCollateral, strike, false);
  } else {
    amount1 -= getAmount1(liquidityCollateral);
  }

  return {
    amount0: createAmountFromRaw(pair.token0, amount0),
    amount1: createAmountFromRaw(pair.token1, amount1),
    position: {
      type: "positionData",
      token: createPosition(
        "Debt",
        {
          token0: pair.token0,
          token1: pair.token1,
          scalingFactor: pair.scalingFactor,
          strike,
          selectorCollateral,
          liquidityGrowthLast: liquidityGrowthLast,
          multiplier,
        },
        1,
      ),
      balance: -amountDesired,
    },
  };
};

export const calculateAccrue = (
  pairData: PairData,
  block: bigint,
  strike: Strike,
) => {
  const liquidityAccrued = _accrue(pairData, block, strike);
  if (liquidityAccrued > 0)
    _removeBorrowedLiquidity(pairData, strike, liquidityAccrued);
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
    liquidityRemaining: bigint;
    liquiditySwapSpread: Tuple<bigint, typeof NUM_SPREADS>;
    liquidityTotalSpread: Tuple<bigint, typeof NUM_SPREADS>;
    amountA: bigint;
    amountB: bigint;
    strike: Strike;
    amountDesired: ERC20Amount<Pair["token0"] | Pair["token1"]>;
  } = {
    liquiditySwap: 0n,
    liquidityTotal: 0n,
    liquidityRemaining: 0n,
    liquiditySwapSpread: [0n, 0n, 0n, 0n, 0n],
    liquidityTotalSpread: [0n, 0n, 0n, 0n, 0n],
    amountA: 0n,
    amountB: 0n,
    strike: pairData.strikeCurrent[0], // I think this is wrong
    amountDesired,
  };

  // search for liquidity in neighboring strikes

  const countLiquidity = () => {
    for (let i = 0; i < NUM_SPREADS; i++) {
      const spreadStrike = isSwap0To1
        ? swapState.strike + (i + 1)
        : swapState.strike - (i + 1);

      if (spreadStrike === pairData.strikeCurrent[i]) {
        const liquidityTotal =
          pairData.strikes[spreadStrike]!.liquidity[i]!.swap;
        const liquiditySwap = fractionQuotient(
          fractionMultiply(
            isSwap0To1
              ? pairData.composition[i]!
              : fractionSubtract(createFraction(1), pairData.composition[i]!),
            liquidityTotal,
          ),
        );

        swapState.liquidityTotalSpread[i] = liquidityTotal;
        swapState.liquiditySwapSpread[i] = liquiditySwap;
        swapState.liquidityTotal += liquidityTotal;
        swapState.liquiditySwap += liquiditySwap;
      }
    }
  };

  countLiquidity();

  while (true) {
    const { amountIn, amountOut } = computeSwapStep(
      pair,
      swapState.strike,
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
      for (let i = 0; i < NUM_SPREADS; i++) {
        if (pairData.strikeCurrent[i]! === swapState.strike) {
          pairData.strikeCurrent[i] =
            pairData.strikes[swapState.strike]!.next0To1 + (i + 1);
          pairData.composition[i] = createFraction(1);
        }
      }

      invariant(
        swapState.strike !== MIN_STRIKE,
        "Dry Powder SDK: Swap out of bounds",
      );
      swapState.strike = pairData.strikes[swapState.strike]!.next0To1;

      swapState.liquiditySwap = 0n;
      swapState.liquidityTotal = 0n;
      swapState.liquiditySwapSpread = [0n, 0n, 0n, 0n, 0n];
      swapState.liquidityTotalSpread = [0n, 0n, 0n, 0n, 0n];

      countLiquidity();
    } else {
      for (let i = 0; i < NUM_SPREADS; i++) {
        if (pairData.strikeCurrent[i]! === swapState.strike) {
          pairData.strikeCurrent[i] =
            pairData.strikes[swapState.strike]!.next0To1 - (i + 1);
          pairData.composition[i] = createFraction(0);
        }
      }

      invariant(
        swapState.strike !== MAX_STRIKE,
        "Dry Powder SDK: Swap out of bounds",
      );
      swapState.strike = pairData.strikes[swapState.strike]!.next1To0;

      swapState.liquiditySwap = 0n;
      swapState.liquidityTotal = 0n;
      swapState.liquiditySwapSpread = [0n, 0n, 0n, 0n, 0n];
      swapState.liquidityTotalSpread = [0n, 0n, 0n, 0n, 0n];

      countLiquidity();
    }
  }

  if (amountDesired.token === pair.token0) {
    return {
      amount0: createAmountFromRaw(pair.token0, swapState.amountA),
      amount1: createAmountFromRaw(pair.token1, swapState.amountB),
    };
  } else {
    return {
      amount0: createAmountFromRaw(pair.token0, swapState.amountB),
      amount1: createAmountFromRaw(pair.token1, swapState.amountA),
    };
  }
};

const _addSwapLiquidity = (
  pairData: PairData,
  strike: Strike,
  spread: Spread,
  liquidity: bigint,
): bigint => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");
  invariant(
    pairData.strikes[strike] !== undefined,
    "Dry Powder SDK: Strike is not defined",
  );

  const existingLiquidity =
    pairData.strikes[strike]!.liquidity[spread - 1]!.swap;
  const borrowedLiquidity =
    pairData.strikes[strike]!.liquidity[spread - 1]!.borrowed;

  invariant(
    existingLiquidity + borrowedLiquidity + liquidity <= MaxUint128,
    "Dry Powder SDK: Liquidity amount overflow. Total liquidity in a strike must fit into a uint128",
  );

  if (spread - 1 < pairData.strikes[strike]!.activeSpread) {
    pairData.strikes[strike]!.liquidity[spread - 1]!.borrowed += liquidity;

    return liquidity;
  } else {
    pairData.strikes[strike]!.liquidity[spread - 1]!.swap += liquidity;

    const strike0To1 = strike - spread;
    const strike1To0 = strike + spread;

    checkStrike(strike0To1);
    checkStrike(strike1To0);

    return 0n;
  }
};

const _removeSwapLiquidity = (
  pairData: PairData,
  strike: Strike,
  spread: Spread,
  liquidity: bigint,
): bigint => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");
  invariant(
    pairData.strikes[strike] !== undefined,
    "Dry Powder SDK: Strike is not defined",
  );

  if (spread - 1 < pairData.strikes[strike]!.activeSpread) {
    pairData.strikes[strike]!.liquidity[spread - 1]!.borrowed -= liquidity;

    return liquidity;
  } else {
    if (liquidity <= pairData.strikes[strike]!.liquidity[spread - 1]!.swap) {
      pairData.strikes[strike]!.liquidity[spread - 1]!.swap -= liquidity;

      return 0n;
    } else {
      invariant(
        spread - 1 === pairData.strikes[strike]!.activeSpread,
        "Dry Powder SDK: Removing more liquidity than is available",
      );

      const remainingLiquidity =
        liquidity - pairData.strikes[strike]!.liquidity[spread - 1]!.swap;

      pairData.strikes[strike]!.liquidity[spread - 1]!.borrowed -=
        remainingLiquidity;
      pairData.strikes[strike]!.liquidity[spread - 1]!.swap = 0n;

      return remainingLiquidity;
    }
  }
};

const _addBorrowedLiquidity = (
  pairData: PairData,
  strike: Strike,
  liquidity: bigint,
) => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");
  invariant(
    pairData.strikes[strike] !== undefined,
    "Dry Powder SDK: Strike is not defined",
  );

  let remainingLiquidity = liquidity;

  while (true) {
    const activeSpread = pairData.strikes[strike]!.activeSpread;

    if (
      pairData.strikes[strike]!.liquidity[activeSpread]!.swap >=
      remainingLiquidity
    ) {
      pairData.strikes[strike]!.liquidity[activeSpread]!.swap -=
        remainingLiquidity;
      pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed +=
        remainingLiquidity;
      break;
    }

    if (pairData.strikes[strike]!.liquidity[activeSpread]!.swap > 0) {
      remainingLiquidity -=
        pairData.strikes[strike]!.liquidity[activeSpread]!.swap;
      pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed +=
        pairData.strikes[strike]!.liquidity[activeSpread]!.swap;
      pairData.strikes[strike]!.liquidity[activeSpread]!.swap = 0n;
    }

    invariant(
      activeSpread !== 4,
      "Dry Powder SDK: Adding borrowed liquidity out of bounds",
    );
    pairData.strikes[strike]!.activeSpread++;
  }
};

const _removeBorrowedLiquidity = (
  pairData: PairData,
  strike: Strike,
  liquidity: bigint,
) => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");
  invariant(
    pairData.strikes[strike] !== undefined,
    "Dry Powder SDK: Strike is not defined",
  );

  let remainingLiquidity = liquidity;

  while (true) {
    const activeSpread = pairData.strikes[strike]!.activeSpread;

    if (
      pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed >=
      remainingLiquidity
    ) {
      pairData.strikes[strike]!.liquidity[activeSpread]!.swap +=
        remainingLiquidity;
      pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed -=
        remainingLiquidity;
      break;
    }

    if (pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed > 0) {
      remainingLiquidity -=
        pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed;
      pairData.strikes[strike]!.liquidity[activeSpread].swap +=
        pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed;
      pairData.strikes[strike]!.liquidity[activeSpread]!.borrowed = 0n;
    }

    invariant(
      activeSpread !== 0,
      "Dry Powder SDK: Removing borrowed liquidity out of bounds",
    );
    pairData.strikes[strike]!.activeSpread--;
  }
};

const _accrue = (
  pairData: PairData,
  blockCurrent: bigint,
  strike: Strike,
): bigint => {
  invariant(pairData.initialized, "Dry Powder SDK: Pair is not initialized");

  if (pairData.strikes[strike] === undefined) {
    pairData.strikes[strike] = {
      liquidityGrowth: createFraction(0n),
      liquidityRepayRate: createFraction(0n),
      liquidityGrowthSpread: [
        createFraction(1),
        createFraction(1),
        createFraction(1),
        createFraction(1),
        createFraction(1),
      ],
      blockLast: blockCurrent,
      liquidity: [
        { swap: 0n, borrowed: 0n },
        { swap: 0n, borrowed: 0n },
        { swap: 0n, borrowed: 0n },
        { swap: 0n, borrowed: 0n },
        { swap: 0n, borrowed: 0n },
      ],
      next0To1: 0,
      next1To0: 0,
      // reference0To1: new Set<Spread>(),
      // reference1To0: new Set<Spread>(),
      activeSpread: 0,
    };
    return 0n;
  }

  const blocks = blockCurrent - pairData.strikes[strike]!.blockLast;
  if (blocks === 0n) return 0n;
  pairData.strikes[strike]!.blockLast = blockCurrent;

  let liquidityAccrued = 0n;
  let liquidityBorrowedTotal = 0n;

  for (let i = 0; i <= pairData.strikes[strike]!.activeSpread; i++) {
    const liquidityBorrowed = pairData.strikes[strike]!.liquidity[i]!.borrowed;
    const liquiditySwap = pairData.strikes[strike]!.liquidity[i]!.swap;

    if (liquidityBorrowed > 0n) {
      const fee = BigInt(i + 1) * blocks;
      const liquidityAccruedSpread =
        fee > 2_000_000n
          ? liquidityBorrowed
          : (fee * liquidityBorrowed) / 2_000_000n;

      liquidityAccrued += liquidityAccruedSpread;
      liquidityBorrowedTotal += liquidityBorrowed;

      pairData.strikes[strike]!.liquidityGrowthSpread[i]! = fractionAdd(
        pairData.strikes[strike]!.liquidityGrowthSpread[i]!,
        q128ToFraction(
          (liquidityAccruedSpread * Q128) / (liquidityBorrowed + liquiditySwap),
        ),
      );
    }
  }

  if (liquidityAccrued === 0n) return 0n;

  pairData.strikes[strike]!.liquidityGrowth = fractionAdd(
    pairData.strikes[strike]!.liquidityGrowth,
    q128ToFraction((liquidityAccrued * Q128) / liquidityBorrowedTotal),
  );

  return fractionQuotient(
    fractionMultiply(
      pairData.strikes[strike]!.liquidityRepayRate,
      liquidityAccrued,
    ),
  );
};

const checkStrike = (strike: Strike) => {
  invariant(
    strike < MAX_STRIKE && strike > MIN_STRIKE,
    "Dry Powder SDK: strike is above maximum or below minimum",
  );
};
