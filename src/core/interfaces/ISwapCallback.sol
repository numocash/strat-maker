// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

interface ISwapCallback {
    function swapCallback(int256 amount0, int256 amount1, bytes calldata data) external;
}
