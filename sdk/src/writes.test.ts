import { engineABI, mockErc20ABI, permit3ABI, routerABI } from "./generated.js";
import { makePosition } from "./positions.js";
import {
  engineGetPair,
  engineGetPositionDebt,
  engineGetStrike,
} from "./reads.js";
import { ALICE } from "./test/constants.js";
import { publicClient, testClient, walletClient } from "./test/utils.js";
import { routerRoute } from "./writes.js";
import Engine from "dry-powder/out/Engine.sol/Engine.json";
import MockERC20 from "dry-powder/out/MockERC20.sol/MockERC20.json";
import Router from "dry-powder/out/Router.sol/Router.json";
import Permit3 from "ilrta-evm/out/Permit3.sol/Permit3.json";
import {
  type ERC20,
  fractionGreaterThan,
  makeAmountFromString,
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
let token0: ERC20;
let token1: ERC20;

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
    type: "erc20",
    symbol: "TEST",
    name: "Test ERC20",
    decimals: 18,
    address: getAddress(tokenAAddress),
    chainID: 1,
  } as const satisfies ERC20;

  const tokenB = {
    type: "erc20",
    symbol: "TEST",
    name: "Test ERC20",
    decimals: 18,
    address: getAddress(tokenBAddress),
    chainID: 1,
  } as const satisfies ERC20;

  [token0, token1] =
    tokenA.address.toLowerCase() < tokenB.address.toLowerCase()
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
    expect(pairData.strikeCurrentCached).toBe(1);
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

    const strikeData = await readAndParse(
      engineGetStrike(publicClient, { pair, strike: 0 }),
    );

    expect(strikeData.liquidityBiDirectional[0]).toBe(0n);
    expect(strikeData.totalSupply[0]).toBe(0n);
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
              strike: 0,
              spread: 1,
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

    const { hash: borrowHash } = await routerRoute(
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
              strike: 0,
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
    await publicClient.waitForTransactionReceipt({
      hash: borrowHash,
    });
    const strikeData = await readAndParse(
      engineGetStrike(publicClient, { pair, strike: 0 }),
    );

    expect(strikeData.liquidityBiDirectional[0]).toBeGreaterThan(0n);
    expect(strikeData.liquidityBorrowed[0]).toBeGreaterThan(0n);
    expect(strikeData.totalSupply[0]).toBe(parseEther("1"));

    const positionData = await readAndParse(
      engineGetPositionDebt(publicClient, {
        owner: ALICE,
        position: makePosition(
          "Debt",
          {
            token0: pair.token0,
            token1: pair.token1,
            scalingFactor: 0,
            strike: 0,
            selectorCollateral: "Token0",
          },
          1,
        ),
      }),
    );
    expect(positionData.balance).toBe(parseEther("0.5"));
    expect(fractionGreaterThan(positionData.data.leverageRatio, 0)).toBe(true);
  });

  test.todo("repay liquidity", async () => {
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

    const { hash: borrowHash } = await routerRoute(
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
              strike: 0,
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
    await publicClient.waitForTransactionReceipt({ hash: borrowHash });

    const positionData = await readAndParse(
      engineGetPositionDebt(publicClient, {
        owner: ALICE,
        position: makePosition(
          "Debt",
          {
            token0: pair.token0,
            token1: pair.token1,
            scalingFactor: 0,
            strike: 0,
            selectorCollateral: "Token0",
          },
          1,
        ),
      }),
    );

    const { hash: repayHash } = await routerRoute(
      publicClient,
      walletClient,
      ALICE,
      {
        to: ALICE,
        commands: [
          {
            command: "RepayLiquidity",
            inputs: {
              pair,
              strike: 0,
              selectorCollateral: "Token0",
              leverageRatio: positionData.data.leverageRatio,
              amountDesiredDebt: positionData.balance,
            },
          },
        ],
        nonce: 3n,
        deadline: block.timestamp + 150n,
        slippage: makeFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: repayHash });

    const strikeData = await readAndParse(
      engineGetStrike(publicClient, { pair, strike: 0 }),
    );

    expect(strikeData.liquidityBiDirectional[0]).toBeGreaterThan(0n);
    expect(strikeData.liquidityBorrowed[0]).toBe(0n);
    expect(strikeData.totalSupply[0]).toBe(parseEther("1"));
  });

  test("swap", async () => {
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

    const { hash: swapHash } = await routerRoute(
      publicClient,
      walletClient,
      ALICE,
      {
        to: ALICE,
        commands: [
          {
            command: "Swap",
            inputs: {
              pair,
              selector: "Token1",
              amountDesired: makeAmountFromString(pair.token1, "0.5").amount,
            },
          },
        ],
        nonce: 2n,
        deadline: block.timestamp + 100n,
        slippage: makeFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: swapHash });

    const pairData = await readAndParse(engineGetPair(publicClient, { pair }));

    expect(fractionGreaterThan(pairData.composition[0], 0)).toBe(true);
  });

  test.todo("accrue");
});
