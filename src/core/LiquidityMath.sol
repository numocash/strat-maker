// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import { getRatioAtTick, Q128 } from "./TickMath.sol";
import { mulDiv } from "./FullMath.sol";

/// @notice Calculates the sum of a geometric series for positive ticks
/// @dev Use r = 1/1.0001
/// i.e. Sn = a1 (1 - r^n) / (1 - r)
/// @dev Takes advantage of the fact that getRatioAtTick(-n) == (1/1.0001)^n
function finiteGeoSeriesSumPos(uint256 a1, int24 n) pure returns (uint256 sum) {
    return 10_001 * (a1 - mulDiv(a1, getRatioAtTick(-n), Q128));
}

/// @notice Calculates the sum of a geometric series for negative ticks
/// @dev Use r = 1.0001
/// i.e. Sn = a1 (1 - r^n) / (1 - r)
/// @dev Takes advantage of the fact that getRatioAtTick(n) == 1.0001^n
function finiteGeoSeriesSumNeg(uint256 a1, int24 n) pure returns (uint256 sum) {
    return 10_000 * (mulDiv(a1, getRatioAtTick(n), Q128) - a1);
}

/// @notice Calculate amount0 delta when tick moves from tickLower to tickUpper.
/// @dev Assumes inputs are valid
/// i.e. x = ∑ L/Pi
/// @custom:team Rouding needs to be checked
function getAmount0Delta(int24 tickLower, int24 tickUpper, uint256 liquidity) pure returns (uint256 amount0) {
    if (tickLower > 0) {
        return finiteGeoSeriesSumPos(mulDiv(liquidity, getRatioAtTick(tickLower), Q128), (tickUpper - tickLower) + 1);
    } else if (tickUpper < 0) {
        return finiteGeoSeriesSumNeg(mulDiv(liquidity, getRatioAtTick(tickLower), Q128), (tickUpper - tickLower) + 1);
    } else {
        return finiteGeoSeriesSumPos(liquidity, tickUpper + 1) + finiteGeoSeriesSumNeg(liquidity, -tickLower + 1)
            - liquidity;
    }
}

/// @notice Calculate amount1 delta when tick moves from tickLower to tickUpper.
/// @dev Assumes inputs are valid
/// i.e. y = L
/// @custom:team Rouding needs to be checked
function getAmount1Delta(int24 tickLower, int24 tickUpper, uint256 liquidity) pure returns (uint256 amount1) {
    return liquidity * (uint24(tickUpper - tickLower) + 1);
}
