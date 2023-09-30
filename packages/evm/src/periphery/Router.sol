// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";
import {ILRTA} from "ilrta/ILRTA.sol";
import {Permit3} from "ilrta/Permit3.sol";

/// @title Router
/// @notice Facilitates transactions with `Engine`
/// @author Robert Leifke and Kyle Scott
contract Router is IExecuteCallback {
    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 ERRORS
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Thrown when callback is called by an invalid address
    error InvalidCaller(address caller);

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                               DATA TYPES
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @notice Data type for callback
    /// @param payer Address of signer of signature transfers
    /// @param signatureTransfer Permit3 data structure specifying a batch of tranfers
    /// @param signature Signature validations transfers in `signatureTransfer`
    struct CallbackData {
        address payer;
        Permit3.SignatureTransferBatch signatureTransfer;
        bytes signature;
    }

    /// @notice Data type of route parameters
    /// @param to Address to receive the output of the transaction
    /// @param commandInputs Actions to run on `engine`
    /// @param signatureTransfer Permit3 data structure specifying a batch of tranfers
    /// @param signature Signature validations transfers in `signatureTransfer`
    struct RouteParams {
        address to;
        Engine.CommandInput[] commandInputs;
        uint256 numTokens;
        uint256 numLPs;
        Permit3.SignatureTransferBatch signatureTransfer;
        bytes signature;
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                STORAGE
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    Engine public immutable engine;

    Permit3 public immutable permit3;

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                              CONSTRUCTOR
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    constructor(address payable _engine, address _permit3) {
        engine = Engine(_engine);
        permit3 = Permit3(_permit3);
    }

    /*<//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>
                                 LOGIC
    <//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\>*/

    /// @custom:team should we return the account
    function route(RouteParams calldata params) external payable {
        CallbackData memory callbackData = CallbackData(msg.sender, params.signatureTransfer, params.signature);

        engine.execute{value: msg.value}(
            params.to, params.commandInputs, params.numTokens, params.numLPs, abi.encode(callbackData)
        );
    }

    /// @notice Callback called by `engine` that expects payment for actions taken
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

                requestedTransfer[i] =
                    Permit3.RequestedTransferDetails(msg.sender, abi.encode(delta > 0 ? uint256(delta) : uint256(0)));
            }

            // Format position data
            for (; i < account.erc20Data.length + account.lpData.length; i++) {
                requestedTransfer[i] = Permit3.RequestedTransferDetails(
                    msg.sender, abi.encode(account.lpData[i - account.erc20Data.length])
                );
            }

            permit3.transferBySignature(
                callbackData.payer, callbackData.signatureTransfer, requestedTransfer, callbackData.signature
            );
        }
    }
}
