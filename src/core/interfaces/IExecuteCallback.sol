// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

/// @custom:team this should take advantage of ilrta transfer structures
interface IExecuteCallback {
    function executeCallback(bytes32[] calldata ids, int256[] calldata balanceChanges, bytes calldata data) external;
}
