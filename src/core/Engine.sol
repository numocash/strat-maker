// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Pairs} from "./Pairs.sol";

import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IAddLiquidityCallback} from "./interfaces/IAddLiquidityCallback.sol";
import {ISwapCallback} from "./interfaces/ISwapCallback.sol";

contract Engine {
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    event PairCreated(address indexed token0, address indexed token1);
    event AddLiquidity();
    event RemoveLiquidity();
    event Swap();

    error InvalidTokenOrder();
    error InsufficientInput();

    mapping(bytes32 => Pairs.Pair) internal pairs;

    function createPair(address token0, address token1, int24 initialTick) external {
        if (token0 >= token1 || token0 == address(0)) revert InvalidTokenOrder();

        Pairs.Pair storage pair = pairs.getPair(token0, token1);
        pair.initialize(initialTick);

        emit PairCreated(token0, token1);
    }

    struct AddLiquidityParams {
        address token0;
        address token1;
        address to;
        uint8 tierID;
        int24 tick;
        uint256 liquidity;
        bytes data;
    }

    function addLiqudity(AddLiquidityParams calldata params) external returns (uint256 amount0, uint256 amount1) {
        Pairs.Pair storage pair = pairs.getPair(params.token0, params.token1);
        (amount0, amount1) = pair.updateLiquidity(params.to, params.tierID, params.tick, int256(params.liquidity));

        uint256 balance0 = BalanceLib.getBalance(params.token0);
        uint256 balance1 = BalanceLib.getBalance(params.token1);
        IAddLiquidityCallback(msg.sender).addLiquidityCallback(amount0, amount1, params.data);
        if (BalanceLib.getBalance(params.token0) < balance0 + amount0) revert InsufficientInput();
        if (BalanceLib.getBalance(params.token1) < balance1 + amount1) revert InsufficientInput();

        emit AddLiquidity();
    }

    struct RemoveLiquidityParams {
        address token0;
        address token1;
        address to;
        uint8 tierID;
        int24 tick;
        uint256 liquidity;
    }

    function removeLiquidity(RemoveLiquidityParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        Pairs.Pair storage pair = pairs.getPair(params.token0, params.token1);
        (amount0, amount1) = pair.updateLiquidity(params.to, params.tierID, params.tick, -int256(params.liquidity));

        SafeTransferLib.safeTransfer(params.token0, params.to, amount0);
        SafeTransferLib.safeTransfer(params.token1, params.to, amount1);

        emit RemoveLiquidity();
    }

    struct SwapParams {
        address token0;
        address token1;
        address to;
        bool isToken0;
        int256 amountDesired;
        bytes data;
    }

    function swap(SwapParams calldata params) external returns (int256 amount0, int256 amount1) {
        Pairs.Pair storage pair = pairs.getPair(params.token0, params.token1);
        (amount0, amount1) = pair.swap(params.isToken0, params.amountDesired);

        if (params.isToken0 == (params.amountDesired > 0)) {
            if (amount1 < 0) SafeTransferLib.safeTransfer(params.token1, params.to, uint256(-amount1));
            uint256 balance0 = BalanceLib.getBalance(params.token0);
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, params.data);
            if (BalanceLib.getBalance(params.token0) < balance0 + uint256(amount0)) revert InsufficientInput();
        } else {
            if (amount0 < 0) SafeTransferLib.safeTransfer(params.token0, params.to, uint256(-amount0));
            uint256 balance1 = BalanceLib.getBalance(params.token1);
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, params.data);
            if (BalanceLib.getBalance(params.token1) < balance1 + uint256(amount1)) revert InsufficientInput();
        }

        emit Swap();
    }
}
