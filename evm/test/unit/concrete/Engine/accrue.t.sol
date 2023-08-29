// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {accrueCommand, createCommand, createCommandInput, pushCommandInputs} from "../../../utils/Commands.sol";

import {Engine} from "src/core/Engine.sol";
import {Accounts} from "src/core/Accounts.sol";
import {Pairs} from "src/core/Pairs.sol";

contract AccrueTest is Test {
    event Accrue(bytes32 indexed pairID, int24 indexed strike, uint136 liquidityAccrued);

    Engine private engine;

    function setUp() external {
        engine = new Engine();
    }

    function test_Accrue_Zero() external {
        vm.pauseGasMetering();

        Engine.CommandInput[] memory commandInputs = createCommandInput();
        commandInputs = pushCommandInputs(commandInputs, createCommand(address(1), address(2), 0, 0));

        engine.execute(address(0), commandInputs, 0, 0, bytes(""));

        delete commandInputs;

        commandInputs = pushCommandInputs(commandInputs, accrueCommand(address(1), address(2), 0, 0));

        vm.expectEmit(true, true, false, true);
        emit Accrue(Pairs.getPairID(address(1), address(2), 0), 0, 0);

        vm.resumeGasMetering();

        Accounts.Account memory account = engine.execute(address(0), commandInputs, 0, 0, bytes(""));

        vm.pauseGasMetering();

        assertEq(account.erc20Data.length, 0);
        assertEq(account.lpData.length, 0);

        Pairs.Strike memory strike = engine.getStrike(address(1), address(2), 0, 0);

        assertEq(strike.blockLast, 1);

        vm.resumeGasMetering();
    }

    function test_Accrue_NonZero() external {}
}
