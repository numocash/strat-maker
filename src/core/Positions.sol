// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {ILRTA} from "ilrta/ILRTA.sol";
import {Engine} from "./Engine.sol";

abstract contract Positions is ILRTA {
    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               DATA TYPES
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    enum OrderType {
        BiDirectional,
        Limit,
        Debt
    }

    struct BiDirectionalID {
        address token0;
        address token1;
        int24 strike;
        uint8 spread;
    }

    struct LimitID {
        address token0;
        address token1;
        int24 strike;
        bool zeroToOne;
        uint256 liquidityGrowthLast;
    }

    struct DebtID {
        address token0;
        address token1;
        int24 strike;
        Engine.TokenSelector selector;
    }

    struct DebtData {
        uint256 liquidityGrowthLast;
        uint256 leverageRatioX128;
    }

    struct DebtTransferDetails {
        address token0;
        address token1;
        int24 strike;
    }

    struct ILRTADataID {
        OrderType orderType;
        bytes data;
    }

    struct ILRTAData {
        uint256 balance;
        OrderType orderType;
        bytes data;
    }

    struct ILRTATransferDetails {
        bytes32 id;
        uint256 amount;
        OrderType orderType;
        bytes data;
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                STORAGE
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    mapping(address => mapping(bytes32 => ILRTAData)) internal _dataOf;

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                              CONSTRUCTOR
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    constructor(address _superSignature)
        ILRTA(_superSignature, "Numoen Dry Powder", "DP", "TransferDetails(bytes32 id,uint256 amount)")
    {}

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    function dataID(bytes memory dataIDBytes) public pure override returns (bytes32) {
        return keccak256(dataIDBytes);
    }

    function dataOf(address owner, bytes32 id) external view override returns (bytes memory) {
        return abi.encode(_dataOf[owner][id]);
    }

    function transfer(address to, bytes calldata transferDetailsBytes) external override returns (bool) {
        ILRTATransferDetails memory transferDetails = abi.decode(transferDetailsBytes, (ILRTATransferDetails));
        return _transfer(msg.sender, to, transferDetails);
    }

    function transferBySignature(
        address from,
        SignatureTransfer calldata signatureTransfer,
        RequestedTransfer calldata requestedTransfer,
        bytes calldata signature
    )
        external
        override
        returns (bool)
    {
        ILRTATransferDetails memory transferDetails =
            abi.decode(requestedTransfer.transferDetails, (ILRTATransferDetails));
        ILRTATransferDetails memory signatureTransferDetails =
            abi.decode(signatureTransfer.transferDetails, (ILRTATransferDetails));

        _checkTransferRequest(transferDetails, signatureTransferDetails);

        verifySignature(from, signatureTransfer, signature);

        return _transfer(from, requestedTransfer.to, transferDetails);
    }

    function transferBySuperSignature(
        address from,
        bytes calldata transferDetails,
        RequestedTransfer calldata requestedTransfer,
        bytes32[] calldata dataHash
    )
        external
        override
        returns (bool)
    {
        ILRTATransferDetails memory requestedTransferDetails =
            abi.decode(requestedTransfer.transferDetails, (ILRTATransferDetails));
        ILRTATransferDetails memory signatureTransferDetails = abi.decode(transferDetails, (ILRTATransferDetails));

        _checkTransferRequest(requestedTransferDetails, signatureTransferDetails);

        verifySuperSignature(from, transferDetails, dataHash);

        return _transfer(from, requestedTransfer.to, requestedTransferDetails);
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                             INTERNAL LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    function _checkTransferRequest(
        ILRTATransferDetails memory requestedTransferDetails,
        ILRTATransferDetails memory signatureTransferDetails
    )
        private
    {
        if (
            requestedTransferDetails.amount > signatureTransferDetails.amount
                || requestedTransferDetails.id != signatureTransferDetails.id
        ) {
            revert InvalidRequest(abi.encode(signatureTransferDetails));
        }
    }

    function _transfer(address from, address to, ILRTATransferDetails memory transferDetails) private returns (bool) {
        if (transferDetails.orderType != OrderType.Debt) {
            _dataOf[from][transferDetails.id].balance -= transferDetails.amount;
            unchecked {
                _dataOf[to][transferDetails.id].balance += transferDetails.amount;
            }

            emit Transfer(from, to, abi.encode(transferDetails));
            return true;
        } else {
            // TODO: accrue interest to sender and receiver
            _dataOf[from][transferDetails.id].balance -= transferDetails.amount;
            unchecked {
                _dataOf[to][transferDetails.id].balance += transferDetails.amount;
            }

            emit Transfer(from, to, abi.encode(transferDetails));
            return true;
        }
    }

    function _mint(address to, bytes32 id, uint256 amount, OrderType orderType, bytes memory data) internal virtual {
        // change in liquidity cannot exceed the maximum liquidity in a strike
        unchecked {
            _dataOf[to][id].balance += amount;
        }

        emit Transfer(address(0), to, abi.encode(ILRTATransferDetails(id, amount, orderType, data)));
    }

    function _burn(address from, bytes32 id, uint256 amount, OrderType orderType, bytes memory data) internal virtual {
        _dataOf[from][id].balance -= amount;

        emit Transfer(from, address(0), abi.encode(ILRTATransferDetails(id, amount, orderType, data)));
    }
}
