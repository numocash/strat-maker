// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Pairs, MAX_TIERS} from "./Pairs.sol";
import {Ticks} from "./Ticks.sol";
import {Positions} from "./Positions.sol";
import {Accounts} from "./Accounts.sol";

import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IExecuteCallback} from "./interfaces/IExecuteCallback.sol";

/// @author Robert Leifke and Kyle Scott
/// @custom:team id could be an issue is someone mines an ilrta id with 24 trailing zeros
/// @custom:team add execute by signature
/// @custom:team check if a function that only does one action is worth it
/// @custom:team pass in token addresses in an array and copy it to memory, so that we dont have to store in storage
contract Engine is Positions {
    using Ticks for Ticks.Tick;
    using Pairs for Pairs.Pair;
    using Accounts for Accounts.Account;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    event PairCreated(address indexed token0, address indexed token1, int24 tickInitial);
    event AddLiquidity(bytes32 indexed pairID, int24 indexed tick, uint8 indexed tier, uint256 liquidity);
    event RemoveLiquidity(bytes32 indexed pairID, int24 indexed tick, uint8 indexed tier, uint256 liquidity);
    event Swap(bytes32 indexed pairID);

    error Reentrancy();
    error InvalidTokenOrder();
    error InsufficientInput();
    error CommandLengthMismatch();
    error InvalidCommand();

    Accounts.Account private account;

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
        int24 tick;
        uint8 tier;
        uint256 liquidity;
    }

    struct RemoveLiquidityParams {
        address token0;
        address token1;
        int24 tick;
        uint8 tier;
        uint256 liquidity;
    }

    struct CreatePairParams {
        address token0;
        address token1;
        int24 tickInitial;
    }

    function execute(Commands[] calldata commands, bytes[] calldata inputs, address to, bytes calldata data) external {
        _execute(commands, inputs, to, data);
    }

    /// @dev Set to address to 0 if creating a pair
    function _execute(
        Commands[] calldata commands,
        bytes[] calldata inputs,
        address to,
        bytes calldata data
    )
        private
        nonReentrant
    {
        if (commands.length != inputs.length) revert CommandLengthMismatch();

        for (uint256 i = 0; i < commands.length;) {
            if (commands[i] == Commands.Swap) {
                SwapParams memory params = abi.decode(inputs[i], (SwapParams));
                (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

                (int256 amount0, int256 amount1) = pair.swap(params.isToken0, params.amountDesired);

                account.update(bytes32(uint256(uint160(params.token0))), amount0);
                account.update(bytes32(uint256(uint160(params.token1))), amount1);

                emit Swap(pairID);
            } else if (commands[i] == Commands.AddLiquidity) {
                AddLiquidityParams memory params = abi.decode(inputs[i], (AddLiquidityParams));
                (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

                (uint256 amount0, uint256 amount1) =
                    pair.updateLiquidity(params.tick, params.tier, int256(params.liquidity));

                account.update(bytes32(uint256(uint160(params.token0))), int256(amount0));
                account.update(bytes32(uint256(uint160(params.token1))), int256(amount1));
                account.update(
                    dataID(abi.encode(Positions.ILRTADataID(params.token0, params.token1, params.tick, params.tier))),
                    -int256(params.liquidity)
                );

                emit AddLiquidity(pairID, params.tick, params.tier, params.liquidity);
            } else if (commands[i] == Commands.RemoveLiquidity) {
                RemoveLiquidityParams memory params = abi.decode(inputs[i], (RemoveLiquidityParams));
                (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);

                (uint256 amount0, uint256 amount1) =
                    pair.updateLiquidity(params.tick, params.tier, -int256(params.liquidity));

                account.update(bytes32(uint256(uint160(params.token0))), -int256(amount0));
                account.update(bytes32(uint256(uint160(params.token1))), -int256(amount1));
                account.update(
                    dataID(abi.encode(Positions.ILRTADataID(params.token0, params.token1, params.tick, params.tier))),
                    int256(params.liquidity)
                );

                emit RemoveLiquidity(pairID, params.tick, params.tier, params.liquidity);
            } else if (commands[i] == Commands.CreatePair) {
                createPair(abi.decode(inputs[i], (CreatePairParams)));
            } else {
                revert InvalidCommand();
            }

            unchecked {
                i++;
            }
        }

        uint256[] memory balancesBefore = new uint256[](account.ids.length);

        for (uint256 i = 0; i < account.ids.length;) {
            int256 balanceChange = account.balanceChanges[i];
            bytes32 id = account.ids[i];

            if (balanceChange < 0) {
                if (id & bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000000000000000) > 0) {
                    _mint(to, id, uint256(-balanceChange));
                } else {
                    SafeTransferLib.safeTransfer(address(uint160(uint256(id))), to, uint256(-balanceChange));
                }
            } else {
                if (id & bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000000000000000) == 0) {
                    balancesBefore[i] = BalanceLib.getBalance(address(uint160(uint256(id))));
                }
            }

            unchecked {
                i++;
            }
        }

        IExecuteCallback(msg.sender).executeCallback(account.ids, account.balanceChanges, data);

        for (uint256 i = 0; i < account.ids.length;) {
            int256 balanceChange = account.balanceChanges[i];

            if (balanceChange > 0) {
                bytes32 id = account.ids[i];

                if (id & bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000000000000000) > 0) {
                    _burn(address(this), id, uint256(balanceChange));
                } else {
                    uint256 balance = BalanceLib.getBalance(address(uint160(uint256(id))));
                    if (balance < balancesBefore[i] + uint256(balanceChange)) revert InsufficientInput();
                }
            }

            account.indexes[account.ids[i]] = 0;

            unchecked {
                i++;
            }
        }

        delete account.ids;
        delete account.balanceChanges;
    }

    function createPair(CreatePairParams memory params) private {
        if (params.token0 >= params.token1 || params.token0 == address(0)) revert InvalidTokenOrder();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(params.token0, params.token1);
        pair.initialize(params.tickInitial);

        emit PairCreated(params.token0, params.token1, params.tickInitial);
    }

    function getPair(
        address token0,
        address token1
    )
        external
        view
        returns (uint128[MAX_TIERS] memory compositions, int24 tickCurrent, int8 offset, uint8 initialized)
    {
        (, Pairs.Pair storage pair) = pairs.getPairAndID(token0, token1);
        (compositions, tickCurrent, offset, initialized) =
            (pair.compositions, pair.tickCurrent, pair.offset, pair.initialized);
    }

    function getTick(address token0, address token1, int24 tick) external view returns (Ticks.Tick memory) {
        (, Pairs.Pair storage pair) = pairs.getPairAndID(token0, token1);

        return pair.ticks[tick];
    }

    function getPosition(
        address token0,
        address token1,
        address owner,
        int24 tick,
        uint8 tier
    )
        external
        view
        returns (Positions.ILRTAData memory)
    {
        return _dataOf[owner][dataID(abi.encode(Positions.ILRTADataID(token0, token1, tick, tier)))];
    }
}
