// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {Permit3} from "ilrta/Permit3.sol";
import {Router} from "src/periphery/Router.sol";

contract ExecuteCallbackTest is Test {
    Router private router;

    function setUp() external {
        router = new Router(payable(address(this)), address(this));
    }

    address private signer;
    Permit3.RequestedTransferDetails[] private requestedTransfer;
    bytes private signature;

    function transferBySignature(
        address _signer,
        Permit3.SignatureTransferBatch calldata,
        Permit3.RequestedTransferDetails[] calldata _requestedTransfer,
        bytes calldata _signature
    )
        external
    {
        vm.pauseGasMetering();

        signer = _signer;
        for (uint256 i = 0; i < _requestedTransfer.length; i++) {
            requestedTransfer.push(_requestedTransfer[i]);
        }
        signature = _signature;

        vm.resumeGasMetering();
    }

    function test_ExecuteCallback_InvalidCaller() external {
        vm.pauseGasMetering();

        Accounts.Account memory account;

        vm.resumeGasMetering();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Router.InvalidCaller.selector, address(1)));
        router.executeCallback(account, bytes(""));
    }

    function test_ExecuteCallback_ERC20DataSingle() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.erc20Data[0].balanceDelta = 1e18;

        Router.CallbackData memory callbackData;
        callbackData.signatureTransfer.transferDetails = new Permit3.TransferDetails[](1);

        vm.resumeGasMetering();

        router.executeCallback(account, abi.encode(callbackData));

        vm.pauseGasMetering();

        assertEq(signer, callbackData.payer);
        assertEq(requestedTransfer.length, 1);
        assertEq(requestedTransfer[0].to, address(this));
        assertEq(requestedTransfer[0].transferDetails, abi.encode(1e18));
        assertEq(signature, callbackData.signature);

        delete signer;
        delete requestedTransfer;
        delete signature;

        vm.resumeGasMetering();
    }

    function test_ExecuteCallback_ERC20DataNegativeDelta() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.erc20Data[0].balanceDelta = -1e18;

        Router.CallbackData memory callbackData;
        callbackData.signatureTransfer.transferDetails = new Permit3.TransferDetails[](1);

        vm.resumeGasMetering();

        router.executeCallback(account, abi.encode(callbackData));

        vm.pauseGasMetering();

        assertEq(signer, callbackData.payer);
        assertEq(requestedTransfer.length, 1);
        assertEq(requestedTransfer[0].to, address(this));
        assertEq(requestedTransfer[0].transferDetails, abi.encode(uint256(0)));
        assertEq(signature, callbackData.signature);

        delete signer;
        delete requestedTransfer;
        delete signature;

        vm.resumeGasMetering();
    }

    function test_ExecuteCallback_ERC20DataMulti() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(2, 0);
        account.erc20Data[0].balanceDelta = 1e18;
        account.erc20Data[1].balanceDelta = 2e18;

        Router.CallbackData memory callbackData;
        callbackData.signatureTransfer.transferDetails = new Permit3.TransferDetails[](2);

        vm.resumeGasMetering();

        router.executeCallback(account, abi.encode(callbackData));

        vm.pauseGasMetering();

        assertEq(signer, callbackData.payer);
        assertEq(requestedTransfer.length, 2);
        assertEq(requestedTransfer[0].to, address(this));
        assertEq(requestedTransfer[0].transferDetails, abi.encode(1e18));
        assertEq(requestedTransfer[1].to, address(this));
        assertEq(requestedTransfer[1].transferDetails, abi.encode(2e18));
        assertEq(signature, callbackData.signature);

        delete signer;
        delete requestedTransfer;
        delete signature;

        vm.resumeGasMetering();
    }

    function test_ExecuteCallback_LPDataSingle() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(0, 1);
        account.lpData[0].id = bytes32(uint256(2));
        account.lpData[0].orderType = Engine.OrderType.Debt;
        account.lpData[0].amountBurned = 1e18;
        account.lpData[0].amountBuffer = 2e18;

        Router.CallbackData memory callbackData;
        callbackData.signatureTransfer.transferDetails = new Permit3.TransferDetails[](1);

        vm.resumeGasMetering();

        router.executeCallback(account, abi.encode(callbackData));

        vm.pauseGasMetering();

        assertEq(signer, callbackData.payer);
        assertEq(requestedTransfer.length, 1);
        assertEq(requestedTransfer[0].to, address(this));
        assertEq(requestedTransfer[0].transferDetails, abi.encode(account.lpData[0]));
        assertEq(signature, callbackData.signature);

        delete signer;
        delete requestedTransfer;
        delete signature;

        vm.resumeGasMetering();
    }

    function test_ExecuteCallback_LPDataMulti() external {
        vm.pauseGasMetering();

        Accounts.Account memory account = Accounts.newAccount(0, 2);
        account.lpData[0].id = bytes32(uint256(2));
        account.lpData[0].orderType = Engine.OrderType.Debt;
        account.lpData[0].amountBurned = 1e18;
        account.lpData[0].amountBuffer = 2e18;
        account.lpData[1].id = bytes32(uint256(3));
        account.lpData[1].orderType = Engine.OrderType.Debt;
        account.lpData[1].amountBurned = 2e18;
        account.lpData[1].amountBuffer = 3e18;

        Router.CallbackData memory callbackData;
        callbackData.signatureTransfer.transferDetails = new Permit3.TransferDetails[](2);

        vm.resumeGasMetering();

        router.executeCallback(account, abi.encode(callbackData));

        vm.pauseGasMetering();

        assertEq(signer, callbackData.payer);
        assertEq(requestedTransfer.length, 2);
        assertEq(requestedTransfer[0].to, address(this));
        assertEq(requestedTransfer[0].transferDetails, abi.encode(account.lpData[0]));
        assertEq(requestedTransfer[1].to, address(this));
        assertEq(requestedTransfer[1].transferDetails, abi.encode(account.lpData[1]));
        assertEq(signature, callbackData.signature);

        delete signer;
        delete requestedTransfer;
        delete signature;

        vm.resumeGasMetering();
    }
}
