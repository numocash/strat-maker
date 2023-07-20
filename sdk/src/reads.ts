import { EngineAddress, TokenSelectorEnum } from "./constants.js";
import { engineABI } from "./generated.js";
import type {
  PositionBiDirectional,
  PositionBiDirectionalData,
  PositionDebt,
  PositionDebtData,
} from "./positions.js";
import type { Pair, PairData, Strike, StrikeData } from "./types.js";
import { q128ToFraction } from "./utils.js";
import type {
  AbiParametersToPrimitiveTypes,
  ExtractAbiFunction,
} from "abitype";
import type { ReverseMirageRead } from "reverse-mirage";
import type { Address, PublicClient } from "viem";

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
          pairData[3],
        ],
      });
      return { pairData, strikeData };
    },
    parse: ({ pairData, strikeData }): PairData => ({
      strikes: {
        [pairData[3]]: {
          // limitData: {
          //   liquidity0To1: strikeData.limit.liquidity0To1,
          //   liquidity1To0: strikeData.limit.liquidity1To0,
          //   liquidity0InPerLiquidity: q128ToFraction(
          //     strikeData.limit.liquidity0InPerLiquidity,
          //   ),
          //   liquidity1InPerLiquidity: q128ToFraction(
          //     strikeData.limit.liquidity1InPerLiquidity,
          //   ),
          // },
          totalSupply: strikeData.totalSupply as StrikeData["totalSupply"],
          liquidityBiDirectional:
            strikeData.liquidityBiDirectional as StrikeData["liquidityBiDirectional"],
          liquidityBorrowed:
            strikeData.liquidityBorrowed as StrikeData["liquidityBorrowed"],
          liquidityGrowth: q128ToFraction(strikeData.liquidityGrowthX128),
          next0To1: strikeData.next0To1,
          next1To0: strikeData.next1To0,
          activeSpread: strikeData.activeSpread as 0 | 1 | 2 | 3 | 4,
        },
      },
      bitMap0To1: {
        centerStrike: pairData[3],
        words: [0n, 0n, 0n],
      },
      bitMap1To0: {
        centerStrike: pairData[3],
        words: [0n, 0n, 0n],
      },
      cachedBlock: pairData[0],
      composition: [
        q128ToFraction(pairData[1][0]),
        q128ToFraction(pairData[1][1]),
        q128ToFraction(pairData[1][2]),
        q128ToFraction(pairData[1][3]),
        q128ToFraction(pairData[1][4]),
      ],
      strikeCurrent: pairData[2] as PairData["strikeCurrent"],
      cachedStrikeCurrent: pairData[3],
      initialized: Boolean(pairData[4]),
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
      // limitData: {
      //   liquidity0To1: data.limit.liquidity0To1,
      //   liquidity1To0: data.limit.liquidity1To0,
      //   liquidity0InPerLiquidity: q128ToFraction(
      //     data.limit.liquidity0InPerLiquidity,
      //   ),
      //   liquidity1InPerLiquidity: q128ToFraction(
      //     data.limit.liquidity1InPerLiquidity,
      //   ),
      // },
      totalSupply: data.totalSupply as StrikeData["totalSupply"],
      liquidityBiDirectional:
        data.liquidityBiDirectional as StrikeData["liquidityBiDirectional"],
      liquidityBorrowed:
        data.liquidityBorrowed as StrikeData["liquidityBorrowed"],
      liquidityGrowth: q128ToFraction(data.liquidityGrowthX128),
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

/**
 * Read and parse biDirectional position data
 * @param publicClient f
 * @param args
 * @returns
 */
export const engineGetPositionBiDirectional = (
  publicClient: PublicClient,
  args: { owner: Address; positionBiDirectional: PositionBiDirectional },
) => {
  return {
    read: () =>
      publicClient.readContract({
        abi: engineABI,
        address: EngineAddress,
        functionName: "getPositionBiDirectional",
        args: [
          args.owner,
          args.positionBiDirectional.data.token0.address,
          args.positionBiDirectional.data.token1.address,
          0,
          args.positionBiDirectional.data.strike,
          args.positionBiDirectional.data.spread,
        ],
      }),
    parse: (data): PositionBiDirectionalData => ({
      position: args.positionBiDirectional,
      balance: data,
      orderType: "BiDirectional",
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
  args: { owner: Address; positionDebt: PositionDebt },
) => {
  return {
    read: () =>
      publicClient.readContract({
        abi: engineABI,
        address: EngineAddress,
        functionName: "getPositionDebt",
        args: [
          args.owner,
          args.positionDebt.data.token0.address,
          args.positionDebt.data.token1.address,
          0,
          args.positionDebt.data.strike,
          TokenSelectorEnum[args.positionDebt.data.selectorCollateral],
        ],
      }),
    parse: (data): PositionDebtData => ({
      position: args.positionDebt,
      balance: data[0],
      orderType: "Debt",
      data: { leverageRatio: q128ToFraction(data[1]) },
    }),
  } satisfies ReverseMirageRead<
    AbiParametersToPrimitiveTypes<
      ExtractAbiFunction<typeof engineABI, "getPositionDebt">["outputs"]
    >
  >;
};
