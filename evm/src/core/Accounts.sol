// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Engine} from "./Engine.sol";
import {BalanceLib} from "src/libraries/BalanceLib.sol";

library Accounts {
    error InvalidAccountLength();

    struct Account {
        address[] tokens;
        int256[] tokenDeltas;
        uint256[] balances;
        bytes32[] lpIDs;
        uint256[] lpDeltas;
        Engine.OrderType[] orderTypes;
    }

    function newAccount(uint256 numTokens, uint256 numLPs) internal pure returns (Account memory account) {
        if (numTokens > 0) {
            account.tokens = new address[](numTokens);
            account.tokenDeltas = new int256[](numTokens);
            account.balances = new uint256[](numTokens);
        }

        if (numLPs > 0) {
            account.lpIDs = new bytes32[](numLPs);
            account.lpDeltas = new uint256[](numLPs);
            account.orderTypes = new Engine.OrderType[](numLPs);
        }
    }

    function updateToken(Account memory account, address token, int256 delta) internal view {
        if (delta == 0) return;

        unchecked {
            for (uint256 i = 0; i < account.tokens.length; i++) {
                if (account.tokens[i] == token) {
                    // change in balance cannot exceed the total supply
                    account.tokenDeltas[i] = account.tokenDeltas[i] + delta;
                    return;
                } else if (account.tokens[i] == address(0)) {
                    account.tokens[i] = token;
                    account.tokenDeltas[i] = delta;

                    if (delta > 0) account.balances[i] = BalanceLib.getBalance(token);
                    return;
                }
            }
        }

        revert InvalidAccountLength();
    }

    /// @custom:team what if ids match but not data
    function updateILRTA(Account memory account, bytes32 id, uint256 delta, Engine.OrderType orderType) internal pure {
        if (delta == 0) return;

        unchecked {
            for (uint256 i = 0; i < account.lpIDs.length; i++) {
                if (account.lpIDs[i] == id) {
                    // change in liquidity cannot exceed the maximum liquidity in a strike
                    account.lpDeltas[i] = account.lpDeltas[i] + delta;
                    return;
                } else if (account.lpIDs[i] == bytes32(0)) {
                    account.lpIDs[i] = id;
                    account.lpDeltas[i] = delta;
                    account.orderTypes[i] = orderType;
                    return;
                }
            }
        }

        revert InvalidAccountLength();
    }
}
