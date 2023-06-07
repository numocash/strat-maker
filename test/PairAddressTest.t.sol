// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {Factory} from "src/core/Factory.sol";
import {computeAddress} from "src/periphery/PairAddress.sol";

contract PairAddressTest is Test {
    Factory public factory;

    function setUp() external {
        factory = new Factory();
    }

    function testDeployedAddress() external {
        address pair = factory.createPair(address(1), address(2));

        address estimatedPair = computeAddress(address(factory), address(1), address(2));

        assertEq(pair, estimatedPair);
    }
}
