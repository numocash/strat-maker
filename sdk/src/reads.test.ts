import { CommandEnum, TokenSelectorEnum } from "./constants.js";
import { engineABI, mockErc20ABI, permit3ABI, routerABI } from "./generated.js";
import {
  engineGetPair,
  engineGetPositionBiDirectional,
  engineGetPositionDebt,
  engineGetStrike,
} from "./reads.js";
import { ALICE } from "./test/constants.js";
import { publicClient, testClient, walletClient } from "./test/utils.js";
import {
  AddLiquidityParams,
  BorrowLiquidityParams,
  CreatePairParams,
} from "./writes.js";
import Engine from "dry-powder/out/Engine.sol/Engine.json";
import MockERC20 from "dry-powder/out/MockERC20.sol/MockERC20.json";
import Router from "dry-powder/out/Router.sol/Router.json";
import Permit3 from "ilrta-evm/out/Permit3.sol/Permit3.json";
import { getTransferBatchTypedDataHash, signSuperSignature } from "ilrta-sdk";
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
    account: ALICE,
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

  // mint tokens
  const { request: mintRequest1 } = await publicClient.simulateContract({
    abi: mockErc20ABI,
    account: ALICE,
    address: token0.address,
    functionName: "mint",
    args: [ALICE, parseEther("3")],
  });
  let hash = await walletClient.writeContract(mintRequest1);
  await publicClient.waitForTransactionReceipt({
    hash,
  });

  const { request: mintRequest2 } = await publicClient.simulateContract({
    abi: mockErc20ABI,
    account: ALICE,
    address: token1.address,
    functionName: "mint",
    args: [ALICE, parseEther("1")],
  });
  hash = await walletClient.writeContract(mintRequest2);
  await publicClient.waitForTransactionReceipt({
    hash,
  });

  // approve tokens
  const { request: approveRequest1 } = await publicClient.simulateContract({
    abi: mockErc20ABI,
    account: ALICE,
    address: token0.address,
    functionName: "approve",
    args: [Permit3Address, parseEther("3")],
  });
  hash = await walletClient.writeContract(approveRequest1);
  await publicClient.waitForTransactionReceipt({
    hash,
  });

  const { request: approveRequest2 } = await publicClient.simulateContract({
    abi: mockErc20ABI,
    account: ALICE,
    address: token1.address,
    functionName: "approve",
    args: [Permit3Address, parseEther("1")],
  });
  hash = await walletClient.writeContract(approveRequest2);
  await publicClient.waitForTransactionReceipt({
    hash,
  });

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
  hash = await walletClient.writeContract(simCreatePair.request);
  await publicClient.waitForTransactionReceipt({ hash });

  // add liquidity
  const block = await publicClient.getBlock();
  let dataHash = getTransferBatchTypedDataHash(1, {
    transferDetails: [makeCurrencyAmountFromString(token0, "1")],
    spender: RouterAddress,
  });

  let verify = {
    dataHash: [dataHash],
    nonce: 0n,
    deadline: block.timestamp + 100n,
  };
  let signature = await signSuperSignature(walletClient, ALICE, verify);

  const simAddLiquidity = await publicClient.simulateContract({
    abi: routerABI,
    functionName: "route",
    address: RouterAddress,
    account: ALICE,
    args: [
      {
        to: ALICE,
        commands: [CommandEnum.AddLiquidity],
        inputs: [
          encodeAbiParameters(AddLiquidityParams, [
            token0.address,
            token1.address,
            0,
            1,
            1,
            TokenSelectorEnum.LiquidityPosition,
            parseEther("1"),
          ]),
        ],
        numTokens: 1n,
        numLPs: 1n,
        permitTransfers: [
          { token: getAddress(token0.address), amount: parseEther("1") },
        ],
        positionTransfers: [],
        verify,
        signature,
      },
    ],
  });
  hash = await walletClient.writeContract(simAddLiquidity.request);
  await publicClient.waitForTransactionReceipt({ hash });

  // borrow liquidity
  dataHash = getTransferBatchTypedDataHash(1, {
    transferDetails: [makeCurrencyAmountFromString(token0, "1.5")],
    spender: RouterAddress,
  });

  verify = {
    dataHash: [dataHash],
    nonce: 1n,
    deadline: block.timestamp + 100n,
  };
  signature = await signSuperSignature(walletClient, ALICE, verify);

  const simBorrowLiquidity = await publicClient.simulateContract({
    abi: routerABI,
    functionName: "route",
    address: RouterAddress,
    account: ALICE,
    args: [
      {
        to: ALICE,
        commands: [CommandEnum.BorrowLiquidity],
        inputs: [
          encodeAbiParameters(BorrowLiquidityParams, [
            token0.address,
            token1.address,
            0,
            1,
            TokenSelectorEnum.Token0,
            parseEther("1.5"),
            parseEther("0.5"),
          ]),
        ],
        numTokens: 1n,
        numLPs: 1n,
        permitTransfers: [
          { token: getAddress(token0.address), amount: parseEther("1.5") },
        ],
        positionTransfers: [],
        verify,
        signature,
      },
    ],
  });
  hash = await walletClient.writeContract(simBorrowLiquidity.request);
  await publicClient.waitForTransactionReceipt({ hash });
}, 200_000);

afterAll(async () => {
  await testClient.reset();
});

describe("reads", () => {
  test("get pair", async () => {
    const pairData = await readAndParse(
      engineGetPair(publicClient, {
        pair: { token0, token1, scalingFactor: 0 },
      }),
    );

    expect(pairData).toBeTruthy();

    expect(pairData.initialized).toBeTruthy();
    expect(pairData.cachedStrikeCurrent).toBe(0);
  });

  test("get strike", async () => {
    const strikeData = await readAndParse(
      engineGetStrike(publicClient, {
        pair: { token0, token1, scalingFactor: 0 },
        strike: 1,
      }),
    );

    expect(strikeData).toBeTruthy();
    expect(strikeData.totalSupply[0]).toBeGreaterThan(0n);
    expect(strikeData.liquidityBiDirectional[0]).toBeGreaterThan(0n);
    expect(strikeData.liquidityBorrowed[0]).toBeGreaterThan(0n);
  });

  test("get bi directional", async () => {
    const positionData = await readAndParse(
      engineGetPositionBiDirectional(publicClient, {
        owner: ALICE,
        positionBiDirectional: {
          orderType: "BiDirectional",
          data: {
            token0,
            token1,
            scalingFactor: 0,
            strike: 1,
            spread: 1,
          },
        },
      }),
    );

    expect(positionData).toBeTruthy();
    expect(positionData.balance).toBeGreaterThan(0n);
  });

  test("get debt", async () => {
    const positionData = await readAndParse(
      engineGetPositionDebt(publicClient, {
        owner: ALICE,
        positionDebt: {
          orderType: "Debt",
          data: {
            token0,
            token1,
            scalingFactor: 0,
            strike: 1,
            selectorCollateral: "Token0",
          },
        },
      }),
    );

    expect(positionData).toBeTruthy();
    expect(positionData.balance).toBeGreaterThan(0n);
  });
});
