import { describe, expect, test } from "vitest";
import { EngineAddress } from "./constants.js";
import { dataID } from "./positions.js";
import { mockERC20 } from "./test/constants.js";

describe("positions", () => {
  test("bi directional data id", () => {
    const position = {
      orderType: "BiDirectional",
      name: "Numoen Dry Powder",
      symbol: "DP",
      address: EngineAddress,
      data: {
        token0: mockERC20,
        token1: mockERC20,
        scalingFactor: 0,
        strike: 0,
        spread: 1,
      },
    } as const;
    const id = dataID(position);
    expect(id).toBeTruthy();
  });

  test("debt data id", () => {
    const position = {
      type: "position",
      chainID: 1,
      orderType: "Debt",
      name: "Numoen Dry Powder",
      symbol: "DP",
      address: EngineAddress,
      data: {
        token0: mockERC20,
        token1: mockERC20,
        scalingFactor: 0,
        strike: 0,
        selectorCollateral: "Token0",
      },
    } as const;
    const id = dataID(position);
    expect(id).toBeTruthy();
  });
});
