// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Engine} from "./Engine.sol";
import {BalanceLib} from "src/libraries/BalanceLib.sol";

/// @title Accounts
/// @notice Library for storing and updating intermediate balance changes in memory
library Accounts {
    error InvalidAccountLength();

    /// @notice Data for balance change of an erc20;
    /// @param token The address of the erc20;
    /// @param balanceBefore This contracts balance of the token before settlement
    /// @param balanceDelta The change in balance for the contract
    /// @custom:team Possibly change to balanceAfter instead of balanceDelta
    struct ERC20Data {
        address token;
        uint256 balanceBefore;
        int256 balanceDelta;
    }

    /// @notice Data for burned liquidity positions
    /// @param id Liquidity position id
    /// @param amountBurned Balance to be burned
    /// @param orderType What type of position does this represent
    struct LPData {
        bytes32 id;
        uint128 amountBurned;
        Engine.OrderType orderType;
    }

    /// @notice Data stored that makes up an account
    /// @param erc20Data Data for erc20 token that are being exchanged
    /// @param lpData Data for liquidity provider tokens that are being burned
    struct Account {
        ERC20Data[] erc20Data;
        LPData[] lpData;
    }

    /// @notice Create a new instance of an account with the specified sizes
    function newAccount(uint256 numERC20, uint256 numLP) internal pure returns (Account memory account) {
        if (numERC20 > 0) account.erc20Data = new ERC20Data[](numERC20);
        if (numLP > 0) account.lpData = new LPData[](numLP);
    }

    /// @notice Update a token's intermediate account balance, creating a new one if one doesn't already exist
    function updateToken(Account memory account, address token, int256 delta) internal pure {
        if (delta == 0) return;

        for (uint256 i = 0; i < account.erc20Data.length;) {
            if (account.erc20Data[i].token == token) {
                // might not need checked math
                account.erc20Data[i].balanceDelta += delta;
                return;
            } else if (account.erc20Data[i].token == address(0)) {
                account.erc20Data[i].token = token;
                account.erc20Data[i].balanceDelta = delta;
                return;
            }

            unchecked {
                i++;
            }
        }

        revert InvalidAccountLength();
    }

    /// @notice Update a liquidity position's intermediate account balance, creating a new one if one doesn't already
    /// exist
    function updateLP(
        Account memory account,
        bytes32 id,
        uint128 amountBurned,
        Engine.OrderType orderType
    )
        internal
        pure
    {
        if (amountBurned == 0) return;

        for (uint256 i = 0; i < account.lpData.length;) {
            if (account.lpData[i].id == id) {
                // might not need checked math
                account.lpData[i].amountBurned += amountBurned;
                return;
            } else if (account.lpData[i].id == bytes32(0)) {
                account.lpData[i].id = id;
                account.lpData[i].amountBurned = amountBurned;
                account.lpData[i].orderType = orderType;
                return;
            }

            unchecked {
                i++;
            }
        }

        revert InvalidAccountLength();
    }

    /// @notice Read and store the current contract balance of tokens being owed to the contract
    function getBalances(Account memory account) internal view {
        unchecked {
            for (uint256 i = 0; i < account.erc20Data.length; i++) {
                if (account.erc20Data[i].balanceDelta > 0) {
                    account.erc20Data[i].balanceBefore = BalanceLib.getBalance(account.erc20Data[i].token);
                }
            }
        }
    }
}
