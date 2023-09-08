// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {mulDiv} from "src/core/math/FullMath.sol";

/// @notice returns true if a mulDiv operation would overflow
function mulDivOverflow(uint256 a, uint256 b, uint256 denominator) pure returns (bool) {
    unchecked {
        // 512-bit multiply [prod1 prod0] = a * b
        // Compute the product mod 2**256 and mod 2**256 - 1
        // then use the Chinese Remainder Theorem to reconstruct
        // the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2**256 + prod0
        uint256 prod0 = a * b; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Make sure the result is less than 2**256.
        // Also prevents denominator == 0

        return (denominator > prod1) ? false : true;
    }
}

/// @notice returns true if a mulDivRoundingUp operation would overflow
function mulDivRoundingUpOverflow(uint256 a, uint256 b, uint256 denominator) pure returns (bool) {
    if (mulDivOverflow(a, b, denominator)) return true;
    uint256 result = mulDiv(a, b, denominator);

    if (mulmod(a, b, denominator) > 0 && result == type(uint256).max) return true;
    else return false;
}
