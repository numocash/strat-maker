// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Tick} from "./Tick.sol";
import {Tier} from "./Tier.sol";
import {Position} from "./Position.sol";
import {Factory} from "./Factory.sol";
import {MIN_TICK, MAX_TICK, getRatioAtTick, Q128, Q96, Q32} from "./TickMath.sol";
import {mulDiv, mulDivRoundingUp} from "./FullMath.sol";
import {addDelta, calcAmountsForLiquidity} from "./LiquidityMath.sol";
import {computeSwapStep} from "./SwapMath.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {BalanceLib} from "src/libraries/BalaneLib.sol";
import {IMintCallback} from "./interfaces/IMintCallback.sol";

contract Pair {
    using Tick for mapping(bytes32 => Tick.Info);
    using Tier for mapping(uint8 => Tier.Info);
    using Position for mapping(bytes32 => Position.Info);

    error InvalidTick();
    error InvalidTier();

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    uint96 public composition;
    int24 public tickCurrent;

    /**
     * @custom:team This is where we should add the offsets of each tier, i.e. an int8 that shows how far each the
     * current tick of a tier is away from the global current tick
     */

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

    struct SwapState {
        uint256 liquidity;
        uint96 composition;
        int24 tickCurrent;
        // pool's balance change of the token which "amountDesired" refers to
        int256 amountA;
        // pool's balance change of the opposite token
        int256 amountB;
    }

    /// @return amount0 The delta of the balance of token0 of the pool
    /// @return amount1 The delta of the balance of token1 of the pool
    function swap(address to, bool isToken0, int256 amountDesired) external returns (int256 amount0, int256 amount1) {
        if (amountDesired == 0) revert();

        bool isExactIn = amountDesired > 0;

        SwapState memory state = SwapState({
            liquidity: tiers.get(0).liquidity,
            composition: composition,
            tickCurrent: tickCurrent,
            amountA: 0,
            amountB: 0
        });

        while (true) {
            uint256 ratioX128 = getRatioAtTick(state.tickCurrent);
            (uint256 amountIn, uint256 amountOut,) =
                computeSwapStep(ratioX128, state.composition, state.liquidity, isToken0, amountDesired);

            if (isExactIn) {
                amountDesired = amountDesired - int256(amountIn);
                state.amountA = state.amountA + int256(amountIn);
                state.amountB = state.amountB - int256(amountOut);
            } else {
                amountDesired = amountDesired + int256(amountOut);
                state.amountA = state.amountA - int256(amountOut);
                state.amountB = state.amountB + int256(amountIn);
            }

            if (amountDesired == 0) {
                // update composition
                break;
            }
            // else cross next tick
        }

        if (isToken0) {
            amount0 = state.amountA;
            amount1 = state.amountB;
        } else {
            amount0 = state.amountB;
            amount1 = state.amountA;
        }

        composition = state.composition;
        tickCurrent = state.tickCurrent;
        tiers.get(0).liquidity = state.liquidity;

        // pay out
        if (amount0 < 0) SafeTransferLib.safeTransfer(token0, to, uint256(-amount0));
        else if (amount1 < 0) SafeTransferLib.safeTransfer(token1, to, uint256(-amount1));

        // receive input

        // emit
    }

    function checkTickInputs(int24 tickLower, int24 tickUpper) internal pure {
        if (tickLower > tickUpper || MIN_TICK > tickLower || tickUpper > MAX_TICK) {
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
        if (tickLower <= tickCurrent && tickCurrent <= tickUpper) {
            tier.liquidity = addDelta(tier.liquidity, liquidity);
        }

        // update ticks
        updateTick(tierID, tickLower, liquidity, true);
        updateTick(tierID, tickUpper, liquidity, false);

        // update position
        updatePosition(to, tierID, tickLower, tickUpper, liquidity);

        // determine amounts
        (amount0, amount1) = calcAmountsForLiquidity(
            tickCurrent, composition, tickLower, tickUpper, liquidity > 0 ? uint256(liquidity) : uint256(-liquidity)
        );
    }

    function updateTick(uint8 tierID, int24 tick, int256 liquidity, bool isLower) internal {
        Tick.Info storage tickInfo = ticks.get(tierID, tick);

        tickInfo.liquidityGross = addDelta(tickInfo.liquidityGross, liquidity);

        if (isLower) {
            tickInfo.liquidityNet += liquidity;
        } else {
            tickInfo.liquidityNet -= liquidity;
        }
    }

    function updatePosition(address to, uint8 tierID, int24 tickLower, int24 tickUpper, int256 liquidity) internal {
        Position.Info storage positionInfo = positions.get(to, tierID, tickLower, tickUpper);

        positionInfo.liquidity = addDelta(positionInfo.liquidity, liquidity);
    }
}
