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
        uint256 liquidityGrowthX128Last;
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

    function _biDirectionalID(
        address token0,
        address token1,
        int24 strike,
        uint8 spread
    )
        internal
        pure
        returns (bytes32)
    {
        return dataID(
            abi.encode(
                ILRTADataID(OrderType.BiDirectional, abi.encode(BiDirectionalID(token0, token1, strike, spread)))
            )
        );
    }

    function _limitID(
        address token0,
        address token1,
        int24 strike,
        bool zeroToOne,
        uint256 liquidityGrowthLast
    )
        internal
        pure
        returns (bytes32)
    {
        return dataID(
            abi.encode(
                ILRTADataID(
                    OrderType.Limit, abi.encode(LimitID(token0, token1, strike, zeroToOne, liquidityGrowthLast))
                )
            )
        );
    }

    function _debtID(
        address token0,
        address token1,
        int24 strike,
        Engine.TokenSelector selector
    )
        internal
        pure
        returns (bytes32)
    {
        return dataID(abi.encode(ILRTADataID(OrderType.Debt, abi.encode(DebtID(token0, token1, strike, selector)))));
    }

    function _biDirectionalDataOf(
        address owner,
        address token0,
        address token1,
        int24 strike,
        uint8 spread
    )
        internal
        view
        returns (uint256 balance)
    {
        return _dataOf[owner][_biDirectionalID(token0, token1, strike, spread)].balance;
    }

    function _limitDataOf(
        address owner,
        address token0,
        address token1,
        int24 strike,
        bool zeroToOne,
        uint256 liquidityGrowthLast
    )
        internal
        view
        returns (uint256 balance)
    {
        return _dataOf[owner][_limitID(token0, token1, strike, zeroToOne, liquidityGrowthLast)].balance;
    }

    function _debtDataOf(
        address owner,
        address token0,
        address token1,
        int24 strike,
        Engine.TokenSelector selector
    )
        internal
        view
        returns (uint256 balance, uint256 liquidityGrowthX128Last, uint256 leverageRatioX128)
    {
        ILRTAData memory data = _dataOf[owner][_debtID(token0, token1, strike, selector)];
        DebtData memory debtData = abi.decode(data.data, (DebtData));

        return (data.balance, debtData.liquidityGrowthX128Last, debtData.leverageRatioX128);
    }

    function _mintBiDirectional(
        address to,
        address token0,
        address token1,
        int24 strike,
        uint8 spread,
        uint256 amount
    )
        internal
    {
        bytes32 id = _biDirectionalID(token0, token1, strike, spread);
        // change in liquidity cannot exceed the maximum liquidity in a strike
        unchecked {
            _dataOf[to][id].balance += amount;
        }

        emit Transfer(address(0), to, abi.encode(ILRTATransferDetails(id, amount, OrderType.BiDirectional, bytes(""))));
    }

    function _mintLimit(
        address to,
        address token0,
        address token1,
        int24 strike,
        bool zeroToOne,
        uint256 liquidityGrowthLast,
        uint256 amount
    )
        internal
    {
        bytes32 id = _limitID(token0, token1, strike, zeroToOne, liquidityGrowthLast);

        unchecked {
            _dataOf[to][id].balance += amount;
        }

        emit Transfer(address(0), to, abi.encode(ILRTATransferDetails(id, amount, OrderType.Limit, bytes(""))));
    }

    function _mintDebt(
        address to,
        address token0,
        address token1,
        int24 strike,
        Engine.TokenSelector selector,
        uint256 amount,
        uint256 liquidityGrowthX128Last,
        uint256 leverageRatioX128
    )
        internal
    {
        bytes32 id = _debtID(token0, token1, strike, selector);

        unchecked {
            _dataOf[to][id].balance += amount;
        }

        emit Transfer(
            address(0),
            to,
            abi.encode(
                ILRTATransferDetails(
                    id, amount, OrderType.Limit, abi.encode(DebtData(liquidityGrowthX128Last, leverageRatioX128))
                )
            )
        );
    }

    function _burnBiDirectional(
        address from,
        address token0,
        address token1,
        int24 strike,
        uint8 spread,
        uint256 amount
    )
        internal
    {
        bytes32 id = _biDirectionalID(token0, token1, strike, spread);

        _dataOf[from][id].balance -= amount;

        emit Transfer(
            from, address(0), abi.encode(ILRTATransferDetails(id, amount, OrderType.BiDirectional, bytes("")))
        );
    }

    function _burn(address from, bytes32 id, uint256 amount, OrderType orderType, bytes memory data) internal {
        _dataOf[from][id].balance -= amount;

        emit Transfer(from, address(0), abi.encode(ILRTATransferDetails(id, amount, orderType, data)));
    }

    function _burnLimit(
        address from,
        address token0,
        address token1,
        int24 strike,
        bool zeroToOne,
        uint256 liquidityGrowthLast,
        uint256 amount
    )
        internal
    {
        bytes32 id = _limitID(token0, token1, strike, zeroToOne, liquidityGrowthLast);

        _dataOf[from][id].balance -= amount;

        emit Transfer(from, address(0), abi.encode(ILRTATransferDetails(id, amount, OrderType.Limit, bytes(""))));
    }

    function _burnDebt(
        address from,
        address token0,
        address token1,
        int24 strike,
        Engine.TokenSelector selector,
        uint256 amount,
        uint256 liquidityGrowthX128Last,
        uint256 leverageRatioX128
    )
        internal
    {
        bytes32 id = _debtID(token0, token1, strike, selector);

        _dataOf[from][id].balance -= amount;

        emit Transfer(
            from,
            address(0),
            abi.encode(
                ILRTATransferDetails(
                    id, amount, OrderType.Limit, abi.encode(DebtData(liquidityGrowthX128Last, leverageRatioX128))
                )
            )
        );
    }
}
