// // SPDX-License-Identifier: GPL-3.0-only
// pragma solidity ^0.8.0;

// import {Test} from "forge-std/Test.sol";
// import {EngineHelper} from "./helpers/EngineHelper.sol";
// import {
//     createCommands,
//     createInputs,
//     pushCommands,
//     pushInputs,
//     borrowLiquidityCommand,
//     repayLiquidityCommand,
//     addLiquidityCommand,
//     removeLiquidityCommand,
//     swapCommand
// } from "./helpers/Utils.sol";

// import {Engine} from "src/core/Engine.sol";
// import {Pairs} from "src/core/Pairs.sol";
// import {mulDiv, mulDivRoundingUp} from "src/core/math/FullMath.sol";
// import {Q128, getRatioAtStrike} from "src/core/math/StrikeMath.sol";

// contract EngineTest is Test, EngineHelper {
//     event PairCreated(address indexed token0, address indexed token1, int24 strikeInitial);

//     function setUp() external {
//         _setUp();
//     }

//     function testCreatePair() external {
//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         commands[0] = Engine.Commands.CreatePair;

//         bytes[] memory inputs = new bytes[](1);
//         inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(2), 0, 1));

//         engine.execute(address(0), commands, inputs, 0, 0, bytes(""));

//         (,, int24 strikeCurrent, uint8 initialized) = engine.getPair(address(1), address(2), 0);
//         assertEq(initialized, 1);
//         assertEq(strikeCurrent, 1);
//     }

//     function testCreatePairBadToken() external {
//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         commands[0] = Engine.Commands.CreatePair;
//         bytes[] memory inputs = new bytes[](1);

//         inputs[0] = abi.encode(Engine.CreatePairParams(address(0), address(1), 0, 1));

//         vm.expectRevert(Engine.InvalidTokenOrder.selector);
//         engine.execute(address(0), commands, inputs, 0, 0, bytes(""));

//         inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(0), 0, 1));

//         vm.expectRevert(Engine.InvalidTokenOrder.selector);
//         engine.execute(address(0), commands, inputs, 0, 0, bytes(""));

//         inputs[0] = abi.encode(Engine.CreatePairParams(address(2), address(1), 0, 1));

//         vm.expectRevert(Engine.InvalidTokenOrder.selector);
//         engine.execute(address(0), commands, inputs, 0, 0, bytes(""));

//         inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(1), 0, 1));

//         vm.expectRevert(Engine.InvalidTokenOrder.selector);
//         engine.execute(address(0), commands, inputs, 0, 0, bytes(""));
//     }

//     function testCreatePairEmit() external {
//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         commands[0] = Engine.Commands.CreatePair;

//         bytes[] memory inputs = new bytes[](1);
//         inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(2), 0, 1));

//         vm.expectEmit(true, true, false, true);
//         emit PairCreated(address(1), address(2), 1);
//         engine.execute(address(0), commands, inputs, 0, 0, bytes(""));
//     }

//     function testCreatePairDoubleInit() external {
//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         commands[0] = Engine.Commands.CreatePair;

//         bytes[] memory inputs = new bytes[](1);
//         inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(2), 0, 0));

//         engine.execute(address(0), commands, inputs, 0, 0, bytes(""));

//         vm.expectRevert(Pairs.Initialized.selector);
//         engine.execute(address(0), commands, inputs, 0, 0, bytes(""));
//     }

//     function testCreatePairBadStrike() external {
//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         commands[0] = Engine.Commands.CreatePair;

//         bytes[] memory inputs = new bytes[](1);
//         inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(2), 0, type(int24).max));

//         vm.expectRevert(Pairs.InvalidStrike.selector);
//         engine.execute(address(0), commands, inputs, 0, 0, bytes(""));
//     }

//     function testAddLiquidity() external {
//         basicCreate();

//         basicAddLiquidity();

//         assertEq(token0.balanceOf(address(this)), 0);
//         assertEq(token1.balanceOf(address(this)), 0);

//         assertEq(token0.balanceOf(address(engine)), 1e18);
//         assertEq(token1.balanceOf(address(engine)), 0);
//     }

//     function testRemoveLiquidity() external {
//         basicCreate();

//         basicAddLiquidity();

//         basicRemoveLiquidity();

//         assertEq(token0.balanceOf(address(this)), 1e18 - 1);
//         assertEq(token1.balanceOf(address(this)), 0);

//         assertEq(token0.balanceOf(address(engine)), 1);
//         assertEq(token1.balanceOf(address(engine)), 0);
//     }

//     function testBorrowLiquidity() external {
//         basicCreate();

//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         commands[0] = Engine.Commands.AddLiquidity;

//         bytes[] memory inputs = new bytes[](1);
//         inputs[0] = abi.encode(Engine.AddLiquidityParams(address(token0), address(token1), 0, 1, 1, 1e18));

//         engine.execute(address(this), commands, inputs, 1, 0, bytes(""));

//         (commands[0], inputs[0]) =
//             borrowLiquidityCommand(address(token0), address(token1), 0, 1, Engine.TokenSelector.Token0, 1.5e18,
// 0.5e18);

//         engine.execute(address(this), commands, inputs, 1, 0, bytes(""));

//         assertEq(token0.balanceOf(address(this)), 0);
//         assertEq(token1.balanceOf(address(this)), 0);

//         assertEq(
//             token0.balanceOf(address(engine)),
//             mulDivRoundingUp(1e18, Q128, getRatioAtStrike(1)) + 1.5e18 - mulDiv(0.5e18, Q128, getRatioAtStrike(1))
//         );
//         assertEq(token1.balanceOf(address(engine)), 0);
//     }

//     function testRepayLiquidity() external {
//         basicCreate();

//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         commands[0] = Engine.Commands.AddLiquidity;

//         bytes[] memory inputs = new bytes[](1);
//         inputs[0] = abi.encode(Engine.AddLiquidityParams(address(token0), address(token1), 0, 1, 1, 1e18));

//         engine.execute(address(this), commands, inputs, 1, 0, bytes(""));

//         (commands[0], inputs[0]) =
//             borrowLiquidityCommand(address(token0), address(token1), 0, 1, Engine.TokenSelector.Token0, 1.5e18,
// 0.5e18);

//         engine.execute(address(this), commands, inputs, 1, 0, bytes(""));

//         (, uint256 leverageRatioX128) =
//             engine.getPositionDebt(address(this), address(token0), address(token1), 0, 1,
// Engine.TokenSelector.Token0);

//         (commands[0], inputs[0]) = repayLiquidityCommand(
//             address(token0), address(token1), 0, 1, Engine.TokenSelector.Token0, leverageRatioX128, 0.5e18
//         );

//         engine.execute(address(this), commands, inputs, 1, 1, bytes(""));

//         uint256 tokens0Owed = mulDivRoundingUp(0.5e18, Q128, getRatioAtStrike(1));
//         uint256 tokens0Collateral = mulDiv((mulDiv(0.5e18, leverageRatioX128, Q128)), Q128, getRatioAtStrike(1));

//         // assertEq(token0.balanceOf(address(this)), tokens0Collateral - tokens0Owed);
//         assertEq(token1.balanceOf(address(this)), 0);
//     }

//     function testSwap() external {
//         basicCreate();

//         basicAddLiquidity();

//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         commands[0] = Engine.Commands.Swap;

//         bytes[] memory inputs = new bytes[](1);
//         inputs[0] = abi.encode(
//             Engine.SwapParams(address(token0), address(token1), 0, Engine.SwapTokenSelector.Token1, 1e18 - 1)
//         );

//         engine.execute(address(this), commands, inputs, 2, 0, bytes(""));

//         uint256 amountOut = mulDiv(1e18 - 1, Q128, getRatioAtStrike(1));

//         assertEq(token0.balanceOf(address(this)), amountOut);
//         assertEq(token1.balanceOf(address(this)), 0);

//         assertEq(token0.balanceOf(address(engine)), 1e18 - amountOut);
//         assertEq(token1.balanceOf(address(engine)), 1e18 - 1);
//     }

//     function testGasAddLiquidity() external {
//         vm.pauseGasMetering();
//         basicCreate();

//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         commands[0] = Engine.Commands.AddLiquidity;

//         bytes[] memory inputs = new bytes[](1);
//         inputs[0] = abi.encode(Engine.AddLiquidityParams(address(token0), address(token1), 0, 0, 1, 1e18));

//         vm.resumeGasMetering();

//         engine.execute(address(this), commands, inputs, 1, 0, bytes(""));
//     }

//     function testGasRemoveLiquidity() external {
//         vm.pauseGasMetering();
//         basicCreate();

//         Engine.Commands[] memory commands = createCommands();
//         bytes[] memory inputs = createInputs();

//         (Engine.Commands addCommand, bytes memory addInput) =
//             addLiquidityCommand(address(token0), address(token1), 0, 0, 1, 1e18);

//         commands = pushCommands(commands, addCommand);
//         inputs = pushInputs(inputs, addInput);

//         engine.execute(address(this), commands, inputs, 1, 1, bytes(""));

//         (Engine.Commands removeCommand, bytes memory removeInput) =
//             removeLiquidityCommand(address(token0), address(token1), 0, 0, 1, 1e18);

//         commands[0] = removeCommand;
//         inputs[0] = removeInput;

//         vm.resumeGasMetering();

//         engine.execute(address(this), commands, inputs, 1, 1, bytes(""));
//     }

//     function testGasBorrowLiquidity() external {
//         vm.pauseGasMetering();
//         basicCreate();

//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         bytes[] memory inputs = new bytes[](1);

//         commands[0] = Engine.Commands.AddLiquidity;
//         inputs[0] = abi.encode(Engine.AddLiquidityParams(address(token0), address(token1), 0, 0, 1, 1e18));

//         engine.execute(address(this), commands, inputs, 1, 0, bytes(""));

//         (commands[0], inputs[0]) =
//             borrowLiquidityCommand(address(token0), address(token1), 0, 0, Engine.TokenSelector.Token0, 1.5e18,
// 0.5e18);

//         vm.resumeGasMetering();

//         engine.execute(address(this), commands, inputs, 1, 0, bytes(""));
//     }

//     function testGasRepayLiquidity() external {
//         vm.pauseGasMetering();
//         basicCreate();

//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         commands[0] = Engine.Commands.AddLiquidity;

//         bytes[] memory inputs = new bytes[](1);
//         inputs[0] = abi.encode(Engine.AddLiquidityParams(address(token0), address(token1), 0, 0, 1, 1e18));

//         engine.execute(address(this), commands, inputs, 1, 0, bytes(""));

//         (commands[0], inputs[0]) =
//             borrowLiquidityCommand(address(token0), address(token1), 0, 0, Engine.TokenSelector.Token0, 1.5e18,
// 0.5e18);

//         engine.execute(address(this), commands, inputs, 1, 0, bytes(""));

//         (, uint256 leverageRatioX128) =
//             engine.getPositionDebt(address(this), address(token0), address(token1), 0, 0,
// Engine.TokenSelector.Token0);

//         (commands[0], inputs[0]) = repayLiquidityCommand(
//             address(token0), address(token1), 0, 0, Engine.TokenSelector.Token0, leverageRatioX128, 0.5e18
//         );

//         vm.resumeGasMetering();

//         engine.execute(address(this), commands, inputs, 1, 1, bytes(""));
//     }

//     function testGasSwap() external {
//         vm.pauseGasMetering();
//         basicCreate();
//         basicAddLiquidity();

//         Engine.Commands[] memory commands = new Engine.Commands[](1);
//         commands[0] = Engine.Commands.Swap;

//         bytes[] memory inputs = new bytes[](1);
//         inputs[0] = abi.encode(
//             Engine.SwapParams(address(token0), address(token1), 0, Engine.SwapTokenSelector.Token1, 1e18 - 1)
//         );

//         vm.resumeGasMetering();

//         engine.execute(address(this), commands, inputs, 2, 0, bytes(""));
//     }

//     function testGasSwapAndAdd() external {
//         vm.pauseGasMetering();
//         basicCreate();
//         basicAddLiquidity();

//         Engine.Commands[] memory commands = createCommands();
//         bytes[] memory inputs = createInputs();

//         (Engine.Commands addCommand, bytes memory addInput) =
//             addLiquidityCommand(address(token0), address(token1), 0, 0, 1, 0.2e18);

//         commands = pushCommands(commands, addCommand);
//         inputs = pushInputs(inputs, addInput);

//         (Engine.Commands _swapCommand, bytes memory swapInput) =
//             swapCommand(address(token0), address(token1), 0, Engine.SwapTokenSelector.Token0Account, 0);

//         commands = pushCommands(commands, _swapCommand);
//         inputs = pushInputs(inputs, swapInput);

//         vm.resumeGasMetering();

//         engine.execute(address(this), commands, inputs, 2, 1, bytes(""));

//         vm.pauseGasMetering();
//         assertEq(token0.balanceOf(address(this)), 0);
//         assertEq(token1.balanceOf(address(this)), 0);
//         vm.resumeGasMetering();
//     }

//     function testGasRemoveAndSwap() external {
//         vm.pauseGasMetering();
//         basicCreate();
//         basicAddLiquidity();

//         Engine.Commands[] memory commands = createCommands();
//         bytes[] memory inputs = createInputs();

//         (Engine.Commands addCommand, bytes memory addInput) =
//             addLiquidityCommand(address(token0), address(token1), 0, -1, 1, 1e18);

//         commands = pushCommands(commands, addCommand);
//         inputs = pushInputs(inputs, addInput);

//         engine.execute(address(this), commands, inputs, 1, 1, bytes(""));

//         (Engine.Commands removeCommand, bytes memory removeInput) =
//             removeLiquidityCommand(address(token0), address(token1), 0, 0, 1, 0.2e18);

//         commands[0] = removeCommand;
//         inputs[0] = removeInput;

//         (Engine.Commands _swapCommand, bytes memory swapInput) =
//             swapCommand(address(token0), address(token1), 0, Engine.SwapTokenSelector.Token0Account, 0);

//         commands = pushCommands(commands, _swapCommand);
//         inputs = pushInputs(inputs, swapInput);

//         vm.resumeGasMetering();

//         engine.execute(address(this), commands, inputs, 2, 1, bytes(""));

//         vm.pauseGasMetering();
//         assertEq(token0.balanceOf(address(this)), 0);
//         vm.resumeGasMetering();
//     }

//     function testGasBorrowAndSwap() external {
//         vm.pauseGasMetering();
//         basicCreate();
//         basicAddLiquidity();

//         Engine.Commands[] memory commands = createCommands();
//         bytes[] memory inputs = createInputs();

//         (Engine.Commands addCommand, bytes memory addInput) =
//             addLiquidityCommand(address(token0), address(token1), 0, -1, 1, 1e18);

//         commands = pushCommands(commands, addCommand);
//         inputs = pushInputs(inputs, addInput);

//         engine.execute(address(this), commands, inputs, 1, 1, bytes(""));

//         (Engine.Commands borrowCommand, bytes memory borrowInput) =
//             borrowLiquidityCommand(address(token0), address(token1), 0, 0, Engine.TokenSelector.Token1, 1e18,
// 0.2e18);

//         commands[0] = borrowCommand;
//         inputs[0] = borrowInput;

//         (Engine.Commands _swapCommand, bytes memory swapInput) =
//             swapCommand(address(token0), address(token1), 0, Engine.SwapTokenSelector.Token0Account, 0);

//         commands = pushCommands(commands, _swapCommand);
//         inputs = pushInputs(inputs, swapInput);

//         vm.resumeGasMetering();

//         engine.execute(address(this), commands, inputs, 2, 1, bytes(""));

//         vm.pauseGasMetering();
//         assertEq(token0.balanceOf(address(this)), 0);
//         assertEq(token1.balanceOf(address(this)), 0);
//         vm.resumeGasMetering();
//     }

//     function testGasSwapAndRepay() external {
//         vm.pauseGasMetering();
//         basicCreate();
//         basicAddLiquidity();

//         Engine.Commands[] memory commands = createCommands();
//         bytes[] memory inputs = createInputs();

//         (Engine.Commands borrowCommand, bytes memory borrowInput) =
//             borrowLiquidityCommand(address(token0), address(token1), 0, 0, Engine.TokenSelector.Token1, 1e18,
// 0.2e18);

//         commands = pushCommands(commands, borrowCommand);
//         inputs = pushInputs(inputs, borrowInput);

//         (Engine.Commands addCommand, bytes memory addInput) =
//             addLiquidityCommand(address(token0), address(token1), 0, -1, 1, 1e18);

//         commands = pushCommands(commands, addCommand);
//         inputs = pushInputs(inputs, addInput);

//         engine.execute(address(this), commands, inputs, 2, 1, bytes(""));

//         (uint128 balance, uint256 leverageRatioX128) =
//             engine.getPositionDebt(address(this), address(token0), address(token1), 0, 0,
// Engine.TokenSelector.Token1);

//         (Engine.Commands repayCommand, bytes memory repayInput) = repayLiquidityCommand(
//             address(token0), address(token1), 0, 0, Engine.TokenSelector.Token1, leverageRatioX128, balance
//         );

//         commands[0] = repayCommand;
//         inputs[0] = repayInput;

//         (Engine.Commands _swapCommand, bytes memory swapInput) =
//             swapCommand(address(token0), address(token1), 0, Engine.SwapTokenSelector.Token0Account, 0);

//         commands[1] = _swapCommand;
//         inputs[1] = swapInput;

//         vm.resumeGasMetering();

//         engine.execute(address(this), commands, inputs, 2, 1, bytes(""));

//         vm.pauseGasMetering();
//         assertEq(token0.balanceOf(address(this)), 0.2e18);
//         assertGe(token1.balanceOf(address(this)), 0);
//         vm.resumeGasMetering();
//     }
// }
