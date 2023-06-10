// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Engine} from "src/core/Engine.sol";

contract EngineTest is Test {
    event PairCreated(address indexed token0, address indexed token1, int24 tickInitial);

    Engine internal engine;

    function setUp() external {
        engine = new Engine();
    }

    // test zero token
    // test same token

    function testEngineEmit() internal {
        vm.expectEmit(true, true, false, true);
        emit PairCreated(address(1), address(2), 4);
        engine.createPair(address(1), address(2), 4);
    }
}
