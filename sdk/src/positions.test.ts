import {
  type PositionBiDirectionalData,
  dataID,
  getTransferTypedDataHash,
  signTransfer,
} from "./positions.js";
import { ALICE, mockERC20 } from "./test/constants.js";
import { anvil, walletClient } from "./test/utils.js";
import { parseEther, recoverAddress } from "viem";
import { describe, expect, test } from "vitest";

describe("positions", () => {
  test("bi directional data id", () => {
    const position = {
      orderType: "BiDirectional",
      data: {
        token0: mockERC20,
        token1: mockERC20,
        strike: 0,
        spread: 1,
      },
    } as const;
    const id = dataID(position);
    expect(id).toBeTruthy();
  });

  // test("limit data id", () => {
  //   const position = {
  //     orderType: "Limit",
  //     data: {
  //       token0: mockERC20,
  //       token1: mockERC20,
  //       strike: 0,
  //       zeroToOne: false,
  //       liquidityGrowthLast: makeFraction(0),
  //     },
  //   } as const;
  //   const id = dataID(position);
  //   expect(id).toBeTruthy();
  // });

  test("debt data id", () => {
    const position = {
      orderType: "Debt",
      data: {
        token0: mockERC20,
        token1: mockERC20,
        strike: 0,
        selectorCollateral: "Token0",
      },
    } as const;
    const id = dataID(position);
    expect(id).toBeTruthy();
  });

  test("sign transfer", async () => {
    const position = {
      position: {
        orderType: "BiDirectional",
        data: {
          token0: mockERC20,
          token1: mockERC20,
          strike: 0,
          spread: 1,
        },
      },
      orderType: "BiDirectional",
      balance: parseEther("1"),
      data: {},
    } as const satisfies PositionBiDirectionalData;
    const datahash = getTransferTypedDataHash(anvil.id, {
      positionData: position,
    });
    const signature = await signTransfer(walletClient, ALICE, {
      positionData: position,
    });
    const address = await recoverAddress({ hash: datahash, signature });
    expect(address).toBe(ALICE);
  });
});
