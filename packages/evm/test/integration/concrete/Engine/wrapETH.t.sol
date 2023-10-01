// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {wrapCommand, createCommandInput, pushCommandInputs} from "../../../utils/Commands.sol";

import {Engine} from "src/core/Engine.sol";
import {Accounts} from "src/core/Accounts.sol";

import {WETH} from "solmate/src/tokens/WETH.sol";

contract WrapWETHTest is Test {
    Engine private engine;
    WETH private weth;

    function executeCallback(Accounts.Account calldata, bytes calldata) external {}

    function setUp() external {
        weth = new WETH();
        engine = new Engine(payable(address(weth)));
    }

    function test_WrapWETH() external {
        vm.pauseGasMetering();

        // Create pair
        Engine.CommandInput[] memory commandInputs = createCommandInput();
        commandInputs = pushCommandInputs(commandInputs, wrapCommand());

        vm.deal(address(this), 1e18);

        vm.resumeGasMetering();

        Accounts.Account memory account = engine.execute{value: 1e18}(address(this), commandInputs, 1, 0, bytes(""));

        vm.pauseGasMetering();

        assertEq(address(this).balance, 0);
        assertEq(address(engine).balance, 0);
        assertEq(address(weth).balance, 1e18);

        assertEq(weth.balanceOf(address(this)), 1e18);
        assertEq(weth.balanceOf(address(engine)), 0);

        assertEq(account.erc20Data[0].token, address(weth));
        assertEq(account.erc20Data[0].balanceDelta, -1e18);

        vm.resumeGasMetering();
    }
}
