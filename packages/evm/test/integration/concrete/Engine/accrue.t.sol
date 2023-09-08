// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {
    accrueCommand,
    addLiquidityCommand,
    createCommand,
    createCommandInput,
    pushCommandInputs
} from "../../../utils/Commands.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Engine} from "src/core/Engine.sol";
import {Accounts} from "src/core/Accounts.sol";
import {Pairs} from "src/core/Pairs.sol";
import {getAmount0} from "src/core/math/LiquidityMath.sol";
import {getRatioAtStrike} from "src/core/math/StrikeMath.sol";

contract AccrueTest is Test {
    event Accrue(bytes32 indexed pairID, int24 indexed strike, uint136 liquidityAccrued);

    Engine private engine;
    MockERC20 private mockERC20_0;
    MockERC20 private mockERC20_1;

    uint256 private amount0;
    uint256 private amount1;

    function executeCallback(Accounts.Account calldata, bytes calldata) external {
        if (amount0 > 0) mockERC20_0.mint(msg.sender, amount0);
        if (amount1 > 0) mockERC20_1.mint(msg.sender, amount1);
    }

    function setUp() external {
        engine = new Engine(payable(address(0)));
        mockERC20_0 = new MockERC20("Mock ERC20", "MOCK", 18);
        mockERC20_1 = new MockERC20("Mock ERC20", "MOCK", 18);
    }

    function test_Accrue_Zero() external {
        vm.pauseGasMetering();

        // Create pair
        Engine.CommandInput[] memory commandInputs = createCommandInput();
        commandInputs =
            pushCommandInputs(commandInputs, createCommand(address(mockERC20_0), address(mockERC20_1), 0, 0));

        engine.execute(address(0), commandInputs, 0, 0, bytes(""));

        delete commandInputs;

        // Add liquidity

        commandInputs = pushCommandInputs(
            commandInputs, addLiquidityCommand(address(mockERC20_0), address(mockERC20_1), 0, 0, 1, 1e18)
        );

        amount0 = getAmount0(1e18, getRatioAtStrike(0), 0, true);

        engine.execute(address(0), commandInputs, 2, 0, bytes(""));

        delete commandInputs;
        delete amount0;

        // Accrue
        commandInputs =
            pushCommandInputs(commandInputs, accrueCommand(address(mockERC20_0), address(mockERC20_1), 0, 0));

        vm.expectEmit(true, true, false, true);
        emit Accrue(Pairs.getPairID(address(mockERC20_0), address(mockERC20_1), 0), 0, 0);

        vm.resumeGasMetering();

        Accounts.Account memory account = engine.execute(address(0), commandInputs, 0, 0, bytes(""));

        vm.pauseGasMetering();

        assertEq(account.erc20Data.length, 0);
        assertEq(account.lpData.length, 0);

        Pairs.Strike memory strike = engine.getStrike(address(mockERC20_0), address(mockERC20_1), 0, 0);

        assertEq(strike.blockLast, 1);
        assertEq(strike.liquidity[0].swap, 1e18);
        assertEq(strike.liquidity[0].borrowed, 0);

        vm.resumeGasMetering();
    }

    function test_Accrue_NonZero() external {
        vm.skip(true);
    }
}
