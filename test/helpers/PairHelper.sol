// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Engine} from "src/core/Engine.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IAddLiquidityCallback} from "src/core/interfaces/IAddLiquidityCallback.sol";
import {ISwapCallback} from "src/core/interfaces/ISwapCallback.sol";

contract PairHelper is IAddLiquidityCallback, ISwapCallback {
    Engine internal engine;
    MockERC20 internal token0;
    MockERC20 internal token1;

    function _setUp() internal {
        engine = new Engine();
        MockERC20 tokenA = new MockERC20();
        MockERC20 tokenB = new MockERC20();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        engine.createPair(address(token0), address(token1), 0);
    }

    function addLiquidityCallback(uint256 amount0, uint256 amount1, bytes calldata) external {
        if (amount0 > 0) token0.mint(msg.sender, amount0);
        if (amount1 > 0) token1.mint(msg.sender, amount1);
    }

    function swapCallback(int256 amount0, int256 amount1, bytes calldata) external {
        if (amount0 > 0) token0.mint(msg.sender, uint256(amount0));
        if (amount1 > 0) token1.mint(msg.sender, uint256(amount1));
    }

    function basicAddLiquidity() internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = engine.addLiquidity(
            Engine.AddLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tier: 0,
                tick: 0,
                liquidity: 1e18,
                data: bytes("")
            })
        );
    }

    function basicRemoveLiquidity() internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = engine.removeLiquidity(
            Engine.RemoveLiquidityParams({
                token0: address(token0),
                token1: address(token1),
                to: address(this),
                tier: 0,
                tick: 0,
                liquidity: 1e18
            })
        );
    }
}
