// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {
    addLiquidityCommand,
    borrowLiquidityCommand,
    repayLiquidityCommand,
    createCommand,
    createCommandInput,
    pushCommandInputs
} from "../../../utils/Commands.sol";
import {MockERC20} from "../../../mocks/MockERC20.sol";

import {Engine} from "src/core/Engine.sol";
import {Accounts} from "src/core/Accounts.sol";
import {Pairs} from "src/core/Pairs.sol";
import {Positions, debtID} from "src/core/Positions.sol";
import {getAmount0} from "src/core/math/LiquidityMath.sol";
import {getRatioAtStrike} from "src/core/math/StrikeMath.sol";
import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";

contract RepayLiquidityTest is Test, IExecuteCallback {
    Engine private engine;
    MockERC20 private mockERC20_0;
    MockERC20 private mockERC20_1;

    uint256 private amount0;
    uint256 private amount1;

    bytes32 private id;
    uint128 private amountPosition;
    uint128 private amountBuffer;

    function setUp() external {
        engine = new Engine(address(0));
        mockERC20_0 = new MockERC20();
        mockERC20_1 = new MockERC20();
    }

    function executeCallback(Accounts.Account calldata, bytes calldata) external {
        if (amount0 > 0) mockERC20_0.mint(msg.sender, amount0);
        if (amount1 > 0) mockERC20_1.mint(msg.sender, amount1);

        engine.transfer_AjLAUd(
            msg.sender, Positions.ILRTATransferDetails(id, Engine.OrderType.Debt, amountPosition, amountBuffer)
        );
    }

    function test_RepayLiquidity_Full() external {
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

        engine.execute(address(this), commandInputs, 1, 0, bytes(""));

        delete commandInputs;
        delete amount0;
        delete amount1;

        commandInputs = pushCommandInputs(
            commandInputs,
            borrowLiquidityCommand(
                address(mockERC20_0), address(mockERC20_1), 0, 0, Engine.TokenSelector.Token1, 1e18, 0.5e18
            )
        );

        amount1 = 1e18;

        engine.execute(address(this), commandInputs, 2, 0, bytes(""));

        delete commandInputs;
        delete amount0;
        delete amount1;

        commandInputs = pushCommandInputs(
            commandInputs,
            repayLiquidityCommand(
                address(mockERC20_0), address(mockERC20_1), 0, 0, Engine.TokenSelector.Token1, 0.5e18, 0.5e18
            )
        );

        id = debtID(address(mockERC20_0), address(mockERC20_1), 0, 0, Engine.TokenSelector.Token1);
        amountPosition = 0.5e18;
        amountBuffer = 0.5e18;
        amount0 = 0.5e18;

        vm.resumeGasMetering();

        Accounts.Account memory accounts = engine.execute(address(this), commandInputs, 2, 1, bytes(""));

        vm.pauseGasMetering();

        Pairs.Strike memory strike = engine.getStrike(address(mockERC20_0), address(mockERC20_1), 0, 0);

        assertEq(strike.blockLast, 1);
        assertEq(strike.liquidity[0].swap, 1e18);

        assertEq(accounts.erc20Data[0].token, address(mockERC20_0));
        assertEq(accounts.erc20Data[0].balanceBefore, 0.5e18 + 1);
        assertEq(accounts.erc20Data[0].balanceDelta, int256(getAmount0(0.5e18, getRatioAtStrike(0), 0, true)));

        assertEq(accounts.erc20Data[1].token, address(mockERC20_1));
        assertEq(accounts.erc20Data[1].balanceBefore, 0);
        assertEq(accounts.erc20Data[0].balanceDelta, int256(getAmount0(0.5e18, getRatioAtStrike(0), 0, true)));

        assertEq(mockERC20_0.balanceOf(address(engine)), 1e18 + 1);
        assertEq(mockERC20_1.balanceOf(address(engine)), 0);

        Positions.ILRTAData memory position = engine.dataOf_cGJnTo(
            address(this), debtID(address(mockERC20_0), address(mockERC20_1), 0, 0, Engine.TokenSelector.Token1)
        );

        assertEq(position.balance, 0);
        assertEq(position.buffer, 0);

        position = engine.dataOf_cGJnTo(
            address(engine), debtID(address(mockERC20_0), address(mockERC20_1), 0, 0, Engine.TokenSelector.Token1)
        );

        assertEq(position.balance, 0);
        assertEq(position.buffer, 0);

        vm.resumeGasMetering();
    }

    function test_RepayLiquidity_Partial() external {
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

        engine.execute(address(this), commandInputs, 1, 0, bytes(""));

        delete commandInputs;
        delete amount0;
        delete amount1;

        commandInputs = pushCommandInputs(
            commandInputs,
            borrowLiquidityCommand(
                address(mockERC20_0), address(mockERC20_1), 0, 0, Engine.TokenSelector.Token1, 1e18, 0.5e18
            )
        );

        amount1 = 1e18;

        engine.execute(address(this), commandInputs, 2, 0, bytes(""));

        delete commandInputs;
        delete amount0;
        delete amount1;

        commandInputs = pushCommandInputs(
            commandInputs,
            repayLiquidityCommand(
                address(mockERC20_0), address(mockERC20_1), 0, 0, Engine.TokenSelector.Token1, 0.25e18, 0.25e18
            )
        );

        id = debtID(address(mockERC20_0), address(mockERC20_1), 0, 0, Engine.TokenSelector.Token1);
        amountPosition = 0.25e18;
        amountBuffer = 0.25e18;
        amount0 = 0.25e18;

        vm.resumeGasMetering();

        Accounts.Account memory accounts = engine.execute(address(this), commandInputs, 2, 1, bytes(""));

        vm.pauseGasMetering();

        Pairs.Strike memory strike = engine.getStrike(address(mockERC20_0), address(mockERC20_1), 0, 0);

        assertEq(strike.blockLast, 1);
        assertEq(strike.liquidity[0].swap, 0.75e18);

        assertEq(accounts.erc20Data[0].token, address(mockERC20_0));
        assertEq(accounts.erc20Data[0].balanceBefore, 0.5e18 + 1);
        assertEq(accounts.erc20Data[0].balanceDelta, int256(getAmount0(0.25e18, getRatioAtStrike(0), 0, true)));

        assertEq(accounts.erc20Data[1].token, address(mockERC20_1));
        assertEq(accounts.erc20Data[1].balanceBefore, 0);
        assertEq(accounts.erc20Data[0].balanceDelta, int256(getAmount0(0.25e18, getRatioAtStrike(0), 0, true)));

        assertEq(mockERC20_0.balanceOf(address(engine)), 0.75e18 + 1);
        assertEq(mockERC20_1.balanceOf(address(engine)), 0.5e18);

        Positions.ILRTAData memory position = engine.dataOf_cGJnTo(
            address(this), debtID(address(mockERC20_0), address(mockERC20_1), 0, 0, Engine.TokenSelector.Token1)
        );

        assertEq(position.balance, 0.25e18);
        assertEq(position.buffer, 0.25e18);

        position = engine.dataOf_cGJnTo(
            address(engine), debtID(address(mockERC20_0), address(mockERC20_1), 0, 0, Engine.TokenSelector.Token1)
        );

        assertEq(position.balance, 0);
        assertEq(position.buffer, 0);

        vm.resumeGasMetering();
    }
}
