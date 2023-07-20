// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

import {Engine} from "src/core/Engine.sol";
import {ILRTA} from "ilrta/ILRTA.sol";
import {Permit3} from "ilrta/Permit3.sol";
import {Router} from "src/periphery/Router.sol";
import {Positions} from "src/core/Positions.sol";
import {SuperSignature} from "ilrta/SuperSignature.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {
    createCommands,
    createInputs,
    pushCommands,
    pushInputs,
    addLiquidityCommand,
    removeLiquidityCommand,
    borrowLiquidityCommand,
    repayLiquidityCommand,
    swapCommand
} from "./helpers/Utils.sol";

contract RouterTest is Test {
    Engine private engine;
    Permit3 private permit3;
    SuperSignature private superSignature;
    Router private router;
    MockERC20 private token0;
    MockERC20 private token1;

    uint256 private privateKey = 0xC0FFEE;
    address private owner = vm.addr(privateKey);

    bytes32 private constant VERIFY_TYPEHASH = keccak256("Verify(bytes32[] dataHash,uint256 nonce,uint256 deadline)");

    bytes32 public constant TRANSFER_DETAILS_TYPEHASH = keccak256("TransferDetails(address token,uint256 amount)");

    bytes32 private constant SUPER_SIGNATURE_TRANSFER_BATCH_TYPEHASH = keccak256(
        "Transfer(TransferDetails[] transferDetails,address spender)TransferDetails(address token,uint256 amount)"
    );

    bytes32 private constant SUPER_SIGNATURE_ILRTA_TRANSFER_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "Transfer(TransferDetails transferDetails,address spender)TransferDetails(bytes32 id,uint256 amount)"
    );

    bytes32 private constant ILRTA_TRANSFER_DETAILS_TYPEHASH = keccak256("TransferDetails(bytes32 id,uint256 amount)");

    function permitDataHash(Permit3.TransferDetails[] memory permitTransfers) private view returns (bytes32) {
        uint256 length = permitTransfers.length;
        bytes32[] memory transfeDetailsHashes = new bytes32[](length);

        for (uint256 i = 0; i < length;) {
            transfeDetailsHashes[i] = keccak256(abi.encode(TRANSFER_DETAILS_TYPEHASH, permitTransfers[i]));

            unchecked {
                i++;
            }
        }

        bytes32 signatureHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                permit3.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        SUPER_SIGNATURE_TRANSFER_BATCH_TYPEHASH,
                        keccak256(abi.encodePacked(transfeDetailsHashes)),
                        address(router)
                    )
                )
            )
        );

        return signatureHash;
    }

    function positionsDataHash(Positions.ILRTATransferDetails memory positionTransfer) private view returns (bytes32) {
        bytes32 signatureHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                engine.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        SUPER_SIGNATURE_ILRTA_TRANSFER_TYPEHASH,
                        keccak256(abi.encode(ILRTA_TRANSFER_DETAILS_TYPEHASH, abi.encode(positionTransfer))),
                        address(router)
                    )
                )
            )
        );

        return signatureHash;
    }

    function signSuperSignature(SuperSignature.Verify memory verify) private view returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    superSignature.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            VERIFY_TYPEHASH, keccak256(abi.encodePacked(verify.dataHash)), verify.nonce, verify.deadline
                        )
                    )
                )
            )
        );

        signature = abi.encodePacked(r, s, v);
    }

    function setUp() external {
        superSignature = new SuperSignature();
        permit3 = new Permit3(address(superSignature));
        engine = new Engine(address(superSignature));
        router = new Router(address(engine), address(permit3), address(superSignature));

        MockERC20 tokenA = new MockERC20();
        MockERC20 tokenB = new MockERC20();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.CreatePair;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.CreatePairParams(address(token0), address(token1), 0, 0));

        engine.execute(address(0), commands, inputs, 0, 0, bytes(""));
    }

    function testGasAddLiquidity() external {
        vm.pauseGasMetering();

        token0.mint(address(owner), 1e18);

        vm.prank(owner);
        token0.approve(address(permit3), 1e18);

        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.AddLiquidity;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            Engine.AddLiquidityParams(
                address(token0), address(token1), 0, 0, 1, Engine.TokenSelector.LiquidityPosition, 1e18
            )
        );

        Permit3.TransferDetails[] memory permitTransferDetails = new Permit3.TransferDetails[](1);
        permitTransferDetails[0] = Permit3.TransferDetails({token: address(token0), amount: 1e18});

        bytes32[] memory dataHash = new bytes32[](1);
        dataHash[0] = permitDataHash(permitTransferDetails);

        SuperSignature.Verify memory verify = SuperSignature.Verify(dataHash, 0, block.timestamp);

        bytes memory signature = signSuperSignature(verify);
        vm.resumeGasMetering();

        vm.prank(owner);
        router.route(
            Router.RouteParams(
                owner,
                commands,
                inputs,
                1,
                1,
                permitTransferDetails,
                new Positions.ILRTATransferDetails[](0),
                verify,
                signature
            )
        );
    }

    function testGasRemoveLiquidity() external {
        vm.pauseGasMetering();

        token0.mint(address(owner), 1e18);

        vm.prank(owner);
        token0.approve(address(permit3), 1e18);

        Engine.Commands[] memory commands = createCommands();
        bytes[] memory inputs = createInputs();

        (Engine.Commands addCommand, bytes memory addInput) =
            addLiquidityCommand(address(token0), address(token1), 0, 0, 1, Engine.TokenSelector.LiquidityPosition, 1e18);

        commands = pushCommands(commands, addCommand);
        inputs = pushInputs(inputs, addInput);

        Permit3.TransferDetails[] memory permitTransferDetails = new Permit3.TransferDetails[](1);
        permitTransferDetails[0] = Permit3.TransferDetails({token: address(token0), amount: 1e18});

        bytes32[] memory dataHash = new bytes32[](1);
        dataHash[0] = permitDataHash(permitTransferDetails);

        SuperSignature.Verify memory verify = SuperSignature.Verify(dataHash, 0, block.timestamp);

        bytes memory signature = signSuperSignature(verify);

        vm.prank(owner);
        router.route(
            Router.RouteParams(
                owner,
                commands,
                inputs,
                1,
                1,
                permitTransferDetails,
                new Positions.ILRTATransferDetails[](0),
                verify,
                signature
            )
        );

        // REMOVE LIQUIDITY

        (Engine.Commands removeCommand, bytes memory removeInput) = removeLiquidityCommand(
            address(token0), address(token1), 0, 0, 1, Engine.TokenSelector.LiquidityPosition, -1e18
        );

        commands[0] = removeCommand;
        inputs[0] = removeInput;

        Positions.ILRTATransferDetails[] memory positionTransfer = new Positions.ILRTATransferDetails[](1);
        positionTransfer[0] = Positions.ILRTATransferDetails(
            engine.dataID(
                abi.encode(
                    Positions.ILRTADataID(
                        Engine.OrderType.BiDirectional,
                        abi.encode(Positions.BiDirectionalID(address(token0), address(token1), 0, 0, 1))
                    )
                )
            ),
            1e18,
            Engine.OrderType.BiDirectional
        );

        dataHash[0] = positionsDataHash(positionTransfer[0]);

        verify = SuperSignature.Verify(dataHash, 1, block.timestamp);

        signature = signSuperSignature(verify);

        vm.resumeGasMetering();

        vm.prank(owner);
        router.route(
            Router.RouteParams(
                owner, commands, inputs, 1, 1, new Permit3.TransferDetails[](0), positionTransfer, verify, signature
            )
        );
    }

    function testGasSwap() external {
        vm.pauseGasMetering();

        token0.mint(address(owner), 1e18);

        vm.prank(owner);
        token0.approve(address(permit3), 1e18);

        Engine.Commands[] memory commands = createCommands();
        bytes[] memory inputs = createInputs();

        (Engine.Commands addCommand, bytes memory addInput) =
            addLiquidityCommand(address(token0), address(token1), 0, 0, 1, Engine.TokenSelector.LiquidityPosition, 1e18);

        commands = pushCommands(commands, addCommand);
        inputs = pushInputs(inputs, addInput);

        Permit3.TransferDetails[] memory permitTransferDetails = new Permit3.TransferDetails[](1);
        permitTransferDetails[0] = Permit3.TransferDetails({token: address(token0), amount: 1e18});

        bytes32[] memory dataHash = new bytes32[](1);
        dataHash[0] = permitDataHash(permitTransferDetails);

        SuperSignature.Verify memory verify = SuperSignature.Verify(dataHash, 0, block.timestamp);
        bytes memory signature = signSuperSignature(verify);

        vm.prank(owner);
        router.route(
            Router.RouteParams(
                owner,
                commands,
                inputs,
                1,
                1,
                permitTransferDetails,
                new Positions.ILRTATransferDetails[](0),
                verify,
                signature
            )
        );

        // SWAP

        token1.mint(address(owner), 1e18);

        vm.prank(owner);
        token1.approve(address(permit3), 1e18);

        (Engine.Commands _swapCommand, bytes memory swapInput) =
            swapCommand(address(token0), address(token1), 0, Engine.TokenSelector.Token1, 1e18 - 1);

        commands[0] = _swapCommand;
        inputs[0] = swapInput;

        permitTransferDetails[0] = Permit3.TransferDetails({token: address(token1), amount: 1e18});

        dataHash[0] = permitDataHash(permitTransferDetails);

        verify = SuperSignature.Verify(dataHash, 1, block.timestamp);
        signature = signSuperSignature(verify);

        vm.resumeGasMetering();

        vm.prank(owner);
        router.route(
            Router.RouteParams(
                owner,
                commands,
                inputs,
                2,
                0,
                permitTransferDetails,
                new Positions.ILRTATransferDetails[](0),
                verify,
                signature
            )
        );
    }

    function testGasBorrowLiquidity() external {
        vm.pauseGasMetering();

        token0.mint(address(owner), 2e18);

        vm.prank(owner);
        token0.approve(address(permit3), 2e18);

        Engine.Commands[] memory commands = createCommands();
        bytes[] memory inputs = createInputs();

        (Engine.Commands addCommand, bytes memory addInput) =
            addLiquidityCommand(address(token0), address(token1), 0, 1, 1, Engine.TokenSelector.LiquidityPosition, 1e18);

        commands = pushCommands(commands, addCommand);
        inputs = pushInputs(inputs, addInput);

        Permit3.TransferDetails[] memory permitTransferDetails = new Permit3.TransferDetails[](1);
        permitTransferDetails[0] = Permit3.TransferDetails({token: address(token0), amount: 1e18});

        bytes32[] memory dataHash = new bytes32[](1);
        dataHash[0] = permitDataHash(permitTransferDetails);

        SuperSignature.Verify memory verify = SuperSignature.Verify(dataHash, 0, block.timestamp);

        bytes memory signature = signSuperSignature(verify);

        vm.prank(owner);
        router.route(
            Router.RouteParams(
                owner,
                commands,
                inputs,
                1,
                1,
                permitTransferDetails,
                new Positions.ILRTATransferDetails[](0),
                verify,
                signature
            )
        );

        // BORROW LIQUIDITY

        (Engine.Commands borrowCommand, bytes memory borrowInput) =
            borrowLiquidityCommand(address(token0), address(token1), 0, 1, Engine.TokenSelector.Token0, 1e18, 0.5e18);

        commands[0] = borrowCommand;
        inputs[0] = borrowInput;

        permitTransferDetails[0] = Permit3.TransferDetails({token: address(token0), amount: 1.5e18});

        dataHash[0] = permitDataHash(permitTransferDetails);

        verify = SuperSignature.Verify(dataHash, 1, block.timestamp);

        signature = signSuperSignature(verify);

        vm.resumeGasMetering();

        vm.prank(owner);
        router.route(
            Router.RouteParams(
                owner,
                commands,
                inputs,
                1,
                1,
                permitTransferDetails,
                new Positions.ILRTATransferDetails[](0),
                verify,
                signature
            )
        );
    }

    function testGasRepayLiquidity() external {
        vm.pauseGasMetering();

        token0.mint(address(owner), 2e18);

        vm.prank(owner);
        token0.approve(address(permit3), 2e18);

        Engine.Commands[] memory commands = createCommands();
        bytes[] memory inputs = createInputs();

        (Engine.Commands addCommand, bytes memory addInput) =
            addLiquidityCommand(address(token0), address(token1), 0, 1, 1, Engine.TokenSelector.LiquidityPosition, 1e18);

        commands = pushCommands(commands, addCommand);
        inputs = pushInputs(inputs, addInput);

        Permit3.TransferDetails[] memory permitTransferDetails = new Permit3.TransferDetails[](1);
        permitTransferDetails[0] = Permit3.TransferDetails({token: address(token0), amount: 1e18});

        bytes32[] memory dataHash = new bytes32[](1);
        dataHash[0] = permitDataHash(permitTransferDetails);

        SuperSignature.Verify memory verify = SuperSignature.Verify(dataHash, 0, block.timestamp);

        bytes memory signature = signSuperSignature(verify);

        vm.prank(owner);
        router.route(
            Router.RouteParams(
                owner,
                commands,
                inputs,
                1,
                1,
                permitTransferDetails,
                new Positions.ILRTATransferDetails[](0),
                verify,
                signature
            )
        );

        // BORROW LIQUIDITY

        (Engine.Commands borrowCommand, bytes memory borrowInput) =
            borrowLiquidityCommand(address(token0), address(token1), 0, 1, Engine.TokenSelector.Token0, 1e18, 0.5e18);

        commands[0] = borrowCommand;
        inputs[0] = borrowInput;

        permitTransferDetails[0] = Permit3.TransferDetails({token: address(token0), amount: 1.5e18});

        dataHash[0] = permitDataHash(permitTransferDetails);

        verify = SuperSignature.Verify(dataHash, 1, block.timestamp);

        signature = signSuperSignature(verify);

        vm.prank(owner);
        router.route(
            Router.RouteParams(
                owner,
                commands,
                inputs,
                1,
                1,
                permitTransferDetails,
                new Positions.ILRTATransferDetails[](0),
                verify,
                signature
            )
        );

        // REPAY LIQUIDITY

        {
            (, uint256 leverageRatioX128) =
                engine.getPositionDebt(owner, address(token0), address(token1), 0, 1, Engine.TokenSelector.Token0);

            (Engine.Commands repayCommand, bytes memory repayInput) = repayLiquidityCommand(
                address(token0), address(token1), 0, 1, Engine.TokenSelector.Token0, leverageRatioX128, 0.5e18
            );

            commands[0] = repayCommand;
            inputs[0] = repayInput;
        }

        Positions.ILRTATransferDetails[] memory positionTransfer = new Positions.ILRTATransferDetails[](1);
        positionTransfer[0] = Positions.ILRTATransferDetails(
            engine.dataID(
                abi.encode(
                    Positions.ILRTADataID(
                        Engine.OrderType.Debt,
                        abi.encode(
                            Positions.DebtID(address(token0), address(token1), 0, 1, Engine.TokenSelector.Token0)
                        )
                    )
                )
            ),
            0.5e18,
            Engine.OrderType.Debt
        );

        dataHash[0] = positionsDataHash(positionTransfer[0]);

        verify = SuperSignature.Verify(dataHash, 2, block.timestamp);

        signature = signSuperSignature(verify);

        vm.resumeGasMetering();

        vm.prank(owner);
        router.route(
            Router.RouteParams(
                owner, commands, inputs, 1, 1, new Permit3.TransferDetails[](0), positionTransfer, verify, signature
            )
        );
    }
}
