// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Engine} from "src/core/Engine.sol";
import {Pairs, NUM_SPREADS} from "src/core/Pairs.sol";

contract GetPairTest is Test, Engine {
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    function test_GetPair_Empty() external {
        (uint128[NUM_SPREADS] memory composition, int24[NUM_SPREADS] memory strikeCurrent, bool initialized) =
            this.getPair(address(0), address(0), 0);

        vm.pauseGasMetering();

        assertEq(composition[0], 0);
        assertEq(strikeCurrent[0], 0);
        assertEq(initialized, false);

        vm.resumeGasMetering();
    }

    function test_GetPair_NonEmpty() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(0), address(0), 0);
        pair.initialize(0);

        pair.composition[0] = type(uint128).max;
        pair.composition[2] = type(uint128).max;
        pair.composition[4] = type(uint128).max;

        vm.resumeGasMetering();

        (uint128[NUM_SPREADS] memory composition, int24[NUM_SPREADS] memory strikeCurrent, bool initialized) =
            this.getPair(address(0), address(0), 0);

        assertEq(composition[0], type(uint128).max);
        assertEq(composition[1], 0);
        assertEq(composition[2], type(uint128).max);
        assertEq(composition[3], 0);
        assertEq(composition[4], type(uint128).max);
        assertEq(strikeCurrent[0], 0);
        assertEq(initialized, true);
    }
}
