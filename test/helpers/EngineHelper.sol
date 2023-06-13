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

    function executeCallback(bytes32[] calldata ids, int256[] calldata balanceChanges, bytes calldata) external {
        for (uint256 i = 0; i < ids.length;) {
            int256 balanceChange = balanceChanges[i];

            if (balanceChange > 0) {
                address id = address(uint160(uint256(ids[i])));

                if (id == address(token0)) {
                    token0.mint(msg.sender, uint256(balanceChange));
                } else if (id == address(token1)) {
                    token1.mint(msg.sender, uint256(balanceChange));
                } else if (ids[i] != bytes32(0)) {
                    engine.transfer(
                        msg.sender, abi.encode(Positions.ILRTATransferDetails(ids[i], uint256(balanceChange)))
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
        inputs[0] = abi.encode(Engine.CreatePairParams(address(token0), address(token1), 0));

        engine.execute(commands, inputs, address(0), 0, bytes(""));
    }

    function basicAddLiquidity() internal {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.AddLiquidity;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.AddLiquidityParams(address(token0), address(token1), 0, 0, 1e18));

        engine.execute(commands, inputs, address(this), 3, bytes(""));
    }

    function basicRemoveLiquidity() internal {
        Engine.Commands[] memory commands = new Engine.Commands[](1);
        commands[0] = Engine.Commands.RemoveLiquidity;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Engine.RemoveLiquidityParams(address(token0), address(token1), 0, 0, 1e18));

        engine.execute(commands, inputs, address(this), 3, bytes(""));
    }
}
