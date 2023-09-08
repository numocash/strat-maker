import { createFraction, fractionEqualTo } from "reverse-mirage";
import { describe, expect, test } from "vitest";
import { Q128 } from "./constants.js";
import { fractionToQ128, q128ToFraction } from "./utils.js";

describe.concurrent("utils", () => {
  test("fraction to q128", () => {
    expect(fractionToQ128(createFraction(5, 2))).toBe((Q128 * 5n) / 2n);
  });

  test("q128 to fraction", () => {
    expect(
      fractionEqualTo(q128ToFraction((Q128 * 5n) / 2n), createFraction(5, 2)),
    ).toBe(true);
  });
});
