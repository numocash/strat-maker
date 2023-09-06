import type {
  AbiParametersToPrimitiveTypes,
  ExtractAbiFunction,
} from "abitype";
import type { ReverseMirageRead } from "reverse-mirage";
import type { Address, PublicClient } from "viem";
import { EngineAddress, TokenSelectorEnum } from "./constants.js";
import { engineABI } from "./generated.js";
import type { Position, PositionData } from "./positions.js";
import type { Pair, PairData, Strike, StrikeData } from "./types.js";
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
        args: [args.pair.token0.address, args.pair.token1.address, 0],
      });
      const strikeData = await publicClient.readContract({
        abi: engineABI,
        address: EngineAddress,
        functionName: "getStrike",
        args: [
          args.pair.token0.address,
          args.pair.token1.address,
          0,
          pairData[2],
        ],
      });
      return { pairData, strikeData };
    },
    parse: ({ pairData, strikeData }): PairData => ({
      strikes: {
        [pairData[2]]: {
          liquidityGrowth: q128ToFraction(strikeData.liquidityGrowthX128),
          blockLast: strikeData.blockLast,
          totalSupply: strikeData.totalSupply as StrikeData["totalSupply"],
          liquidityBiDirectional:
            strikeData.liquidityBiDirectional as StrikeData["liquidityBiDirectional"],
          liquidityBorrowed:
            strikeData.liquidityBorrowed as StrikeData["liquidityBorrowed"],
          next0To1: strikeData.next0To1,
          next1To0: strikeData.next1To0,
          activeSpread: strikeData.activeSpread as 0 | 1 | 2 | 3 | 4,
        },
      },
      bitMap0To1: {
        centerStrike: pairData[2],
        words: [0n, 0n, 0n],
      },
      bitMap1To0: {
        centerStrike: pairData[3],
        words: [0n, 0n, 0n],
      },
      composition: [
        q128ToFraction(pairData[0][0]),
        q128ToFraction(pairData[0][1]),
        q128ToFraction(pairData[0][2]),
        q128ToFraction(pairData[0][3]),
        q128ToFraction(pairData[0][4]),
      ],
      strikeCurrent: pairData[1] as PairData["strikeCurrent"],
      strikeCurrentCached: pairData[2],
      initialized: Boolean(pairData[3]),
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
      blockLast: data.blockLast,
      totalSupply: data.totalSupply as StrikeData["totalSupply"],
      liquidityBiDirectional:
        data.liquidityBiDirectional as StrikeData["liquidityBiDirectional"],
      liquidityBorrowed:
        data.liquidityBorrowed as StrikeData["liquidityBorrowed"],
      next0To1: data.next0To1,
      next1To0: data.next1To0,
      activeSpread: data.activeSpread as 0 | 1 | 2 | 3 | 4,
    }),
  } satisfies ReverseMirageRead<
    AbiParametersToPrimitiveTypes<
      ExtractAbiFunction<typeof engineABI, "getStrike">["outputs"]
    >[0]
  >;
};

// TODO: just have get position and infer types
/**
 * Read and parse biDirectional position data
 * @param publicClient f
 * @param args
 * @returns
 */
export const engineGetPositionBiDirectional = (
  publicClient: PublicClient,
  args: { owner: Address; position: Position<"BiDirectional"> },
) => {
  return {
    read: () =>
      publicClient.readContract({
        abi: engineABI,
        address: EngineAddress,
        functionName: "getPositionBiDirectional",
        args: [
          args.owner,
          args.position.data.token0.address,
          args.position.data.token1.address,
          args.position.data.scalingFactor,
          args.position.data.strike,
          args.position.data.spread,
        ],
      }),
    parse: (data): PositionData<"BiDirectional"> => ({
      type: "positionData",
      token: args.position,
      balance: data,
      data: {},
    }),
  } satisfies ReverseMirageRead<
    AbiParametersToPrimitiveTypes<
      ExtractAbiFunction<
        typeof engineABI,
        "getPositionBiDirectional"
      >["outputs"]
    >[0]
  >;
};

/**
 * Read and parse limit position data
 */
// export const engineGetPositionLimit = (
//   publicClient: PublicClient,
//   args: { owner: Address; positionLimit: PositionLimit },
// ) => {
//   return {
//     read: () =>
//       publicClient.readContract({
//         abi: engineABI,
//         address: EngineAddress,
//         functionName: "getPositionLimit",
//         args: [
//           args.owner,
//           args.positionLimit.data.token0.address,
//           args.positionLimit.data.token1.address,
//           0,
//           args.positionLimit.data.strike,
//           args.positionLimit.data.zeroToOne,
//           fractionToQ128(args.positionLimit.data.liquidityGrowthLast),
//         ],
//       }),
//     parse: (data): PositionLimitData => ({
//       position: args.positionLimit,
//       balance: data,
//       orderType: "Limit",
//       data: {},
//     }),
//   } satisfies ReverseMirageRead<
//     AbiParametersToPrimitiveTypes<
//       ExtractAbiFunction<typeof engineABI, "getPositionLimit">["outputs"]
//     >[0]
//   >;
// };

/**
 * Read and parse debt position data
 */
export const engineGetPositionDebt = (
  publicClient: PublicClient,
  args: { owner: Address; position: Position<"Debt"> },
) => {
  return {
    read: () =>
      publicClient.readContract({
        abi: engineABI,
        address: EngineAddress,
        functionName: "getPositionDebt",
        args: [
          args.owner,
          args.position.data.token0.address,
          args.position.data.token1.address,
          args.position.data.scalingFactor,
          args.position.data.strike,
          TokenSelectorEnum[args.position.data.selectorCollateral],
        ],
      }),
    parse: (data): PositionData<"Debt"> => ({
      type: "positionData",
      token: args.position,
      balance: data[0],
      data: { leverageRatio: q128ToFraction(data[1]) },
    }),
  } satisfies ReverseMirageRead<
    AbiParametersToPrimitiveTypes<
      ExtractAbiFunction<typeof engineABI, "getPositionDebt">["outputs"]
    >
  >;
};
