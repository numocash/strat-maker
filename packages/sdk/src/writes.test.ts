import Engine from "dry-powder/out/Engine.sol/Engine.json";
import MockERC20 from "dry-powder/out/MockERC20.sol/MockERC20.json";
import Permit3 from "dry-powder/out/Permit3.sol/Permit3.json";
import Router from "dry-powder/out/Router.sol/Router.json";
import {
  type ERC20,
  MaxUint256,
  createAmountFromString,
  createFraction,
} from "reverse-mirage";
import invariant from "tiny-invariant";
import { type Hex, getAddress, parseEther } from "viem";
import { beforeEach, describe, test } from "vitest";
import { engineABI, mockErc20ABI, permit3ABI, routerABI } from "./generated.js";
import { type Position, approve, createPosition } from "./positions.js";
import { ALICE } from "./test/constants.js";
import { publicClient, testClient, walletClient } from "./test/utils.js";
import { routerRoute } from "./writes.js";

let id: Hex | undefined = undefined;
let token0: ERC20;
let token1: ERC20;
let position: Position<"BiDirectional">;

beforeEach(async () => {
  if (id === undefined) {
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
      args: ["Mock ERC20", "MOCK", 18],
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
      args: ["Mock ERC20", "MOCK", 18],
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

    console.log(token0, token1);

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
      args: [Permit3Address, MaxUint256],
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
      args: [Permit3Address, MaxUint256],
    });
    hash = await walletClient.writeContract(approveRequest2);
    await publicClient.waitForTransactionReceipt({
      hash,
    });

    position = createPosition(
      "BiDirectional",
      { token0, token1, scalingFactor: 0, strike: 0, spread: 1 },
      1,
    );

    const { hash: approveHash } = await approve(
      publicClient,
      walletClient,
      ALICE,
      {
        spender: Permit3Address,
        approvalDetails: {
          type: "positionApproval",
          ilrta: position,
          approved: true,
        },
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: approveHash });
  } else {
    await testClient.revert({ id });
  }
  id = await testClient.snapshot();
}, 100_000);

describe("writes", () => {
  test("empty command input", async () => {
    const block = await publicClient.getBlock();
    const { hash } = await routerRoute(publicClient, walletClient, ALICE, {
      to: ALICE,
      commands: [],
      nonce: 0n,
      deadline: block.timestamp + 100n,
      slippage: createFraction(2, 100),
    });
    await publicClient.waitForTransactionReceipt({ hash });
  });

  test.todo("wrap weth");

  test.todo("unwrap weth");

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
      slippage: createFraction(2, 100),
    });
    await publicClient.waitForTransactionReceipt({ hash });
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
        slippage: createFraction(2, 100),
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
        slippage: createFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: addHash });
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
        slippage: createFraction(2, 100),
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
        slippage: createFraction(2, 100),
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
        slippage: createFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: removeHash });
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
        slippage: createFraction(2, 100),
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
        slippage: createFraction(2, 100),
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
              amountDesiredCollateral: createAmountFromString(token0, "1.5"),
              amountDesiredDebt: parseEther("0.5"),
            },
          },
        ],
        nonce: 2n,
        deadline: block.timestamp + 100n,
        slippage: createFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({
      hash: borrowHash,
    });
  });

  test.skip("repay liquidity", async () => {
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
        slippage: createFraction(2, 100),
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
        slippage: createFraction(2, 100),
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
              amountDesiredCollateral: createAmountFromString(token0, "1.5"),
              amountDesiredDebt: parseEther("0.5"),
            },
          },
        ],
        nonce: 2n,
        deadline: block.timestamp + 100n,
        slippage: createFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: borrowHash });

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
              liquidityGrowthLast: createFraction(0),
              multiplier: createFraction(1),
              amountDesired: parseEther("0.5"),
            },
          },
        ],
        nonce: 3n,
        deadline: block.timestamp + 150n,
        slippage: createFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: repayHash });
  });

  test.skip("swap", async () => {
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
        slippage: createFraction(2, 100),
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
        slippage: createFraction(2, 100),
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
              amountDesired: createAmountFromString(pair.token1, "0.5"),
            },
          },
        ],
        nonce: 2n,
        deadline: block.timestamp + 100n,
        slippage: createFraction(2, 100),
      },
    );
    await publicClient.waitForTransactionReceipt({ hash: swapHash });
  });

  test.todo("accrue");

  test.todo("borrow and swap");

  test.todo("repay and swap");
});
