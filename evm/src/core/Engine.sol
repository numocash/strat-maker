// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Accounts} from "./Accounts.sol";
import {toInt128, toInt256} from "./math/LiquidityMath.sol";
import {Pairs, NUM_SPREADS} from "./Pairs.sol";
import {Positions} from "./Positions.sol";
import {mulDiv} from "./math/FullMath.sol";
import {
    getAmounts,
    getAmount0,
    getAmount1,
    getLiquidityForAmount0,
    getLiquidityForAmount1,
    scaleLiquidityUp,
    scaleLiquidityDown
} from "./math/LiquidityMath.sol";
import {
    balanceToLiquidity,
    liquidityToBalance,
    debtBalanceToLiquidity,
    debtLiquidityToBalance
} from "./math/PositionMath.sol";
import {getRatioAtStrike, Q128} from "./math/StrikeMath.sol";

import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IExecuteCallback} from "./interfaces/IExecuteCallback.sol";

/// @author Kyle Scott and Robert Leifke
/// @custom:team return data and events
/// @custom:team pass minted position information back to callback
contract Engine is Positions {
    using Pairs for Pairs.Pair;
    using Accounts for Accounts.Account;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 EVENTS
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    event Swap(bytes32 indexed pairID);
    event AddLiquidity(bytes32 indexed pairID, int24 indexed strike, uint8 indexed spread, uint128 liquidity);
    event BorrowLiquidity(bytes32 indexed pairID);
    event RepayLiquidity(bytes32 indexed pairID);
    event AccruePosition(bytes32 indexed pairID);
    event Accrue(bytes32 indexed pairID);
    event RemoveLiquidity(bytes32 indexed pairID, int24 indexed strike, uint8 indexed spread, uint128 liquidity);
    event PairCreated(address indexed token0, address indexed token1, int24 strikeInitial);

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 ERRORS
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    error Reentrancy();
    error InvalidTokenOrder();
    error InsufficientInput();
    error CommandLengthMismatch();
    error InvalidCommand();
    error InvalidSelector();
    error InvalidAmountDesired();

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               DATA TYPES
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    enum Commands {
        Swap,
        AddLiquidity,
        BorrowLiquidity,
        RepayLiquidity,
        RemoveLiquidity,
        Accrue,
        CreatePair
    }

    enum TokenSelector {
        Token0,
        Token1
    }

    enum SwapTokenSelector {
        Token0,
        Token1,
        Token0Account,
        Token1Account
    }

    enum OrderType {
        BiDirectional,
        Debt
    }

    struct SwapParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        SwapTokenSelector selector;
        int256 amountDesired;
    }

    struct AddLiquidityParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        uint8 spread;
        uint128 amountDesired;
    }

    struct BorrowLiquidityParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        TokenSelector selectorCollateral;
        uint256 amountDesiredCollateral;
        uint128 amountDesiredDebt;
    }

    struct RepayLiquidityParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        TokenSelector selectorCollateral;
        uint256 leverageRatioX128;
        uint128 amountDesiredDebt;
    }

    struct RemoveLiquidityParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        uint8 spread;
        uint128 amountDesired;
    }

    struct AccrueParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
    }

    struct CreatePairParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strikeInitial;
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                STORAGE
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    mapping(bytes32 => Pairs.Pair) private pairs;

    /// @dev this should be checked when reading any `get` function from another contract to prevent read-only
    /// reentrancy
    uint256 public locked = 1;

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                MODIFIER
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    modifier nonReentrant() {
        if (locked != 1) revert Reentrancy();

        locked = 2;

        _;

        locked = 1;
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    function execute(
        address to,
        Commands[] calldata commands,
        bytes[] calldata inputs,
        uint256 numTokens,
        uint256 numLPs,
        bytes calldata data
    )
        external
        nonReentrant
    {
        if (commands.length != inputs.length) {
            revert CommandLengthMismatch();
        }

        Accounts.Account memory account = Accounts.newAccount(numTokens, numLPs);

        // find command helper with binary search
        for (uint256 i = 0; i < commands.length;) {
            if (commands[i] < Commands.RemoveLiquidity) {
                if (commands[i] < Commands.BorrowLiquidity) {
                    if (commands[i] == Commands.Swap) {
                        _swap(abi.decode(inputs[i], (SwapParams)), account);
                    } else {
                        _addLiquidity(to, abi.decode(inputs[i], (AddLiquidityParams)), account);
                    }
                } else {
                    if (commands[i] == Commands.BorrowLiquidity) {
                        _borrowLiquidity(to, abi.decode(inputs[i], (BorrowLiquidityParams)), account);
                    } else {
                        _repayLiquidity(abi.decode(inputs[i], (RepayLiquidityParams)), account);
                    }
                }
            } else {
                if (commands[i] < Commands.CreatePair) {
                    if (commands[i] == Commands.RemoveLiquidity) {
                        _removeLiquidity(abi.decode(inputs[i], (RemoveLiquidityParams)), account);
                    } else {
                        _accrue(abi.decode(inputs[i], (AccrueParams)));
                    }
                } else {
                    if (commands[i] == Commands.CreatePair) {
                        _createPair(abi.decode(inputs[i], (CreatePairParams)));
                    } else {
                        revert InvalidCommand();
                    }
                }
            }

            unchecked {
                i++;
            }
        }

        // transfer tokens out
        for (uint256 i = 0; i < numTokens;) {
            int256 delta = account.tokenDeltas[i];
            address token = account.tokens[i];

            if (token == address(0)) break;
            if (delta < 0) SafeTransferLib.safeTransfer(token, to, uint256(-delta));

            unchecked {
                i++;
            }
        }

        // callback if necessary
        if (numTokens > 0 || numLPs > 0) {
            IExecuteCallback(msg.sender).executeCallback(
                IExecuteCallback.CallbackParams(
                    account.tokens, account.tokenDeltas, account.lpIDs, account.lpDeltas, account.orderTypes, data
                )
            );
        }

        // check tokens in
        for (uint256 i = 0; i < numTokens;) {
            int256 delta = account.tokenDeltas[i];
            address token = account.tokens[i];

            if (token == address(0)) break;
            if (delta > 0) {
                uint256 balance = BalanceLib.getBalance(token);
                if (balance < account.balances[i] + uint256(delta)) revert InsufficientInput();
            }

            unchecked {
                i++;
            }
        }

        // check liquidity positions in
        for (uint256 i = 0; i < numLPs;) {
            uint128 delta = account.lpDeltas[i];
            bytes32 id = account.lpIDs[i];

            if (id == bytes32(0)) break;
            if (delta < 0) {
                _burn(address(this), id, delta, account.orderTypes[i]);
            }

            unchecked {
                i++;
            }
        }
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               INTERNAL LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    function _swap(SwapParams memory params, Accounts.Account memory account) private {
        (bytes32 pairID, Pairs.Pair storage pair) =
            pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

        int256 amount0;
        int256 amount1;
        if (params.selector < SwapTokenSelector.Token0Account) {
            (amount0, amount1) =
                pair.swap(params.scalingFactor, params.selector == SwapTokenSelector.Token0, params.amountDesired);
        } else if (params.selector == SwapTokenSelector.Token0Account) {
            assert(account.tokens[uint256(params.amountDesired)] == params.token0);
            (amount0, amount1) =
                pair.swap(params.scalingFactor, true, -account.tokenDeltas[uint256(params.amountDesired)]);
        } else if (params.selector == SwapTokenSelector.Token1Account) {
            assert(account.tokens[uint256(params.amountDesired)] == params.token1);
            (amount0, amount1) =
                pair.swap(params.scalingFactor, false, -account.tokenDeltas[uint256(params.amountDesired)]);
        } else {
            revert InvalidSelector();
        }
        account.updateToken(params.token0, amount0);
        account.updateToken(params.token1, amount1);

        emit Swap(pairID);
    }

    function _addLiquidity(address to, AddLiquidityParams memory params, Accounts.Account memory account) private {
        (bytes32 pairID, Pairs.Pair storage pair) =
            pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);
        pair.accrue(params.strike);

        // calculate how much to add
        int128 liquidity = toInt128(params.amountDesired);
        int128 balance = toInt128(liquidityToBalance(pair, params.strike, params.spread, params.amountDesired));
        (uint256 _amount0, uint256 _amount1) = getAmounts(
            pair, scaleLiquidityUp(params.amountDesired, params.scalingFactor), params.strike, params.spread, true
        );
        int256 amount0 = int256(_amount0);
        int256 amount1 = int256(_amount1);

        // add to pair
        pair.updateStrike(params.strike, params.spread, balance, liquidity);

        // update accounts
        account.updateToken(params.token0, amount0);
        account.updateToken(params.token1, amount1);

        // mint position token
        _mintBiDirectional(
            to, params.token0, params.token1, params.scalingFactor, params.strike, params.spread, uint128(balance)
        );

        emit AddLiquidity(pairID, params.strike, params.spread, uint128(balance));
    }

    function _borrowLiquidity(
        address to,
        BorrowLiquidityParams memory params,
        Accounts.Account memory account
    )
        private
    {
        (bytes32 pairID, Pairs.Pair storage pair) =
            pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);
        pair.accrue(params.strike);

        uint128 liquidityToken1 = pair.borrowLiquidity(params.strike, params.amountDesiredDebt);

        // calculate the the tokens that are borrowed
        account.updateToken(
            params.token0,
            -toInt256(
                getAmount0(
                    scaleLiquidityUp(params.amountDesiredDebt - liquidityToken1, params.scalingFactor),
                    getRatioAtStrike(params.strike),
                    false
                )
            )
        );
        account.updateToken(
            params.token1, -toInt256(getAmount1(scaleLiquidityUp(liquidityToken1, params.scalingFactor)))
        );

        // add collateral to account
        uint128 liquidityCollateral;
        if (params.selectorCollateral == TokenSelector.Token0) {
            account.updateToken(params.token0, toInt256(params.amountDesiredCollateral));
            liquidityCollateral = scaleLiquidityDown(
                getLiquidityForAmount0(params.amountDesiredCollateral, getRatioAtStrike(params.strike)),
                params.scalingFactor
            );
        } else if (params.selectorCollateral == TokenSelector.Token1) {
            account.updateToken(params.token1, toInt256(params.amountDesiredCollateral));
            liquidityCollateral =
                scaleLiquidityDown(getLiquidityForAmount1(params.amountDesiredCollateral), params.scalingFactor);
        } else {
            revert InvalidSelector();
        }

        if (params.amountDesiredDebt > liquidityCollateral) revert InsufficientInput();

        uint128 balance =
            debtLiquidityToBalance(params.amountDesiredDebt, pair.strikes[params.strike].liquidityGrowthExpX128);

        // mint position to user
        _mintDebt(
            to,
            params.token0,
            params.token1,
            params.scalingFactor,
            params.strike,
            params.selectorCollateral,
            balance,
            uint120(liquidityCollateral - params.amountDesiredDebt) // can be unchecked
        );

        emit BorrowLiquidity(pairID);
    }

    function _repayLiquidity(RepayLiquidityParams memory params, Accounts.Account memory account) private {
        (bytes32 pairID, Pairs.Pair storage pair) =
            pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);
        pair.accrue(params.strike);

        uint128 liquidityDebt =
            debtBalanceToLiquidity(params.amountDesiredDebt, pair.strikes[params.strike].liquidityGrowthExpX128);

        pair.repayLiquidity(params.strike, liquidityDebt);

        // calculate tokens owed and add to account
        (uint256 amount0, uint256 amount1) = getAmounts(
            pair,
            scaleLiquidityUp(params.amountDesiredDebt, params.scalingFactor),
            params.strike,
            pair.strikes[params.strike].activeSpread + 1,
            true
        );
        account.updateToken(params.token0, toInt256(amount0));
        account.updateToken(params.token1, toInt256(amount1));

        // add unlocked collateral to account
        uint256 liquidityCollateral = mulDiv(params.amountDesiredDebt, params.leverageRatioX128, Q128)
            - 2 * (params.amountDesiredDebt - liquidityDebt);
        if (params.selectorCollateral == TokenSelector.Token0) {
            account.updateToken(
                params.token0, -toInt256(getAmount0(liquidityCollateral, getRatioAtStrike(params.strike), false))
            );
        } else if (params.selectorCollateral == TokenSelector.Token1) {
            account.updateToken(params.token0, -toInt256(getAmount1(liquidityCollateral)));
        } else {
            revert InvalidSelector();
        }

        // add burned position to account

        bytes32 id =
            _debtID(params.token0, params.token1, params.scalingFactor, params.strike, params.selectorCollateral);
        account.updateILRTA(id, params.amountDesiredDebt, OrderType.Debt);

        emit RepayLiquidity(pairID);
    }

    function _removeLiquidity(RemoveLiquidityParams memory params, Accounts.Account memory account) private {
        (bytes32 pairID, Pairs.Pair storage pair) =
            pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);
        pair.accrue(params.strike);

        // calculate how much to remove
        int128 balance = -toInt128(params.amountDesired);
        int128 liquidity =
            -toInt128(balanceToLiquidity(pair, params.strike, params.spread, uint128(params.amountDesired)));
        (uint256 _amount0, uint256 _amount1) = getAmounts(
            pair, scaleLiquidityUp(uint128(-liquidity), params.scalingFactor), params.strike, params.spread, false
        );
        int256 amount0 = -int256(_amount0);
        int256 amount1 = -int256(_amount1);

        // remove from pair
        pair.updateStrike(params.strike, params.spread, balance, liquidity);

        // update accounts
        account.updateToken(params.token0, amount0);
        account.updateToken(params.token1, amount1);
        account.updateILRTA(
            _biDirectionalID(params.token0, params.token1, params.scalingFactor, params.strike, params.spread),
            uint128(-balance),
            OrderType.BiDirectional
        );

        emit RemoveLiquidity(pairID, params.strike, params.spread, uint128(-balance));
    }

    function _accrue(AccrueParams memory params) private {
        (bytes32 pairID, Pairs.Pair storage pair) =
            pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

        pair.accrue(params.strike);

        emit Accrue(pairID);
    }

    function _createPair(CreatePairParams memory params) private {
        if (params.token0 >= params.token1 || params.token0 == address(0)) revert InvalidTokenOrder();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);
        pair.initialize(params.strikeInitial);

        emit PairCreated(params.token0, params.token1, params.strikeInitial);
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               VIEW LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    function getPair(
        address token0,
        address token1,
        uint8 scalingFactor
    )
        external
        view
        returns (
            uint128[NUM_SPREADS] memory composition,
            int24[NUM_SPREADS] memory strikeCurrentCached,
            int24 cachedStrikeCurrent,
            uint8 initialized
        )
    {
        (, Pairs.Pair storage pair) = pairs.getPairAndID(token0, token1, scalingFactor);
        (composition, strikeCurrentCached, cachedStrikeCurrent, initialized) =
            (pair.composition, pair.strikeCurrent, pair.strikeCurrentCached, pair.initialized);
    }

    function getStrike(
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike
    )
        external
        view
        returns (Pairs.Strike memory)
    {
        (, Pairs.Pair storage pair) = pairs.getPairAndID(token0, token1, scalingFactor);

        return pair.strikes[strike];
    }
}
