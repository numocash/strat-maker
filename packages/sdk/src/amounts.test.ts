import {
  calculateAddLiquidity,
  calculateBorrowLiquidity,
  calculateInitialize,
  calculateRemoveLiquidity,
  calculateRepayLiquidity,
  calculateSwap,
} from "./amounts.js";
import { Q128 } from "./constants.js";
import type { Pair } from "./types.js";
import {
  type ERC20,
  MaxUint256,
  fractionEqualTo,
  makeAmountFromRaw,
  makeFraction,
} from "reverse-mirage";
import { parseEther } from "viem";
import { describe, expect, test } from "vitest";

const token0 = {
  type: "erc20",
  chainID: 1,
  address: "0x0000000000000000000000000000000000000001",
  decimals: 18,
  name: "Token 0",
  symbol: "TOKEN0",
} as const satisfies ERC20;

const token1 = {
  type: "erc20",
  chainID: 1,
  address: "0x0000000000000000000000000000000000000002",
  decimals: 18,
  name: "Token 1",
  symbol: "TOKEN1",
} as const satisfies ERC20;

const pair = { token0, token1, scalingFactor: 0 } as const satisfies Pair;

const oneEther = parseEther("1");
const ratioAtStrikeNeg1 = 0xfff97272373d413259a407b06395f90fn;

// TODO: fix sign of amounts
describe.concurrent("amounts", () => {
  test("initialized", () => {
    const pairData = calculateInitialize(1);

    expect(pairData.strikes[1]).toBeTruthy();
    expect(pairData.bitMap0To1.centerStrike).toBe(1);
    expect(pairData.bitMap1To0.centerStrike).toBe(1);
    expect(pairData.strikeCurrent).toStrictEqual([1, 1, 1, 1, 1]);
    expect(pairData.strikeCurrentCached).toBe(1);
    expect(pairData.initialized).toBe(true);
  });

  test("calculate add liquidity", () => {
    const pairData = calculateInitialize(0);
    const { amount0, amount1, position } = calculateAddLiquidity(
      pair,
      pairData,
      0n,
      0,
      1,
      oneEther,
    );

    // amounts
    expect(amount0.amount).toBe(oneEther - 1n);
    expect(amount1.amount).toBe(0n);
    expect(position.balance).toBe(oneEther);
    expect(amount0.token === token0).toBe(true);
    expect(amount1.token === token1).toBe(true);

    // pair data
    expect(pairData.strikes[0]).toBeTruthy();
    expect(pairData.strikes[0]!.totalSupply).toStrictEqual([
      oneEther,
      0n,
      0n,
      0n,
      0n,
    ]);
    expect(pairData.strikes[0]!.liquidityBiDirectional).toStrictEqual([
      oneEther,
      0n,
      0n,
      0n,
      0n,
    ]);
  });

  test("calculate remove liquidity", () => {
    const pairData = calculateInitialize(0);

    calculateAddLiquidity(pair, pairData, 0n, 0, 1, oneEther);
    const { amount0, amount1, position } = calculateRemoveLiquidity(
      pair,
      pairData,
      0n,
      0,
      1,
      oneEther,
    );

    // amounts
    expect(amount0.amount).toBe(1n - oneEther);
    expect(amount1.amount).toBe(0n);
    expect(position.balance).toBe(-oneEther);
    expect(amount0.token === token0).toBe(true);
    expect(amount1.token === token1).toBe(true);

    // pair data
    expect(pairData.strikes[0]).toBeTruthy();
    expect(pairData.strikes[0]!.totalSupply).toStrictEqual([
      0n,
      0n,
      0n,
      0n,
      0n,
    ]);
    expect(pairData.strikes[0]!.liquidityBiDirectional).toStrictEqual([
      0n,
      0n,
      0n,
      0n,
      0n,
    ]);
  });

  test("calculate borrow liquidity", () => {
    const pairData = calculateInitialize(0);
    calculateAddLiquidity(pair, pairData, 0n, 1, 1, oneEther);
    const { amount0, amount1, position } = calculateBorrowLiquidity(
      pair,
      pairData,
      0n,
      1,
      "Token0",
      parseEther("1.5"),
      parseEther("0.5"),
    );

    // amounts
    expect(amount0.amount).toBe(
      parseEther("1.5") -
        (parseEther("0.5") * ratioAtStrikeNeg1 * Q128) / MaxUint256,
    );
    expect(amount1.amount).toBe(0n);
    expect(position.balance).toBe(parseEther("0.5"));
    expect(
      fractionEqualTo(
        position.data.leverageRatio,
        makeFraction(
          (parseEther("1.5") * Q128) / ratioAtStrikeNeg1,
          parseEther("0.5"),
        ),
      ),
    ).toBe(true);
    expect(amount0.token === token0).toBe(true);
    expect(amount1.token === token1).toBe(true);

    // pair data
    expect(pairData.strikes[1]).toBeTruthy();
    expect(pairData.strikes[1]!.liquidityBorrowed).toStrictEqual([
      parseEther("0.5"),
      0n,
      0n,
      0n,
      0n,
    ]);
    expect(pairData.strikes[1]!.liquidityBiDirectional).toStrictEqual([
      parseEther("0.5"),
      0n,
      0n,
      0n,
      0n,
    ]);
  });

  test("calculate repay liquidity", () => {
    const pairData = calculateInitialize(0);
    calculateAddLiquidity(pair, pairData, 0n, 1, 1, oneEther);
    calculateBorrowLiquidity(
      pair,
      pairData,
      0n,
      1,
      "Token0",
      parseEther("1.5"),
      parseEther("0.5"),
    );
    const { amount0, amount1, position } = calculateRepayLiquidity(
      pair,
      pairData,
      0n,
      1,
      "Token0",
      makeFraction(
        (parseEther("1.5") * Q128) / ratioAtStrikeNeg1,
        parseEther("0.5"),
      ),
      parseEther("0.5"),
    );

    // amounts
    expect(amount0.amount).toBe(
      (parseEther("0.5") * ratioAtStrikeNeg1 * Q128) / MaxUint256 -
        parseEther("1.5") +
        1n,
    );
    expect(amount1.amount).toBe(0n);
    expect(position.balance).toBe(-parseEther("0.5"));
    expect(amount0.token === token0).toBe(true);
    expect(amount1.token === token1).toBe(true);

    // pair data
    expect(pairData.strikes[1]).toBeTruthy();
    expect(pairData.strikes[1]!.liquidityBorrowed).toStrictEqual([
      0n,
      0n,
      0n,
      0n,
      0n,
    ]);
    expect(pairData.strikes[1]!.liquidityBiDirectional).toStrictEqual([
      oneEther,
      0n,
      0n,
      0n,
      0n,
    ]);
  });

  test.todo("calculate swap token 1 exact in", () => {
    const pairData = calculateInitialize(0);
    calculateAddLiquidity(pair, pairData, 0n, 0, 1, oneEther);
    const { amount0, amount1 } = calculateSwap(
      pair,
      pairData,
      makeAmountFromRaw(token1, oneEther - 1n),
    );
    expect(amount0.amount).toBe(oneEther - 1n);
    expect(amount1.amount).toBe(oneEther - 1n);
    expect(amount0.token === token0).toBe(true);
    expect(amount1.token === token1).toBe(true);
  });

  test.todo("calculate accrue", () => {});
});
