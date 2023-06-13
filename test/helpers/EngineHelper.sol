// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Engine} from "src/core/Engine.sol";
import {Positions} from "src/core/Positions.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";

contract EngineHelper is IExecuteCallback {
    Engine internal engine;
    MockERC20 internal token0;
    MockERC20 internal token1;

    function _setUp() internal {
        engine = new Engine();
        MockERC20 tokenA = new MockERC20();
        MockERC20 tokenB = new MockERC20();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function executeCallback(
        address[] calldata tokens,
        int256[] calldata tokensDelta,
        bytes32[] calldata ids,
        int256[] calldata ilrtaDeltas,
        bytes calldata
    )
        external
    {
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

        for (uint256 i = 0; i < ids.length;) {
            int256 delta = ilrtaDeltas[i];

            if (delta > 0) {
                bytes32 id = ids[i];

                if (ids[i] != bytes32(0)) {
                    engine.transfer(msg.sender, abi.encode(Positions.ILRTATransferDetails(id, uint256(delta))));
                }
            }

            unchecked {
                i++;
            }
        }
    }

    function basicCreate() internal {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.CreatePair;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.CreatePairParams(address(token0), address(token1), 0));

        engine.execute(commands, inputs, address(0), new address[](0), new bytes32[](0), bytes(""));
    }

    function basicAddLiquidity() internal {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.AddLiquidity;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.AddLiquidityParams(address(token0), address(token1), 0, 0, 1e18));

        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = engine.dataID(abi.encode(Positions.ILRTADataID(address(token0), address(token1), 0, 0)));

        engine.execute(commands, inputs, address(this), tokens, ids, bytes(""));
    }

    function basicRemoveLiquidity() internal {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.RemoveLiquidity;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.RemoveLiquidityParams(address(token0), address(token1), 0, 0, 1e18));

        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = engine.dataID(abi.encode(Positions.ILRTADataID(address(token0), address(token1), 0, 0)));

        engine.execute(commands, inputs, address(this), tokens, ids, bytes(""));
    }
}
