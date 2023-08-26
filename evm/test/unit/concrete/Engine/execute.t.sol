// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Engine} from "src/core/Engine.sol";

contract ExecuteTest is Test {
    Engine private engine;

    function setUp() external {
        engine = new Engine();
    }
}
