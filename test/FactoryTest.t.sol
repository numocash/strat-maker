// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Factory} from "src/core/Factory.sol";
import {Pair} from "src/periphery/PairAddress.sol";
import {computeAddress} from "src/periphery/PairAddress.sol";

contract FactoryTest is Test {
    event PairCreated(address indexed token0, address indexed token1, address pair);

    Factory public factory;

    function setUp() external {
        factory = new Factory();
    }

    function testGetPair() external {
        address pair = factory.createPair(address(1), address(2));

        assertEq(pair, factory.getPair(address(1), address(2)));
        assertEq(pair, factory.getPair(address(2), address(1)));
    }

    function testSameTokenError() external {
        vm.expectRevert(Factory.SameTokenError.selector);
        factory.createPair(address(1), address(1));
    }

    function testZeroAddressError() external {
        vm.expectRevert(Factory.ZeroAddressError.selector);
        factory.createPair(address(0), address(1));

        vm.expectRevert(Factory.ZeroAddressError.selector);
        factory.createPair(address(1), address(0));
    }

    function testDeployedError() external {
        factory.createPair(address(1), address(2));

        vm.expectRevert(Factory.DeployedError.selector);
        factory.createPair(address(1), address(2));
    }

    function helpParametersZero() private {
        (address token0, address token1) = factory.parameters();

        assertEq(address(0), token0);
        assertEq(address(0), token1);
    }

    function testParameters() external {
        helpParametersZero();

        factory.createPair(address(1), address(2));

        helpParametersZero();
    }

    function testEmit() external {
        address pair = computeAddress(address(factory), address(1), address(2));

        vm.expectEmit(true, true, false, true, address(factory));
        emit PairCreated(address(1), address(2), pair);
        factory.createPair(address(1), address(2));
    }
}
