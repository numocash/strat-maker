import { engineABI, mockErc20ABI, permit3ABI, routerABI } from "./generated.js";
import { engineGetPair, engineGetStrike } from "./reads.js";
import { ALICE } from "./test/constants.js";
import { publicClient, testClient, walletClient } from "./test/utils.js";
import { routerRoute } from "./writes.js";
import Engine from "dry-powder/out/Engine.sol/Engine.json";
import MockERC20 from "dry-powder/out/MockERC20.sol/MockERC20.json";
import Router from "dry-powder/out/Router.sol/Router.json";
import Permit3 from "ilrta-evm/out/Permit3.sol/Permit3.json";
import {
  type Token,
  currencySortsBefore,
  makeFraction,
  readAndParse,
} from "reverse-mirage";
import invariant from "tiny-invariant";
import { type Hex, getAddress, parseEther } from "viem";
import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  test,
} from "vitest";

let id: Hex;
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
}, 200_000);

beforeEach(async () => {
  if (id !== undefined) await testClient.revert({ id });
  id = await testClient.snapshot();
});

afterAll(async () => {
  await testClient.reset();
});

describe("writes", () => {
  test("create pair", async () => {
    const block = await publicClient.getBlock();
    const pair = { token0, token1, scalingFactor: 0 } as const;
    const { hash } = await routerRoute(publicClient, walletClient, ALICE, {
      to: ALICE,
      commands: [
        {
          command: "CreatePair",
          inputs: {
            pair,
            strike: 1,
          },
        },
      ],
      nonce: 0n,
      deadline: block.timestamp + 100n,
      slippage: makeFraction(2, 100),
    });
    await publicClient.waitForTransactionReceipt({ hash });
    const pairData = await readAndParse(engineGetPair(publicClient, { pair }));
    expect(pairData.initialized).toBe(true);
    expect(pairData.cachedStrikeCurrent).toBe(1);
  });

  test("add liqudity", async () => {
    const block = await publicClient.getBlock();
    const pair = { token0, token1, scalingFactor: 0 } as const;
    const { hash: createHash } = await routerRoute(
      publicClient,
      walletClient,
      ALICE,
      {
        to: ALICE,
        commands: [
          {
            command: "CreatePair",
            inputs: {
              pair,
              strike: 0,
            },
          },
        ],
        nonce: 0n,
        deadline: block.timestamp + 100n,
        slippage: makeFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: createHash });

    const { hash: addHash } = await routerRoute(
      publicClient,
      walletClient,
      ALICE,
      {
        to: ALICE,
        commands: [
          {
            command: "AddLiquidity",
            inputs: {
              pair,
              strike: 0,
              spread: 1,
              tokenSelector: "LiquidityPosition",
              amountDesired: parseEther("1"),
            },
          },
        ],
        nonce: 1n,
        deadline: block.timestamp + 100n,
        slippage: makeFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: addHash });
    const strikeData = await readAndParse(
      engineGetStrike(publicClient, { pair, strike: 0 }),
    );

    expect(strikeData.liquidityBiDirectional[0]).toBe(parseEther("1"));
  });

  test("remove liquidity", async () => {
    const block = await publicClient.getBlock();
    const pair = { token0, token1, scalingFactor: 0 } as const;
    const { hash: createHash } = await routerRoute(
      publicClient,
      walletClient,
      ALICE,
      {
        to: ALICE,
        commands: [
          {
            command: "CreatePair",
            inputs: {
              pair,
              strike: 0,
            },
          },
        ],
        nonce: 0n,
        deadline: block.timestamp + 100n,
        slippage: makeFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: createHash });

    const { hash: addHash } = await routerRoute(
      publicClient,
      walletClient,
      ALICE,
      {
        to: ALICE,
        commands: [
          {
            command: "AddLiquidity",
            inputs: {
              pair,
              strike: 0,
              spread: 1,
              tokenSelector: "LiquidityPosition",
              amountDesired: parseEther("1"),
            },
          },
        ],
        nonce: 1n,
        deadline: block.timestamp + 100n,
        slippage: makeFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: addHash });

    const { hash: removeHash } = await routerRoute(
      publicClient,
      walletClient,
      ALICE,
      {
        to: ALICE,
        commands: [
          {
            command: "RemoveLiquidity",
            inputs: {
              pair,
              strike: 0,
              spread: 1,
              tokenSelector: "LiquidityPosition",
              amountDesired: parseEther("1"),
            },
          },
        ],
        nonce: 2n,
        deadline: block.timestamp + 100n,
        slippage: makeFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: removeHash });
    // const pairData = await readAndParse(engineGetPair(publicClient, { pair }));
  });

  test("borrow liquidity", async () => {
    const block = await publicClient.getBlock();
    const pair = { token0, token1, scalingFactor: 0 } as const;
    const { hash: createHash } = await routerRoute(
      publicClient,
      walletClient,
      ALICE,
      {
        to: ALICE,
        commands: [
          {
            command: "CreatePair",
            inputs: {
              pair,
              strike: 0,
            },
          },
        ],
        nonce: 0n,
        deadline: block.timestamp + 100n,
        slippage: makeFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: createHash });

    const { hash: addHash } = await routerRoute(
      publicClient,
      walletClient,
      ALICE,
      {
        to: ALICE,
        commands: [
          {
            command: "AddLiquidity",
            inputs: {
              pair,
              strike: 1,
              spread: 1,
              tokenSelector: "LiquidityPosition",
              amountDesired: parseEther("1"),
            },
          },
        ],
        nonce: 1n,
        deadline: block.timestamp + 100n,
        slippage: makeFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: addHash });

    const { hash: removeHash } = await routerRoute(
      publicClient,
      walletClient,
      ALICE,
      {
        to: ALICE,
        commands: [
          {
            command: "BorrowLiquidity",
            inputs: {
              pair,
              strike: 1,
              selectorCollateral: "Token0",
              amountDesiredCollateral: parseEther("1.5"),
              amountDesiredDebt: parseEther("0.5"),
            },
          },
        ],
        nonce: 2n,
        deadline: block.timestamp + 100n,
        slippage: makeFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: removeHash });
    // const pairData = await readAndParse(engineGetPair(publicClient, { pair }));
  });

  test.todo("repay liquidity");

  test.todo("swap");

  test.todo("accrue");
});
