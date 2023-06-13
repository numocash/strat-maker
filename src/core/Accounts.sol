// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

library Accounts {
    /// @param indexes maps token to (index + 1) in ids and balanceChanges arrays, 0 means uninitialized
    /// @param ids The id of the token. If any of the last 12 bytes are flipped, this represents a ILRTA positions id,
    /// otherwise represents a token address
    /// @param balanceChanges The change in balance for the engine
    /// @custom:team why can't this be implemented in memory
    struct Account {
        mapping(bytes32 => uint256) indexes;
        bytes32[] ids;
        int256[] balanceChanges;
    }

    function update(Account storage account, bytes32 id, int256 balanceChange) internal {
        uint256 index = account.indexes[id];
        if (index == 0) {
            account.indexes[id] = account.ids.length + 1;
            account.ids.push(id);
            account.balanceChanges.push(balanceChange);
        } else {
            account.balanceChanges[index - 1] = account.balanceChanges[index - 1] + balanceChange;
        }
    }
}
