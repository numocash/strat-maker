import { Q128 } from "./constants.js";
import { getAmount0Delta, getAmount1Delta } from "./math.js";
import { MaxUint256 } from "reverse-mirage";
import { parseEther } from "viem";
import { describe, expect, test } from "vitest";

const oneEther = parseEther("1");
const ratioAtStrikeNeg1 = 0xfff97272373d413259a407b06395f90fn;

describe.concurrent("math", () => {
  test("get amount 0 delta", () => {
    expect(getAmount0Delta(oneEther, 0)).toBe(oneEther);
    expect(getAmount0Delta(2n * oneEther, 0)).toBe(2n * oneEther);

    expect(getAmount0Delta(oneEther, 1)).toBe(
      (oneEther * ratioAtStrikeNeg1 * Q128) / MaxUint256,
    );
    expect(getAmount0Delta(oneEther, -1)).toBe(
      (oneEther * Q128) / ratioAtStrikeNeg1,
    );
  });

  test("get amount 1 delta", () => {
    expect(getAmount1Delta(oneEther)).toBe(oneEther);
    expect(getAmount1Delta(2n * oneEther)).toBe(2n * oneEther);
  });

  test.todo("get liquidity amount 0 delta", () => {});

  test.todo("get liquidity amount 1 delta", () => {});

  test.todo("get amount 0 from composition", () => {});

  test.todo("get amount 1 from composition", () => {});

  test.todo("get amount 0 for liquidity", () => {});

  test.todo("get amount 1 for liquidity", () => {});

  test.todo("get amounts for liquidity", () => {});

  test.todo("get liquidity for amount 0", () => {});

  test.todo("get liquidity for amount 1", () => {});

  test.todo("balance to liquidity", () => {});

  test.todo("liquidity to balance", () => {});

  test.todo("debt balance to liquidity", () => {});

  test.todo("debt liquidity to balance", () => {});

  test.todo("get ratio at strike", () => {});

  test.todo("compute swap step", () => {});
});
