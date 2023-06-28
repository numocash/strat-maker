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
    getAmount1Delta
} from "./math/LiquidityMath.sol";
import {balanceToLiquidity, liquidityToBalance} from "./math/PositionMath.sol";
import {Q128} from "./math/StrikeMath.sol";

import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IExecuteCallback} from "./interfaces/IExecuteCallback.sol";

/// @author Robert Leifke and Kyle Scott
/// @custom:team return data and events
/// @custom:team tree for function selector
/// @custom:team accrue and accruePosition
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

    event PairCreated(address indexed token0, address indexed token1, int24 strikeInitial);
    event AddLiquidity(bytes32 indexed pairID, int24 indexed strike, uint8 indexed spread, uint256 liquidity);
    event RemoveLiquidity(bytes32 indexed pairID, int24 indexed strike, uint8 indexed spread, uint256 liquidity);
    event Swap(bytes32 indexed pairID);

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
        CreatePair
    }

    enum TokenSelector {
        Token0,
        Token1,
        LiquidityPosition
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

    struct CreatePairParams {
        address token0;
        address token1;
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
                              CONSTRUCTOR
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    constructor(address _superSignature) Positions(_superSignature) {}

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @dev Set to address to 0 if creating a pair
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
        if (commands.length != inputs.length) revert CommandLengthMismatch();

        Accounts.Account memory account = Accounts.newAccount(numTokens, numLPs);

        for (uint256 i = 0; i < commands.length;) {
            if (commands[i] == Commands.Swap) {
                _swap(abi.decode(inputs[i], (SwapParams)), account);
            } else if (commands[i] == Commands.AddLiquidity) {
                _addLiquidity(to, abi.decode(inputs[i], (AddLiquidityParams)), account);
            } else if (commands[i] == Commands.BorrowLiquidity) {
                _borrowLiquidity(to, abi.decode(inputs[i], (BorrowLiquidityParams)), account);
            } else if (commands[i] == Commands.RepayLiquidity) {
                _repayLiquidity(to, abi.decode(inputs[i], (RepayLiquidityParams)), account);
            } else if (commands[i] == Commands.RemoveLiquidity) {
                _removeLiquidity(abi.decode(inputs[i], (RemoveLiquidityParams)), account);
            } else if (commands[i] == Commands.CreatePair) {
                _createPair(abi.decode(inputs[i], (CreatePairParams)));
            } else {
                revert InvalidCommand();
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

            if (delta < 0) {
                SafeTransferLib.safeTransfer(token, to, uint256(-delta));
            }

            unchecked {
                i++;
            }
        }

        // callback if necessary
        if (numTokens > 0 || numLPs > 0) {
            IExecuteCallback(msg.sender).executeCallback(
                account.tokens, account.tokenDeltas, account.lpIDs, account.lpDeltas, data
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

            // TODO: fix extra data
            if (delta < 0) {
                _burn(address(this), id, delta, Positions.OrderType.BiDirectional, bytes(""));
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
            amount1 = 0;
        } else if (params.selector == TokenSelector.Token1) {
            if (params.amountDesired < 0) revert InvalidAmountDesired();

            liquidity = toInt256(
                getLiquidityForAmount1(pair, params.strike, params.spread, uint256(params.amountDesired), true)
            );
            amount0 = 0;
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
        } else if (params.selectorCollateral == TokenSelector.Token1) {
            account.updateToken(params.token1, toInt256(params.amountDesiredCollateral));
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
            liquidityDebt,
            pair.strikes[params.strike].liquidityGrowthX128,
            mulDiv(liquidityCollateral, Q128, liquidityDebt)
        );

        // emit
    }

    function _repayLiquidity(address to, RepayLiquidityParams memory params, Accounts.Account memory account) private {
        (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

        bytes32 id = _debtID(params.token0, params.token1, params.strike, params.selectorCollateral);

        // calculate liquidity debt
        uint256 liquidityDebt;
        uint256 leverageRatioX128;
        // (liquidityDebt, ,leverageRatioX128) = _debtDataOf()

        pair.repayLiquidity(params.strike, liquidityDebt);

        // (uint256 amount0, uint256 amount1) = calcAmountsForLiquidity(
        //     pair.cachedStrikeCurrent, pair.composition[pair], params.strike, liquidityDebt, true
        // );

        // calculate tokens owed and add to account

        // add unlocked collateral to account
        // uint256 collateral = mulDiv(liquidityDebt, , Q128);

        // add burned position to account

        // emit
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
            // TODO: fix this function to not have to read composition
            (uint256 _amount0, uint256 _amount1) =
                getAmountsForLiquidity(pair, params.strike, params.spread, uint256(liquidity), false);
            amount0 = -int256(_amount0);
            amount1 = -int256(_amount1);
        } else if (params.selector == TokenSelector.Token0) {
            if (params.amountDesired > 0) revert InvalidAmountDesired();

            liquidity = -toInt256(getLiquidityForAmount0(pair, params.strike, params.spread, uint256(-params.amountDesired), true));
            amount0 = params.amountDesired;
            amount1 = 0;
        } else if (params.selector == TokenSelector.Token1) {
            if (params.amountDesired > 0) revert InvalidAmountDesired();

            liquidity = -toInt256(getLiquidityForAmount1(pair, params.strike, params.spread, uint256(-params.amountDesired), true));
            amount0 = 0;
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
            _biDirectionalID(params.token0, params.token1, params.strike, params.spread), uint256(-balance)
        );

        emit RemoveLiquidity(pairID, params.strike, params.spread, uint256(-balance));
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
        return _biDirectionalDataOf(owner, token0, token1, strike, spread);
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
        return _limitDataOf(owner, token0, token1, strike, zeroToOne, liquidityGrowthLast);
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
        returns (uint256 balance, uint256 liquidityGrowthX128Last, uint256 leverageRatioX128)
    {
        return _debtDataOf(owner, token0, token1, strike, selector);
    }
}
