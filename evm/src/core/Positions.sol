// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Engine} from "./Engine.sol";
import {ILRTA} from "ilrta/ILRTA.sol";

/// @notice Returns the id of a liquidity position
function biDirectionalID(
    address token0,
    address token1,
    uint8 scalingFactor,
    int24 strike,
    uint8 spread
)
    pure
    returns (bytes32)
{
    return keccak256(
        abi.encode(
            Positions.ILRTADataID(
                Engine.OrderType.BiDirectional,
                abi.encode(Positions.BiDirectionalID(token0, token1, scalingFactor, strike, spread))
            )
        )
    );
}

/// @notice Returns the id of a debt position
function debtID(
    address token0,
    address token1,
    uint8 scalingFactor,
    int24 strike,
    Engine.TokenSelector selector
)
    pure
    returns (bytes32)
{
    return keccak256(
        abi.encode(
            Positions.ILRTADataID(
                Engine.OrderType.Debt, abi.encode(Positions.DebtID(token0, token1, scalingFactor, strike, selector))
            )
        )
    );
}

/// @title Positions
/// @notice Representation of a position on the exchange
/// @author Robert Leifke and Kyle Scott
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
    /// @param balance The balance of the position either in units of share of liquidity provided or non-interested
    /// adjusted liquidity debt
    /// @param liquidityBuffer The amount of non-fee adjusted liquidity collateral - liquidity debt when order type is
    /// debt, else 0
    struct ILRTAData {
        uint128 balance;
        uint128 liquidityBuffer;
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
        uint128 fromBalance = _dataOf[from][transferDetails.id].balance;

        _dataOf[from][transferDetails.id].balance = fromBalance - transferDetails.amount;
        unchecked {
            _dataOf[to][transferDetails.id].balance += transferDetails.amount;
        }

        if (transferDetails.orderType == Engine.OrderType.Debt) {
            // transfer a proportional amount of the liquidity buffer
            uint128 liquidityBufferTransfer;
            uint128 fromLiquidityBuffer = _dataOf[from][transferDetails.id].liquidityBuffer;
            unchecked {
                liquidityBufferTransfer =
                    uint128((uint256(fromLiquidityBuffer) * uint256(transferDetails.amount)) / uint256(fromBalance));
                _dataOf[from][transferDetails.id].liquidityBuffer = fromLiquidityBuffer - liquidityBufferTransfer;
            }
            _dataOf[to][transferDetails.id].liquidityBuffer += liquidityBufferTransfer;
        }

        emit Transfer(from, to, abi.encode(transferDetails));
        return true;
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
        bytes32 id = biDirectionalID(token0, token1, scalingFactor, strike, spread);
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
        uint128 liquidityBuffer
    )
        internal
    {
        bytes32 id = debtID(token0, token1, scalingFactor, strike, selector);
        uint128 balance = _dataOf[to][id].balance;

        if (balance == 0) {
            _dataOf[to][id].balance = amount;
            _dataOf[to][id].liquidityBuffer = liquidityBuffer;
        } else {
            unchecked {
                _dataOf[to][id].balance = balance + amount;
                _dataOf[to][id].liquidityBuffer += liquidityBuffer;
            }
        }

        emit Transfer(address(0), to, abi.encode(ILRTATransferDetails(id, Engine.OrderType.Debt, amount)));
    }

    /// @custom:team How to handle `liquidityBuffer`
    function _burn(address from, bytes32 id, uint128 amount, Engine.OrderType orderType) internal {
        _dataOf[from][id].balance -= amount;

        emit Transfer(from, address(0), abi.encode(ILRTATransferDetails(id, orderType, amount)));
    }
}
