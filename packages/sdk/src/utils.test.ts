import { Q128 } from "./constants.js";
import { fractionToQ128, q128ToFraction } from "./utils.js";
import { fractionEqualTo, makeFraction } from "reverse-mirage";
import { describe, expect, test } from "vitest";

describe.concurrent("utils", () => {
  test("fraction to q128", () => {
    expect(fractionToQ128(makeFraction(5, 2))).toBe((Q128 * 5n) / 2n);
  });

  test("q128 to fraction", () => {
    expect(
      fractionEqualTo(q128ToFraction((Q128 * 5n) / 2n), makeFraction(5, 2)),
    ).toBe(true);
  });
});
