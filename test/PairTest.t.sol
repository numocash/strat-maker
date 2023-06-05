// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { Factory } from "src/core/Factory.sol";
import { Pair } from "src/periphery/PairAddress.sol";
import { computeAddress } from "src/periphery/PairAddress.sol";

contract PairTest is Test {
    Factory private factory;
    Pair private pair;

    function mintTest() external { }
}
