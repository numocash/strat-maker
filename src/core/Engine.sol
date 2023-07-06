// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Accounts} from "./Accounts.sol";
import {toInt256} from "./math/LiquidityMath.sol";
import {Pairs, NUM_SPREADS} from "./Pairs.sol";
import {Positions} from "./Positions.sol";
import {mulDiv} from "./math/FullMath.sol";
import {
    getLiquidityForAmount0,
    getLiquidityForAmount1,
    getAmountsForLiquidity,
    getAmount0Delta,
    getAmount1Delta,
    getLiquidityDeltaAmount0,
    getLiquidityDeltaAmount1,
    getAmount0ForLiquidity,
    getAmount1ForLiquidity
} from "./math/LiquidityMath.sol";
import {
    balanceToLiquidity,
    liquidityToBalance,
    debtBalanceToLiquidity,
    debtLiquidityToBalance
} from "./math/PositionMath.sol";
import {Q128} from "./math/StrikeMath.sol";

import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IExecuteCallback} from "./interfaces/IExecuteCallback.sol";

/// @author Kyle Scott and Robert Leifke
/// @custom:team return data and events
/// @custom:team tree for function selector
/// @custom:team pass minted position information back to callback
/// @custom:team don't allow for transferring if a position isn't accrued
/// @custom:team amount desired is impossible
contract Engine is Positions {
    using Pairs for Pairs.Pair;
    using Accounts for Accounts.Account;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 EVENTS
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    event Swap(bytes32 indexed pairID);
    event AddLiquidity(bytes32 indexed pairID, int24 indexed strike, uint8 indexed spread, uint256 liquidity);
    event BorrowLiquidity(bytes32 indexed pairID);
    event RepayLiquidity(bytes32 indexed pairID);
    event AccruePosition(bytes32 indexed pairID);
    event Accrue(bytes32 indexed pairID);
    event RemoveLiquidity(bytes32 indexed pairID, int24 indexed strike, uint8 indexed spread, uint256 liquidity);
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
        Token1,
        LiquidityPosition
    }

    enum OrderType {
        BiDirectional,
        Limit,
        Debt
    }

    struct SwapParams {
        address token0;
        address token1;
        TokenSelector selector;
        int256 amountDesired;
    }

    struct AddLiquidityParams {
        address token0;
        address token1;
        int24 strike;
        uint8 spread;
        TokenSelector selector;
        int256 amountDesired;
    }

    struct BorrowLiquidityParams {
        address token0;
        address token1;
        int24 strike;
        TokenSelector selectorCollateral;
        uint256 amountDesiredCollateral;
        TokenSelector selectorDebt;
        uint256 amountDesiredDebt;
    }

    struct RepayLiquidityParams {
        address token0;
        address token1;
        int24 strike;
        TokenSelector selectorCollateral;
        uint256 leverageRatioX128;
        TokenSelector selectorDebt;
        uint256 amountDesiredDebt;
    }

    struct RemoveLiquidityParams {
        address token0;
        address token1;
        int24 strike;
        uint8 spread;
        TokenSelector selector;
        int256 amountDesired;
    }

    struct AccruePositionParams {
        address token0;
        address token1;
        int24 strike;
        TokenSelector selectorCollateral;
        address owner;
    }

    struct AccrueParams {
        address token0;
        address token1;
    }

    struct CreatePairParams {
        address token0;
        address token1;
        int24 strikeInitial;
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                STORAGE
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

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
                              CONSTRUCTOR
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    constructor(address _superSignature) Positions(_superSignature) {}

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
                        // command must be 1, which is add liquidity
                        _addLiquidity(to, abi.decode(inputs[i], (AddLiquidityParams)), account);
                    }
                } else {
                    if (commands[i] == Commands.BorrowLiquidity) {
                        _borrowLiquidity(to, abi.decode(inputs[i], (BorrowLiquidityParams)), account);
                    } else {
                        // must be _repayLiquidity
                        _repayLiquidity(abi.decode(inputs[i], (RepayLiquidityParams)), account);
                    }
                }
            } else {
                if (commands[i] < Commands.CreatePair) {
                    if (commands[i] == Commands.RemoveLiquidity) {
                        _removeLiquidity(abi.decode(inputs[i], (RemoveLiquidityParams)), account);
                    } else {
                        // accrue
                        _accrue(abi.decode(inputs[i], (AccrueParams)));
                    }
                } else {
                    if (commands[i] == Commands.CreatePair) {
                        // create pair
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

            // token is zero, so skip it.
            if (token == address(0)) {
                i++;
            } else {
                // if delta is negative, transfer token to recipient address
                if (delta < 0) {
                    SafeTransferLib.safeTransfer(token, to, uint256(-delta));
                }

                // increment the loop counter.
                unchecked {
                    i++;
                }
            }
        }

        // callback if necessary
        if (numTokens > 0 || numLPs > 0) {
            IExecuteCallback(msg.sender).executeCallback(
                IExecuteCallback.CallbackParams(
                    account.tokens,
                    account.tokenDeltas,
                    account.lpIDs,
                    account.lpDeltas,
                    account.orderTypes,
                    account.datas,
                    data
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
            uint256 delta = account.lpDeltas[i];
            bytes32 id = account.lpIDs[i];

            if (id == bytes32(0)) break;

            if (delta < 0) {
                _burn(address(this), id, delta, account.orderTypes[i], account.datas[i]);
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
        (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

        if (params.selector != TokenSelector.Token0 && params.selector != TokenSelector.Token1) {
            revert InvalidSelector();
        }

        (int256 amount0, int256 amount1) = pair.swap(params.selector == TokenSelector.Token0, params.amountDesired);
        account.updateToken(params.token0, amount0);
        account.updateToken(params.token1, amount1);

        emit Swap(pairID);
    }

    function _addLiquidity(address to, AddLiquidityParams memory params, Accounts.Account memory account) private {
        (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

        // calculate how much to add
        int256 balance;
        int256 liquidity;
        int256 amount0;
        int256 amount1;
        if (params.selector == TokenSelector.LiquidityPosition) {
            if (params.amountDesired < 0) revert InvalidAmountDesired();

            balance = params.amountDesired;
            liquidity = toInt256(balanceToLiquidity(pair, params.strike, params.spread, uint256(balance), true));
            (uint256 _amount0, uint256 _amount1) =
                getAmountsForLiquidity(pair, params.strike, params.spread, uint256(liquidity), true);
            amount0 = int256(_amount0);
            amount1 = int256(_amount1);
        } else if (params.selector == TokenSelector.Token0) {
            if (params.amountDesired < 0) revert InvalidAmountDesired();

            liquidity = toInt256(
                getLiquidityForAmount0(pair, params.strike, params.spread, uint256(params.amountDesired), true)
            );
            amount0 = params.amountDesired;
            amount1 = toInt256(getAmount1ForLiquidity(pair, params.strike, params.spread, uint256(liquidity), true));
        } else if (params.selector == TokenSelector.Token1) {
            if (params.amountDesired < 0) revert InvalidAmountDesired();

            liquidity = toInt256(
                getLiquidityForAmount1(pair, params.strike, params.spread, uint256(params.amountDesired), true)
            );
            amount0 = toInt256(getAmount0ForLiquidity(pair, params.strike, params.spread, uint256(liquidity), true));
            amount1 = params.amountDesired;
        } else {
            revert InvalidSelector();
        }

        if (params.selector == TokenSelector.Token0 || params.selector == TokenSelector.Token1) {
            balance = toInt256(liquidityToBalance(pair, params.strike, params.spread, uint256(liquidity), false));
        }

        // add to pair
        pair.updateStrike(params.strike, params.spread, balance, liquidity);

        // update accounts
        account.updateToken(params.token0, amount0);
        account.updateToken(params.token1, amount1);

        // mint position token
        _mintBiDirectional(to, params.token0, params.token1, params.strike, params.spread, uint256(balance));

        emit AddLiquidity(pairID, params.strike, params.spread, uint256(balance));
    }

    function _borrowLiquidity(
        address to,
        BorrowLiquidityParams memory params,
        Accounts.Account memory account
    )
        private
    {
        (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

        // calculate how much liquidity is borrowed
        uint256 liquidityDebt;
        if (params.selectorDebt == TokenSelector.LiquidityPosition) {
            liquidityDebt = params.amountDesiredDebt;
        } else if (params.selectorDebt == TokenSelector.Token0) {
            revert InvalidSelector();
        } else if (params.selectorDebt == TokenSelector.Token1) {
            revert InvalidSelector();
        } else {
            revert InvalidSelector();
        }

        pair.borrowLiquidity(params.strike, liquidityDebt);

        // calculate the the tokens that are borrowed
        if (params.strike > pair.cachedStrikeCurrent) {
            account.updateToken(params.token0, -toInt256(getAmount0Delta(liquidityDebt, params.strike, false)));
        } else {
            account.updateToken(params.token1, -toInt256(getAmount1Delta(liquidityDebt)));
        }

        // add collateral to account
        uint256 liquidityCollateral;
        if (params.selectorCollateral == TokenSelector.Token0) {
            account.updateToken(params.token0, toInt256(params.amountDesiredCollateral));
            liquidityCollateral = getLiquidityDeltaAmount0(params.amountDesiredCollateral, params.strike, false);
        } else if (params.selectorCollateral == TokenSelector.Token1) {
            account.updateToken(params.token1, toInt256(params.amountDesiredCollateral));
            liquidityCollateral = getLiquidityDeltaAmount1(params.amountDesiredCollateral);
        } else {
            revert InvalidSelector();
        }

        // mint position to user
        _mintDebt(
            to,
            params.token0,
            params.token1,
            params.strike,
            params.selectorCollateral,
            debtLiquidityToBalance(liquidityDebt, pair.strikes[params.strike].liquidityGrowthX128, false),
            mulDiv(liquidityCollateral, Q128, liquidityDebt)
        );

        emit BorrowLiquidity(pairID);
    }

    function _repayLiquidity(RepayLiquidityParams memory params, Accounts.Account memory account) private {
        (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);
        if (pair.cachedStrikeCurrent == params.strike) pair._accrue(params.strike);

        uint256 _liquidityGrowthX128 = pair.strikes[params.strike].liquidityGrowthX128;

        // calculate liquidity to repay
        uint256 amount;
        uint256 liquidityDebt;
        if (params.selectorDebt == TokenSelector.LiquidityPosition) {
            amount = params.amountDesiredDebt;
            liquidityDebt = debtBalanceToLiquidity(amount, _liquidityGrowthX128, true);
        } else if (params.selectorDebt == TokenSelector.Token0) {
            revert InvalidSelector();
        } else if (params.selectorDebt == TokenSelector.Token1) {
            revert InvalidSelector();
        } else {
            revert InvalidSelector();
        }

        pair.repayLiquidity(params.strike, liquidityDebt);

        // calculate tokens owed and add to account
        (uint256 amount0, uint256 amount1) = getAmountsForLiquidity(
            pair, params.strike, pair.strikes[params.strike].activeSpread + 1, liquidityDebt, true
        );
        account.updateToken(params.token0, toInt256(amount0));
        account.updateToken(params.token1, toInt256(amount1));

        // add unlocked collateral to account
        {
            uint256 liquidityCollateral = mulDiv(liquidityDebt, params.leverageRatioX128, Q128);
            if (params.selectorCollateral == TokenSelector.Token0) {
                account.updateToken(
                    params.token0, -toInt256(getAmount0Delta(liquidityCollateral, params.strike, false))
                );
            } else {
                account.updateToken(params.token0, -toInt256(getAmount1Delta(liquidityCollateral)));
            }
        }

        // add burned position to account
        {
            bytes32 id = _debtID(params.token0, params.token1, params.strike, params.selectorCollateral);
            account.updateILRTA(id, amount, OrderType.Debt, abi.encode(DebtData(params.leverageRatioX128)));
        }

        emit RepayLiquidity(pairID);
    }

    function _removeLiquidity(RemoveLiquidityParams memory params, Accounts.Account memory account) private {
        (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

        // calculate how much to remove
        int256 balance;
        int256 liquidity;
        int256 amount0;
        int256 amount1;
        if (params.selector == TokenSelector.LiquidityPosition) {
            if (params.amountDesired > 0) revert InvalidAmountDesired();

            balance = params.amountDesired;
            liquidity = -toInt256(balanceToLiquidity(pair, params.strike, params.spread, uint256(-balance), false));
            (uint256 _amount0, uint256 _amount1) =
                getAmountsForLiquidity(pair, params.strike, params.spread, uint256(-liquidity), false);
            amount0 = -int256(_amount0);
            amount1 = -int256(_amount1);
        } else if (params.selector == TokenSelector.Token0) {
            if (params.amountDesired > 0) revert InvalidAmountDesired();

            liquidity = -toInt256(getLiquidityForAmount0(pair, params.strike, params.spread, uint256(-params.amountDesired), false));
            amount0 = params.amountDesired;
            amount1 = -toInt256(getAmount1ForLiquidity(pair, params.strike, params.spread, uint256(-liquidity), false));
        } else if (params.selector == TokenSelector.Token1) {
            if (params.amountDesired > 0) revert InvalidAmountDesired();

            liquidity = -toInt256(getLiquidityForAmount1(pair, params.strike, params.spread, uint256(-params.amountDesired), false));
            amount0 = -toInt256(getAmount0ForLiquidity(pair, params.strike, params.spread, uint256(-liquidity), false));
            amount1 = params.amountDesired;
        } else {
            revert InvalidSelector();
        }

        if (params.selector == TokenSelector.Token0 || params.selector == TokenSelector.Token1) {
            balance = -toInt256(liquidityToBalance(pair, params.strike, params.spread, uint256(-liquidity), true));
        }

        // remove from pair
        pair.updateStrike(params.strike, params.spread, balance, liquidity);

        // update accounts
        account.updateToken(params.token0, amount0);
        account.updateToken(params.token1, amount1);
        account.updateILRTA(
            _biDirectionalID(params.token0, params.token1, params.strike, params.spread),
            uint256(-balance),
            OrderType.BiDirectional,
            bytes("")
        );

        emit RemoveLiquidity(pairID, params.strike, params.spread, uint256(-balance));
    }

    function _accrue(AccrueParams memory params) private {
        (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

        pair.accrue();

        emit Accrue(pairID);
    }

    function _createPair(CreatePairParams memory params) private {
        if (params.token0 >= params.token1 || params.token0 == address(0)) revert InvalidTokenOrder();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);
        pair.initialize(params.strikeInitial);

        emit PairCreated(params.token0, params.token1, params.strikeInitial);
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               VIEW LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    function getPair(
        address token0,
        address token1
    )
        external
        view
        returns (
            uint128[NUM_SPREADS] memory composition,
            int24[NUM_SPREADS] memory strikeCurrent,
            int24 cachedStrikeCurrent,
            uint8 initialized
        )
    {
        (, Pairs.Pair storage pair) = pairs.getPairAndID(token0, token1);
        (composition, strikeCurrent, cachedStrikeCurrent, initialized) =
            (pair.composition, pair.strikeCurrent, pair.cachedStrikeCurrent, pair.initialized);
    }

    function getStrike(address token0, address token1, int24 strike) external view returns (Pairs.Strike memory) {
        (, Pairs.Pair storage pair) = pairs.getPairAndID(token0, token1);

        return pair.strikes[strike];
    }

    function getPositionBiDirectional(
        address owner,
        address token0,
        address token1,
        int24 strike,
        uint8 spread
    )
        external
        view
        returns (uint256 balance)
    {
        return _dataOf[owner][_biDirectionalID(token0, token1, strike, spread)].balance;
    }

    function getPositionLimit(
        address owner,
        address token0,
        address token1,
        int24 strike,
        bool zeroToOne,
        uint256 liquidityGrowthLast
    )
        external
        view
        returns (uint256 balance)
    {
        return _dataOf[owner][_limitID(token0, token1, strike, zeroToOne, liquidityGrowthLast)].balance;
    }

    function getPositionDebt(
        address owner,
        address token0,
        address token1,
        int24 strike,
        Engine.TokenSelector selector
    )
        external
        view
        returns (uint256 balance, uint256 leverageRatioX128)
    {
        balance = _dataOf[owner][_debtID(token0, token1, strike, selector)].balance;
        Positions.DebtData memory debtData = _dataOfDebt(owner, token0, token1, strike, selector);

        return (balance, debtData.leverageRatioX128);
    }
}
