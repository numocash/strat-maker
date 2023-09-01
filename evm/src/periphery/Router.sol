// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";
import {ILRTA} from "ilrta/ILRTA.sol";
import {Permit3} from "ilrta/Permit3.sol";

/// @author Robert Leifke and Kyle Scott
contract Router is IExecuteCallback {
    Engine private immutable engine;
    Permit3 private immutable permit3;

    error InvalidCaller(address caller);

    struct CallbackData {
        address payer;
        Permit3.SignatureTransferBatch signatureTransfer;
        bytes signature;
    }

    constructor(address payable _engine, address _permit3) {
        engine = Engine(_engine);
        permit3 = Permit3(_permit3);
    }

    struct RouteParams {
        address to;
        Engine.CommandInput[] commandInputs;
        uint256 numTokens;
        uint256 numLPs;
        Permit3.SignatureTransferBatch signatureTransfer;
        bytes signature;
    }

    function route(RouteParams calldata params) external payable {
        CallbackData memory callbackData = CallbackData(msg.sender, params.signatureTransfer, params.signature);

        engine.execute{value: msg.value}(
            params.to, params.commandInputs, params.numTokens, params.numLPs, abi.encode(callbackData)
        );
    }

    function executeCallback(Accounts.Account calldata account, bytes calldata data) external {
        unchecked {
            if (msg.sender != address(engine)) revert InvalidCaller(msg.sender);

            CallbackData memory callbackData = abi.decode(data, (CallbackData));

            // build array of transfer requests, then send as a batch
            Permit3.RequestedTransferDetails[] memory requestedTransfer =
                new Permit3.RequestedTransferDetails[](callbackData.signatureTransfer.transferDetails.length);

            uint256 i = 0;

            // Format ERC20 data
            for (; i < account.erc20Data.length; i++) {
                int256 delta = account.erc20Data[i].balanceDelta;

                if (delta > 0) {
                    requestedTransfer[i] = Permit3.RequestedTransferDetails(msg.sender, abi.encode(uint256(delta)));
                }
            }

            // Format position data
            for (; i < account.lpData.length + account.erc20Data.length; i++) {
                requestedTransfer[i] = Permit3.RequestedTransferDetails(msg.sender, abi.encode(account.lpData[i]));
            }

            permit3.transferBySignature(
                callbackData.payer, callbackData.signatureTransfer, requestedTransfer, callbackData.signature
            );
        }
    }
}
