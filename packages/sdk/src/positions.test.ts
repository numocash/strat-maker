import { describe, expect, test } from "vitest";
import { createPosition, dataID } from "./positions.js";
import { mockERC20 } from "./test/constants.js";
import { foundry } from "viem/chains";
import { createFraction } from "reverse-mirage";

describe("positions", () => {
  test("bi directional data id", () => {
    const position = createPosition(
      "BiDirectional",
      {
        token0: mockERC20,
        token1: mockERC20,
        scalingFactor: 0,
        strike: 0,
        spread: 1,
      },
      foundry.id,
    );
    const id = dataID(position);
    expect(id).toBeTruthy();
  });

  test("debt data id", () => {
    const position = createPosition(
      "Debt",
      {
        token0: mockERC20,
        token1: mockERC20,
        scalingFactor: 0,
        strike: 0,
        selectorCollateral: "Token1",
        liquidityGrowthLast: createFraction(1),
        multiplier: createFraction(2),
      },
      foundry.id,
    );
    const id = dataID(position);
    expect(id).toBeTruthy();
  });
});
