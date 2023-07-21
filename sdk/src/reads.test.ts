import { CommandEnum, TokenSelectorEnum } from "./constants.js";
import { engineABI, mockErc20ABI, permit3ABI, routerABI } from "./generated.js";
import { engineGetPair } from "./reads.js";
import { ALICE, BOB } from "./test/constants.js";
import { publicClient, testClient, walletClient } from "./test/utils.js";
import { AddLiquidityParams, CreatePairParams } from "./writes.js";
import Engine from "dry-powder/out/Engine.sol/Engine.json";
import MockERC20 from "dry-powder/out/MockERC20.sol/MockERC20.json";
import Router from "dry-powder/out/Router.sol/Router.json";
import Permit3 from "ilrta-evm/out/Permit3.sol/Permit3.json";
import { getTransferTypedDataHash, signSuperSignature } from "ilrta-sdk";
import {
  type Token,
  currencySortsBefore,
  makeCurrencyAmountFromString,
  readAndParse,
} from "reverse-mirage";
import invariant from "tiny-invariant";
import {
  type Hex,
  encodeAbiParameters,
  getAddress,
  parseEther,
  zeroAddress,
} from "viem";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

let token0: Token;
let token1: Token;

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

  // deploy tokens
  deployHash = await walletClient.deployContract({
    account: ALICE,
    abi: mockErc20ABI,
    bytecode: MockERC20.bytecode.object as Hex,
  });
  const { contractAddress: tokenAAddress } =
    await publicClient.waitForTransactionReceipt({
      hash: deployHash,
    });
  invariant(tokenAAddress);

  deployHash = await walletClient.deployContract({
    account: ALICE,
    abi: mockErc20ABI,
    bytecode: MockERC20.bytecode.object as Hex,
  });
  const { contractAddress: tokenBAddress } =
    await publicClient.waitForTransactionReceipt({
      hash: deployHash,
    });
  invariant(tokenBAddress);

  const tokenA = {
    type: "token",
    symbol: "TEST",
    name: "Test ERC20",
    decimals: 18,
    address: getAddress(tokenAAddress),
    chainID: 1,
  } as const satisfies Token;

  const tokenB = {
    type: "token",
    symbol: "TEST",
    name: "Test ERC20",
    decimals: 18,
    address: getAddress(tokenBAddress),
    chainID: 1,
  } as const satisfies Token;

  [token0, token1] = currencySortsBefore(tokenA, tokenB)
    ? [tokenA, tokenB]
    : [tokenB, tokenA];

  // create pair
  const simCreatePair = await publicClient.simulateContract({
    abi: engineABI,
    functionName: "execute",
    address: EngineAddress,
    args: [
      zeroAddress,
      [CommandEnum.CreatePair],
      [
        encodeAbiParameters(CreatePairParams, [
          token0.address,
          token1.address,
          0,
          0,
        ]),
      ],
      0n,
      0n,
      "0x",
    ],
  });
  let hash = await walletClient.writeContract(simCreatePair.request);
  await publicClient.waitForTransactionReceipt({ hash });

  // add liquidity
  const block = await publicClient.getBlock();
  const dataHash = getTransferTypedDataHash(1, {
    transferDetails: makeCurrencyAmountFromString(token0, "1"),
    spender: RouterAddress,
  });
  const signature = await signSuperSignature(walletClient, ALICE, {
    dataHash: [dataHash],
    nonce: 0n,
    deadline: block.timestamp + 100n,
  });

  // const simAddLiquidity = await publicClient.simulateContract({
  //   abi: routerABI,
  //   functionName: "route",
  //   address: RouterAddress,
  //   args: [
  //     {
  //       to: ALICE,
  //       commands: [CommandEnum.AddLiquidity],
  //       inputs: [
  //         encodeAbiParameters(AddLiquidityParams, [
  //           token0.address,
  //           token1.address,
  //           0,
  //           0,
  //           1,
  //           TokenSelectorEnum.LiquidityPosition,
  //           parseEther("1"),
  //         ]),
  //       ],
  //       numLPs: 1n,
  //       numTokens: 1n,
  //       permitTransfers: [{ token: token0.address, amount: parseEther("1") }],
  //       positionTransfers: [],
  //       verify: {
  //         dataHash: [dataHash],
  //         nonce: 0n,
  //         deadline: block.timestamp + 100n,
  //       },
  //       signature,
  //     },
  //     // ALICE,
  //     // [CommandEnum.AddLiquidity],
  //     // [
  //     //   encodeAbiParameters(AddLiquidityParams, [
  //     //     token0.address,
  //     //     token1.address,
  //     //     0,
  //     //     0,
  //     //     1,
  //     //     TokenSelectorEnum.LiquidityPosition,
  //     //     parseEther("1"),
  //     //   ]),
  //     // ],
  //     // 1n,
  //     // 1n,
  //     // signature,
  //   ],
  // });
  // hash = await walletClient.writeContract(simAddLiquidity.request);
  // await publicClient.waitForTransactionReceipt({ hash });
  // borrow liquidity
}, 200_000);

afterAll(async () => {
  await testClient.reset();
});

describe("reads", () => {
  test("read initialized", async () => {
    const pairData = await readAndParse(
      engineGetPair(publicClient, {
        pair: { token0, token1, scalingFactor: 0 },
      }),
    );

    expect(pairData).toBeTruthy();

    expect(pairData.initialized).toBeTruthy();
    expect(pairData.cachedStrikeCurrent).toBe(0);
  });
});
