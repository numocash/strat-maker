// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

// import {Test} from "forge-std/Test.sol";

// import {Engine} from "src/core/Engine.sol";

// contract EngineTest is Test {
//     event PairCreated(address indexed token0, address indexed token1, int24 tickInitial);

//     Engine internal engine;

//     function setUp() external {
//         engine = new Engine();
//     }

//     function testBadToken() external {
//         vm.expectRevert(Engine.InvalidTokenOrder.selector);
//         engine.createPair(address(1), address(0), 0);

//         vm.expectRevert(Engine.InvalidTokenOrder.selector);
//         engine.createPair(address(0), address(1), 0);

//         vm.expectRevert(Engine.InvalidTokenOrder.selector);
//         engine.createPair(address(2), address(1), 1);

//         vm.expectRevert(Engine.InvalidTokenOrder.selector);
//         engine.createPair(address(1), address(1), 1);
//     }

//     function testEngineEmit() external {
//         vm.expectEmit(true, true, false, true);
//         emit PairCreated(address(1), address(2), 4);
//         engine.createPair(address(1), address(2), 4);
//     }
// }

// contract InitializationTest is Test {
//     Engine internal engine;

//     function setUp() external {
//         engine = new Engine();
//     }

//     function testInitialize() external {
//         engine.createPair(address(1), address(2), 5);

//         (, int24 tickCurrent,, uint8 lock) = engine.getPair(address(1), address(2));

//         assertEq(tickCurrent, 5);
//         assertEq(lock, 1);
//     }

//     function testInitializeTickMaps() external {
//         engine.createPair(address(1), address(2), 0);

//         Ticks.Tick memory tick = engine.getTick(address(1), address(2), 0);
//         assertEq(tick.next0To1, MIN_TICK);
//         assertEq(tick.next1To0, MAX_TICK);

//         tick = engine.getTick(address(1), address(2), MAX_TICK);
//         assertEq(tick.next0To1, 0);

//         tick = engine.getTick(address(1), address(2), MIN_TICK);
//         assertEq(tick.next1To0, 0);
//     }

//     function testInitializeDouble() external {
//         engine.createPair(address(1), address(2), 5);
//         vm.expectRevert(Pairs.Initialized.selector);
//         engine.createPair(address(1), address(2), 5);
//     }

//     function testInitializeBadTick() external {
//         vm.expectRevert(Pairs.InvalidTick.selector);
//         engine.createPair(address(1), address(2), type(int24).max);
//     }
// }
