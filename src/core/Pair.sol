// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Tick} from "./libraries/Tick.sol";
import {Tier} from "./libraries/Tier.sol";
import {Position} from "./libraries/Position.sol";

contract Pair {
    using Tick for mapping(bytes32 => Tick.Info);
    using Tier for mapping(uint8 => Tier.Info);
    using Position for mapping(bytes32 => Position.Info);

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    uint24 tick;
    uint256 composition;
    // tier => uint8 tickOffset

    mapping(bytes32 tickID => Tick.Info) public ticks;
    mapping(uint8 spreadTier => Tier.Info) public tiers;
    mapping(bytes32 positionID => Position.Info) public positions;

    constructor(address _factory, address _token0, address _token1) {
        factory = _factory;
        token0 = _token0;
        token1 = _token1;
    }

    // mint
    // burn
    // swap
}
