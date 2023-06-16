// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {BalanceLib} from "src/libraries/BalanceLib.sol";

library Accounts {
    struct Account {
        address[] tokens;
        int256[] tokenDeltas;
        uint256[] balances;
        bytes32[] ids;
        int256[] ilrtaDeltas;
    }

    function newAccount(uint256 numTokens, uint256 numILRTA) internal pure returns (Account memory account) {
        if (numTokens > 0) {
            account.tokens = new address[](numTokens);
            account.tokenDeltas = new int256[](numTokens);
            account.balances = new uint256[](numTokens);
        }

        if (numILRTA > 0) {
            account.ids = new bytes32[](numILRTA);
            account.ilrtaDeltas = new int256[](numILRTA);
        }
    }

    function updateToken(Account memory account, address token, int256 delta) internal view {
        if (delta == 0) return;

        for (uint256 i = 0; i < account.tokens.length;) {
            if (account.tokens[i] == token) {
                // change in balance cannot exceed the total supply
                unchecked {
                    account.tokenDeltas[i] = account.tokenDeltas[i] + delta;
                }
                return;
            } else if (account.tokens[i] == address(0)) {
                account.tokens[i] = token;
                account.tokenDeltas[i] = delta;

                if (delta > 0) account.balances[i] = BalanceLib.getBalance(token);

                return;
            }

            unchecked {
                i++;
            }
        }
    }

    function updateILRTA(Account memory account, bytes32 id, int256 delta) internal pure {
        if (delta == 0) return;

        for (uint256 i = 0; i < account.ids.length;) {
            if (account.ids[i] == id) {
                // change in liquidity cannot exceed the maximum liquidity in a strike
                unchecked {
                    account.ilrtaDeltas[i] = account.ilrtaDeltas[i] + delta;
                }
                return;
            } else if (account.ids[i] == bytes32(0)) {
                account.ids[i] = id;
                account.ilrtaDeltas[i] = delta;
                return;
            }

            unchecked {
                i++;
            }
        }
    }
}
