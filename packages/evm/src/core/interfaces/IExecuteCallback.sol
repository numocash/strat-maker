// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {Accounts} from "../Accounts.sol";

/// @notice Interface for callback that is called in the `execute` function
interface IExecuteCallback {
    /// @param data Extra data passed back to the callback from the caller
    function executeCallback(Accounts.Account calldata account, bytes calldata data) external;
}
