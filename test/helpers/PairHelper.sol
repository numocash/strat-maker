// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Factory} from "src/core/Factory.sol";
import {Pair} from "src/periphery/PairAddress.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IMintCallback} from "src/core/interfaces/IMintCallback.sol";
import {ISwapCallback} from "src/core/interfaces/ISwapCallback.sol";

contract PairHelper is IMintCallback {
    Factory internal factory;
    MockERC20 internal token0;
    MockERC20 internal token1;
    Pair internal pair;

    function _setUp() internal {
        factory = new Factory();
        MockERC20 tokenA = new MockERC20();
        MockERC20 tokenB = new MockERC20();
        pair = Pair(factory.createPair(address(tokenA), address(tokenB)));

        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function mintCallback(uint256 amount0, uint256 amount1, bytes calldata) external {
        if (amount0 > 0) token0.mint(msg.sender, amount0);
        if (amount1 > 0) token1.mint(msg.sender, amount1);
    }

    function swapCallback(int256 amount0, int256 amount1, bytes calldata) external {
        if (amount0 > 0) token0.mint(msg.sender, uint256(amount0));
        if (amount1 > 0) token1.mint(msg.sender, uint256(amount1));
    }

    function basicMint() internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = pair.addLiquidity(address(this), 0, -1, 1, 1e18, bytes(""));
    }

    function basicBurn() internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = pair.removeLiquidity(address(this), 0, -1, 1, 1e18);
    }
}
