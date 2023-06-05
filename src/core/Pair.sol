// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import { Tick } from "./Tick.sol";
import { Tier } from "./Tier.sol";
import { Position } from "./Position.sol";
import { Factory } from "./Factory.sol";
import { MIN_TICK, MAX_TICK } from "./TickMath.sol";
import { addDelta, calcAmountsForLiquidity } from "./LiquidityMath.sol";
import { SafeTransferLib } from "src/SafeTransferLib.sol";
import { BalanceLib } from "src/BalaneLib.sol";
import { IMintCallback } from "./interfaces/IMintCallback.sol";

contract Pair {
    using Tick for mapping(bytes32 => Tick.Info);
    using Tier for mapping(uint8 => Tier.Info);
    using Position for mapping(bytes32 => Position.Info);

    error InvalidTick();
    error InvalidTier();

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    /**
     * @custom:team This is where we should add the offsets of each tier, i.e. an int8 that shows how far each the
     * current tick of a tier is away from the global current tick
     */
    struct Slot0 {
        uint96 composition;
        int24 tick;
    }

    Slot0 public slot0;

    mapping(bytes32 tickID => Tick.Info) public ticks;
    mapping(uint8 tierID => Tier.Info) public tiers;
    mapping(bytes32 positionID => Position.Info) public positions;

    constructor() {
        factory = msg.sender;
        (token0, token1) = Factory(msg.sender).parameters();
    }

    function mint(
        address to,
        uint8 tierID,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        bytes calldata data
    )
        external
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = updateLiquidity(to, tierID, tickLower, tickUpper, int256(liquidity));

        uint256 balance0 = BalanceLib.getBalance(token0);
        uint256 balance1 = BalanceLib.getBalance(token1);
        IMintCallback(msg.sender).mintCallback(token0, token1, amount0, amount1, data);
        if (BalanceLib.getBalance(token0) < balance0 + amount0) revert();
        if (BalanceLib.getBalance(token1) < balance1 + amount1) revert();

        // emit
    }

    function burn(
        address to,
        uint8 tierID,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity
    )
        external
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = updateLiquidity(to, tierID, tickLower, tickUpper, -int256(liquidity));

        SafeTransferLib.safeTransfer(token0, to, amount0);
        SafeTransferLib.safeTransfer(token1, to, amount1);

        // emit
    }

    // swap

    function checkTickInputs(int24 tickLower, int24 tickUpper) internal pure {
        if (tickLower >= tickUpper || MIN_TICK > tickLower || tickUpper > MAX_TICK) {
            revert InvalidTick();
        }
    }

    function checkTier(uint8 tier) internal pure {
        if (tier > 3) revert InvalidTier();
    }

    function updateLiquidity(
        address to,
        uint8 tierID,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidity
    )
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        checkTickInputs(tickLower, tickUpper);
        checkTier(tierID);

        // update current liquidity if in-range
        Tier.Info storage tier = tiers.get(tierID);
        if (tickLower <= slot0.tick && slot0.tick < tickUpper) {
            tier.liquidity = addDelta(tier.liquidity, liquidity);
        }

        // update ticks
        updateTick(tierID, tickLower, liquidity, true);
        updateTick(tierID, tickUpper, liquidity, false);

        // update position
        updatePosition(to, tierID, tickLower, tickUpper, liquidity);

        // determine amounts
        (amount0, amount1) = calcAmountsForLiquidity(
            slot0.tick,
            slot0.composition,
            tickLower,
            tickUpper,
            liquidity > 0 ? uint256(liquidity) : uint256(-liquidity)
        );
    }

    function updateTick(uint8 tierID, int24 tick, int256 liquidity, bool isLower) internal {
        Tick.Info storage tickInfo = ticks.get(tierID, tick);

        tickInfo.liquidityGross = addDelta(tickInfo.liquidityGross, liquidity);

        if (isLower) {
            tickInfo.liquidityNet = addDelta(tickInfo.liquidityNet, liquidity);
        } else {
            tickInfo.liquidityNet = addDelta(tickInfo.liquidityNet, -liquidity);
        }
    }

    function updatePosition(address to, uint8 tierID, int24 tickLower, int24 tickUpper, int256 liquidity) internal {
        Position.Info storage positionInfo = positions.get(to, tierID, tickLower, tickUpper);

        positionInfo.liquidity = addDelta(positionInfo.liquidity, liquidity);
    }
}
