// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

uint256 constant Q128 = 0x100000000000000000000000000000000;

int24 constant MAX_STRIKE = 726_861;
int24 constant MIN_STRIKE = -726_861;

error InvalidStrike();

/// @notice Calculates ((1 + 2^13) / 2^13)^strike * 2^128
/**
 * @dev Uses binary decomposition of |strike|
 *
 * Let b_i = the i-th bit of x and b_i ∈ {0, 1}
 * Then  x = (b0 * 2^0) + (b1 * 2^1) + (b2 * 2^2) + ...
 * Thus, r = u^x
 *         = u^(b0 * 2^0) * u^(b1 * 2^1) * u^(b2 * 2^2) * ...
 *         = k0^b0 * k1^b1 * k2^b2 * ... (where k_i = u^(2^i))
 * We pre-compute k_i in script/StrikeMathScript.s.sol since u is a known constant. In practice, we use u = 2^13 / (1 +
 * 2^13) to prevent overflow during the computation, then inverse the result at the end.
 */
/// @dev From Uniswap (), and Muffin ()
function getRatioAtStrike(int24 strike) pure returns (uint256 ratioX128) {
    unchecked {
        if (strike < MIN_STRIKE || strike > MAX_STRIKE) revert InvalidStrike();

        uint256 x = uint256(uint24(strike < 0 ? -strike : strike));
        ratioX128 = Q128;

        if (x & 0x1 > 0) ratioX128 = (ratioX128 * 0xfff8003ffe000fff8003ffe000fff801) >> 128;
        if (x & 0x2 > 0) ratioX128 = (ratioX128 * 0xfff000bff8004ffd001bff0008ffb003) >> 128;
        if (x & 0x4 > 0) ratioX128 = (ratioX128 * 0xffe0027fd8022fe4014ff100a4f92048) >> 128;
        if (x & 0x8 > 0) ratioX128 = (ratioX128 * 0xffc008ff10149e741ace5319219a92fe) >> 128;
        if (x & 0x10 > 0) ratioX128 = (ratioX128 * 0xff8021f9a0f221bb4f8cc17aaa70f73b) >> 128;
        if (x & 0x20 > 0) ratioX128 = (ratioX128 * 0xff0083d14cc5a03dccb16e44d1eda995) >> 128;
        if (x & 0x40 > 0) ratioX128 = (ratioX128 * 0xfe02069b3ad194ebd17e4dc79fbba464) >> 128;
        if (x & 0x80 > 0) ratioX128 = (ratioX128 * 0xfc080520235073ac61aeeec24d49334b) >> 128;
        if (x & 0x100 > 0) ratioX128 = (ratioX128 * 0xf81fca5797a2de2c989740d058136f9c) >> 128;
        if (x & 0x200 > 0) ratioX128 = (ratioX128 * 0xf07d9bfc56f0a12da794ef0a5376c3dc) >> 128;
        if (x & 0x400 > 0) ratioX128 = (ratioX128 * 0xe1ebc21ad67b9f35ab3e10ee5aee0b67) >> 128;
        if (x & 0x800 > 0) ratioX128 = (ratioX128 * 0xc76044511d77c4b645a8160706981b39) >> 128;
        if (x & 0x1000 > 0) ratioX128 = (ratioX128 * 0x9b46ce696ae17f0232af3b4295fb8c0d) >> 128;
        if (x & 0x2000 > 0) ratioX128 = (ratioX128 * 0x5e2ed1892f815689e09526c4f3ffca90) >> 128;
        if (x & 0x4000 > 0) ratioX128 = (ratioX128 * 0x22a66a70b7b1571d6b06bd776f94a597) >> 128;
        if (x & 0x8000 > 0) ratioX128 = (ratioX128 * 0x4b0a074273adee0e5b432d64eab85ff) >> 128;
        if (x & 0x10000 > 0) ratioX128 = (ratioX128 * 0x15fee0a5812da6a65f91c049eb4db2) >> 128;
        if (x & 0x20000 > 0) ratioX128 = (ratioX128 * 0x1e3ce9db4bfe0fda77e9293a4f8) >> 128;
        if (x & 0x40000 > 0) ratioX128 = (ratioX128 * 0x392554dda3c16fe369c83) >> 128;
        if (x & 0x80000 > 0) ratioX128 = (ratioX128 * 0xcc1a53c58) >> 128;
        // Stop computation here since |strike| < 2**20

        // Inverse r since base = 2^13 / (1 + 2^13)
        if (strike > 0) ratioX128 = type(uint256).max / ratioX128;
    }
}
