// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Accounts} from "./Accounts.sol";
import {toInt256} from "./math/LiquidityMath.sol";
import {Pairs, NUM_SPREADS} from "./Pairs.sol";
import {Positions, biDirectionalID, debtID} from "./Positions.sol";
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
import {getRatioAtStrike} from "./math/StrikeMath.sol";

import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IExecuteCallback} from "./interfaces/IExecuteCallback.sol";

/// @title Engine
/// @notice ERC20 exchange
/// @author Kyle Scott and Robert Leifke
/// @custom:team Add minted position info to account
contract Engine is Positions {
    using Accounts for Accounts.Account;
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 EVENTS
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    event Swap(bytes32 indexed pairID, int256 amount0, int256 amount1);
    event AddLiquidity(
        bytes32 indexed pairID,
        int24 indexed strike,
        uint8 indexed spread,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    event BorrowLiquidity(bytes32 indexed pairID, int24 indexed strike, uint128 liquidity);
    event RepayLiquidity(bytes32 indexed pairID, int24 indexed strike, uint128 liquidity);
    event RemoveLiquidity(
        bytes32 indexed pairID,
        int24 indexed strike,
        uint8 indexed spread,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    event Accrue(bytes32 indexed pairID, int24 indexed strike, uint136 liquidityAccrued);
    event PairCreated(address indexed token0, address indexed token1, uint8 scalingFactor, int24 strikeInitial);

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 ERRORS
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    error InsufficientInput();
    error InvalidAmountDesired();
    error InvalidCommand();
    error InvalidSelector();
    error InvalidTokenOrder();
    error Reentrancy();

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               DATA TYPES
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Types of commands to execute
    enum Commands {
        Swap,
        AddLiquidity,
        BorrowLiquidity,
        RepayLiquidity,
        RemoveLiquidity,
        Accrue,
        CreatePair
    }

    /// @notice Type of command with input to that command
    struct CommandInput {
        Commands command;
        bytes input;
    }

    /// @notice Type to describe which token in the pair is being referred to
    enum TokenSelector {
        Token0,
        Token1
    }

    /// @notice Type to describe what is being exchanged in a swap
    /// @param Token0 The swap is token 0
    /// @param Token1 The swap is token 1
    /// @param Account The swap indexes into the account data
    enum SwapTokenSelector {
        Token0,
        Token1,
        Account
    }

    /// @notice Type to describe a liquidity position
    enum OrderType {
        BiDirectional,
        Debt
    }

    /// @notice Data to pass to a swap action
    /// @param token0 Token in the 0 position of the pair
    /// @param token1 Token in the 1 position of the pair
    /// @param scalingFactor Amount to divide liquidity by to make it fit in a uint128
    /// @param selector What to swap
    /// @param amountDesired Amount of the token that `selector` refers to, when `selector` == Account, this indexes
    /// into the `Accounts` data
    struct SwapParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        SwapTokenSelector selector;
        int256 amountDesired;
    }

    /// @notice Data to pass to an add liquidity action
    /// @param token0 Token in the 0 position of the pair
    /// @param token1 Token in the 1 position of the pair
    /// @param scalingFactor Amount to divide liquidity by to make it fit in a uint128
    /// @param strike The strike to provide liquidity to
    /// @param spread The spread to impose on the liquidity
    /// @param amountDesired The amount of liquidity to add
    struct AddLiquidityParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        uint8 spread;
        uint128 amountDesired;
    }

    /// @notice Data to pass to a borrow liquidity action
    /// @param token0 Token in the 0 position of the pair
    /// @param token1 Token in the 1 position of the pair
    /// @param scalingFactor Amount to divide liquidity by to make it fit in a uint128
    /// @param strike The strike to borrow liquidity from
    /// @param selectorCollateral What token is used as collateral
    /// @param amountDesiredCollateral The amount of token that `selectorCollateral` refers to to use as collateral
    /// @param amountDesiredDebt The amount of liquidity to use as debt
    struct BorrowLiquidityParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        TokenSelector selectorCollateral;
        uint256 amountDesiredCollateral;
        uint128 amountDesiredDebt;
    }

    /// @notice Data to pass to a repay liquidity action
    /// @param token0 Token in the 0 position of the pair
    /// @param token1 Token in the 1 position of the pair
    /// @param scalingFactor Amount to divide liquidity by to make it fit in a uint128
    /// @param strike The strike to repay liquidity to
    /// @param selectorCollateral What token is used as collateral
    /// @param amountDesired The amount of balance to repay
    /// @param amountBuffer The amount of buffer to repay
    struct RepayLiquidityParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        TokenSelector selectorCollateral;
        uint128 amountDesired;
        uint128 amountBuffer;
    }

    /// @notice Data to pass to a remove liquidity action
    /// @param token0 Token in the 0 position of the pair
    /// @param token1 Token in the 1 position of the pair
    /// @param scalingFactor Amount to divide liquidity by to make it fit in a uint128
    /// @param strike The strike to remove liquidity from
    /// @param spread The spread on the liquidity
    /// @param amountDesired The amount of balance to remove
    struct RemoveLiquidityParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        uint8 spread;
        uint128 amountDesired;
    }

    /// @notice Data to pass to an accrue action
    /// @param pairID ID of the pair
    /// @param strike The strike to accrue interest to
    struct AccrueParams {
        bytes32 pairID;
        int24 strike;
    }

    /// @notice Data to pass to a create pair action
    /// @param token0 Token in the 0 position of the pair
    /// @param token1 Token in the 1 position of the pair
    /// @param scalingFactor Amount to divide liquidity by to make it fit in a uint128
    /// @param strikeInitial The strike to start the pair at
    struct CreatePairParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strikeInitial;
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                STORAGE
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    mapping(bytes32 => Pairs.Pair) internal pairs;

    uint256 public locked = 1;

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                MODIFIER
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Reentrancy lock
    modifier nonReentrant() {
        if (locked != 1) revert Reentrancy();

        locked = 2;

        _;

        locked = 1;
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Execute an action on the exchange
    /// @param to Address to send the output to
    /// @param commandInputs List of command inputs
    /// @param data Untouched data passed back to the callback
    /// @custom:team Try changing commandInputs to memory
    function execute(
        address to,
        CommandInput[] calldata commandInputs,
        uint256 numTokens,
        uint256 numLPs,
        bytes calldata data
    )
        external
        nonReentrant
        returns (Accounts.Account memory)
    {
        Accounts.Account memory account = Accounts.newAccount(numTokens, numLPs);

        // find command helper with binary search
        for (uint256 i = 0; i < commandInputs.length;) {
            if (commandInputs[i].command < Commands.RemoveLiquidity) {
                if (commandInputs[i].command < Commands.BorrowLiquidity) {
                    if (commandInputs[i].command == Commands.Swap) {
                        _swap(abi.decode(commandInputs[i].input, (SwapParams)), account);
                    } else {
                        _addLiquidity(to, abi.decode(commandInputs[i].input, (AddLiquidityParams)), account);
                    }
                } else {
                    if (commandInputs[i].command == Commands.BorrowLiquidity) {
                        _borrowLiquidity(to, abi.decode(commandInputs[i].input, (BorrowLiquidityParams)), account);
                    } else {
                        _repayLiquidity(abi.decode(commandInputs[i].input, (RepayLiquidityParams)), account);
                    }
                }
            } else {
                if (commandInputs[i].command < Commands.CreatePair) {
                    if (commandInputs[i].command == Commands.RemoveLiquidity) {
                        _removeLiquidity(abi.decode(commandInputs[i].input, (RemoveLiquidityParams)), account);
                    } else {
                        _accrue(abi.decode(commandInputs[i].input, (AccrueParams)));
                    }
                } else {
                    if (commandInputs[i].command == Commands.CreatePair) {
                        _createPair(abi.decode(commandInputs[i].input, (CreatePairParams)));
                    } else {
                        revert InvalidCommand();
                    }
                }
            }

            unchecked {
                i++;
            }
        }

        // record token balances
        account.getBalances();

        // transfer tokens out
        for (uint256 i = 0; i < numTokens;) {
            int256 balanceDelta = account.erc20Data[i].balanceDelta;
            address token = account.erc20Data[i].token;

            if (token == address(0)) break;
            if (balanceDelta < 0) SafeTransferLib.safeTransfer(token, to, uint256(-balanceDelta));

            unchecked {
                i++;
            }
        }

        // callback if necessary
        if (numTokens > 0 || numLPs > 0) {
            IExecuteCallback(msg.sender).executeCallback(account, data);
        }

        // check tokens in
        for (uint256 i = 0; i < numTokens;) {
            int256 balanceDelta = account.erc20Data[i].balanceDelta;
            address token = account.erc20Data[i].token;

            if (token == address(0)) break;
            if (balanceDelta > 0) {
                uint256 balance = BalanceLib.getBalance(token);
                if (balance < account.erc20Data[i].balanceBefore + uint256(balanceDelta)) revert InsufficientInput();
            }

            unchecked {
                i++;
            }
        }

        // check liquidity positions in
        for (uint256 i = 0; i < numLPs;) {
            uint128 amountBurned = account.lpData[i].amountBurned;
            uint128 amountBuffer = account.lpData[i].amountBuffer;
            bytes32 id = account.lpData[i].id;

            if (id == bytes32(0)) break;
            _burn(address(this), id, account.lpData[i].orderType, amountBurned, amountBuffer);

            unchecked {
                i++;
            }
        }

        return account;
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               INTERNAL LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Helper swap function
    /// @custom:team Should we admit the `to` address
    function _swap(SwapParams memory params, Accounts.Account memory account) internal {
        (bytes32 pairID, Pairs.Pair storage pair) =
            pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

        int256 amount0;
        int256 amount1;
        if (params.selector < SwapTokenSelector.Account) {
            (amount0, amount1) = pair.swap(params.selector == SwapTokenSelector.Token0, params.amountDesired);
        } else if (params.selector == SwapTokenSelector.Account) {
            address token = account.erc20Data[uint256(params.amountDesired)].token;
            int256 swapAmount = -account.erc20Data[uint256(params.amountDesired)].balanceDelta;
            (amount0, amount1) = pair.swap(params.token0 == token, swapAmount);
        } else {
            revert InvalidSelector();
        }

        account.updateToken(params.token0, amount0);
        account.updateToken(params.token1, amount1);

        emit Swap(pairID, amount0, amount1);
    }

    /// @notice Helper add liquidity function
    function _addLiquidity(address to, AddLiquidityParams memory params, Accounts.Account memory account) internal {
        unchecked {
            if (params.amountDesired == 0) revert InsufficientInput();

            (bytes32 pairID, Pairs.Pair storage pair) =
                pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

            {
                uint136 liquidityAccrued = pair.accrue(params.strike);
                if (liquidityAccrued > 0) pair.removeBorrowedLiquidity(params.strike, liquidityAccrued);
            }

            // add liquidity to pair
            uint136 liquidityDisplaced = pair.addSwapLiquidity(params.strike, params.spread, params.amountDesired);
            if (liquidityDisplaced > 0) pair.removeBorrowedLiquidity(params.strike, liquidityDisplaced);

            // Calculate how much tokens to add
            (uint256 _amount0, uint256 _amount1) = getAmounts(
                pair, scaleLiquidityUp(params.amountDesired, params.scalingFactor), params.strike, params.spread, true
            );

            // update accounts
            account.updateToken(params.token0, toInt256(_amount0));
            account.updateToken(params.token1, toInt256(_amount1));

            // mint position token
            uint128 balance = liquidityToBalance(
                params.amountDesired,
                pair.strikes[params.strike].liquidityGrowthSpreadX128[params.spread - 1].liquidityGrowthX128
            );

            _mintBiDirectional(
                to, params.token0, params.token1, params.scalingFactor, params.strike, params.spread, balance
            );

            emit AddLiquidity(pairID, params.strike, params.spread, params.amountDesired, _amount0, _amount1);
        }
    }

    /// @notice Helper borrow liquidity function
    /// @custom:team Test liquidity accrued being max value
    function _borrowLiquidity(
        address to,
        BorrowLiquidityParams memory params,
        Accounts.Account memory account
    )
        internal
    {
        unchecked {
            (bytes32 pairID, Pairs.Pair storage pair) =
                pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

            {
                uint136 liquidityAccrued = pair.accrue(params.strike);
                pair.removeBorrowedLiquidity(params.strike, liquidityAccrued);
            }

            pair.addBorrowedLiquidity(params.strike, params.amountDesiredDebt);

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

            uint256 _liquidityGrowthX128 = pair.strikes[params.strike].liquidityGrowthX128.liquidityGrowthX128;
            uint128 balance = debtLiquidityToBalance(params.amountDesiredDebt, _liquidityGrowthX128);
            uint128 collateralBalance = debtLiquidityToBalance(liquidityCollateral, _liquidityGrowthX128);

            if (collateralBalance >= balance) revert InsufficientInput();

            // mint position to user
            _mintDebt(
                to,
                params.token0,
                params.token1,
                params.scalingFactor,
                params.strike,
                params.selectorCollateral,
                balance,
                collateralBalance - balance
            );

            emit BorrowLiquidity(pairID, params.strike, params.amountDesiredDebt);
        }
    }

    /// @notice Helper repay liquidity function
    /// @custom:team use scale
    /// @custom:team check zero amounts
    function _repayLiquidity(RepayLiquidityParams memory params, Accounts.Account memory account) internal {
        unchecked {
            (bytes32 pairID, Pairs.Pair storage pair) =
                pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

            {
                uint136 liquidityAccrued = pair.accrue(params.strike);
                pair.removeBorrowedLiquidity(params.strike, liquidityAccrued);
            }

            uint256 _liquidityGrowthX128 = pair.strikes[params.strike].liquidityGrowthX128.liquidityGrowthX128;
            uint128 liquidityDebt = debtBalanceToLiquidity(params.amountDesired, _liquidityGrowthX128);

            pair.removeBorrowedLiquidity(params.strike, liquidityDebt);

            // unlock collateral
            uint256 liquidityCollateral =
                params.amountDesired + debtBalanceToLiquidity(params.amountBuffer, _liquidityGrowthX128);

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
            account.updateLP(
                debtID(params.token0, params.token1, params.scalingFactor, params.strike, params.selectorCollateral),
                OrderType.Debt,
                params.amountDesired,
                params.amountBuffer
            );

            emit RepayLiquidity(pairID, params.strike, liquidityDebt);
        }
    }

    /// @notice Helper remove liquidity function
    function _removeLiquidity(RemoveLiquidityParams memory params, Accounts.Account memory account) internal {
        (bytes32 pairID, Pairs.Pair storage pair) =
            pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

        uint136 liquidityAccrued = pair.accrue(params.strike);

        // Calculate how much to remove
        // Note: subtraction can underflow, will be invalid index error
        uint128 liquidity;
        unchecked {
            liquidity = balanceToLiquidity(
                params.amountDesired,
                pair.strikes[params.strike].liquidityGrowthSpreadX128[params.spread - 1].liquidityGrowthX128
            );
            uint136 liquidityDisplaced = pair.removeSwapLiquidity(params.strike, params.spread, liquidity);
            if (liquidityDisplaced > liquidityAccrued) {
                pair.addBorrowedLiquidity(params.strike, liquidityDisplaced - liquidityAccrued);
            } else if (liquidityDisplaced < liquidityAccrued) {
                pair.removeBorrowedLiquidity(params.strike, liquidityAccrued - liquidityDisplaced);
            }
        }

        (uint256 _amount0, uint256 _amount1) =
            getAmounts(pair, scaleLiquidityUp(liquidity, params.scalingFactor), params.strike, params.spread, false);

        // update accounts
        account.updateToken(params.token0, -toInt256(_amount0));
        account.updateToken(params.token1, -toInt256(_amount1));

        // update position token
        account.updateLP(
            biDirectionalID(params.token0, params.token1, params.scalingFactor, params.strike, params.spread),
            OrderType.BiDirectional,
            params.amountDesired,
            0
        );

        emit RemoveLiquidity(pairID, params.strike, params.spread, liquidity, _amount0, _amount1);
    }

    /// @notice Helper accrue function
    function _accrue(AccrueParams memory params) internal {
        Pairs.Pair storage pair = pairs[params.pairID];

        uint136 liquidityAccrued = pair.accrue(params.strike);
        if (liquidityAccrued > 0) pair.removeBorrowedLiquidity(params.strike, liquidityAccrued);

        emit Accrue(params.pairID, params.strike, liquidityAccrued);
    }

    /// @notice Helper create pair function
    function _createPair(CreatePairParams memory params) internal {
        if (params.token0 >= params.token1 || params.token0 == address(0)) revert InvalidTokenOrder();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);
        pair.initialize(params.strikeInitial);

        emit PairCreated(params.token0, params.token1, params.scalingFactor, params.strikeInitial);
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               VIEW LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Return the state of the pair
    function getPair(
        address token0,
        address token1,
        uint8 scalingFactor
    )
        external
        view
        returns (uint128[NUM_SPREADS] memory composition, int24[NUM_SPREADS] memory strikeCurrent, bool initialized)
    {
        (, Pairs.Pair storage pair) = pairs.getPairAndID(token0, token1, scalingFactor);

        (composition, strikeCurrent, initialized) = (pair.composition, pair.strikeCurrent, pair.initialized);
    }

    /// @notice Return the state of the strike
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
