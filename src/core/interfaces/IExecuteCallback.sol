// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Engine} from "../Engine.sol";

/// @custom:team this should take advantage of ilrta transfer structures
interface IExecuteCallback {
    struct CallbackParams {
        address[] tokens;
        int256[] tokensDelta;
        bytes32[] lpIDs;
        uint256[] lpDeltas;
        Engine.OrderType[] orderTypes;
        bytes[] datas;
        bytes data;
    }

    function executeCallback(CallbackParams calldata params) external;
}
