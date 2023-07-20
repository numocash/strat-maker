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
        engine = new Engine(address(0));
        MockERC20 tokenA = new MockERC20();
        MockERC20 tokenB = new MockERC20();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function executeCallback(IExecuteCallback.CallbackParams calldata params) external {
        for (uint256 i = 0; i < params.tokens.length;) {
            int256 delta = params.tokensDelta[i];

            if (delta > 0) {
                address token = params.tokens[i];

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

        for (uint256 i = 0; i < params.lpIDs.length;) {
            uint256 delta = params.lpDeltas[i];

            if (delta < 0) {
                bytes32 id = params.lpIDs[i];

                if (params.lpIDs[i] != bytes32(0)) {
                    engine.transfer(
                        msg.sender, abi.encode(Positions.ILRTATransferDetails(id, delta, params.orderTypes[i]))
                    );
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
        inputs[0] = abi.encode(Engine.CreatePairParams(address(token0), address(token1), 0, 0));

        engine.execute(address(0), commands, inputs, 0, 0, bytes(""));
    }

    function basicAddLiquidity() internal {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.AddLiquidity;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            Engine.AddLiquidityParams(
                address(token0), address(token1), 0, 0, 1, Engine.TokenSelector.LiquidityPosition, 1e18
            )
        );

        engine.execute(address(this), commands, inputs, 1, 1, bytes(""));
    }

    function basicRemoveLiquidity() internal {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.RemoveLiquidity;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            Engine.RemoveLiquidityParams(
                address(token0), address(token1), 0, 0, 1, Engine.TokenSelector.LiquidityPosition, -1e18
            )
        );

        engine.execute(address(this), commands, inputs, 1, 1, bytes(""));
    }
}
