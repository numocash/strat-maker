import { engineABI, permit3ABI, routerABI } from "./generated.js";
import { ALICE, BOB } from "./test/constants.js";
import { publicClient, testClient, walletClient } from "./test/utils.js";
import Engine from "dry-powder/out/Engine.sol/Engine.json";
import Router from "dry-powder/out/Router.sol/Router.json";
import Permit3 from "ilrta-evm/out/Permit3.sol/Permit3.json";
import invariant from "tiny-invariant";
import { type Hex, getAddress } from "viem";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

beforeAll(async () => {
  // deploy permit3
  let deployHash = await walletClient.deployContract({
    account: ALICE,
    abi: permit3ABI,
    bytecode: Permit3.bytecode.object as Hex,
  });

  const { contractAddress: Permit3Address } =
    await publicClient.waitForTransactionReceipt({
      hash: deployHash,
    });
  invariant(Permit3Address);
  console.log("permit 3 address", Permit3Address);

  // deploy engine
  deployHash = await walletClient.deployContract({
    account: BOB,
    abi: engineABI,
    bytecode: Engine.bytecode.object as Hex,
    args: [getAddress(Permit3Address)],
  });

  const { contractAddress: EngineAddress } =
    await publicClient.waitForTransactionReceipt({
      hash: deployHash,
    });
  invariant(EngineAddress);
  console.log("engine address", EngineAddress);

  // deploy router
  deployHash = await walletClient.deployContract({
    account: ALICE,
    abi: routerABI,
    bytecode: Router.bytecode.object as Hex,
    args: [EngineAddress, Permit3Address],
  });

  const { contractAddress: RouterAddress } =
    await publicClient.waitForTransactionReceipt({
      hash: deployHash,
    });
  invariant(RouterAddress);
  console.log("router address", RouterAddress);

  // create pair
  // add liquidity
  // borrow liquidity
}, 200_000);

afterAll(async () => {
  await testClient.reset();
});

describe("reads", () => {});
