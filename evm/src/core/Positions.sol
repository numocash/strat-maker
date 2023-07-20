// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Engine} from "./Engine.sol";
import {addPositions} from "./math/PositionMath.sol";
import {ILRTA} from "ilrta/ILRTA.sol";
import {SignatureVerification} from "ilrta/SignatureVerification.sol";

abstract contract Positions is ILRTA {
    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               DATA TYPES
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    struct BiDirectionalID {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        uint8 spread;
    }

    // struct LimitID {
    //     address token0;
    //     address token1;
    //     int24 strike;
    //     bool zeroToOne;
    //     uint256 liquidityGrowthLast;
    // }

    struct DebtID {
        address token0;
        address token1;
        uint8 scalingFactor;
        int24 strike;
        Engine.TokenSelector selector;
    }

    struct DebtData {
        uint256 leverageRatioX128;
    }

    struct ILRTADataID {
        Engine.OrderType orderType;
        bytes data;
    }

    struct ILRTAData {
        uint256 balance;
        Engine.OrderType orderType;
        bytes data;
    }

    struct ILRTATransferDetails {
        bytes32 id;
        Engine.OrderType orderType;
        uint256 amount;
    }

    struct SignatureTransfer {
        uint256 nonce;
        uint256 deadline;
        ILRTATransferDetails transferDetails;
    }

    struct RequestedTransfer {
        address to;
        ILRTATransferDetails transferDetails;
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                STORAGE
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    mapping(address => mapping(bytes32 => ILRTAData)) internal _dataOf;

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                              CONSTRUCTOR
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    constructor(address _superSignature)
        ILRTA(_superSignature, "Numoen Dry Powder", "DP", "TransferDetails(bytes32 id,uint8 orderType,uint256 amount)")
    {}

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    function dataID(ILRTADataID memory data) public pure returns (bytes32) {
        return keccak256(abi.encode(data));
    }

    function dataOf(address owner, bytes32 id) external view returns (ILRTAData memory) {
        return _dataOf[owner][id];
    }

    function transfer(address to, bytes calldata transferDetailsBytes) external returns (bool) {
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
        returns (bool)
    {
        _checkTransferRequest(requestedTransfer.transferDetails, signatureTransfer.transferDetails);

        _verifySignature(from, signatureTransfer, signature);

        return _transfer(from, requestedTransfer.to, requestedTransfer.transferDetails);
    }

    function transferBySuperSignature(
        address from,
        ILRTATransferDetails calldata transferDetails,
        RequestedTransfer calldata requestedTransfer,
        bytes32[] calldata dataHash
    )
        external
        returns (bool)
    {
        _checkTransferRequest(requestedTransfer.transferDetails, transferDetails);

        _verifySuperSignature(from, transferDetails, dataHash);

        return _transfer(from, requestedTransfer.to, requestedTransfer.transferDetails);
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                             INTERNAL LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    function _verifySignature(
        address from,
        SignatureTransfer calldata signatureTransfer,
        bytes calldata signature
    )
        private
    {
        if (block.timestamp > signatureTransfer.deadline) revert SignatureExpired(signatureTransfer.deadline);

        useUnorderedNonce(from, signatureTransfer.nonce);

        bytes32 signatureHash = hashTypedData(
            keccak256(
                abi.encode(
                    TRANSFER_TYPEHASH,
                    keccak256(abi.encode(TRANSFER_DETAILS_TYPEHASH, signatureTransfer.transferDetails)),
                    msg.sender,
                    signatureTransfer.nonce,
                    signatureTransfer.deadline
                )
            )
        );

        SignatureVerification.verify(signature, signatureHash, from);
    }

    function _verifySuperSignature(
        address from,
        ILRTATransferDetails calldata transferDetails,
        bytes32[] calldata dataHash
    )
        private
    {
        bytes32 signatureHash = hashTypedData(
            keccak256(
                abi.encode(
                    SUPER_SIGNATURE_TRANSFER_TYPEHASH,
                    keccak256(abi.encode(TRANSFER_DETAILS_TYPEHASH, transferDetails)),
                    msg.sender
                )
            )
        );

        if (dataHash[0] != signatureHash) revert DataHashMismatch();

        superSignature.verifyData(from, dataHash);
    }

    function _checkTransferRequest(
        ILRTATransferDetails memory requestedTransferDetails,
        ILRTATransferDetails memory signatureTransferDetails
    )
        private
        pure
    {
        if (
            requestedTransferDetails.amount > signatureTransferDetails.amount
                || requestedTransferDetails.id != signatureTransferDetails.id
        ) {
            revert InvalidRequest(abi.encode(signatureTransferDetails));
        }
    }

    function _transfer(address from, address to, ILRTATransferDetails memory transferDetails) private returns (bool) {
        if (transferDetails.orderType != Engine.OrderType.Debt) {
            _dataOf[from][transferDetails.id].balance -= transferDetails.amount;
            unchecked {
                _dataOf[to][transferDetails.id].balance += transferDetails.amount;
            }

            emit Transfer(from, to, abi.encode(transferDetails));
            return true;
        } else {
            uint256 senderBalance = _dataOf[from][transferDetails.id].balance;
            uint256 recipientBalance = _dataOf[to][transferDetails.id].balance;

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
        return dataID(
            ILRTADataID(
                Engine.OrderType.BiDirectional,
                abi.encode(BiDirectionalID(token0, token1, scalingFactor, strike, spread))
            )
        );
    }

    // function _limitID(
    //     address token0,
    //     address token1,
    //     int24 strike,
    //     bool zeroToOne,
    //     uint256 liquidityGrowthLast
    // )
    //     internal
    //     pure
    //     returns (bytes32)
    // {
    //     return dataID(
    //         abi.encode(
    //             ILRTADataID(
    //                 Engine.OrderType.Limit, abi.encode(LimitID(token0, token1, strike, zeroToOne,
    // liquidityGrowthLast))
    //             )
    //         )
    //     );
    // }

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
        return dataID(
            ILRTADataID(Engine.OrderType.Debt, abi.encode(DebtID(token0, token1, scalingFactor, strike, selector)))
        );
    }

    function _dataOfDebt(
        address owner,
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike,
        Engine.TokenSelector selector
    )
        internal
        view
        returns (DebtData memory)
    {
        ILRTAData memory data = _dataOf[owner][_debtID(token0, token1, scalingFactor, strike, selector)];
        return abi.decode(data.data, (DebtData));
    }

    function _mintBiDirectional(
        address to,
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike,
        uint8 spread,
        uint256 amount
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

    // function _mintLimit(
    //     address to,
    //     address token0,
    //     address token1,
    //     int24 strike,
    //     bool zeroToOne,
    //     uint256 liquidityGrowthLast,
    //     uint256 amount
    // )
    //     internal
    // {
    //     bytes32 id = _limitID(token0, token1, strike, zeroToOne, liquidityGrowthLast);

    //     unchecked {
    //         _dataOf[to][id].balance += amount;
    //     }

    //     emit Transfer(address(0), to, abi.encode(ILRTATransferDetails(id, amount, Engine.OrderType.Limit)));
    // }

    function _mintDebt(
        address to,
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike,
        Engine.TokenSelector selector,
        uint256 amount,
        uint256 leverageRatioX128
    )
        internal
    {
        bytes32 id = _debtID(token0, token1, scalingFactor, strike, selector);
        uint256 balance = _dataOf[to][id].balance;

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

    function _burnBiDirectional(
        address from,
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike,
        uint8 spread,
        uint256 amount
    )
        internal
    {
        bytes32 id = _biDirectionalID(token0, token1, scalingFactor, strike, spread);

        _dataOf[from][id].balance -= amount;

        emit Transfer(from, address(0), abi.encode(ILRTATransferDetails(id, Engine.OrderType.BiDirectional, amount)));
    }

    function _burn(address from, bytes32 id, uint256 amount, Engine.OrderType orderType) internal {
        _dataOf[from][id].balance -= amount;

        emit Transfer(from, address(0), abi.encode(ILRTATransferDetails(id, orderType, amount)));
    }

    // function _burnLimit(
    //     address from,
    //     address token0,
    //     address token1,
    //     int24 strike,
    //     bool zeroToOne,
    //     uint256 liquidityGrowthLast,
    //     uint256 amount
    // )
    //     internal
    // {
    //     bytes32 id = _limitID(token0, token1, strike, zeroToOne, liquidityGrowthLast);

    //     _dataOf[from][id].balance -= amount;

    //     emit Transfer(from, address(0), abi.encode(ILRTATransferDetails(id, amount, Engine.OrderType.Limit)));
    // }

    function _burnDebt(
        address from,
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike,
        Engine.TokenSelector selector,
        uint256 amount
    )
        internal
    {
        bytes32 id = _debtID(token0, token1, scalingFactor, strike, selector);

        uint256 balance = _dataOf[from][id].balance;

        if (balance == amount) delete _dataOf[from][id];
        else _dataOf[from][id].balance = balance - amount;

        emit Transfer(from, address(0), abi.encode(ILRTATransferDetails(id, Engine.OrderType.Debt, amount)));
    }
}
