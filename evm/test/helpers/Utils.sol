// // SPDX-License-Identifier: GPL-3.0-only
// pragma solidity ^0.8.0;

// import {Engine} from "src/core/Engine.sol";

// function createCommand(
//     address token0,
//     address token1,
//     uint8 scalingFactor,
//     int24 tickInitial
// )
//     pure
//     returns (Engine.Commands command, bytes memory input)
// {
//     return (Engine.Commands.CreatePair, abi.encode(Engine.CreatePairParams(token0, token1, scalingFactor,
// tickInitial)));
// }

// function borrowLiquidityCommand(
//     address token0,
//     address token1,
//     uint8 scalingFactor,
//     int24 strike,
//     Engine.TokenSelector selectorCollateral,
//     uint256 amountDesiredCollateral,
//     uint128 amountDesiredDebt
// )
//     pure
//     returns (Engine.Commands command, bytes memory input)
// {
//     return (
//         Engine.Commands.BorrowLiquidity,
//         abi.encode(
//             Engine.BorrowLiquidityParams(
//                 token0, token1, scalingFactor, strike, selectorCollateral, amountDesiredCollateral, amountDesiredDebt
//             )
//             )
//     );
// }

// function repayLiquidityCommand(
//     address token0,
//     address token1,
//     uint8 scalingFactor,
//     int24 strike,
//     Engine.TokenSelector selectorCollateral,
//     uint256 leverageRatioX128,
//     uint128 amountDesiredDebt
// )
//     pure
//     returns (Engine.Commands command, bytes memory input)
// {
//     return (
//         Engine.Commands.RepayLiquidity,
//         abi.encode(
//             Engine.RepayLiquidityParams(
//                 token0, token1, scalingFactor, strike, selectorCollateral, leverageRatioX128, amountDesiredDebt
//             )
//             )
//     );
// }

// function addLiquidityCommand(
//     address token0,
//     address token1,
//     uint8 scalingFactor,
//     int24 strike,
//     uint8 spread,
//     uint128 amountDesired
// )
//     pure
//     returns (Engine.Commands command, bytes memory input)
// {
//     return (
//         Engine.Commands.AddLiquidity,
//         abi.encode(Engine.AddLiquidityParams(token0, token1, scalingFactor, strike, spread, amountDesired))
//     );
// }

// function removeLiquidityCommand(
//     address token0,
//     address token1,
//     uint8 scalingFactor,
//     int24 strike,
//     uint8 spread,
//     uint128 amountDesired
// )
//     pure
//     returns (Engine.Commands command, bytes memory input)
// {
//     return (
//         Engine.Commands.RemoveLiquidity,
//         abi.encode(Engine.RemoveLiquidityParams(token0, token1, scalingFactor, strike, spread, amountDesired))
//     );
// }

// function swapCommand(
//     address token0,
//     address token1,
//     uint8 scalingFactor,
//     Engine.SwapTokenSelector selector,
//     int256 amountDesired
// )
//     pure
//     returns (Engine.Commands command, bytes memory input)
// {
//     return (Engine.Commands.Swap, abi.encode(Engine.SwapParams(token0, token1, scalingFactor, selector,
// amountDesired)));
// }

// function createCommands() pure returns (Engine.Commands[] memory commands) {
//     return new Engine.Commands[](0);
// }

// function createInputs() pure returns (bytes[] memory inputs) {
//     return new bytes[](0);
// }

// function pushCommands(
//     Engine.Commands[] memory commands,
//     Engine.Commands command
// )
//     pure
//     returns (Engine.Commands[] memory)
// {
//     Engine.Commands[] memory newCommands = new Engine.Commands[](commands.length +1);

//     for (uint256 i = 0; i < commands.length; i++) {
//         newCommands[i] = commands[i];
//     }

//     newCommands[commands.length] = command;

//     return newCommands;
// }

// function pushInputs(bytes[] memory inputs, bytes memory input) pure returns (bytes[] memory) {
//     bytes[] memory newInputs = new bytes[](inputs.length + 1);

//     for (uint256 i = 0; i < inputs.length; i++) {
//         newInputs[i] = inputs[i];
//     }

//     newInputs[inputs.length] = input;

//     return newInputs;
// }
