// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Engine} from "src/core/Engine.sol";
import {Pairs} from "src/core/Pairs.sol";

contract AccrueTest is Test, Engine(address(0)) {
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    function test_Accure_Zero() external {
        vm.pauseGasMetering();

        (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        pair.initialize(0);
        pair.addSwapLiquidity(0, 1, 1e18);

        vm.resumeGasMetering();

        _accrue(Engine.AccrueParams(pairID, 0));

        vm.pauseGasMetering();

        assertEq(pair.strikes[0].blockLast, 1);
        assertEq(pair.strikes[0].liquidity[0].swap, 1e18);

        vm.resumeGasMetering();
    }

    function test_Accure_NonZero() external {
        vm.pauseGasMetering();

        (bytes32 pairID, Pairs.Pair storage pair) = pairs.getPairAndID(address(1), address(2), 0);
        pair.initialize(0);
        pair.addSwapLiquidity(0, 1, 1e18);
        pair.addBorrowedLiquidity(0, 0.5e18);

        vm.resumeGasMetering();

        _accrue(Engine.AccrueParams(pairID, 0));

        vm.pauseGasMetering();

        assertEq(pair.strikes[0].blockLast, 1);
        assertEq(pair.strikes[0].liquidity[0].swap, 0.5e18 + 0.5e18 / 10_000);
        assertEq(pair.strikes[0].liquidity[0].borrowed, 0.5e18 - 0.5e18 / 10_000);

        vm.resumeGasMetering();
    }
}
