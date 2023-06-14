// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Pairs, MAX_SPREADS} from "./Pairs.sol";
import {Strikes} from "./Strikes.sol";
import {Positions} from "./Positions.sol";
import {Accounts} from "./Accounts.sol";

import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IExecuteCallback} from "./interfaces/IExecuteCallback.sol";

/// @author Robert Leifke and Kyle Scott
/// @custom:team return data
contract Engine is Positions {
    using Strikes for Strikes.Strike;
    using Pairs for Pairs.Pair;
    using Accounts for Accounts.Account;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    event PairCreated(address indexed token0, address indexed token1, int24 strikeInitial);
    event AddLiquidity(bytes32 indexed pairID, int24 indexed strike, uint8 indexed spread, uint256 liquidity);
    event RemoveLiquidity(bytes32 indexed pairID, int24 indexed strike, uint8 indexed spread, uint256 liquidity);
    event Swap(bytes32 indexed pairID);

    error Reentrancy();
    error InvalidTokenOrder();
    error InsufficientInput();
    error CommandLengthMismatch();
    error InvalidCommand();

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

    struct SwapParams {
        address token0;
        address token1;
        bool isToken0;
        int256 amountDesired;
    }

    struct AddLiquidityParams {
        address token0;
        address token1;
        int24 strike;
        uint8 spread;
        uint256 liquidity;
    }

    struct RemoveLiquidityParams {
        address token0;
        address token1;
        int24 strike;
        uint8 spread;
        uint256 liquidity;
    }

    struct CreatePairParams {
        address token0;
        address token1;
        int24 strikeInitial;
    }

    function execute(
        Commands[] calldata commands,
        bytes[] calldata inputs,
        address to,
        uint256 numTokens,
        uint256 numILRTA,
        bytes calldata data
    )
        external
    {
        _execute(commands, inputs, to, numTokens, numILRTA, data);
    }

    /// @dev Set to address to 0 if creating a pair
    function _execute(
        Commands[] calldata commands,
        bytes[] calldata inputs,
        address to,
        uint256 numTokens,
        uint256 numILRTA,
        bytes calldata data
    )
        private
        nonReentrant
    {
        if (commands.length != inputs.length) revert CommandLengthMismatch();

        Accounts.Account memory account = Accounts.newAccount(numTokens, numILRTA);

        for (uint256 i = 0; i < commands.length;) {
            if (commands[i] == Commands.Swap) {
                SwapParams memory params = abi.decode(inputs[i], (SwapParams));
                (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

                (int256 amount0, int256 amount1) = pair.swap(params.isToken0, params.amountDesired);

                account.updateToken(params.token0, amount0);
                account.updateToken(params.token1, amount1);

                emit Swap(pairID);
            } else if (commands[i] == Commands.AddLiquidity) {
                AddLiquidityParams memory params = abi.decode(inputs[i], (AddLiquidityParams));
                (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

                (uint256 amount0, uint256 amount1) =
                    pair.updateLiquidity(params.strike, params.spread, int256(params.liquidity));

                account.updateToken(params.token0, int256(amount0));
                account.updateToken(params.token1, int256(amount1));
                account.updateILRTA(
                    dataID(
                        abi.encode(Positions.ILRTADataID(params.token0, params.token1, params.strike, params.spread))
                    ),
                    -int256(params.liquidity)
                );

                emit AddLiquidity(pairID, params.strike, params.spread, params.liquidity);
            } else if (commands[i] == Commands.RemoveLiquidity) {
                RemoveLiquidityParams memory params = abi.decode(inputs[i], (RemoveLiquidityParams));
                (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

                (uint256 amount0, uint256 amount1) =
                    pair.updateLiquidity(params.strike, params.spread, -int256(params.liquidity));

                account.updateToken(params.token0, -int256(amount0));
                account.updateToken(params.token1, -int256(amount1));
                account.updateILRTA(
                    dataID(
                        abi.encode(Positions.ILRTADataID(params.token0, params.token1, params.strike, params.spread))
                    ),
                    int256(params.liquidity)
                );

                emit RemoveLiquidity(pairID, params.strike, params.spread, params.liquidity);
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

        for (uint256 i = 0; i < numILRTA;) {
            int256 delta = account.ilrtaDeltas[i];
            bytes32 id = account.ids[i];

            if (id == bytes32(0)) break;

            if (delta < 0) {
                _mint(to, id, uint256(-delta));
            }

            unchecked {
                i++;
            }
        }

        if (numTokens > 0 || numILRTA > 0) {
            IExecuteCallback(msg.sender).executeCallback(
                account.tokens, account.tokenDeltas, account.ids, account.ilrtaDeltas, data
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

        for (uint256 i = 0; i < numILRTA;) {
            int256 delta = account.ilrtaDeltas[i];
            bytes32 id = account.ids[i];

            if (id == bytes32(0)) break;

            if (delta > 0) {
                _burn(address(this), id, uint256(delta));
            }

            unchecked {
                i++;
            }
        }
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
        returns (uint128[MAX_SPREADS] memory compositions, int24 strikeCurrent, int8 offset, uint8 initialized)
    {
        (, Pairs.Pair storage pair) = pairs.getPairAndID(token0, token1);
        (compositions, strikeCurrent, offset, initialized) =
            (pair.compositions, pair.strikeCurrent, pair.offset, pair.initialized);
    }

    function getStrike(address token0, address token1, int24 strike) external view returns (Strikes.Strike memory) {
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
        return _dataOf[owner][dataID(abi.encode(Positions.ILRTADataID(token0, token1, strike, spread)))];
    }
}
