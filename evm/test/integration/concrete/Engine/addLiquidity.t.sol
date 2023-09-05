// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {addLiquidityCommand, createCommand, createCommandInput, pushCommandInputs} from "../../../utils/Commands.sol";
import {MockERC20} from "../../../mocks/MockERC20.sol";

import {Engine} from "src/core/Engine.sol";
import {Accounts} from "src/core/Accounts.sol";
import {Pairs} from "src/core/Pairs.sol";
import {Positions, biDirectionalID} from "src/core/Positions.sol";
import {getAmount0} from "src/core/math/LiquidityMath.sol";
import {getRatioAtStrike} from "src/core/math/StrikeMath.sol";
import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";

contract AddLiquidityTest is Test, IExecuteCallback {
    event AddLiquidity(
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

    function setUp() external {
        engine = new Engine(payable(address(0)));
        mockERC20_0 = new MockERC20();
        mockERC20_1 = new MockERC20();
    }

    function executeCallback(Accounts.Account calldata, bytes calldata) external {
        if (amount0 > 0) mockERC20_0.mint(msg.sender, amount0);
        if (amount1 > 0) mockERC20_1.mint(msg.sender, amount1);
    }

    function test_AddLiquidity_Cold() external {
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

        vm.expectEmit(true, true, true, true);
        emit AddLiquidity(Pairs.getPairID(address(mockERC20_0), address(mockERC20_1), 0), 0, 1, 1e18, amount0, 0);
        vm.resumeGasMetering();

        Accounts.Account memory accounts = engine.execute(address(this), commandInputs, 2, 0, bytes(""));

        vm.pauseGasMetering();

        Pairs.Strike memory strike = engine.getStrike(address(mockERC20_0), address(mockERC20_1), 0, 0);

        assertEq(strike.blockLast, 1);
        assertEq(strike.liquidity[0].swap, 1e18);

        assertEq(accounts.erc20Data[0].token, address(mockERC20_0));
        assertEq(accounts.erc20Data[0].balanceBefore, 0);
        assertEq(accounts.erc20Data[0].balanceDelta, int256(amount0));

        assertEq(mockERC20_0.balanceOf(address(engine)), amount0);

        Positions.ILRTAData memory position =
            engine.dataOf_cGJnTo(address(this), biDirectionalID(address(mockERC20_0), address(mockERC20_1), 0, 0, 1));

        assertEq(position.balance, 1e18);

        vm.resumeGasMetering();
    }

    function test_AddLiquidity_Hot() external {
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

        vm.expectEmit(true, true, true, true);
        emit AddLiquidity(Pairs.getPairID(address(mockERC20_0), address(mockERC20_1), 0), 0, 1, 1e18, amount0, 0);
        vm.resumeGasMetering();

        Accounts.Account memory accounts = engine.execute(address(this), commandInputs, 2, 0, bytes(""));

        vm.pauseGasMetering();

        Pairs.Strike memory strike = engine.getStrike(address(mockERC20_0), address(mockERC20_1), 0, 0);

        assertEq(strike.blockLast, 1);
        assertEq(strike.liquidity[0].swap, 2e18);

        assertEq(accounts.erc20Data[0].token, address(mockERC20_0));
        assertEq(accounts.erc20Data[0].balanceBefore, amount0);
        assertEq(accounts.erc20Data[0].balanceDelta, int256(amount0));

        assertEq(mockERC20_0.balanceOf(address(engine)), 2 * amount0);

        Positions.ILRTAData memory position =
            engine.dataOf_cGJnTo(address(this), biDirectionalID(address(mockERC20_0), address(mockERC20_1), 0, 0, 1));

        assertEq(position.balance, 2e18);

        vm.resumeGasMetering();
    }
}
