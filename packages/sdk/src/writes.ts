import { signSuperSignature } from "ilrta-sdk";
import { getTransferBatchTypedDataHash } from "ilrta-sdk";
import {
  amountAdd,
  amountGreaterThan,
  fractionAdd,
  fractionMultiply,
  fractionQuotient,
  makeAmountFromRaw,
  readAndParse,
} from "reverse-mirage";
import type {
  ERC20,
  ERC20Amount,
  Fraction,
  ReverseMirageWrite,
} from "reverse-mirage";
import {
  type Account as ViemAccount,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
  encodeAbiParameters,
} from "viem";
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
  SwapTokenSelectorEnum,
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
import { engineGetPair, engineGetStrike } from "./reads.js";
import type { Command, OrderType, PairData, Strike } from "./types.js";
import { fractionToQ128 } from "./utils.js";

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

  const pairData: Record<string, PairData> = {};

  // calculate amounts
  for (const c of args.commands) {
    const id = `${c.inputs.pair.token0.address}_${c.inputs.pair.token1.address}_${c.inputs.pair.scalingFactor}`;
    if (pairData[id] === undefined) {
      pairData[id] = await readAndParse(
        engineGetPair(publicClient, {
          pair: c.inputs.pair,
        }),
      );
    }

    const loadStrike = async (strike: Strike) => {
      if (pairData[id]!.strikes[strike] !== undefined) return;
      const strikeData = await readAndParse(
        engineGetStrike(publicClient, {
          pair: c.inputs.pair,
          strike: strike,
        }),
      );
      pairData[id]!.strikes[strike] = strikeData;
    };
    if (c.command === "CreatePair") {
      // TODO": a pair that isn't created
    } else if (c.command === "AddLiquidity") {
      await loadStrike(c.inputs.strike);

      const { amount0, amount1, position } = calculateAddLiquidity(
        c.inputs.pair,
        pairData[id]!,
        blockNumber,
        c.inputs.strike,
        c.inputs.spread,
        c.inputs.amountDesired,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "RemoveLiquidity") {
      await loadStrike(c.inputs.strike);

      const { amount0, amount1, position } = calculateRemoveLiquidity(
        c.inputs.pair,
        pairData[id]!,
        blockNumber,
        c.inputs.strike,
        c.inputs.spread,
        c.inputs.amountDesired,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "BorrowLiquidity") {
      await loadStrike(c.inputs.strike);

      const { amount0, amount1, position } = calculateBorrowLiquidity(
        c.inputs.pair,
        pairData[id]!,
        blockNumber,
        c.inputs.strike,
        c.inputs.selectorCollateral,
        c.inputs.amountDesiredCollateral,
        c.inputs.amountDesiredDebt,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "RepayLiquidity") {
      await loadStrike(c.inputs.strike);
      const { amount0, amount1, position } = calculateRepayLiquidity(
        c.inputs.pair,
        pairData[id]!,
        blockNumber,
        c.inputs.strike,
        c.inputs.selectorCollateral,
        c.inputs.leverageRatio,
        c.inputs.amountDesiredDebt,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "Swap") {
      const { amount0, amount1 } = calculateSwap(
        c.inputs.pair,
        pairData[id]!,
        c.inputs.selector === "Token0"
          ? makeAmountFromRaw(c.inputs.pair.token0, c.inputs.amountDesired)
          : c.inputs.selector === "Token1"
          ? makeAmountFromRaw(c.inputs.pair.token1, c.inputs.amountDesired)
          : c.inputs.selector === "Token0Account"
          ? makeAmountFromRaw(
              c.inputs.pair.token0,
              account.tokens[c.inputs.pair.token0.address]!.amount,
            )
          : makeAmountFromRaw(
              c.inputs.pair.token1,
              account.tokens[c.inputs.pair.token1.address]!.amount,
            ),
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
    } else if (c.command === "Accrue") {
      calculateAccrue(
        pairData[id]!,
        pairData[id]!.strikeCurrentCached,
        blockNumber,
      );
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
    .filter((c) => amountGreaterThan(c, 0))
    .map((t) => ({
      ...t,
      amount: fractionQuotient(
        fractionMultiply(fractionAdd(args.slippage, 1), t.amount),
      ),
    }));

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
          token: t.token.address,
          amount: t.amount,
        })),
        positionTransfers: transferRequestsLP.map((t) => ({
          id: dataID(t.token),
          orderType: OrderTypeEnum[t.token.orderType],
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
  tokens: { [address: Address]: ERC20Amount<ERC20> };
  liquidityPositions: {
    [id_orderType: `${Hex}_${OrderType}`]: PositionData<OrderType>;
  };
};

const updateToken = (account: Account, currencyAmount: ERC20Amount<ERC20>) => {
  if (currencyAmount.amount === 0n) return;

  if (account.tokens[currencyAmount.token.address] !== undefined) {
    account.tokens[currencyAmount.token.address] = amountAdd(
      account.tokens[currencyAmount.token.address]!,
      currencyAmount.amount,
    );
  } else {
    account.tokens[currencyAmount.token.address] = currencyAmount;
  }
};

const updateLiquidityPosition = (
  account: Account,
  positionData: PositionData<OrderType>,
) => {
  if (positionData.balance === 0n) return;

  const id = `${dataID(positionData.token)}_${
    positionData.token.orderType
  }` as const;

  if (account.liquidityPositions[id] === undefined) {
    account.liquidityPositions[id] = positionData;
  } else {
    if (positionIsBiDirectional(positionData.token)) {
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
        command.inputs.amountDesired,
      ])
    : command.command === "RemoveLiquidity"
    ? encodeAbiParameters(RemoveLiquidityParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
        command.inputs.spread,
        command.inputs.amountDesired,
      ])
    : command.command === "BorrowLiquidity"
    ? encodeAbiParameters(BorrowLiquidityParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
        TokenSelectorEnum[command.inputs.selectorCollateral],
        command.inputs.amountDesiredCollateral,
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
        command.inputs.amountDesiredDebt,
      ])
    : command.command === "Swap"
    ? encodeAbiParameters(SwapParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        SwapTokenSelectorEnum[command.inputs.selector],
        command.inputs.amountDesired,
      ])
    : command.command === "Accrue"
    ? encodeAbiParameters(AccrueParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
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
  { name: "amountDesired", type: "uint128" },
] as const;

export const BorrowLiquidityParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
  { name: "selectorCollateral", type: "uint8" },
  { name: "amountDesiredCollateral", type: "int256" },
  { name: "amountDesiredDebt", type: "uint128" },
] as const;

export const RepayLiquidityParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
  { name: "selectorCollateral", type: "uint8" },
  { name: "leverageRatioX128", type: "uint256" },
  { name: "amountDesiredDebt", type: "uint128" },
] as const;

export const RemoveLiquidityParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
  { name: "spread", type: "uint8" },
  { name: "amountDesired", type: "uint128" },
] as const;

export const AccrueParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
] as const;

export const CreatePairParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strikeInitial", type: "int24" },
] as const;
