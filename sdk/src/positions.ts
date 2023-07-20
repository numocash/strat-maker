import {
  EngineAddress,
  OrderTypeEnum,
  TokenSelectorEnum,
} from "./constants.js";
import type { OrderType, Spread, Strike, TokenSelector } from "./types.js";
import { fractionToQ128 } from "./utils.js";
import type { Fraction, Token } from "reverse-mirage";
import invariant from "tiny-invariant";
import {
  type Account,
  type Address,
  type Hex,
  type WalletClient,
  encodeAbiParameters,
  hashTypedData,
  keccak256,
} from "viem";

type ILRTADataID<TOrderType extends OrderType, TIDData extends object> = {
  orderType: TOrderType;
  data: TIDData;
};

type ILRTAData<
  TPosition extends ILRTADataID<OrderType, object>,
  TData extends object,
> = {
  position: TPosition;
  balance: bigint;
  orderType: TPosition["orderType"];
  data: TData;
};

export type PositionBiDirectional = ILRTADataID<
  "BiDirectional",
  {
    token0: Token;
    token1: Token;
    strike: Strike;
    spread: Spread;
  }
>;

export type PositionLimit = ILRTADataID<
  "Limit",
  {
    token0: Token;
    token1: Token;
    strike: Strike;
    zeroToOne: boolean;
    liquidityGrowthLast: Fraction;
  }
>;

export type PositionDebt = ILRTADataID<
  "Debt",
  {
    token0: Token;
    token1: Token;
    strike: Strike;
    selectorCollateral: Exclude<TokenSelector, "LiquidityPosition">;
  }
>;

export type PositionBiDirectionalData = ILRTAData<PositionBiDirectional, {}>;

export type PositionLimitData = ILRTAData<PositionLimit, {}>;

export type PositionDebtData = ILRTAData<
  PositionDebt,
  { leverageRatio: Fraction }
>;

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
    name: "ilrtaDataID",
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
      { name: "strike", type: "int24" },
      { name: "spread", type: "uint8" },
    ],
    name: "biDirectionalID",
    type: "tuple",
  },
] as const;

export const LimitID = [
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
      { name: "strike", type: "int24" },
      { name: "zeroToOne", type: "bool" },
      { name: "liquidityGrowthLast", type: "uint256" },
    ],
    name: "limitID",
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
      { name: "strike", type: "int24" },
      { name: "selector", type: "uint8" },
    ],
    name: "debtID",
    type: "tuple",
  },
] as const;

export const dataID = (
  position: PositionBiDirectional | PositionLimit | PositionDebt,
): Hex =>
  position.orderType === "BiDirectional"
    ? keccak256(
        encodeAbiParameters(ILRTADataID, [
          {
            orderType: OrderTypeEnum.BiDirectional,
            data: encodeAbiParameters(BiDirectionalID, [
              {
                token0: position.data.token0.address,
                token1: position.data.token1.address,
                strike: position.data.strike,
                spread: position.data.spread,
              },
            ]),
          },
        ]),
      )
    : position.orderType === "Limit"
    ? keccak256(
        encodeAbiParameters(ILRTADataID, [
          {
            orderType: OrderTypeEnum.Limit,
            data: encodeAbiParameters(LimitID, [
              {
                token0: position.data.token0.address,
                token1: position.data.token1.address,
                strike: position.data.strike,
                zeroToOne: position.data.zeroToOne,
                liquidityGrowthLast: fractionToQ128(
                  position.data.liquidityGrowthLast,
                ),
              },
            ]),
          },
        ]),
      )
    : keccak256(
        encodeAbiParameters(ILRTADataID, [
          {
            orderType: OrderTypeEnum.Debt,
            data: encodeAbiParameters(DebtID, [
              {
                token0: position.data.token0.address,
                token1: position.data.token1.address,
                strike: position.data.strike,
                selector: TokenSelectorEnum[position.data.selectorCollateral],
              },
            ]),
          },
        ]),
      );

const ILRTATransferDetails = {
  ILRTATransferDetails: [
    {
      name: "id",
      type: "bytes32",
    },
    { name: "amount", type: "uint256" },
    { name: "orderType", type: "uint8" },
  ],
} as const;

export const getTransferTypedDataHash = (
  chainID: number,
  transfer: {
    positionData:
      | PositionBiDirectionalData
      | PositionLimitData
      | PositionDebtData;
  },
): Hex => {
  const domain = {
    name: "Numoen Dry Powder",
    version: "1",
    chainId: chainID,
    verifyingContract: EngineAddress,
  } as const;

  const id = dataID(transfer.positionData.position);

  return hashTypedData({
    domain,
    types: ILRTATransferDetails,
    primaryType: "ILRTATransferDetails",
    message: {
      id,
      orderType: OrderTypeEnum[transfer.positionData.orderType],
      amount: transfer.positionData.balance,
    },
  });
};

export const signTransfer = (
  walletClient: WalletClient,
  account: Account | Address,
  transfer: {
    positionData:
      | PositionBiDirectionalData
      | PositionLimitData
      | PositionDebtData;
  },
): Promise<Hex> => {
  const chainID = walletClient.chain?.id;
  invariant(chainID);

  const domain = {
    name: "Numoen Dry Powder",
    version: "1",
    chainId: chainID,
    verifyingContract: EngineAddress,
  } as const;

  const id = dataID(transfer.positionData.position);

  return walletClient.signTypedData({
    domain,
    account,
    types: ILRTATransferDetails,
    primaryType: "ILRTATransferDetails",
    message: {
      id,
      orderType: OrderTypeEnum[transfer.positionData.orderType],
      amount: transfer.positionData.balance,
    },
  });
};
