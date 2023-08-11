// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Engine} from "./Engine.sol";
import {addPositions} from "./math/PositionMath.sol";
import {ILRTA} from "ilrta/ILRTA.sol";

/// @title Positions
/// @notice Representation of a position on the exchange
abstract contract Positions is ILRTA("Numoen Dry Powder", "DP") {
    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               DATA TYPES
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice The data that distinguishes between positions
    /// @dev bytes32 id = keccak256(abi.encode(ILRTADataID))
    /// @param orderType Signifies the type of position
    /// @param data Extra data that is either of type BiDirectionalID or DebtID depending on `orderType`
    struct ILRTADataID {
        Engine.OrderType orderType;
        bytes data;
    }

    /// @notice The data that a position records
    /// @param balance The balance of the position either in units of share of liquidity provided or interested adjusted
    /// liquidity debt
    /// @param orderType Signifies the type of position
    /// @param data Extra data that is either empty or type of DebtData
    struct ILRTAData {
        uint128 balance;
        Engine.OrderType orderType;
        bytes data;
    }

    /// @notice Information needed to describe a transfer
    /// @param id The unique identifier of a position
    /// @param orderType Signifies the type of position
    /// @param amount The amount of the position to transfer either in units of share of liquidity provided or
    /// interested adjusted liquidity debt
    struct ILRTATransferDetails {
        bytes32 id;
        Engine.OrderType orderType;
        uint128 amount;
    }

    /// @notice Information needed to describe an approval
    /// @param approved True if the `spender` is allowed full control of the position of `owner`
    struct ILRTAApprovalDetails {
        bool approved;
    }

    /// @notice Extra data needed to distinguish between liquidity positions
    /// @param token0 Address of the first token
    /// @param token1 Address of the second token
    /// @param scalingFactor Divisor such that liquidity  / 2 ** `scalingFactor` fits in a uint128
    /// @param strike Strike which to center liquidity around
    /// @param spread Distance from `strike` in units of strikes which to trade 0 => 1 (`strike` - `spread`) or
    /// 1 => 0 (`strike` + `spread`)
    struct BiDirectionalID {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        uint8 spread;
    }

    /// @notice Extra data needed to distinguish between debt positions
    /// @param token0 Address of the first token
    /// @param token1 Address of the second token
    /// @param scalingFactor Divisor such that liquidity  / 2 ** `scalingFactor` fits in a uint128
    /// @param strike Strike where liquidity is borrowed from
    /// @param selector Token used for the collateral
    struct DebtID {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        Engine.TokenSelector selector;
    }

    /// @notice Extra data needed for a debt position
    /// @param leverageRatioX128
    /// @custom:team fill out leverageRatioX128
    struct DebtData {
        uint256 leverageRatioX128;
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                STORAGE
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    mapping(address owner => mapping(bytes32 id => ILRTAData data)) internal _dataOf;

    mapping(address owner => mapping(address spender => ILRTAApprovalDetails approvalDetails)) private _allowanceOf;

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Reads and returns the data of the position
    /// @dev Function selector is keccak("dataOf()"")
    function dataOf_cGJnTo(address owner, bytes32 id) external view returns (ILRTAData memory) {
        return _dataOf[owner][id];
    }

    /// @notice Reads and returns the allowance of the position
    /// @dev Function selector is keccak("allowanceOf()")
    function allowanceOf_QDmnOj(
        address owner,
        address spender,
        bytes32
    )
        external
        view
        returns (ILRTAApprovalDetails memory)
    {
        return _allowanceOf[owner][spender];
    }

    /// @notice Returns true if `requestedTransferDetails` is valid given the `signedTransferDetails`
    /// @dev Function selector is keccak256("validateRequest()"")
    function validateRequest_bzlHQU(
        ILRTATransferDetails calldata signedTransferDetails,
        ILRTATransferDetails calldata requestedTransferDetails
    )
        external
        pure
        returns (bool)
    {
        return (
            requestedTransferDetails.amount > signedTransferDetails.amount
                || requestedTransferDetails.id != signedTransferDetails.id
                || requestedTransferDetails.orderType != signedTransferDetails.orderType
        ) ? false : true;
    }

    /// @notice Transfer from `msg.sender` to `to` described by `transferDetails`
    /// @dev Function selector is keccak256("transfer()")
    function transfer_Jvpprd(address to, ILRTATransferDetails calldata transferDetails) external returns (bool) {
        return _transfer(msg.sender, to, transferDetails);
    }

    /// @notice Allow `spender` the allowance described by `approvalDetails` on the position of  `msg.sender`
    /// @dev Function selector is keccak256("approve()")
    function approve_BKoIou(address spender, ILRTAApprovalDetails calldata approvalDetails) external returns (bool) {
        _allowanceOf[msg.sender][spender] = approvalDetails;

        emit Approval(msg.sender, spender, abi.encode(approvalDetails));

        return true;
    }

    /// @notice Transfer from `from` to `to` described by `transferDetails` if the allowance is adequate, else revert
    /// @dev Function selector is keccak256("transferFrom()")
    function transferFrom_jDUYFr(
        address from,
        address to,
        ILRTATransferDetails calldata transferDetails
    )
        external
        returns (bool)
    {
        ILRTAApprovalDetails memory allowed = _allowanceOf[from][msg.sender];

        if (!allowed.approved) revert();

        return _transfer(from, to, transferDetails);
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                             INTERNAL LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Helper function for transfers, uses `orderType` and updates a position based on the type
    function _transfer(address from, address to, ILRTATransferDetails memory transferDetails) private returns (bool) {
        if (transferDetails.orderType != Engine.OrderType.Debt) {
            _dataOf[from][transferDetails.id].balance -= transferDetails.amount;
            unchecked {
                _dataOf[to][transferDetails.id].balance += transferDetails.amount;
            }

            emit Transfer(from, to, abi.encode(transferDetails));
            return true;
        } else {
            uint128 senderBalance = _dataOf[from][transferDetails.id].balance;
            uint128 recipientBalance = _dataOf[to][transferDetails.id].balance;

            uint256 leverageRatioX128 = recipientBalance == 0
                ? abi.decode(_dataOf[from][transferDetails.id].data, (DebtData)).leverageRatioX128
                : addPositions(
                    transferDetails.amount,
                    recipientBalance,
                    abi.decode(_dataOf[from][transferDetails.id].data, (DebtData)),
                    abi.decode(_dataOf[to][transferDetails.id].data, (DebtData))
                );

            if (senderBalance == transferDetails.amount) delete _dataOf[from][transferDetails.id];
            else _dataOf[from][transferDetails.id].balance = senderBalance - transferDetails.amount;

            unchecked {
                _dataOf[to][transferDetails.id].balance = recipientBalance + transferDetails.amount;
            }

            _dataOf[to][transferDetails.id].data = abi.encode(DebtData(leverageRatioX128));

            emit Transfer(from, to, abi.encode(transferDetails));
            return true;
        }
    }

    /// @notice Returns the id of a liquidity position
    function _biDirectionalID(
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike,
        uint8 spread
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                ILRTADataID(
                    Engine.OrderType.BiDirectional,
                    abi.encode(BiDirectionalID(token0, token1, scalingFactor, strike, spread))
                )
            )
        );
    }

    /// @notice Returns the id of a debt position
    function _debtID(
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike,
        Engine.TokenSelector selector
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                ILRTADataID(Engine.OrderType.Debt, abi.encode(DebtID(token0, token1, scalingFactor, strike, selector)))
            )
        );
    }

    /// @notice Mint a liquidty position
    function _mintBiDirectional(
        address to,
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike,
        uint8 spread,
        uint128 amount
    )
        internal
    {
        bytes32 id = _biDirectionalID(token0, token1, scalingFactor, strike, spread);
        // change in liquidity cannot exceed the maximum liquidity in a strike
        unchecked {
            _dataOf[to][id].balance += amount;
        }

        emit Transfer(address(0), to, abi.encode(ILRTATransferDetails(id, Engine.OrderType.BiDirectional, amount)));
    }

    /// @notice Mint a debt position
    function _mintDebt(
        address to,
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike,
        Engine.TokenSelector selector,
        uint128 amount,
        uint256 leverageRatioX128
    )
        internal
    {
        bytes32 id = _debtID(token0, token1, scalingFactor, strike, selector);
        uint128 balance = _dataOf[to][id].balance;

        if (balance == 0) {
            _dataOf[to][id].balance = amount;
            _dataOf[to][id].data = abi.encode(DebtData(leverageRatioX128));
        } else {
            DebtData memory debtData = abi.decode(_dataOf[to][id].data, (DebtData));

            _dataOf[to][id].data =
                abi.encode(DebtData(addPositions(amount, balance, DebtData(leverageRatioX128), debtData)));

            unchecked {
                _dataOf[to][id].balance = balance + amount;
            }
        }

        emit Transfer(address(0), to, abi.encode(ILRTATransferDetails(id, Engine.OrderType.Debt, amount)));
    }

    function _burn(address from, bytes32 id, uint128 amount, Engine.OrderType orderType) internal {
        _dataOf[from][id].balance -= amount;

        emit Transfer(from, address(0), abi.encode(ILRTATransferDetails(id, orderType, amount)));
    }
}
