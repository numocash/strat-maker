// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Pairs} from "./Pairs.sol";
import {mulDiv} from "./math/FullMath.sol";
import {getRatioAtStrike, Q128} from "./math/strikeMath.sol";
import {ILRTA} from "ilrta/ILRTA.sol";

abstract contract Positions is ILRTA {
    mapping(address => mapping(bytes32 => ILRTAData)) internal _dataOf;

    constructor(address _superSignature)
        ILRTA(
            _superSignature,
            "Yikes",
            "YIKES",
            "TransferDetails(address token0,address token1,int24 strike,uint8 spread,uint256 amount)"
        )
    {}

    enum OrderType {
        BiDirectional,
        ZeroToOne,
        OneToZero
    }

    struct ILRTADataID {
        address token0;
        address token1;
        OrderType orderType;
        int24 strike;
        uint8 spread;
    }

    struct ILRTAData {
        uint256 liquidity;
        uint256 liquidity0InPerLiquidityLast; //Q128.128
        uint256 liquidity1InPerLiquidityLast; // Q128.128
        uint256 token0Owed;
        uint256 token1Owed;
    }

    struct ILRTATransferDetails {
        bytes32 id;
        uint256 amount;
    }

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

        if (
            transferDetails.amount > signatureTransferDetails.amount
                || transferDetails.id != signatureTransferDetails.id
        ) {
            revert InvalidRequest(abi.encode(signatureTransfer.transferDetails));
        }

        verifySignature(from, signatureTransfer, signature);

        return
        /* solhint-disable-next-line max-line-length */
        _transfer(from, requestedTransfer.to, abi.decode(requestedTransfer.transferDetails, (ILRTATransferDetails)));
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

        if (
            requestedTransferDetails.amount > signatureTransferDetails.amount
                || requestedTransferDetails.id != signatureTransferDetails.id
        ) {
            revert InvalidRequest(abi.encode(requestedTransferDetails));
        }

        verifySuperSignature(from, transferDetails, dataHash);

        return
        /* solhint-disable-next-line max-line-length */
        _transfer(from, requestedTransfer.to, abi.decode(requestedTransfer.transferDetails, (ILRTATransferDetails)));
    }

    function _transfer(address from, address to, ILRTATransferDetails memory transferDetails) private returns (bool) {
        _dataOf[from][transferDetails.id].liquidity -= transferDetails.amount;

        // change in liquidity cannot exceed the maximum liquidity in a strike
        unchecked {
            _dataOf[to][transferDetails.id].liquidity += transferDetails.amount;
        }

        emit Transfer(from, to, abi.encode(transferDetails));

        return true;
    }

    function _mint(address to, bytes32 id, uint256 amount) internal virtual {
        // change in liquidity cannot exceed the maximum liquidity in a strike
        unchecked {
            _dataOf[to][id].liquidity += amount;
        }

        emit Transfer(address(0), to, abi.encode(ILRTATransferDetails({amount: amount, id: id})));
    }

    function _burn(address from, bytes32 id, uint256 amount) internal virtual {
        _dataOf[from][id].liquidity -= amount;

        emit Transfer(from, address(0), abi.encode(ILRTATransferDetails({amount: amount, id: id})));
    }

    function _getTokensOwed(
        Pairs.Pair storage pair,
        int24 strike,
        uint8 spread,
        Positions.ILRTAData storage position
    )
        internal
        returns (uint256 amount0Owed, uint256 amount1Owed)
    {
        unchecked {
            if (position.liquidity > 0) {
                // solhint-disable-next-line max-line-length
                uint256 liquidity0InPerLiquidityDelta = pair.strikes[strike - int8(spread)].liquidity0InPerLiquidity[spread]
                    - position.liquidity0InPerLiquidityLast;

                // solhint-disable-next-line max-line-length
                uint256 liquidity1InPerLiquidityDelta = pair.strikes[strike + int8(spread)].liquidity1InPerLiquidity[spread]
                    - position.liquidity1InPerLiquidityLast;

                uint256 liquidity0Volume = mulDiv(liquidity0InPerLiquidityDelta, position.liquidity, Q128);
                uint256 liquidity1Volume = mulDiv(liquidity1InPerLiquidityDelta, position.liquidity, Q128);

                uint256 strikePrice = getRatioAtStrike(strike);
                uint256 strikePrice0To1 = getRatioAtStrike(strike - int8(spread));
                uint256 strikePrice1To0 = getRatioAtStrike(strike + int8(spread));

                amount0Owed =
                    mulDiv(liquidity0Volume, Q128, strikePrice0To1) - mulDiv(liquidity0Volume, Q128, strikePrice);
                amount1Owed = liquidity1Volume - mulDiv(liquidity1Volume, strikePrice, strikePrice1To0);

                position.token0Owed += amount0Owed;
                position.token1Owed += amount1Owed;
            }
            // solhint-disable-next-line max-line-length
            position.liquidity0InPerLiquidityLast = pair.strikes[strike - int8(spread)].liquidity0InPerLiquidity[spread];
            // solhint-disable-next-line max-line-length
            position.liquidity1InPerLiquidityLast = pair.strikes[strike + int8(spread)].liquidity1InPerLiquidity[spread];
        }
    }
}
