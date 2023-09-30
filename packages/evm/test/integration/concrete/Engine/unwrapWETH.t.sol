// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {wrapCommand, unwrapCommand, createCommandInput, pushCommandInputs} from "../../../utils/Commands.sol";

import {Engine} from "src/core/Engine.sol";
import {Accounts} from "src/core/Accounts.sol";

import {WETH} from "solmate/src/tokens/WETH.sol";

contract UnwrapWETHTest is Test {
    Engine private engine;
    WETH private weth;

    uint256 private amount;

    function executeCallback(Accounts.Account calldata, bytes calldata) external {
        weth.transfer(msg.sender, amount);
    }

    function setUp() external {
        weth = new WETH();
        engine = new Engine(payable(address(weth)));
    }

    receive() external payable {}

    function test_UnwrapWETH() external {
        vm.pauseGasMetering();

        // Create pair
        Engine.CommandInput[] memory commandInputs = createCommandInput();
        commandInputs = pushCommandInputs(commandInputs, wrapCommand());

        vm.deal(address(this), 1e18);

        commandInputs = pushCommandInputs(commandInputs, unwrapCommand(0));

        vm.resumeGasMetering();

        Accounts.Account memory account = engine.execute{value: 1e18}(address(this), commandInputs, 1, 0, bytes(""));

        vm.pauseGasMetering();

        assertEq(address(this).balance, 1e18);
        assertEq(address(engine).balance, 0);
        assertEq(address(weth).balance, 0);

        assertEq(weth.balanceOf(address(this)), 0);
        assertEq(weth.balanceOf(address(engine)), 0);

        assertEq(account.erc20Data[0].token, address(weth));
        assertEq(account.erc20Data[0].balanceDelta, 0);

        vm.resumeGasMetering();
    }
}
