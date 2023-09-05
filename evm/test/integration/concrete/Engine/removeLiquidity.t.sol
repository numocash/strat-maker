// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {
    addLiquidityCommand,
    removeLiquidityCommand,
    createCommand,
    createCommandInput,
    pushCommandInputs
} from "../../../utils/Commands.sol";
import {MockERC20} from "../../../mocks/MockERC20.sol";

import {Engine} from "src/core/Engine.sol";
import {Accounts} from "src/core/Accounts.sol";
import {Pairs} from "src/core/Pairs.sol";
import {Positions, biDirectionalID} from "src/core/Positions.sol";
import {getAmount0} from "src/core/math/LiquidityMath.sol";
import {getRatioAtStrike} from "src/core/math/StrikeMath.sol";
import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";

contract RemoveLiquidityTest is Test, IExecuteCallback {
    event RemoveLiquidity(
        bytes32 indexed pairID,
        int24 indexed strike,
        uint8 indexed spread,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    Engine private engine;
    MockERC20 private mockERC20_0;
    MockERC20 private mockERC20_1;

    uint256 private amount0;
    uint256 private amount1;

    bytes32 private id;
    uint128 private amountPosition;
    uint128 private amountBuffer;

    function setUp() external {
        engine = new Engine(payable(address(0)));
        mockERC20_0 = new MockERC20();
        mockERC20_1 = new MockERC20();
    }

    function executeCallback(Accounts.Account calldata, bytes calldata) external {
        if (amount0 > 0) mockERC20_0.mint(msg.sender, amount0);
        if (amount1 > 0) mockERC20_1.mint(msg.sender, amount1);

        engine.transfer_oHLEec(msg.sender, Positions.ILRTATransferDetails(id, amountPosition));
    }

    function test_RemoveLiquidityFull() external {
        vm.pauseGasMetering();
        Engine.CommandInput[] memory commandInputs = createCommandInput();
        commandInputs =
            pushCommandInputs(commandInputs, createCommand(address(mockERC20_0), address(mockERC20_1), 0, 0));

        engine.execute(address(0), commandInputs, 0, 0, bytes(""));

        delete commandInputs;

        commandInputs = pushCommandInputs(
            commandInputs, addLiquidityCommand(address(mockERC20_0), address(mockERC20_1), 0, 0, 1, 1e18)
        );

        amount0 = getAmount0(1e18, getRatioAtStrike(0), 0, true);

        engine.execute(address(this), commandInputs, 2, 0, bytes(""));

        delete commandInputs;
        delete amount0;
        delete amount1;

        commandInputs = pushCommandInputs(
            commandInputs, removeLiquidityCommand(address(mockERC20_0), address(mockERC20_1), 0, 0, 1, 1e18)
        );

        id = biDirectionalID(address(mockERC20_0), address(mockERC20_1), 0, 0, 1);

        amountPosition = 1e18;

        // vm.expectEmit(true, true, true, true);
        // emit RemoveLiquidity(id, 2, 1, 1e18, getAmount0(1e18, getRatioAtStrike(2), 0, false), 0);
        vm.resumeGasMetering();

        Accounts.Account memory accounts = engine.execute(address(this), commandInputs, 2, 1, bytes(""));

        vm.pauseGasMetering();

        Pairs.Strike memory strike = engine.getStrike(address(mockERC20_0), address(mockERC20_1), 0, 0);

        assertEq(strike.blockLast, 1);
        assertEq(strike.liquidity[0].swap, 0);

        assertEq(accounts.erc20Data[0].token, address(mockERC20_0));
        assertEq(accounts.erc20Data[0].balanceBefore, 0);
        assertEq(accounts.erc20Data[0].balanceDelta, -int256(getAmount0(1e18, getRatioAtStrike(0), 0, false)));

        assertEq(accounts.lpData[0].id, id);
        assertEq(accounts.lpData[0].amountBurned, 1e18);

        assertEq(mockERC20_0.balanceOf(address(engine)), 1);

        Positions.ILRTAData memory position = engine.dataOf_cGJnTo(address(this), id);

        assertEq(position.balance, 0);

        position = engine.dataOf_cGJnTo(address(engine), id);

        assertEq(position.balance, 0);

        vm.resumeGasMetering();
    }

    function test_RemoveLiquidityPartial() external {
        vm.pauseGasMetering();
        Engine.CommandInput[] memory commandInputs = createCommandInput();
        commandInputs =
            pushCommandInputs(commandInputs, createCommand(address(mockERC20_0), address(mockERC20_1), 0, 0));

        engine.execute(address(0), commandInputs, 0, 0, bytes(""));

        delete commandInputs;

        commandInputs = pushCommandInputs(
            commandInputs, addLiquidityCommand(address(mockERC20_0), address(mockERC20_1), 0, 0, 1, 1e18)
        );

        amount0 = getAmount0(1e18, getRatioAtStrike(0), 0, true);

        engine.execute(address(this), commandInputs, 2, 0, bytes(""));

        delete commandInputs;
        delete amount0;
        delete amount1;

        commandInputs = pushCommandInputs(
            commandInputs, removeLiquidityCommand(address(mockERC20_0), address(mockERC20_1), 0, 0, 1, 0.5e18)
        );

        id = biDirectionalID(address(mockERC20_0), address(mockERC20_1), 0, 0, 1);

        amountPosition = 0.5e18;

        // vm.expectEmit(true, true, true, true);
        // emit RemoveLiquidity(id, 2, 1, 1e18, getAmount0(1e18, getRatioAtStrike(2), 0, false), 0);
        vm.resumeGasMetering();

        Accounts.Account memory accounts = engine.execute(address(this), commandInputs, 2, 1, bytes(""));

        vm.pauseGasMetering();

        Pairs.Strike memory strike = engine.getStrike(address(mockERC20_0), address(mockERC20_1), 0, 0);

        assertEq(strike.blockLast, 1);
        assertEq(strike.liquidity[0].swap, 0.5e18);

        assertEq(accounts.erc20Data[0].token, address(mockERC20_0));
        assertEq(accounts.erc20Data[0].balanceBefore, 0);
        assertEq(accounts.erc20Data[0].balanceDelta, -int256(getAmount0(0.5e18, getRatioAtStrike(0), 0, false)));

        assertEq(accounts.lpData[0].id, id);
        assertEq(accounts.lpData[0].amountBurned, 0.5e18);

        assertEq(mockERC20_0.balanceOf(address(engine)), getAmount0(0.5e18, getRatioAtStrike(0), 0, true) + 1);

        Positions.ILRTAData memory position = engine.dataOf_cGJnTo(address(this), id);

        assertEq(position.balance, 0.5e18);

        position = engine.dataOf_cGJnTo(address(engine), id);

        assertEq(position.balance, 0);

        vm.resumeGasMetering();
    }
}
