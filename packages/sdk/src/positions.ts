import {
  type ILRTA,
  type ILRTAApprovalDetails,
  type ILRTAData,
  type ILRTATransferDetails,
} from "ilrta-sdk";
import type {
  ERC20,
  Fraction,
  ReverseMirageRead,
  ReverseMirageWrite,
} from "reverse-mirage";
import invariant from "tiny-invariant";
import {
  type Account,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
  encodeAbiParameters,
  keccak256,
} from "viem";
import {
  EngineAddress,
  OrderTypeEnum,
  TokenSelectorEnum,
} from "./constants.js";
import { positionsABI } from "./generated.js";
import type { OrderType, Spread, Strike, TokenSelector } from "./types.js";
import { fractionToQ128 } from "./utils.js";

export type Position<TOrderType extends OrderType> = ILRTA<"position"> & {
  name: "Numoen Dry Powder";
  symbol: "DP";
  orderType: TOrderType;
  data: TOrderType extends "BiDirectional"
    ? {
        token0: ERC20;
        token1: ERC20;
        scalingFactor: number;
        strike: Strike;
        spread: Spread;
      }
    : {
        token0: ERC20;
        token1: ERC20;
        scalingFactor: number;
        strike: Strike;
        selectorCollateral: TokenSelector;
        liquidityGrowthLast: Fraction;
        multiplier: Fraction;
      };
};

export type PositionData<TOrderType extends OrderType> = ILRTAData<
  Position<TOrderType>,
  {
    balance: bigint;
  }
>;

export const createPosition = <TOrderType extends OrderType>(
  orderType: TOrderType,
  data: Position<TOrderType>["data"],
  chainID: number,
): Position<TOrderType> => ({
  type: "position",
  chainID: chainID,
  orderType,
  name: "Numoen Dry Powder",
  symbol: "DP",
  address: EngineAddress,
  data,
});

export type TransferDetailsType<TOrderType extends OrderType> =
  ILRTATransferDetails<Position<TOrderType>, { amount: bigint }>;

export type ApprovalDetailsType<TOrderType extends OrderType> =
  ILRTAApprovalDetails<Position<TOrderType>, { approved: boolean }>;

export const Data = [{ name: "balance", type: "uint128" }] as const;

export const PositionTransferDetails = [
  { name: "id", type: "bytes32" },
  { name: "amount", type: "uint128" },
] as const;

export const PositionApprovalDetails = [
  { name: "approved", type: "bool" },
] as const;

export const ILRTADataID = [
  {
    components: [
      {
        name: "orderType",
        type: "uint8",
      },
      {
        name: "data",
        type: "bytes",
      },
    ],
    name: "ILRTADataID",
    type: "tuple",
  },
] as const;

export const BiDirectionalID = [
  {
    components: [
      {
        name: "token0",
        type: "address",
      },
      {
        name: "token1",
        type: "address",
      },
      { name: "scalingFactor", type: "uint8" },
      { name: "strike", type: "int24" },
      { name: "spread", type: "uint8" },
    ],
    name: "BiDirectionalID",
    type: "tuple",
  },
] as const;

export const DebtID = [
  {
    components: [
      {
        name: "token0",
        type: "address",
      },
      {
        name: "token1",
        type: "address",
      },
      { name: "scalingFactor", type: "uint8" },
      { name: "strike", type: "int24" },
      { name: "selector", type: "uint8" },
      { name: "liquidityGrowthX128Last", type: "uint256" },
      { name: "multiplier", type: "uint136" },
    ],
    name: "DebtID",
    type: "tuple",
  },
] as const;

export const positionIsBiDirectional = (
  position: Pick<Position<OrderType>, "orderType">,
): position is Position<"BiDirectional"> =>
  position.orderType === "BiDirectional";

export const positionIsDebt = (
  position: Pick<Position<OrderType>, "orderType">,
): position is Position<"Debt"> => position.orderType === "Debt";

export const dataID = (
  position: Pick<Position<OrderType>, "orderType" | "data">,
): Hex => {
  if (positionIsBiDirectional(position))
    return keccak256(
      encodeAbiParameters(ILRTADataID, [
        {
          orderType: OrderTypeEnum.BiDirectional,
          data: encodeAbiParameters(BiDirectionalID, [
            {
              token0: position.data.token0.address,
              token1: position.data.token1.address,
              scalingFactor: position.data.scalingFactor,
              strike: position.data.strike,
              spread: position.data.spread,
            },
          ]),
        },
      ]),
    );
  else {
    invariant(positionIsDebt(position));
    return keccak256(
      encodeAbiParameters(ILRTADataID, [
        {
          orderType: OrderTypeEnum.Debt,
          data: encodeAbiParameters(DebtID, [
            {
              token0: position.data.token0.address,
              token1: position.data.token1.address,
              scalingFactor: position.data.scalingFactor,
              strike: position.data.strike,
              selector: TokenSelectorEnum[position.data.selectorCollateral],
              liquidityGrowthX128Last: fractionToQ128(
                position.data.liquidityGrowthLast,
              ),
              multiplier: fractionToQ128(position.data.multiplier),
            },
          ]),
        },
      ]),
    );
  }
};

export const transfer = async <TOrderType extends OrderType>(
  publicClient: PublicClient,
  walletClient: WalletClient,
  account: Account | Address,
  args: { to: Address; transferDetails: TransferDetailsType<TOrderType> },
): Promise<ReverseMirageWrite<typeof positionsABI, "transfer_oHLEec">> => {
  const { request, result } = await publicClient.simulateContract({
    account,
    abi: positionsABI,
    functionName: "transfer_oHLEec",
    args: [
      args.to,
      {
        id: dataID(args.transferDetails.ilrta),
        amount: args.transferDetails.amount,
      },
    ],
    address: args.transferDetails.ilrta.address,
  });
  const hash = await walletClient.writeContract(request);
  return { hash, result, request };
};

// transferFrom

export const approve = async <TOrderType extends OrderType>(
  publicClient: PublicClient,
  walletClient: WalletClient,
  account: Account | Address,
  args: { spender: Address; approvalDetails: ApprovalDetailsType<TOrderType> },
): Promise<ReverseMirageWrite<typeof positionsABI, "approve_BKoIou">> => {
  const { request, result } = await publicClient.simulateContract({
    account,
    abi: positionsABI,
    functionName: "approve_BKoIou",
    args: [
      args.spender,
      {
        approved: args.approvalDetails.approved,
      },
    ],
    address: args.approvalDetails.ilrta.address,
  });
  const hash = await walletClient.writeContract(request);
  return { hash, result, request };
};

export const dataOf = <TOrderType extends OrderType>(
  publicClient: PublicClient,
  args: { position: Position<TOrderType>; owner: Address },
) =>
  ({
    read: () =>
      publicClient.readContract({
        abi: positionsABI,
        address: args.position.address,
        functionName: "dataOf_cGJnTo",
        args: [args.owner, dataID(args.position)],
      }),
    parse: (data): PositionData<TOrderType> => ({
      type: "positionData",
      token: args.position,
      balance: data.balance,
    }),
  }) satisfies ReverseMirageRead<{
    balance: bigint;
  }>;

export const allowanceOf = <TOrderType extends OrderType>(
  publicClient: PublicClient,
  args: { position: Position<TOrderType>; owner: Address; spender: Address },
) =>
  ({
    read: () =>
      publicClient.readContract({
        abi: positionsABI,
        address: args.position.address,
        functionName: "allowanceOf_QDmnOj",
        args: [args.owner, args.spender, dataID(args.position)],
      }),
    parse: (data): ApprovalDetailsType<TOrderType> => ({
      type: "positionApproval",
      ilrta: args.position,
      approved: data.approved,
    }),
  }) satisfies ReverseMirageRead<{
    approved: boolean;
  }>;
