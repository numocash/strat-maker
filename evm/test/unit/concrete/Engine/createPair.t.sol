// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Engine} from "src/core/Engine.sol";
import {Pairs} from "src/core/Pairs.sol";
import {MIN_STRIKE, MAX_STRIKE} from "src/core/math/StrikeMath.sol";

contract CreatePairTest is Test, Engine(payable(address(0))) {
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    function test_CreatePair_ZeroScale() external {
        _createPair(Engine.CreatePairParams(address(1), address(2), 0, 0));

        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);

        assertEq(pair.initialized, true);

        vm.resumeGasMetering();
    }

    function test_CreatePair_Scale() external {
        _createPair(Engine.CreatePairParams(address(1), address(2), 8, 0));

        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 8);

        assertEq(pair.initialized, true);

        vm.resumeGasMetering();
    }

    function test_CreatePair_ZeroInitial() external {
        _createPair(Engine.CreatePairParams(address(1), address(2), 0, 0));

        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);

        assertEq(pair.strikes[0].next0To1, MIN_STRIKE);
        assertEq(pair.strikes[0].next1To0, MAX_STRIKE);

        vm.resumeGasMetering();
    }

    function test_CreatePair_Initial() external {
        _createPair(Engine.CreatePairParams(address(1), address(2), 0, 32));

        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);

        assertEq(pair.strikes[32].next0To1, MIN_STRIKE);
        assertEq(pair.strikes[32].next1To0, MAX_STRIKE);

        vm.resumeGasMetering();
    }

    function test_CreatePair_ZeroToken() external {
        vm.expectRevert(Engine.InvalidTokenOrder.selector);
        _createPair(Engine.CreatePairParams(address(0), address(1), 0, 0));
    }

    function test_CreatePair_InvalidOrder() external {
        vm.expectRevert(Engine.InvalidTokenOrder.selector);
        _createPair(Engine.CreatePairParams(address(2), address(1), 0, 0));
    }
}
