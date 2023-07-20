// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Engine} from "src/core/Engine.sol";
import {Positions} from "src/core/Positions.sol";
import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";
import {ILRTA} from "ilrta/ILRTA.sol";
import {Permit3} from "ilrta/Permit3.sol";
import {SuperSignature} from "ilrta/SuperSignature.sol";

/// @author Robert Leifke and Kyle Scott
/// @custom:team route by signature
contract Router is IExecuteCallback {
    Engine private immutable engine;
    Permit3 private immutable permit3;

    error InvalidCaller(address caller);

    struct CallbackData {
        Permit3.TransferDetails[] permitTransfers;
        Positions.ILRTATransferDetails[] positionTransfers;
        bytes32[] dataHash;
        address payer;
    }

    constructor(address _engine, address _permit3) {
        engine = Engine(_engine);
        permit3 = Permit3(_permit3);
    }

    struct RouteParams {
        address to;
        Engine.Commands[] commands;
        bytes[] inputs;
        uint256 numTokens;
        uint256 numLPs;
        Permit3.TransferDetails[] permitTransfers;
        Positions.ILRTATransferDetails[] positionTransfers;
        SuperSignature.Verify verify;
        bytes signature;
    }

    function route(RouteParams calldata params) external {
        permit3.verifyAndStoreRoot(msg.sender, params.verify, params.signature);

        CallbackData memory callbackData =
            CallbackData(params.permitTransfers, params.positionTransfers, params.verify.dataHash, msg.sender);

        return engine.execute(
            params.to, params.commands, params.inputs, params.numTokens, params.numLPs, abi.encode(callbackData)
        );
    }

    function executeCallback(IExecuteCallback.CallbackParams calldata params) external {
        if (msg.sender != address(engine)) revert InvalidCaller(msg.sender);
        CallbackData memory callbackData = abi.decode(params.data, (CallbackData));

        // send all liquidity positions individually
        uint256 j = 0;
        for (uint256 i = 0; i < params.lpIDs.length;) {
            uint128 delta = params.lpDeltas[i];
            bytes32 id = params.lpIDs[i];
            if (delta > 0 && id != bytes32(0)) {
                engine.transferBySuperSignature(
                    callbackData.payer,
                    callbackData.positionTransfers[j],
                    Positions.RequestedTransfer(
                        msg.sender, Positions.ILRTATransferDetails(id, params.orderTypes[i], delta)
                    ),
                    callbackData.dataHash
                );

                unchecked {
                    j++;
                }
            }

            unchecked {
                i++;
            }
        }

        // build array of transfer requests, then send as a batch
        bytes32[] memory permitDataHash = new bytes32[](1);
        if (callbackData.dataHash.length > 0) {
            permitDataHash[0] = callbackData.dataHash[callbackData.dataHash.length - 1];
        }

        Permit3.RequestedTransferDetails[] memory requestedTransfer =
            new Permit3.RequestedTransferDetails[](callbackData.permitTransfers.length);

        j = 0;
        for (uint256 i = 0; i < params.tokensDelta.length;) {
            int256 delta = params.tokensDelta[i];

            if (delta > 0 && params.tokens[i] != address(0)) {
                requestedTransfer[j] = Permit3.RequestedTransferDetails(msg.sender, uint256(delta));

                unchecked {
                    j++;
                }
            }

            unchecked {
                i++;
            }
        }

        if (callbackData.permitTransfers.length > 0) {
            permit3.transferBySuperSignature(
                callbackData.payer, callbackData.permitTransfers, requestedTransfer, permitDataHash
            );
        }
    }
}
