// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Engine} from "src/core/Engine.sol";
import {Pairs} from "src/core/Pairs.sol";

contract GetStrikeTest is Test, Engine(address(0)) {
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    function test_GetStrike_Empty() external {
        Pairs.Strike memory strike = this.getStrike(address(0), address(0), 0, 0);

        vm.pauseGasMetering();

        assertEq(strike.liquidity[0].swap, 0);
        assertEq(strike.blockLast, 0);
        assertEq(strike.reference0To1, 0);
        assertEq(strike.next0To1, 0);

        vm.resumeGasMetering();
    }

    function test_GetStrike_NonEmpty() external {
        vm.pauseGasMetering();

        (, Pairs.Pair storage pair) = pairs.getPairAndID(address(0), address(0), 0);

        pair.strikes[0].liquidity[0].swap = 1e18;
        pair.strikes[0].liquidity[2].swap = 1e18;
        pair.strikes[0].liquidity[4].swap = 1e18;

        pair.strikes[0].activeSpread = 3;

        vm.resumeGasMetering();

        Pairs.Strike memory strike = this.getStrike(address(0), address(0), 0, 0);

        assertEq(strike.liquidity[0].swap, 1e18);
        assertEq(strike.liquidity[1].swap, 0);
        assertEq(strike.liquidity[2].swap, 1e18);
        assertEq(strike.liquidity[3].swap, 0);
        assertEq(strike.liquidity[4].swap, 1e18);

        assertEq(strike.activeSpread, 3);
    }
}
