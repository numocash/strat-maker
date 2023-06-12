// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {EIP712} from "ilrta/EIP712.sol";
import {ILRTA} from "ilrta/ILRTA.sol";

abstract contract Positions2 is EIP712, ILRTA {
    string public constant name = "Yikes";
    string public constant symbol = "YIKES";

    mapping(bytes32 => ILRTAData data) public _dataOf;

    constructor()
        ILRTA("TransferDetails(address token0,address token1,int24 tick,uint8 tier,uint256 amount)")
        EIP712(keccak256(bytes(name)))
    {}

    struct ILRTADataID {
        address token0;
        address token1;
        int24 tick;
        uint8 tier;
    }

    struct ILRTAData {
        uint256 liquidity;
    }

    struct ILRTATransferDetails {
        bytes idBytes;
        uint256 amount;
    }

    // how to go from address + dataID to data

    function dataID(address owner, bytes memory dataIDBytes) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, dataIDBytes));
    }

    function dataOf(bytes32 id) external view override returns (bytes memory) {
        return abi.encode(_dataOf[id]);
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
        if (
            abi.decode(requestedTransfer.transferDetails, (ILRTATransferDetails)).amount
                > abi.decode(signatureTransfer.transferDetails, (ILRTATransferDetails)).amount
        ) {
            revert InvalidRequest(abi.encode(signatureTransfer.transferDetails));
        }

        verifySignature(from, signatureTransfer, signature);

        return
        /* solhint-disable-next-line max-line-length */
        _transfer(from, requestedTransfer.to, abi.decode(requestedTransfer.transferDetails, (ILRTATransferDetails)));
    }

    function _transfer(address from, address to, ILRTATransferDetails memory transferDetails) internal returns (bool) {
        _dataOf[dataID(from, transferDetails.idBytes)].liquidity -= transferDetails.amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            _dataOf[dataID(from, transferDetails.idBytes)].liquidity += transferDetails.amount;
        }

        emit Transfer(from, to, abi.encode(transferDetails));

        return true;
    }

    function _mint(address to, bytes memory id, uint256 amount) internal virtual {
        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            _dataOf[dataID(to, id)].liquidity += amount;
        }

        emit Transfer(address(0), to, abi.encode(ILRTATransferDetails({amount: amount, idBytes: id})));
    }

    function _burn(address from, bytes memory id, uint256 amount) internal virtual {
        _dataOf[dataID(from, id)].liquidity -= amount;

        emit Transfer(from, address(0), abi.encode(ILRTATransferDetails({amount: amount, idBytes: id})));
    }
}
