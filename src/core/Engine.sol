// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Accounts} from "./Accounts.sol";
import {toInt256} from "./math/LiquidityMath.sol";
import {Pairs, NUM_SPREADS} from "./Pairs.sol";
import {Positions} from "./Positions.sol";
import {calcLiquidityForAmount0, calcLiquidityForAmount1} from "./math/LiquidityMath.sol";

import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IExecuteCallback} from "./interfaces/IExecuteCallback.sol";

/// @author Robert Leifke and Kyle Scott
/// @custom:team return data and events
contract Engine is Positions {
    using Pairs for Pairs.Pair;
    using Accounts for Accounts.Account;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    event PairCreated(address indexed token0, address indexed token1, int24 strikeInitial);
    event AddLiquidity(bytes32 indexed pairID, int24 indexed strike, uint8 indexed spread, uint256 liquidity);
    event Collect(
        bytes32 indexed pairID,
        int24 indexed strike,
        uint8 spread,
        address indexed owner,
        uint256 amount0Owed,
        uint256 amount1Owed
    );
    event RemoveLiquidity(bytes32 indexed pairID, int24 indexed strike, uint8 indexed spread, uint256 liquidity);
    event Swap(bytes32 indexed pairID);

    error Reentrancy();
    error InvalidTokenOrder();
    error InsufficientInput();
    error CommandLengthMismatch();
    error InvalidCommand();
    error InvalidSelector();
    error InvalidAmountDesired();

    /// @dev this should be checked when reading any `get` function from another contract to prevent read-only
    /// reentrancy
    uint256 public locked = 1;

    modifier nonReentrant() {
        if (locked != 1) revert Reentrancy();

        locked = 2;

        _;

        locked = 1;
    }

    mapping(bytes32 => Pairs.Pair) private pairs;

    enum Commands {
        Swap,
        AddLiquidity,
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

    struct CollectParams {
        address token0;
        address token1;
        address owner;
        int24 strike;
        uint8 spread;
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

    constructor(address _superSignature) Positions(_superSignature) {}

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

        if (numTokens > 0 || numLPs > 0) {
            IExecuteCallback(msg.sender).executeCallback(
                account.tokens, account.tokenDeltas, account.lpIDs, account.lpDeltas, data
            );
        }

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

        for (uint256 i = 0; i < numLPs;) {
            uint256 delta = account.lpDeltas[i];
            bytes32 id = account.lpIDs[i];

            if (id == bytes32(0)) break;

            if (delta < 0) {
                _burn(address(this), id, delta);
            }

            unchecked {
                i++;
            }
        }
    }

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

        uint256 balance;
        int256 liquidity;
        if (params.selector == TokenSelector.LiquidityPosition) {
            if (params.amountDesired < 0) revert InvalidAmountDesired();

            balance = uint256(params.amountDesired);
            liquidity = toInt256(_balanceToLiquidity(pair, params.strike, params.spread, balance));
        } else if (params.selector == TokenSelector.Token0) {
            if (params.amountDesired < 0) revert InvalidAmountDesired();

            liquidity = toInt256(
                calcLiquidityForAmount0(
                    pair.strikeCurrent[params.spread - 1],
                    pair.composition[params.spread - 1],
                    params.strike,
                    uint256(params.amountDesired),
                    false
                )
            );
            balance = _liquidityToBalance(pair, params.strike, params.spread, uint256(liquidity));
        } else if (params.selector == TokenSelector.Token1) {
            if (params.amountDesired < 0) revert InvalidAmountDesired();

            liquidity = toInt256(
                calcLiquidityForAmount1(
                    pair.strikeCurrent[params.spread - 1],
                    pair.composition[params.spread - 1],
                    params.strike,
                    uint256(params.amountDesired),
                    false
                )
            );
            balance = _liquidityToBalance(pair, params.strike, params.spread, uint256(liquidity));
        } else {
            revert InvalidSelector();
        }

        (uint256 amount0, uint256 amount1) = pair.updateLiquidity(params.strike, params.spread, liquidity);

        account.updateToken(params.token0, toInt256(amount0));
        account.updateToken(params.token1, toInt256(amount1));

        _mint(
            to,
            dataID(
                abi.encode(
                    Positions.ILRTADataID(
                        params.token0, params.token1, Positions.OrderType.BiDirectional, params.strike, params.spread
                    )
                )
            ),
            balance
        );

        emit AddLiquidity(pairID, params.strike, params.spread, balance);
    }

    function _removeLiquidity(RemoveLiquidityParams memory params, Accounts.Account memory account) private {
        (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

        uint256 balance;
        int256 liquidity;
        if (params.selector == TokenSelector.LiquidityPosition) {
            if (params.amountDesired > 0) revert InvalidAmountDesired();

            balance = uint256(-params.amountDesired);
            liquidity = -toInt256(_balanceToLiquidity(pair, params.strike, params.spread, balance));
        } else if (params.selector == TokenSelector.Token0) {
            if (params.amountDesired > 0) revert InvalidAmountDesired();

            liquidity = -toInt256(
                calcLiquidityForAmount0(
                    pair.strikeCurrent[params.spread - 1],
                    pair.composition[params.spread - 1],
                    params.strike,
                    uint256(-params.amountDesired),
                    true
                )
            );
            balance = _liquidityToBalance(pair, params.strike, params.spread, uint256(-liquidity));
        } else if (params.selector == TokenSelector.Token1) {
            if (params.amountDesired > 0) revert InvalidAmountDesired();

            liquidity = -toInt256(
                calcLiquidityForAmount1(
                    pair.strikeCurrent[params.spread - 1],
                    pair.composition[params.spread - 1],
                    params.strike,
                    uint256(-params.amountDesired),
                    true
                )
            );
            balance = _liquidityToBalance(pair, params.strike, params.spread, uint256(-liquidity));
        } else {
            revert InvalidSelector();
        }

        (uint256 amount0, uint256 amount1) = pair.updateLiquidity(params.strike, params.spread, liquidity);

        account.updateToken(params.token0, -toInt256(amount0));
        account.updateToken(params.token1, -toInt256(amount1));
        account.updateILRTA(
            dataID(
                abi.encode(
                    Positions.ILRTADataID(
                        params.token0, params.token1, Positions.OrderType.BiDirectional, params.strike, params.spread
                    )
                )
            ),
            balance
        );

        emit RemoveLiquidity(pairID, params.strike, params.spread, balance);
    }

    function _createPair(CreatePairParams memory params) private {
        if (params.token0 >= params.token1 || params.token0 == address(0)) revert InvalidTokenOrder();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);
        pair.initialize(params.strikeInitial);

        emit PairCreated(params.token0, params.token1, params.strikeInitial);
    }

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

    function getPosition(
        address token0,
        address token1,
        address owner,
        int24 strike,
        uint8 spread
    )
        external
        view
        returns (Positions.ILRTAData memory)
    {
        return _dataOf[owner][dataID(
            abi.encode(Positions.ILRTADataID(token0, token1, Positions.OrderType.BiDirectional, strike, spread))
        )];
    }
}
