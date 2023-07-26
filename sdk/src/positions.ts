import {
  EngineAddress,
  OrderTypeEnum,
  TokenSelectorEnum,
} from "./constants.js";
import type { OrderType, Spread, Strike, TokenSelector } from "./types.js";
import {
  type ILRTA,
  type ILRTAData,
  type ILRTARequestedTransfer,
  type ILRTASignatureTransfer,
  ILRTASuperSignatureTransfer,
  ILRTATransfer,
  type ILRTATransferDetails,
} from "ilrta-sdk";
import type { ERC20, Fraction } from "reverse-mirage";
import invariant from "tiny-invariant";
import {
  type Account,
  type Address,
  type Hex,
  type WalletClient,
  encodeAbiParameters,
  getAddress,
  hashTypedData,
  keccak256,
} from "viem";

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
      };
};

export type PositionData<TOrderType extends OrderType> = ILRTAData<
  Position<TOrderType>,
  {
    balance: bigint;
    data: TOrderType extends "BiDirectional" ? {} : { leverageRatio: Fraction };
  }
>;

export const makePosition = <TOrderType extends OrderType>(
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
  id: dataID({ orderType, data }),
});

export type PositionTransferDetails<TOrderType extends OrderType> =
  ILRTATransferDetails<Position<TOrderType>, { amount: bigint }>;

export type SignatureTransfer<TOrderType extends OrderType> =
  ILRTASignatureTransfer<PositionTransferDetails<TOrderType>>;

export type RequestedTransfer<TOrderType extends OrderType> =
  ILRTARequestedTransfer<PositionTransferDetails<TOrderType>>;

export const Data = [
  { name: "balance", type: "uint128" },
  { name: "orderType", type: "uint8" },
  { name: "data", type: "bytes" },
] as const;

export const TransferDetails = [
  { name: "id", type: "bytes32" },
  { name: "orderType", type: "uint8" },
  { name: "amount", type: "uint128" },
] as const;

export const Transfer = ILRTATransfer(TransferDetails);

export const SuperSignatureTransfer =
  ILRTASuperSignatureTransfer(TransferDetails);

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
      { name: "scalingFactor", type: "uint8" },
      { name: "strike", type: "int24" },
      { name: "spread", type: "uint8" },
    ],
    name: "biDirectionalID",
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
    ],
    name: "debtID",
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
            },
          ]),
        },
      ]),
    );
  }
};

export const getTransferTypedDataHash = (
  chainID: number,
  transfer: {
    positionData: PositionData<OrderType>;
    spender: Address;
  },
): Hex => {
  const domain = {
    name: "Numoen Dry Powder",
    version: "1",
    chainId: chainID,
    verifyingContract: EngineAddress,
  } as const;

  const id = dataID(transfer.positionData.token);

  return hashTypedData({
    domain,
    types: SuperSignatureTransfer,
    primaryType: "Transfer",
    message: {
      transferDetails: {
        id,
        orderType: OrderTypeEnum[transfer.positionData.token.orderType],
        amount: transfer.positionData.balance,
      },
      spender: getAddress(transfer.spender),
    },
  });
};

export const signTransfer = (
  walletClient: WalletClient,
  account: Account | Address,
  transfer: SignatureTransfer<OrderType> & { spender: Address },
): Promise<Hex> => {
  const chainID = walletClient.chain?.id;
  invariant(chainID);

  const domain = {
    name: "Numoen Dry Powder",
    version: "1",
    chainId: chainID,
    verifyingContract: EngineAddress,
  } as const;

  const id = dataID(transfer.transferDetails.ilrta);

  return walletClient.signTypedData({
    domain,
    account,
    types: Transfer,
    primaryType: "Transfer",
    message: {
      transferDetails: {
        id,
        orderType: OrderTypeEnum[transfer.transferDetails.ilrta.orderType],
        amount: transfer.transferDetails.amount,
      },
      spender: transfer.spender,
      nonce: transfer.nonce,
      deadline: transfer.deadline,
    },
  });
};
