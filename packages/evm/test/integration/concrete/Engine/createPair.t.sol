// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {createCommand, createCommandInput, pushCommandInputs} from "../../../utils/Commands.sol";

import {Engine} from "src/core/Engine.sol";
import {Accounts} from "src/core/Accounts.sol";
import {NUM_SPREADS} from "src/core/Pairs.sol";

contract CreatePairTest is Test {
    event PairCreated(address indexed token0, address indexed token1, uint8 scalingFactor, int24 strikeInitial);

    Engine private engine;

    function setUp() external {
        engine = new Engine(payable(address(0)));
    }

    function test_CreatePair() external {
        vm.pauseGasMetering();
        Engine.CommandInput[] memory commandInputs = createCommandInput();
        commandInputs = pushCommandInputs(commandInputs, createCommand(address(1), address(2), 0, 0));

        // vm.expectEmit(true, true, false, true);
        // emit PairCreated(address(1), address(2), 0, 0);
        vm.resumeGasMetering();

        Accounts.Account memory account = engine.execute(address(0), commandInputs, 0, 0, bytes(""));

        vm.pauseGasMetering();

        assertEq(account.erc20Data.length, 0);
        assertEq(account.lpData.length, 0);

        (, int24[NUM_SPREADS] memory strikeCurrent, bool initialized) = engine.getPair(address(1), address(2), 0);

        assertEq(strikeCurrent[0], 0);
        assertEq(initialized, true);

        vm.resumeGasMetering();
    }
}
