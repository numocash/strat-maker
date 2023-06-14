// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {EngineHelper} from "./helpers/EngineHelper.sol";

import {Engine} from "src/core/Engine.sol";
import {Positions} from "src/core/Positions.sol";
import {Pairs} from "src/core/Pairs.sol";

contract EngineTest is Test, EngineHelper {
    event PairCreated(address indexed token0, address indexed token1, int24 tickInitial);

    function setUp() external {
        _setUp();
    }

    function testCreatePair() external {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.CreatePair;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(2), 1));

        engine.execute(commands, inputs, address(0), 0, 0, bytes(""));

        (, int24 tickCurrent,, uint8 initialized) = engine.getPair(address(1), address(2));
        assertEq(initialized, 1);
        assertEq(tickCurrent, 1);
    }

    function testCreatePairBadToken() external {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.CreatePair;
        bytes[] memory inputs = new bytes[](1);

        inputs[0] = abi.encode(Engine.CreatePairParams(address(0), address(1), 1));

        vm.expectRevert(Engine.InvalidTokenOrder.selector);
        engine.execute(commands, inputs, address(0), 0, 0, bytes(""));

        inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(0), 1));

        vm.expectRevert(Engine.InvalidTokenOrder.selector);
        engine.execute(commands, inputs, address(0), 0, 0, bytes(""));

        inputs[0] = abi.encode(Engine.CreatePairParams(address(2), address(1), 1));

        vm.expectRevert(Engine.InvalidTokenOrder.selector);
        engine.execute(commands, inputs, address(0), 0, 0, bytes(""));

        inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(1), 1));

        vm.expectRevert(Engine.InvalidTokenOrder.selector);
        engine.execute(commands, inputs, address(0), 0, 0, bytes(""));
    }

    function testCreatePairEmit() external {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.CreatePair;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(2), 1));

        vm.expectEmit(true, true, false, true);
        emit PairCreated(address(1), address(2), 1);
        engine.execute(commands, inputs, address(0), 0, 0, bytes(""));
    }

    function testCreatePairDoubleInit() external {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.CreatePair;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(2), 0));

        engine.execute(commands, inputs, address(0), 0, 0, bytes(""));

        vm.expectRevert(Pairs.Initialized.selector);
        engine.execute(commands, inputs, address(0), 0, 0, bytes(""));
    }

    function testCreatePairBadTick() external {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.CreatePair;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.CreatePairParams(address(1), address(2), type(int24).max));

        vm.expectRevert(Pairs.InvalidTick.selector);
        engine.execute(commands, inputs, address(0), 0, 0, bytes(""));
    }

    function testAddLiquidity() external {
        basicCreate();

        basicAddLiquidity();
    }

    function testRemoveLiquidity() external {
        basicCreate();

        basicAddLiquidity();

        basicRemoveLiquidity();
    }

    function testSwap() external {
        basicCreate();

        basicAddLiquidity();

        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.Swap;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.SwapParams(address(token0), address(token1), false, 1e18 - 1));

        engine.execute(commands, inputs, address(this), 2, 0, bytes(""));
    }

    function testGasAddLiquidity() external {
        vm.pauseGasMetering();
        basicCreate();

        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.AddLiquidity;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.AddLiquidityParams(address(token0), address(token1), 0, 1, 1e18));

        vm.resumeGasMetering();

        engine.execute(commands, inputs, address(this), 1, 1, bytes(""));
    }

    function testGasRemoveLiquidity() external {
        vm.pauseGasMetering();
        basicCreate();
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.AddLiquidity;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.AddLiquidityParams(address(token0), address(token1), 0, 1, 1e18));

        address[] memory tokens = new address[](1);
        tokens[0] = address(token0);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = engine.dataID(abi.encode(Positions.ILRTADataID(address(token0), address(token1), 0, 1)));

        engine.execute(commands, inputs, address(this), 1, 1, bytes(""));

        commands[0] = Engine.Commands.RemoveLiquidity;

        inputs[0] = abi.encode(Engine.RemoveLiquidityParams(address(token0), address(token1), 0, 1, 1e18));

        vm.resumeGasMetering();

        engine.execute(commands, inputs, address(this), 1, 1, bytes(""));
    }

    function testGasSwap() external {
        vm.pauseGasMetering();
        basicCreate();
        basicAddLiquidity();

        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.Swap;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.SwapParams(address(token0), address(token1), false, 1e18 - 1));

        vm.resumeGasMetering();

        engine.execute(commands, inputs, address(this), 2, 0, bytes(""));
    }
}
