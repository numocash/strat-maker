// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

import {Engine} from "src/core/Engine.sol";
import {ILRTA} from "ilrta/ILRTA.sol";
import {Permit2} from "permit2/src/Permit2.sol";
import {Router} from "src/periphery/Router.sol";
import {Positions} from "src/core/Positions.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

contract RouterTest is Test {
    Engine private engine;
    Permit2 private permit2;
    Router private router;
    MockERC20 private token0;
    MockERC20 private token1;

    bytes32 private constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    bytes32 private constant PERMIT_BATCH_TRANSFER_FROM_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "PermitBatchTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

    bytes32 private constant ILRTA_TRANSFER_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "Transfer(TransferDetails transferDetails,address spender,uint256 nonce,uint256 deadline)TransferDetails(address token0,address token1,int24 strike,uint8 spread,uint256 amount)"
    );

    bytes32 private constant ILRTA_TRANSFER_DETAILS_TYPEHASH =
        keccak256("TransferDetails(address token0,address token1,int24 strike,uint8 spread,uint256 amount)");

    function setUp() external {
        engine = new Engine();
        permit2 = new Permit2();
        router = new Router(address(engine), address(permit2));

        MockERC20 tokenA = new MockERC20();
        MockERC20 tokenB = new MockERC20();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.CreatePair;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.CreatePairParams(address(token0), address(token1), 0));

        engine.execute(commands, inputs, address(0), 0, 0, bytes(""));
    }

    function testGasAddLiquidity() external {
        vm.pauseGasMetering();
        uint256 privateKey = 0xC0FFEE;
        address owner = vm.addr(privateKey);

        token0.mint(address(owner), 1e18);

        vm.prank(owner);
        token0.approve(address(permit2), 1e18);

        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.AddLiquidity;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.AddLiquidityParams(address(token0), address(token1), 0, 0, 1e18));

        ISignatureTransfer.TokenPermissions[] memory permitted = new ISignatureTransfer.TokenPermissions[](1);
        permitted[0] = ISignatureTransfer.TokenPermissions({token: address(token0), amount: 1e18});

        ISignatureTransfer.PermitBatchTransferFrom memory permitBatch =
            ISignatureTransfer.PermitBatchTransferFrom({permitted: permitted, nonce: 0, deadline: block.timestamp});

        bytes32[] memory tokenPermissions = new bytes32[](permitBatch.permitted.length);
        for (uint256 i = 0; i < permitBatch.permitted.length; ++i) {
            tokenPermissions[i] = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permitBatch.permitted[i]));
        }

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    permit2.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_BATCH_TRANSFER_FROM_TYPEHASH,
                            keccak256(abi.encodePacked(tokenPermissions)),
                            address(router),
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        bytes memory signature = abi.encodePacked(r, s, v);
        vm.resumeGasMetering();

        vm.prank(owner);
        router.execute(
            commands, inputs, owner, 1, 1, permitBatch, signature, new ILRTA.SignatureTransfer[](0), new bytes[](0)
        );
    }

    function testGasRemoveLiquidity() external {
        vm.pauseGasMetering();
        uint256 privateKey = 0xC0FFEE;
        address owner = vm.addr(privateKey);

        token0.mint(address(owner), 1e18);

        vm.prank(owner);
        token0.approve(address(permit2), 1e18);

        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.AddLiquidity;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.AddLiquidityParams(address(token0), address(token1), 0, 0, 1e18));

        ISignatureTransfer.TokenPermissions[] memory permitted = new ISignatureTransfer.TokenPermissions[](1);
        permitted[0] = ISignatureTransfer.TokenPermissions({token: address(token0), amount: 1e18});

        ISignatureTransfer.PermitBatchTransferFrom memory permitBatch =
            ISignatureTransfer.PermitBatchTransferFrom({permitted: permitted, nonce: 0, deadline: block.timestamp});

        bytes32[] memory tokenPermissions = new bytes32[](permitBatch.permitted.length);
        for (uint256 i = 0; i < permitBatch.permitted.length; ++i) {
            tokenPermissions[i] = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permitBatch.permitted[i]));
        }

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    permit2.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_BATCH_TRANSFER_FROM_TYPEHASH,
                            keccak256(abi.encodePacked(tokenPermissions)),
                            address(router),
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(owner);
        router.execute(
            commands, inputs, owner, 1, 0, permitBatch, signature, new ILRTA.SignatureTransfer[](0), new bytes[](0)
        );

        // REMOVE LIQUIDITY

        commands[0] = Engine.Commands.RemoveLiquidity;
        inputs[0] = abi.encode(Engine.RemoveLiquidityParams(address(token0), address(token1), 0, 0, 1e18));

        ILRTA.SignatureTransfer[] memory signatureTransfers = new ILRTA.SignatureTransfer[](1);
        signatureTransfers[0] = ILRTA.SignatureTransfer(
            0,
            block.timestamp,
            abi.encode(
                Positions.ILRTATransferDetails(
                    engine.dataID(abi.encode(Positions.ILRTADataID(address(token0), address(token1), 0, 0))), 1e18
                )
            )
        );

        (v, r, s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    engine.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            ILRTA_TRANSFER_TYPEHASH,
                            keccak256(
                                abi.encode(ILRTA_TRANSFER_DETAILS_TYPEHASH, signatureTransfers[0].transferDetails)
                            ),
                            address(router),
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        signature = abi.encodePacked(r, s, v);

        ISignatureTransfer.PermitBatchTransferFrom memory permitBatchEmpty;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.resumeGasMetering();

        vm.prank(owner);
        router.execute(commands, inputs, owner, 0, 1, permitBatchEmpty, bytes(""), signatureTransfers, signatures);
    }
}
