import { MaxUint256 } from "reverse-mirage";
import { parseEther } from "viem";
import { describe, expect, test } from "vitest";
import { Q128 } from "./constants.js";
import { getAmount0, getAmount1 } from "./math.js";

const oneEther = parseEther("1");
const ratioAtStrikeNeg1 = 0xfff97272373d413259a407b06395f90fn;

describe.concurrent("math", () => {
  test("get amount 0 delta", () => {
    expect(getAmount0(oneEther, 0, false)).toBe(oneEther);
    expect(getAmount0(2n * oneEther, 0, false)).toBe(2n * oneEther);

    expect(getAmount0(oneEther, 1, false)).toBe(
      (oneEther * ratioAtStrikeNeg1 * Q128) / MaxUint256,
    );
    expect(getAmount0(oneEther, -1, false)).toBe(
      (oneEther * Q128) / ratioAtStrikeNeg1,
    );
  });

  test("get amount 1 delta", () => {
    expect(getAmount1(oneEther)).toBe(oneEther);
    expect(getAmount1(2n * oneEther)).toBe(2n * oneEther);
  });

  test.todo("get liquidity amount 0 delta", () => {});

  test.todo("get liquidity amount 1 delta", () => {});

  test.todo("get amount 0 from composition", () => {});

  test.todo("get amount 1 from composition", () => {});

  test.todo("get amount 0 for liquidity", () => {});

  test.todo("get amount 1 for liquidity", () => {});

  test.todo("get amounts for liquidity", () => {});

  test.todo("balance to liquidity", () => {});

  test.todo("liquidity to balance", () => {});

  test.todo("debt balance to liquidity", () => {});

  test.todo("get ratio at strike", () => {});

  test.todo("compute swap step", () => {});
});
