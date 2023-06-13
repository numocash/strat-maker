// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {BalanceLib} from "src/libraries/BalanceLib.sol";

library Accounts {
    /// @param ids The id of the token. If any of the last 12 bytes are flipped, this represents a ILRTA positions id,
    /// otherwise represents a token address
    /// @param balanceChanges The change in balance for the engine
    struct Account {
        bytes32[] ids;
        int256[] balanceChanges;
        uint256[] balances;
    }

    function newAccount(uint256 numAccounts) internal pure returns (Account memory) {
        bytes32[] memory ids = new bytes32[](numAccounts);
        int256[] memory balanceChanges = new int256[](numAccounts);
        uint256[] memory balances = new uint256[](numAccounts);

        return Account(ids, balanceChanges, balances);
    }

    function update(Account memory account, bytes32 id, int256 balanceChange) internal view {
        if (balanceChange == 0) return;

        for (uint256 i = 0; i < account.ids.length;) {
            if (account.ids[i] == id) {
                account.balanceChanges[i] = account.balanceChanges[i] + balanceChange;
            } else if (account.ids[i] == bytes32(0)) {
                account.ids[i] = id;
                account.balanceChanges[i] = balanceChange;

                if (
                    balanceChange > 0
                        && id & bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000000000000000) == 0
                ) {
                    account.balances[i] = BalanceLib.getBalance(address(uint160(uint256(id))));
                }

                break;
            }

            unchecked {
                i++;
            }
        }
    }
}
