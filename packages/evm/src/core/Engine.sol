// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Accounts} from "./Accounts.sol";
import {toInt256} from "./math/LiquidityMath.sol";
import {Pairs, NUM_SPREADS} from "./Pairs.sol";
import {Positions, biDirectionalID, debtID} from "./Positions.sol";
import {mulDiv} from "src/core/math/FullMath.sol";
import {
    getAmounts,
    getAmount0,
    getAmount1,
    getLiquidityForAmount0,
    getLiquidityForAmount1,
    scaleLiquidityUp,
    scaleLiquidityDown
} from "./math/LiquidityMath.sol";
import {balanceToLiquidity, liquidityToBalance, debtBalanceToLiquidity} from "./math/PositionMath.sol";
import {getRatioAtStrike, Q128} from "./math/StrikeMath.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";

import {IExecuteCallback} from "./interfaces/IExecuteCallback.sol";

// Multiplier corresponding to 2000x leverage
uint256 constant MIN_MULTIPLIER = Q128 / 2000;

/// @title Engine
/// @notice ERC20 exchange protocol
/// @author Kyle Scott and Robert Leifke
/// @custom:team Add minted position info to account
contract Engine is Positions {
    using Accounts for Accounts.Account;
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 ERRORS
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    error InsufficientInput();
    error InvalidAmountDesired();
    error InvalidTokenOrder();
    error InvalidWETHIndex();
    error Reentrancy();

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               DATA TYPES
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Types of commands to execute
    enum Commands {
        Swap,
        WrapWETH,
        UnwrapWETH,
        AddLiquidity,
        RemoveLiquidity,
        BorrowLiquidity,
        RepayLiquidity,
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

    /// @notice Data to pass to a unwrap weth action
    struct UnwrapWETHParams {
        uint256 wethIndex;
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
    /// @param liquidityGrowthX128Last
    /// @param multiplierX128
    /// @param amountDesired The amount of balance to repay
    struct RepayLiquidityParams {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        TokenSelector selectorCollateral;
        uint256 liquidityGrowthX128Last;
        uint136 multiplierX128;
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

    address payable immutable weth;

    mapping(bytes32 => Pairs.Pair) internal pairs;

    uint256 public locked = 1;

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                              CONSTRUCTOR
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    constructor(address payable _weth) {
        weth = _weth;
    }

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

    /// @notice Allow contract to receive ether from weth
    receive() external payable {
        if (msg.sender != weth) revert();
    }

    /// @notice Execute an action on the exchange
    /// @param to Address to send the output to
    /// @param commandInputs List of command inputs
    /// @param data Untouched data passed back to the callback
    function execute(
        address to,
        CommandInput[] calldata commandInputs,
        uint256 numTokens,
        uint256 numLPs,
        bytes calldata data
    )
        external
        payable
        nonReentrant
        returns (Accounts.Account memory)
    {
        Accounts.Account memory account = Accounts.newAccount(numTokens, numLPs);

        // find command helper with binary search
        for (uint256 i = 0; i < commandInputs.length;) {
            if (commandInputs[i].command < Commands.RemoveLiquidity) {
                if (commandInputs[i].command < Commands.UnwrapWETH) {
                    if (commandInputs[i].command == Commands.Swap) {
                        _swap(abi.decode(commandInputs[i].input, (SwapParams)), account);
                    } else {
                        _wrapWETH(account);
                    }
                } else {
                    if (commandInputs[i].command == Commands.UnwrapWETH) {
                        _unwrapWETH(to, abi.decode(commandInputs[i].input, (UnwrapWETHParams)), account);
                    } else {
                        _addLiquidity(to, abi.decode(commandInputs[i].input, (AddLiquidityParams)), account);
                    }
                }
            } else {
                if (commandInputs[i].command < Commands.RepayLiquidity) {
                    if (commandInputs[i].command == Commands.RemoveLiquidity) {
                        _removeLiquidity(abi.decode(commandInputs[i].input, (RemoveLiquidityParams)), account);
                    } else {
                        _borrowLiquidity(to, abi.decode(commandInputs[i].input, (BorrowLiquidityParams)), account);
                    }
                } else {
                    if (commandInputs[i].command == Commands.RepayLiquidity) {
                        _repayLiquidity(abi.decode(commandInputs[i].input, (RepayLiquidityParams)), account);
                    } else if (commandInputs[i].command == Commands.Accrue) {
                        _accrue(abi.decode(commandInputs[i].input, (AccrueParams)));
                    } else {
                        _createPair(abi.decode(commandInputs[i].input, (CreatePairParams)));
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
            if (balanceDelta < 0) SafeTransferLib.safeTransfer(ERC20(token), to, uint256(-balanceDelta));

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
                uint256 balance = ERC20(token).balanceOf(address(this));
                if (balance < account.erc20Data[i].balanceBefore + uint256(balanceDelta)) revert InsufficientInput();
            }

            unchecked {
                i++;
            }
        }

        // check liquidity positions in
        for (uint256 i = 0; i < numLPs;) {
            uint128 amountBurned = account.lpData[i].amountBurned;
            bytes32 id = account.lpData[i].id;

            if (id == bytes32(0)) break;
            _burn(address(this), id, amountBurned);

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
    /// @custom:team Should we emit the `to` address
    function _swap(SwapParams memory params, Accounts.Account memory account) internal {
        (, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

        int256 amount0;
        int256 amount1;
        if (params.selector < SwapTokenSelector.Account) {
            if (params.amountDesired == 0) revert InvalidAmountDesired();
            (amount0, amount1) = pair.swap(params.selector == SwapTokenSelector.Token0, params.amountDesired);
        } else {
            address token = account.erc20Data[uint256(params.amountDesired)].token;
            int256 swapAmount = -account.erc20Data[uint256(params.amountDesired)].balanceDelta;
            if (swapAmount == 0) revert InvalidAmountDesired();
            (amount0, amount1) = pair.swap(params.token0 == token, swapAmount);
        }

        account.updateToken(params.token0, amount0);
        account.updateToken(params.token1, amount1);
    }

    /// @notice Helper wrap weth function
    function _wrapWETH(Accounts.Account memory account) internal {
        account.updateToken(weth, -toInt256(msg.value));

        WETH(weth).deposit{value: msg.value}();
    }

    /// @notice Helper unwrap weth function
    function _unwrapWETH(address to, UnwrapWETHParams memory params, Accounts.Account memory account) internal {
        if (account.erc20Data[params.wethIndex].token != weth) revert InvalidWETHIndex();

        int256 balanceDelta = account.erc20Data[params.wethIndex].balanceDelta;

        if (balanceDelta < 0) {
            uint256 amount = uint256(-balanceDelta);

            account.erc20Data[params.wethIndex].balanceDelta = 0;

            WETH(weth).withdraw(amount);
            SafeTransferLib.safeTransferETH(to, amount);
        }
    }

    /// @notice Helper add liquidity function
    function _addLiquidity(address to, AddLiquidityParams memory params, Accounts.Account memory account) internal {
        unchecked {
            if (params.amountDesired == 0) revert InvalidAmountDesired();

            (, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

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

            // calculate how much to mint
            uint128 balance = liquidityToBalance(
                params.amountDesired,
                pair.strikes[params.strike].liquidityGrowthSpreadX128[params.spread - 1].liquidityGrowthX128
            );

            // mint position token
            _mint(
                to,
                biDirectionalID(params.token0, params.token1, params.scalingFactor, params.strike, params.spread),
                balance
            );
        }
    }

    /// @notice Helper remove liquidity function
    function _removeLiquidity(RemoveLiquidityParams memory params, Accounts.Account memory account) internal {
        unchecked {
            (, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

            {
                uint136 liquidityAccrued = pair.accrue(params.strike);
                if (liquidityAccrued > 0) pair.removeBorrowedLiquidity(params.strike, liquidityAccrued);
            }

            // Calculate how much to remove
            // Note: subtraction can underflow, will be invalid index error
            uint128 liquidity = balanceToLiquidity(
                params.amountDesired,
                pair.strikes[params.strike].liquidityGrowthSpreadX128[params.spread - 1].liquidityGrowthX128
            );

            if (liquidity == 0) revert InvalidAmountDesired();

            // remove liquidity from pair
            uint136 liquidityDisplaced = pair.removeSwapLiquidity(params.strike, params.spread, liquidity);
            if (liquidityDisplaced > 0) pair.addBorrowedLiquidity(params.strike, liquidityDisplaced);

            // calculate how much tokens to remove
            (uint256 _amount0, uint256 _amount1) =
                getAmounts(pair, scaleLiquidityUp(liquidity, params.scalingFactor), params.strike, params.spread, false);

            // update accounts
            account.updateToken(params.token0, -toInt256(_amount0));
            account.updateToken(params.token1, -toInt256(_amount1));

            // update position token
            account.updateLP(
                biDirectionalID(params.token0, params.token1, params.scalingFactor, params.strike, params.spread),
                params.amountDesired
            );
        }
    }

    /// @notice Helper borrow liquidity function
    /// @custom:team Liquidity collateral overflow
    function _borrowLiquidity(
        address to,
        BorrowLiquidityParams memory params,
        Accounts.Account memory account
    )
        internal
    {
        unchecked {
            (, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

            {
                uint136 liquidityAccrued = pair.accrue(params.strike);
                if (liquidityAccrued > 0) pair.removeBorrowedLiquidity(params.strike, liquidityAccrued);
            }

            // borrow liquidity from pair
            if (params.amountDesiredDebt == 0) revert InvalidAmountDesired();
            pair.addBorrowedLiquidity(params.strike, params.amountDesiredDebt);

            // calculate how much tokens to remove
            {
                uint256 amount0;
                uint256 amount1;

                uint8 _activeSpread = pair.strikes[params.strike].activeSpread;
                uint128 liquidity = params.amountDesiredDebt;

                while (true) {
                    uint128 borrowedLiquidity = pair.strikes[params.strike].liquidity[_activeSpread].borrowed;

                    if (borrowedLiquidity >= liquidity) {
                        (uint256 _amount0, uint256 _amount1) = getAmounts(
                            pair,
                            scaleLiquidityUp(liquidity, params.scalingFactor),
                            params.strike,
                            _activeSpread + 1,
                            false
                        );

                        amount0 += _amount0;
                        amount1 += _amount1;

                        break;
                    }

                    if (borrowedLiquidity > 0) {
                        (uint256 _amount0, uint256 _amount1) = getAmounts(
                            pair,
                            scaleLiquidityUp(borrowedLiquidity, params.scalingFactor),
                            params.strike,
                            _activeSpread + 1,
                            false
                        );

                        amount0 += _amount0;
                        amount1 += _amount1;

                        liquidity -= borrowedLiquidity;
                    }

                    _activeSpread--;
                }

                // update accounts
                account.updateToken(params.token0, -toInt256(amount0));
                account.updateToken(params.token1, -toInt256(amount1));
            }

            // add collateral to account
            uint128 liquidityCollateral;
            if (params.selectorCollateral == TokenSelector.Token0) {
                account.updateToken(params.token0, toInt256(params.amountDesiredCollateral));
                liquidityCollateral = scaleLiquidityDown(
                    getLiquidityForAmount0(params.amountDesiredCollateral, getRatioAtStrike(params.strike)),
                    params.scalingFactor
                );
            } else {
                account.updateToken(params.token1, toInt256(params.amountDesiredCollateral));
                liquidityCollateral =
                    scaleLiquidityDown(getLiquidityForAmount1(params.amountDesiredCollateral), params.scalingFactor);
            }

            // calculate how much to mint
            if (liquidityCollateral < params.amountDesiredDebt) revert InvalidAmountDesired();
            uint256 _multiplierX128 =
                ((liquidityCollateral - params.amountDesiredDebt) * Q128) / params.amountDesiredDebt;
            if (_multiplierX128 > type(uint136).max || _multiplierX128 < MIN_MULTIPLIER) revert InvalidAmountDesired();

            // update pair repay multiplier
            pair.strikes[params.strike].liquidityRepayRateX128 +=
                mulDiv(params.amountDesiredDebt, Q128, _multiplierX128);

            // mint position token
            _mint(
                to,
                debtID(
                    params.token0,
                    params.token1,
                    params.scalingFactor,
                    params.strike,
                    params.selectorCollateral,
                    pair.strikes[params.strike].liquidityGrowthX128,
                    uint136(_multiplierX128)
                ),
                params.amountDesiredDebt
            );
        }
    }

    /// @notice Helper repay liquidity function
    function _repayLiquidity(RepayLiquidityParams memory params, Accounts.Account memory account) internal {
        unchecked {
            (, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);

            {
                uint136 liquidityAccrued = pair.accrue(params.strike);
                if (liquidityAccrued > 0) pair.removeBorrowedLiquidity(params.strike, liquidityAccrued);
            }

            // calculate how much to repay
            uint128 liquidityDebt = debtBalanceToLiquidity(
                params.amountDesired,
                params.multiplierX128,
                pair.strikes[params.strike].liquidityGrowthX128 - params.liquidityGrowthX128Last
            );

            // repay liqudity to pair
            if (liquidityDebt == 0) revert InvalidAmountDesired();
            pair.removeBorrowedLiquidity(params.strike, liquidityDebt);

            // update pair repay multiplier
            pair.strikes[params.strike].liquidityRepayRateX128 -=
                mulDiv(params.amountDesired, Q128, params.multiplierX128);

            // calculate how much tokens to repay
            {
                uint256 amount0;
                uint256 amount1;

                uint8 _activeSpread = pair.strikes[params.strike].activeSpread;
                uint128 liquidity = liquidityDebt;

                while (true) {
                    uint128 swapLiquidity = pair.strikes[params.strike].liquidity[_activeSpread].swap;

                    if (swapLiquidity >= liquidity) {
                        (uint256 _amount0, uint256 _amount1) = getAmounts(
                            pair,
                            scaleLiquidityUp(liquidity, params.scalingFactor),
                            params.strike,
                            _activeSpread + 1,
                            true
                        );

                        amount0 += _amount0;
                        amount1 += _amount1;

                        break;
                    }

                    if (swapLiquidity > 0) {
                        (uint256 _amount0, uint256 _amount1) = getAmounts(
                            pair,
                            scaleLiquidityUp(swapLiquidity, params.scalingFactor),
                            params.strike,
                            _activeSpread + 1,
                            true
                        );

                        amount0 += _amount0;
                        amount1 += _amount1;

                        liquidity -= swapLiquidity;
                    }

                    _activeSpread++;
                }

                // update accounts
                account.updateToken(params.token0, toInt256(amount0));
                account.updateToken(params.token1, toInt256(amount1));
            }
            // calculate unlocked collateral and update account
            // Note: cannot overflow because liquidity collateral is strictly decreasing
            uint128 liquidityCollateral = liquidityDebt + uint128(mulDiv(params.multiplierX128, liquidityDebt, Q128));
            if (params.selectorCollateral == TokenSelector.Token0) {
                account.updateToken(
                    params.token0,
                    -toInt256(
                        getAmount0(
                            scaleLiquidityUp(liquidityCollateral, params.scalingFactor),
                            getRatioAtStrike(params.strike),
                            false
                        )
                    )
                );
            } else {
                account.updateToken(
                    params.token1, -toInt256(getAmount1(scaleLiquidityUp(liquidityCollateral, params.scalingFactor)))
                );
            }

            // update position token
            account.updateLP(
                debtID(
                    params.token0,
                    params.token1,
                    params.scalingFactor,
                    params.strike,
                    params.selectorCollateral,
                    params.liquidityGrowthX128Last,
                    params.multiplierX128
                ),
                params.amountDesired
            );
        }
    }

    /// @notice Helper accrue function
    function _accrue(AccrueParams memory params) internal {
        Pairs.Pair storage pair = pairs[params.pairID];

        uint136 liquidityAccrued = pair.accrue(params.strike);
        if (liquidityAccrued > 0) pair.removeBorrowedLiquidity(params.strike, liquidityAccrued);
    }

    /// @notice Helper create pair function
    function _createPair(CreatePairParams memory params) internal {
        if (params.token0 >= params.token1 || params.token0 == address(0)) revert InvalidTokenOrder();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1, params.scalingFactor);
        pair.initialize(params.strikeInitial);
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
