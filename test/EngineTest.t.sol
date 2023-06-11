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

    function testBadToken() external {
        vm.expectRevert(Engine.InvalidTokenOrder.selector);
        engine.createPair(address(1), address(0), 0);

        vm.expectRevert(Engine.InvalidTokenOrder.selector);
        engine.createPair(address(0), address(1), 0);

        vm.expectRevert(Engine.InvalidTokenOrder.selector);
        engine.createPair(address(2), address(1), 1);

        vm.expectRevert(Engine.InvalidTokenOrder.selector);
        engine.createPair(address(1), address(1), 1);
    }

    function testEngineEmit() external {
        vm.expectEmit(true, true, false, true);
        emit PairCreated(address(1), address(2), 4);
        engine.createPair(address(1), address(2), 4);
    }
}
