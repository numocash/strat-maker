// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../../../mocks/MockERC20.sol";
import {MockPositions} from "../../../mocks/MockPositions.sol";

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Permit3} from "ilrta/Permit3.sol";
import {Positions, debtID} from "src/core/Engine.sol";
import {Router} from "src/periphery/Router.sol";

import {console2} from "forge-std/console2.sol";

contract ExecuteCallbackTest is Test {
    Permit3 private permit3;
    Router private router;
    MockERC20 private mockERC20;
    MockPositions private mockPositions;

    bytes32 private constant TRANSFER_DETAILS_TYPEHASH =
        keccak256("TransferDetails(address token,uint8 tokenType,bytes4 functionSelector,bytes transferDetails)");

    bytes32 private constant TRANSFER_BATCH_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "Transfer(TransferDetails[] transferDetails,address spender,uint256 nonce,uint256 deadline)TransferDetails(address token,uint8 tokenType,bytes4 functionSelector,bytes transferDetails)"
    );

    function setUp() external {
        permit3 = new Permit3();
        router = new Router(payable(address(this)), address(permit3));
        mockERC20 = new MockERC20();
        mockPositions = new MockPositions();
    }

    function signTransferDetails(
        Permit3.SignatureTransferBatch memory signatureTransfer,
        uint256 privateKey
    )
        private
        view
        returns (bytes memory)
    {
        bytes32[] memory transferDetailsHashes = new bytes32[](signatureTransfer.transferDetails.length);
        for (uint256 i = 0; i < transferDetailsHashes.length; i++) {
            transferDetailsHashes[i] =
                keccak256(abi.encode(TRANSFER_DETAILS_TYPEHASH, signatureTransfer.transferDetails[i]));
        }

        bytes32 signatureHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                permit3.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        TRANSFER_BATCH_TYPEHASH,
                        keccak256(abi.encodePacked(transferDetailsHashes)),
                        address(router),
                        0,
                        block.timestamp
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, signatureHash);

        return abi.encodePacked(r, s, v);
    }

    function test_ExecuteCallback_ERC20() external {
        vm.pauseGasMetering();

        uint256 privateKey = 0xC0FFEE;
        address owner = vm.addr(privateKey);

        mockERC20.mint(owner, 1e18);
        vm.prank(owner);
        mockERC20.approve(address(permit3), type(uint256).max);

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.erc20Data[0].balanceDelta = 1e18;

        Router.CallbackData memory callbackData;
        callbackData.payer = owner;
        callbackData.signatureTransfer.transferDetails = new Permit3.TransferDetails[](1);
        callbackData.signatureTransfer.transferDetails[0].token = address(mockERC20);
        callbackData.signatureTransfer.transferDetails[0].tokenType = Permit3.TokenType.ERC20;
        callbackData.signatureTransfer.transferDetails[0].functionSelector = ERC20.transferFrom.selector;
        callbackData.signatureTransfer.transferDetails[0].transferDetails = abi.encode(uint256(1e18));
        callbackData.signatureTransfer.nonce = 0;
        callbackData.signatureTransfer.deadline = block.timestamp;

        callbackData.signature = signTransferDetails(callbackData.signatureTransfer, privateKey);

        vm.resumeGasMetering();

        router.executeCallback(account, abi.encode(callbackData));

        vm.pauseGasMetering();

        assertEq(mockERC20.balanceOf(owner), 0);
        assertEq(mockERC20.balanceOf(address(this)), 1e18);

        vm.resumeGasMetering();
    }

    function test_ExecuteCallback_ERC20Negative() external {
        vm.pauseGasMetering();

        uint256 privateKey = 0xC0FFEE;
        address owner = vm.addr(privateKey);

        mockERC20.mint(owner, 1e18);
        vm.prank(owner);
        mockERC20.approve(address(permit3), type(uint256).max);

        Accounts.Account memory account = Accounts.newAccount(1, 0);
        account.erc20Data[0].balanceDelta = -1e18;

        Router.CallbackData memory callbackData;
        callbackData.payer = owner;
        callbackData.signatureTransfer.transferDetails = new Permit3.TransferDetails[](1);
        callbackData.signatureTransfer.transferDetails[0].token = address(mockERC20);
        callbackData.signatureTransfer.transferDetails[0].tokenType = Permit3.TokenType.ERC20;
        callbackData.signatureTransfer.transferDetails[0].functionSelector = ERC20.transferFrom.selector;
        callbackData.signatureTransfer.transferDetails[0].transferDetails = abi.encode(uint256(1e18));
        callbackData.signatureTransfer.nonce = 0;
        callbackData.signatureTransfer.deadline = block.timestamp;

        callbackData.signature = signTransferDetails(callbackData.signatureTransfer, privateKey);

        vm.resumeGasMetering();

        router.executeCallback(account, abi.encode(callbackData));

        vm.pauseGasMetering();

        assertEq(mockERC20.balanceOf(owner), 1e18);
        assertEq(mockERC20.balanceOf(address(this)), 0);

        vm.resumeGasMetering();
    }

    function test_ExecuteCallback_LPDataZero() external {}

    function test_ExecuteCallback_LPData() external {
        vm.pauseGasMetering();

        uint256 privateKey = 0xC0FFEE;
        address owner = vm.addr(privateKey);

        bytes32 id = debtID(address(0), address(0), 0, 0, Engine.TokenSelector.Token1);

        mockPositions.mintDebt(owner, address(0), address(0), 0, 0, Engine.TokenSelector.Token1, 1e18, 1e18);

        vm.prank(owner);
        mockPositions.approve_BKoIou(address(permit3), Positions.ILRTAApprovalDetails(true));

        Accounts.Account memory account = Accounts.newAccount(0, 1);
        account.lpData[0].id = id;
        account.lpData[0].orderType = Engine.OrderType.Debt;
        account.lpData[0].amountBurned = 1e18;
        account.lpData[0].amountBuffer = 0.5e18;

        Router.CallbackData memory callbackData;
        callbackData.payer = owner;
        callbackData.signatureTransfer.transferDetails = new Permit3.TransferDetails[](1);
        callbackData.signatureTransfer.transferDetails[0].token = address(mockPositions);
        callbackData.signatureTransfer.transferDetails[0].tokenType = Permit3.TokenType.ILRTA;
        callbackData.signatureTransfer.transferDetails[0].functionSelector = Positions.transferFrom_OEpkUx.selector;
        callbackData.signatureTransfer.transferDetails[0].transferDetails = abi.encode(account.lpData[0]);
        callbackData.signatureTransfer.nonce = 0;
        callbackData.signatureTransfer.deadline = block.timestamp;

        console2.log(
            "id: %x",
            uint256(
                abi.decode(
                    callbackData.signatureTransfer.transferDetails[0].transferDetails, (Positions.ILRTATransferDetails)
                ).id
            )
        );

        callbackData.signature = signTransferDetails(callbackData.signatureTransfer, privateKey);

        vm.resumeGasMetering();

        router.executeCallback(account, abi.encode(callbackData));

        vm.pauseGasMetering();

        vm.resumeGasMetering();
    }
}
