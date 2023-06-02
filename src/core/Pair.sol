// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Tick} from "./Tick.sol";
import {Tier} from "./Tier.sol";
import {Position} from "./Position.sol";
import {Factory} from "./Factory.sol";

contract Pair {
    using Tick for mapping(bytes32 => Tick.Info);
    using Tier for mapping(uint8 => Tier.Info);
    using Position for mapping(bytes32 => Position.Info);

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    /**
     * @custom:team This is where we should add the offsets of each tier, i.e. an int8 that shows how far each the
     * current tick of a tier is away from the global current tick
     */
    struct Slot0 {
        uint96 composition;
        uint24 tick;
    }

    Slot0 public slot0;

    mapping(bytes32 tickID => Tick.Info) public ticks;
    mapping(uint8 tierID => Tier.Info) public tiers;
    mapping(bytes32 positionID => Position.Info) public positions;

    constructor() {
        factory = msg.sender;
        (token0, token1) = Factory(msg.sender).paramters();
    }

    function mint(
        address to,
        int24 tickLower,
        int24 tickUpper,
        uint256 amountLiquidity
    )
        external
        returns (uint256 amount0, uint256 amount1)
    {
        // check ticks
        // check tier
        // check amount

        // determine amounts
        // update state: ticks, liquidity, position
        // recieve amounts
    }

    // burn
    // swap
}
