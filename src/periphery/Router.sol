// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Engine} from "src/core/Engine.sol";
import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";
import {Permit2} from "permit2/src/Permit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

contract Router is IExecuteCallback {
    Engine private immutable engine;
    Permit2 private immutable permit2;

    error InvalidCaller(address caller);

    struct CallbackData {
        ISignatureTransfer.PermitBatchTransferFrom batchPermit;
        bytes permitSignature;
        address payer;
    }

    constructor(address _engine, address _permit2) {
        engine = Engine(_engine);
        permit2 = Permit2(_permit2);
    }

    function execute(
        Engine.Commands[] calldata commands,
        bytes[] calldata inputs,
        address to,
        uint256 numTokens,
        uint256 numILRTA,
        ISignatureTransfer.PermitBatchTransferFrom calldata batchPermit,
        bytes calldata permitSignature
    )
        external
    {
        return engine.execute(
            commands,
            inputs,
            to,
            numTokens,
            numILRTA,
            abi.encode(CallbackData(batchPermit, permitSignature, msg.sender))
        );
    }

    function executeCallback(
        address[] calldata,
        int256[] calldata tokensDelta,
        bytes32[] calldata,
        int256[] calldata,
        bytes calldata data
    )
        external
    {
        if (msg.sender != address(engine)) revert InvalidCaller(msg.sender);

        CallbackData memory callbackData = abi.decode(data, (CallbackData));

        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails =
            new ISignatureTransfer.SignatureTransferDetails[](callbackData.batchPermit.permitted.length);

        uint256 j = 0;
        for (uint256 i = 0; i < tokensDelta.length;) {
            int256 delta = tokensDelta[i];

            if (delta > 0) {
                transferDetails[j] = ISignatureTransfer.SignatureTransferDetails(msg.sender, uint256(delta));

                unchecked {
                    j++;
                }
            }

            unchecked {
                i++;
            }
        }

        permit2.permitTransferFrom(
            callbackData.batchPermit, transferDetails, callbackData.payer, callbackData.permitSignature
        );

        // for (uint256 i = 0; i < ids.length;) {
        //     int256 delta = ilrtaDeltas[i];

        //     if (delta > 0) {
        //         bytes32 id = ids[i];

        //         if (ids[i] != bytes32(0)) {
        //             engine.transfer(msg.sender, abi.encode(Positions.ILRTATransferDetails(id, uint256(delta))));
        //         }
        //     }

        //     unchecked {
        //         i++;
        //     }
        // }
    }
}
