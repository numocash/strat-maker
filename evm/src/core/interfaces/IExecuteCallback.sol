// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Accounts} from "../Accounts.sol";

/// @custom:team this should take advantage of ilrta transfer structures
interface IExecuteCallback {
    struct CallbackParams {
        Accounts.Account account;
        bytes data;
    }

    function executeCallback(CallbackParams calldata params) external;
}
