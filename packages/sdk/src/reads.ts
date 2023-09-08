import type {
  AbiParametersToPrimitiveTypes,
  ExtractAbiFunction,
} from "abitype";
import { type ReverseMirageRead, createFraction } from "reverse-mirage";
import type { PublicClient } from "viem";
import { EngineAddress } from "./constants.js";
import { engineABI } from "./generated.js";
import {
  type Pair,
  type PairData,
  type Strike,
  type StrikeData,
} from "./types.js";
import { q128ToFraction } from "./utils.js";

/**
 * Read and parse the pair data and then based on the pair data read the currently active strike data
 */
export const engineGetPair = (
  publicClient: PublicClient,
  args: { pair: Pair },
) => {
  return {
    read: async () => {
      const pairData = await publicClient.readContract({
        abi: engineABI,
        address: EngineAddress,
        functionName: "getPair",
        args: [
          args.pair.token0.address,
          args.pair.token1.address,
          args.pair.scalingFactor,
        ],
      });
      const strikeData = await publicClient.readContract({
        abi: engineABI,
        address: EngineAddress,
        functionName: "getStrike",
        args: [
          args.pair.token0.address,
          args.pair.token1.address,
          args.pair.scalingFactor,
          pairData[1][0],
        ],
      });
      return { pairData, strikeData };
    },
    parse: ({ pairData, strikeData }): PairData => ({
      strikes: {
        [pairData[1][0]]: {
          liquidityGrowth: q128ToFraction(strikeData.liquidityGrowthX128),
          liquidityRepayRate: q128ToFraction(strikeData.liquidityRepayRateX128),
          liquidityGrowthSpread: strikeData.liquidityGrowthSpreadX128.map(
            (lg) =>
              lg.liquidityGrowthX128 === 0n
                ? createFraction(1)
                : q128ToFraction(lg.liquidityGrowthX128),
          ) as StrikeData["liquidityGrowthSpread"],
          liquidity: strikeData.liquidity as StrikeData["liquidity"],
          blockLast: strikeData.blockLast,
          next0To1: strikeData.next0To1,
          next1To0: strikeData.next1To0,
          // reference0To1: new Set<Spread>(
          //   [1, 2, 3, 4, 5].map(
          //     (i) => strikeData.reference0To1 & (1 << (i - 1)),
          //   ) as Spread[],
          // ),
          // reference1To0: new Set<Spread>(
          //   [1, 2, 3, 4, 5].map(
          //     (i) => strikeData.reference1To0 & (1 << (i - 1)),
          //   ) as Spread[],
          // ),
          activeSpread: strikeData.activeSpread as 0 | 1 | 2 | 3 | 4,
        },
      },
      composition: [
        q128ToFraction(pairData[0][0]),
        q128ToFraction(pairData[0][1]),
        q128ToFraction(pairData[0][2]),
        q128ToFraction(pairData[0][3]),
        q128ToFraction(pairData[0][4]),
      ],
      strikeCurrent: pairData[1] as PairData["strikeCurrent"],
      initialized: Boolean(pairData[2]),
    }),
  } satisfies ReverseMirageRead<{
    pairData: AbiParametersToPrimitiveTypes<
      ExtractAbiFunction<typeof engineABI, "getPair">["outputs"]
    >;
    strikeData: AbiParametersToPrimitiveTypes<
      ExtractAbiFunction<typeof engineABI, "getStrike">["outputs"]
    >[0];
  }>;
};

/**
 * Read and parse strike data for the specified strike
 */
export const engineGetStrike = (
  publicClient: PublicClient,
  args: { pair: Pair; strike: Strike },
) => {
  return {
    read: () =>
      publicClient.readContract({
        abi: engineABI,
        address: EngineAddress,
        functionName: "getStrike",
        args: [
          args.pair.token0.address,
          args.pair.token1.address,
          0,
          args.strike,
        ],
      }),
    parse: (data): StrikeData => ({
      liquidityGrowth: q128ToFraction(data.liquidityGrowthX128),
      liquidityRepayRate: q128ToFraction(data.liquidityRepayRateX128),
      liquidityGrowthSpread: data.liquidityGrowthSpreadX128.map((lg) =>
        lg.liquidityGrowthX128 === 0n
          ? createFraction(1)
          : q128ToFraction(lg.liquidityGrowthX128),
      ) as StrikeData["liquidityGrowthSpread"],
      liquidity: data.liquidity as StrikeData["liquidity"],
      blockLast: data.blockLast,
      next0To1: data.next0To1,
      next1To0: data.next1To0,
      // reference0To1: new Set<Spread>(
      //   [1, 2, 3, 4, 5].map(
      //     (i) => data.reference0To1 & (1 << (i - 1)),
      //   ) as Spread[],
      // ),
      // reference1To0: new Set<Spread>(
      //   [1, 2, 3, 4, 5].map(
      //     (i) => data.reference1To0 & (1 << (i - 1)),
      //   ) as Spread[],
      // ),
      activeSpread: data.activeSpread as 0 | 1 | 2 | 3 | 4,
    }),
  } satisfies ReverseMirageRead<
    AbiParametersToPrimitiveTypes<
      ExtractAbiFunction<typeof engineABI, "getStrike">["outputs"]
    >[0]
  >;
};
