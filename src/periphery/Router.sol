// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

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
        address[] calldata tokens,
        int256[] calldata tokensDelta,
        bytes32[] calldata ids,
        int256[] calldata ilrtaDeltas,
        bytes calldata data
    )
        external
    {
        if (msg.sender != address(engine)) revert InvalidCaller(msg.sender);

        CallbackData memory data = abi.decode(data, (CallbackData));

        SignatureTransferDetails[] memory transferDetails =
            new SignatureTransferDetails[](data.batchPermit.permitted.length);
        for (uint256 i = 0; i < tokens.length;) {
            int256 delta = tokensDelta[i];

            if (delta > 0) {
                address token = tokens[i];

                if (token == address(token0)) {
                    token0.mint(msg.sender, uint256(delta));
                } else if (token == address(token1)) {
                    token1.mint(msg.sender, uint256(delta));
                }
            }

            unchecked {
                i++;
            }
        }

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
