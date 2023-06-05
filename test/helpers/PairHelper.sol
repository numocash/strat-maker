// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Factory} from "src/core/Factory.sol";
import {Pair} from "src/periphery/PairAddress.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IMintCallback} from "src/core/interfaces/IMintCallback.sol";

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

    function mintCallback(address, address, uint256 amount0, uint256 amount1, bytes calldata) external {
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }

    function basicMint() internal returns (uint256 amount0, uint256 amount1) {
        token0.mint(address(this), 1e18);
        token1.mint(address(this), 1e18);
        (amount0, amount1) = pair.mint(address(this), 0, -1, 0, 1e18, bytes(""));
    }

    function basicBurn() internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = pair.burn(address(this), 0, -1, 0, 1e18);
    }
}
