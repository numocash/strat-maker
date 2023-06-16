// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

/// @custom:team this should take advantage of ilrta transfer structures
interface IExecuteCallback {
    function executeCallback(
        address[] calldata tokens,
        int256[] calldata tokensDelta,
        bytes32[] calldata lpIDs,
        int256[] calldata lpDeltas,
        bytes calldata data
    )
        external;
}
