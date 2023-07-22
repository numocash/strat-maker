import {
  calculateAccrue,
  calculateAddLiquidity,
  calculateBorrowLiquidity,
  calculateRemoveLiquidity,
  calculateRepayLiquidity,
  calculateSwap,
} from "./amounts.js";
import {
  CommandEnum,
  OrderTypeEnum,
  RouterAddress,
  TokenSelectorEnum,
} from "./constants.js";
import { routerABI } from "./generated.js";
import { addDebtPositions } from "./math.js";
import {
  type PositionData,
  dataID,
  getTransferTypedDataHash as getTransferTypedDataHashLP,
  positionIsBiDirectional,
} from "./positions.js";
import { engineGetPair } from "./reads.js";
import type { Command, OrderType } from "./types.js";
import { fractionToQ128 } from "./utils.js";
import { signSuperSignature } from "ilrta-sdk";
import { getTransferBatchTypedDataHash } from "ilrta-sdk";
import {
  currencyAmountAdd,
  currencyAmountGreaterThan,
  currencyEqualTo,
  fractionAdd,
  fractionMultiply,
  fractionQuotient,
  readAndParse,
} from "reverse-mirage";
import type {
  CurrencyAmount,
  Fraction,
  ReverseMirageWrite,
  Token,
} from "reverse-mirage";
import {
  type Account as ViemAccount,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
  encodeAbiParameters,
} from "viem";

// TODO: write directly to engine when doing actions that don't require payment

export const routerRoute = async (
  publicClient: PublicClient,
  walletClient: WalletClient,
  userAccount: ViemAccount | Address,
  args: {
    to: Address;
    commands: Command[];
    nonce: bigint;
    deadline: bigint;
    slippage: Fraction;
  },
): Promise<ReverseMirageWrite<typeof routerABI, "route">> => {
  const blockNumber = await publicClient.getBlockNumber();
  const account: Account = { tokens: {}, liquidityPositions: {} };

  // calculate amounts
  for (const c of args.commands) {
    // TODO: save pairData between loops
    const pairData = await readAndParse(
      engineGetPair(publicClient, {
        pair: c.inputs.pair,
      }),
    );

    if (c.command === "CreatePair") {
      // TODO": a pair that isn't created
    } else if (c.command === "AddLiquidity") {
      const { amount0, amount1, position } = calculateAddLiquidity(
        c.inputs.pair,
        pairData,
        blockNumber,
        c.inputs.strike,
        c.inputs.spread,
        c.inputs.tokenSelector,
        c.inputs.amountDesired,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "RemoveLiquidity") {
      const { amount0, amount1, position } = calculateRemoveLiquidity(
        c.inputs.pair,
        pairData,
        blockNumber,
        c.inputs.strike,
        c.inputs.spread,
        c.inputs.tokenSelector,
        c.inputs.amountDesired,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "BorrowLiquidity") {
      const { amount0, amount1, position } = calculateBorrowLiquidity(
        c.inputs.pair,
        pairData,
        c.inputs.strike,
        c.inputs.selectorCollateral,
        c.inputs.amountDesiredCollateral,
        // c.inputs.selectorDebt,
        c.inputs.amountDesiredDebt,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "RepayLiquidity") {
      const { amount0, amount1, position } = calculateRepayLiquidity(
        c.inputs.pair,
        pairData,
        c.inputs.strike,
        c.inputs.selectorCollateral,
        c.inputs.leverageRatio,
        // c.inputs.selectorDebt,
        c.inputs.amountDesiredDebt,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "Swap") {
      const { amount0, amount1 } = calculateSwap(
        c.inputs.pair,
        pairData,
        c.inputs.amountDesired,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
    } else if (c.command === "Accrue") {
      calculateAccrue(pairData, pairData.cachedStrikeCurrent, blockNumber);
    }
  }

  // filter amounts owed
  const transferRequestsLP = Object.values(account.liquidityPositions)
    .filter((lp) => lp.balance < 0n)
    .map((lp) => ({ ...lp, balance: -lp.balance }))
    .map((lp) => ({
      ...lp,
      balance: fractionQuotient(
        fractionMultiply(fractionAdd(args.slippage, 1), lp.balance),
      ),
    }));
  const transferRequestsToken = Object.values(account.tokens)
    .filter((c) => currencyAmountGreaterThan(c, 0))
    .map((t) => ({
      ...t,
      amount: fractionQuotient(
        fractionMultiply(fractionAdd(args.slippage, 1), t.amount),
      ),
    }));
  console.log(transferRequestsLP);
  // get datahashes
  const lpTransferDataHash = transferRequestsLP.map((t) =>
    getTransferTypedDataHashLP(walletClient.chain!.id, {
      positionData: t,
      spender: RouterAddress,
    }),
  );
  const permitTransferDataHash = getTransferBatchTypedDataHash(
    walletClient.chain!.id,
    { transferDetails: transferRequestsToken, spender: RouterAddress },
  );

  // sign
  const signature = await signSuperSignature(walletClient, userAccount, {
    dataHash: lpTransferDataHash.concat(permitTransferDataHash),
    nonce: args.nonce,
    deadline: args.deadline,
  });

  const { request, result } = await publicClient.simulateContract({
    address: RouterAddress,
    abi: routerABI,
    functionName: "route",
    account: userAccount,
    args: [
      {
        to: args.to,
        commands: args.commands.map((c) => CommandEnum[c.command]),
        inputs: args.commands.map((c) => encodeInput(c)),
        numTokens: BigInt(Object.values(account.tokens).length),
        numLPs: BigInt(Object.values(account.liquidityPositions).length),
        permitTransfers: transferRequestsToken.map((t) => ({
          token: t.currency.address,
          amount: t.amount,
        })),
        positionTransfers: transferRequestsLP.map((t) => ({
          id: dataID(t.position),
          orderType: OrderTypeEnum[t.position.orderType],
          amount: t.balance,
        })),
        verify: {
          dataHash: lpTransferDataHash.concat(permitTransferDataHash),
          nonce: args.nonce,
          deadline: args.deadline,
        },
        signature,
      },
    ],
  });

  const hash = await walletClient.writeContract(request);

  return { hash, request, result };
};

type Account = {
  tokens: { [address: Address]: CurrencyAmount<Token> };
  liquidityPositions: {
    [id_orderType: `${Hex}_${OrderType}`]: PositionData<OrderType>;
  };
};

const updateToken = (
  account: Account,
  currencyAmount: CurrencyAmount<Token>,
) => {
  if (currencyAmount.amount === 0n) return;

  if (account.tokens[currencyAmount.currency.address] !== undefined) {
    account.tokens[currencyAmount.currency.address] = currencyAmountAdd(
      account.tokens[currencyAmount.currency.address]!,
      currencyAmount.amount,
    );
  } else {
    account.tokens[currencyAmount.currency.address] = currencyAmount;
  }
};

const updateLiquidityPosition = (
  account: Account,
  positionData: PositionData<OrderType>,
) => {
  if (positionData.balance === 0n) return;

  const id = `${dataID(positionData.position)}_${
    positionData.position.orderType
  }` as const;

  if (account.liquidityPositions[id] === undefined) {
    account.liquidityPositions[id] = positionData;
  } else {
    if (positionIsBiDirectional(positionData.position)) {
      account.liquidityPositions[id]!.balance += positionData.balance;
    } else {
      account.liquidityPositions[id] = addDebtPositions(
        account.liquidityPositions[id]! as PositionData<"Debt">,
        positionData as PositionData<"Debt">,
      );
    }
  }
};

const encodeInput = (command: Command): Hex =>
  command.command === "AddLiquidity"
    ? encodeAbiParameters(AddLiquidityParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
        command.inputs.spread,
        TokenSelectorEnum[command.inputs.tokenSelector],
        command.inputs.amountDesired,
      ])
    : command.command === "RemoveLiquidity"
    ? encodeAbiParameters(RemoveLiquidityParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
        command.inputs.spread,
        TokenSelectorEnum[command.inputs.tokenSelector],
        command.inputs.tokenSelector === "LiquidityPosition"
          ? -command.inputs.amountDesired
          : command.inputs.amountDesired,
      ])
    : command.command === "BorrowLiquidity"
    ? encodeAbiParameters(BorrowLiquidityParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
        TokenSelectorEnum[command.inputs.selectorCollateral],
        command.inputs.amountDesiredCollateral,
        // TokenSelectorEnum[command.inputs.selectorDebt],
        command.inputs.amountDesiredDebt,
      ])
    : command.command === "RepayLiquidity"
    ? encodeAbiParameters(RepayLiquidityParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
        TokenSelectorEnum[command.inputs.selectorCollateral],
        fractionToQ128(command.inputs.leverageRatio),
        // TokenSelectorEnum[command.inputs.selectorDebt],
        command.inputs.amountDesiredDebt,
      ])
    : command.command === "Swap"
    ? encodeAbiParameters(SwapParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        currencyEqualTo(
          command.inputs.amountDesired.currency,
          command.inputs.pair.token0,
        )
          ? TokenSelectorEnum.Token0
          : TokenSelectorEnum.Token1,
        command.inputs.amountDesired.amount,
      ])
    : command.command === "Accrue"
    ? encodeAbiParameters(AccrueParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
      ])
    : encodeAbiParameters(CreatePairParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
      ]);

export const SwapParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "selector", type: "uint8" },
  { name: "amountDesired", type: "int256" },
] as const;

export const AddLiquidityParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
  { name: "spread", type: "uint8" },
  { name: "selector", type: "uint8" },
  { name: "amountDesired", type: "int256" },
] as const;

export const BorrowLiquidityParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
  { name: "selectorCollateral", type: "uint8" },
  { name: "amountDesiredCollateral", type: "int256" },
  // { name: "selectorDebt", type: "uint8" },
  { name: "amountDesiredDebt", type: "uint256" },
] as const;

export const RepayLiquidityParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
  { name: "selectorCollateral", type: "uint8" },
  { name: "leverageRatioX128", type: "uint256" },
  // { name: "selectorDebt", type: "uint8" },
  { name: "amountDesiredDebt", type: "uint256" },
] as const;

export const RemoveLiquidityParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
  { name: "spread", type: "uint8" },
  { name: "selector", type: "uint8" },
  { name: "amountDesired", type: "int256" },
] as const;

export const AccrueParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
] as const;

export const CreatePairParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strikeInitial", type: "int24" },
] as const;
