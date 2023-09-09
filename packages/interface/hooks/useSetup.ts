import { ALICE } from "@/constants";
import { useEnvironment } from "@/contexts/environment";
import { testClient, walletClient } from "@/pages/_app";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import Engine from "dry-powder/out/Engine.sol/Engine.json";
import MockERC20 from "dry-powder/out/MockERC20.sol/MockERC20.json";
import Permit3 from "dry-powder/out/Permit3.sol/Permit3.json";
import Router from "dry-powder/out/Router.sol/Router.json";
import { MaxUint256, createErc20 } from "reverse-mirage";
import invariant from "tiny-invariant";
import { type Hex, getAddress, parseEther } from "viem";
import { useChainId, usePublicClient } from "wagmi";
import { engineABI, mockErc20ABI, permit3ABI, routerABI } from "../generated";

export const useSetup = () => {
  const publicClient = usePublicClient();
  const queryClient = useQueryClient();
  const chainID = useChainId();
  const { id, setID, setPair, setRouter, setPermit } = useEnvironment();

  return useMutation({
    mutationFn: async () => {
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
        setPermit(Permit3Address);

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
        setRouter(RouterAddress);

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

        const tokenA = createErc20(tokenAAddress, "token a", "a", 18, chainID);

        const tokenB = createErc20(tokenBAddress, "token b", "b", 18, chainID);

        const [token0, token1] =
          tokenA.address.toLowerCase() < tokenB.address.toLowerCase()
            ? [tokenA, tokenB]
            : [tokenB, tokenA];

        const pair = { token0, token1, scalingFactor: 0 } as const;
        setPair(pair);

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
        const { request: approveRequest1 } =
          await publicClient.simulateContract({
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

        const { request: approveRequest2 } =
          await publicClient.simulateContract({
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

        // const { hash: routeHash } = await routerRoute(
        //   publicClient,
        //   walletClient,
        //   ALICE,
        //   {
        //     to: ALICE,
        //     commands: [
        //       {
        //         command: "CreatePair",
        //         inputs: {
        //           pair,
        //           strike: 0,
        //         },
        //       },
        //       {
        //         command: "AddLiquidity",
        //         inputs: {
        //           pair,
        //           strike: 0,
        //           spread: 1,
        //           amountDesired: parseEther("1"),
        //         },
        //       },
        //     ],
        //     nonce: 0n,
        //     deadline: MaxUint256,
        //     slippage: createFraction(2, 100),
        //   },
        // );
        // await publicClient.waitForTransactionReceipt({ hash: routeHash });

        // const { hash: addHash } = await routerRoute(
        //   publicClient,
        //   walletClient,
        //   ALICE,
        //   {
        //     to: ALICE,
        //     commands: [
        // {
        //   command: "AddLiquidity",
        //   inputs: {
        //     pair,
        //     strike: 0,
        //     spread: 1,
        //     amountDesired: parseEther("1"),
        //   },
        // },
        //     ],
        //     nonce: 1n,
        //     deadline: block.timestamp + 100n,
        //     slippage: createFraction(2, 100),
        //   },
        // );
        // await publicClient.waitForTransactionReceipt({ hash: addHash });

        // const { hash: borrowHash } = await routerRoute(
        //   publicClient,
        //   walletClient,
        //   ALICE,
        //   {
        //     to: ALICE,
        //     commands: [
        //       {
        //         command: "BorrowLiquidity",
        //         inputs: {
        //           pair,
        //           strike: 0,
        //           amountDesiredCollateral: createAmountFromString(
        //             token0,
        //             "1.5",
        //           ),
        //           amountDesiredDebt: parseEther("0.5"),
        //         },
        //       },
        //     ],
        //     nonce: 2n,
        //     deadline: block.timestamp + 100n,
        //     slippage: createFraction(2, 100),
        //   },
        // );
        // await publicClient.waitForTransactionReceipt({
        //   hash: borrowHash,
        // });

        setID(await testClient.snapshot());
      } else {
        await testClient.revert({ id });
        setID(await testClient.snapshot());
        await queryClient.invalidateQueries();
      }
    },
    retry: false,
  });
};
