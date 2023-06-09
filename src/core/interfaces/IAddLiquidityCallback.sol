// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

interface IAddLiquidityCallback {
    function addLiquidityCallback(uint256 amount0, uint256 amount1, bytes calldata data) external;
}