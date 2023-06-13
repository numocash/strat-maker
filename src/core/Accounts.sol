// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

library Accounts {
    /// @param ids The id of the token. If any of the last 12 bytes are flipped, this represents a ILRTA positions id,
    /// otherwise represents a token address
    /// @param balanceChanges The change in balance for the engine
    struct Account {
        int256[] tokenDeltas;
        int256[] ilrtaDeltas;
    }

    function newAccount(uint256 numTokens, uint256 numILRTA) internal pure returns (Account memory account) {
        if (numTokens > 0) {
            account.tokenDeltas = new int256[](numTokens);
        }

        if (numILRTA > 0) {
            account.ilrtaDeltas = new int256[](numILRTA);
        }
    }

    function updateToken(
        Account memory account,
        address[] calldata tokens,
        address token,
        int256 delta
    )
        internal
        pure
    {
        if (delta == 0) return;

        for (uint256 i = 0; i < tokens.length;) {
            if (tokens[i] == token) {
                account.tokenDeltas[i] = account.tokenDeltas[i] + delta;
                return;
            }

            unchecked {
                i++;
            }
        }

        revert();
    }

    function updateILRTA(Account memory account, bytes32[] calldata ids, bytes32 id, int256 delta) internal pure {
        if (delta == 0) return;

        for (uint256 i = 0; i < ids.length;) {
            if (ids[i] == id) {
                account.ilrtaDeltas[i] = account.ilrtaDeltas[i] + delta;
                return;
            }

            unchecked {
                i++;
            }
        }

        revert();
    }
}
