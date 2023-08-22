// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Pairs} from "src/core/Pairs.sol";
import {BitMaps} from "src/core/BitMaps.sol";
import {MAX_STRIKE, MIN_STRIKE} from "src/core/math/StrikeMath.sol";

contract InitializeTest is Test {
    using Pairs for Pairs.Pair;
    using BitMaps for BitMaps.BitMap;

    Pairs.Pair private pair;

    function test_Initialize_Initialized() external {
        vm.pauseGasMetering();

        pair.initialize(0);

        vm.resumeGasMetering();

        vm.expectRevert();
        pair.initialize(1);
    }

    function test_Initialize_InvalidStrike() external {
        vm.expectRevert();
        pair.initialize(type(int24).max);
    }

    function test_Initialize_Zero() external {
        pair.initialize(0);

        vm.pauseGasMetering();

        assertEq(pair.strikes[MIN_STRIKE].next0To1, 0);
        assertEq(pair.strikes[MIN_STRIKE].next1To0, 0);

        assertEq(pair.strikes[MAX_STRIKE].next0To1, 0);
        assertEq(pair.strikes[MAX_STRIKE].next1To0, 0);

        assertEq(pair.strikes[0].next0To1, MIN_STRIKE);
        assertEq(pair.strikes[0].next1To0, MAX_STRIKE);

        assertEq(pair.bitMap0To1.nextBelow(0), MIN_STRIKE);
        assertEq(pair.bitMap1To0.nextBelow(0), MIN_STRIKE);

        assertEq(pair.bitMap0To1.nextBelow(MAX_STRIKE), 0);
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 0);

        vm.resumeGasMetering();
    }

    function test_Initialize_NonZero() external {
        pair.initialize(1);

        vm.pauseGasMetering();

        assertEq(pair.strikes[MIN_STRIKE].next0To1, 0);
        assertEq(pair.strikes[MIN_STRIKE].next1To0, 1);

        assertEq(pair.strikes[MAX_STRIKE].next0To1, 1);
        assertEq(pair.strikes[MAX_STRIKE].next1To0, 0);

        assertEq(pair.strikes[1].next0To1, MIN_STRIKE);
        assertEq(pair.strikes[1].next1To0, MAX_STRIKE);

        assertEq(pair.bitMap0To1.nextBelow(-1), MIN_STRIKE);
        assertEq(pair.bitMap1To0.nextBelow(1), MIN_STRIKE);

        assertEq(pair.bitMap0To1.nextBelow(MAX_STRIKE), -1);
        assertEq(pair.bitMap1To0.nextBelow(MAX_STRIKE), 1);

        vm.resumeGasMetering();
    }
}
