// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {MockPair} from "../mocks/MockPair.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";

contract PairHelper is IExecuteCallback {
    MockPair internal pair;
    MockERC20 internal token0;
    MockERC20 internal token1;

    function _setUp() internal {
        MockERC20 tokenA = new MockERC20();
        MockERC20 tokenB = new MockERC20();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = new MockPair(address(0), address(token0), address(token1), 0);
    }

    function executeCallback(
        address[] calldata tokens,
        int256[] calldata tokensDelta,
        bytes32[] calldata,
        int256[] calldata,
        bytes calldata
    )
        external
    {
        for (uint256 i = 0; i < tokens.length;) {
            int256 delta = tokensDelta[i];

            if (delta > 0) {
                address token = tokens[i];

                if (token == address(token0)) {
                    token0.mint(msg.sender, uint256(delta));
                } else if (token == address(token1)) {
                    token1.mint(msg.sender, uint256(delta));
                }
            }

            unchecked {
                i++;
            }
        }
    }

    function basicAddLiquidity() internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = pair.addLiquidity(0, 1, 1e18);
    }

    function basicRemoveLiquidity() internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = pair.removeLiquidity(0, 1, 1e18);
    }
}
