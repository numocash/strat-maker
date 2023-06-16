// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Engine} from "src/core/Engine.sol";
import {Positions} from "src/core/Positions.sol";
import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";
import {Permit2} from "permit2/src/Permit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ILRTA} from "ilrta/ILRTA.sol";

contract Router is IExecuteCallback {
    Engine private immutable engine;
    Permit2 private immutable permit2;

    error InvalidCaller(address caller);

    struct CallbackData {
        ISignatureTransfer.PermitBatchTransferFrom batchPermit;
        ILRTA.SignatureTransfer[] ilrtaSignatureTransfers;
        bytes permitSignature;
        bytes[] ilrtaSignatures;
        address payer;
    }

    constructor(address _engine, address _permit2) {
        engine = Engine(_engine);
        permit2 = Permit2(_permit2);
    }

    function execute(
        address to,
        Engine.Commands[] calldata commands,
        bytes[] calldata inputs,
        uint256 numTokens,
        uint256 numILRTA,
        ISignatureTransfer.PermitBatchTransferFrom calldata batchPermit,
        ILRTA.SignatureTransfer[] calldata signatureTransfers,
        bytes calldata permitSignature,
        bytes[] calldata ilrtaSignatures
    )
        external
    {
        return engine.execute(
            to,
            commands,
            inputs,
            numTokens,
            numILRTA,
            abi.encode(CallbackData(batchPermit, signatureTransfers, permitSignature, ilrtaSignatures, msg.sender))
        );
    }

    function executeCallback(
        address[] calldata tokens,
        int256[] calldata tokensDelta,
        bytes32[] calldata ids,
        int256[] calldata ilrtaDeltas,
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

            if (delta > 0 && tokens[i] != address(0)) {
                transferDetails[j] = ISignatureTransfer.SignatureTransferDetails(msg.sender, uint256(delta));

                unchecked {
                    j++;
                }
            }

            unchecked {
                i++;
            }
        }

        if (callbackData.batchPermit.permitted.length > 0) {
            permit2.permitTransferFrom(
                callbackData.batchPermit, transferDetails, callbackData.payer, callbackData.permitSignature
            );
        }

        j = 0;
        for (uint256 i = 0; i < ilrtaDeltas.length;) {
            int256 delta = ilrtaDeltas[i];
            bytes32 id = ids[i];

            if (delta > 0 && id != bytes32(0)) {
                engine.transferBySignature(
                    callbackData.payer,
                    callbackData.ilrtaSignatureTransfers[j],
                    ILRTA.RequestedTransfer(msg.sender, abi.encode(Positions.ILRTATransferDetails(id, uint256(delta)))),
                    callbackData.ilrtaSignatures[j]
                );

                unchecked {
                    j++;
                }
            }

            unchecked {
                i++;
            }
        }
    }
}
