// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

uint256 constant Q128 = 0x100000000000000000000000000000000;

int24 constant MAX_STRIKE = 776_363;
int24 constant MIN_STRIKE = -776_363;

error InvalidStrike();

/**
 * @dev Uses binary decomposition of |strike|
 *
 * Let b_i = the i-th bit of x and b_i ∈ {0, 1}
 * Then  x = (b0 * 2^0) + (b1 * 2^1) + (b2 * 2^2) + ...
 * Thus, r = u^x
 *         = u^(b0 * 2^0) * u^(b1 * 2^1) * u^(b2 * 2^2) * ...
 *         = k0^b0 * k1^b1 * k2^b2 * ... (where k_i = u^(2^i))
 * We pre-compute k_i since u is a known constant. In practice, we use u = 1/sqrt(1.0001) to
 * prevent overflow during the computation, then inverse the result at the end.
 */
/// @dev From Uniswap (), and Muffin ()
function getRatioAtStrike(int24 strike) pure returns (uint256 ratioX128) {
    unchecked {
        if (strike == 0) return Q128;
        if (strike < MIN_STRIKE || strike > MAX_STRIKE) revert InvalidStrike();

        uint256 x = uint256(uint24(strike < 0 ? -strike : strike));
        ratioX128 = Q128;

        if (x & 0x1 > 0) ratioX128 = (ratioX128 * 0xFFFCB933BD6FAD37AA2D162D1A594001) >> 128;
        if (x & 0x2 > 0) ratioX128 = (ratioX128 * 0xFFF97272373D413259A46990580E213A) >> 128;
        if (x & 0x4 > 0) ratioX128 = (ratioX128 * 0xFFF2E50F5F656932EF12357CF3C7FDCC) >> 128;
        if (x & 0x8 > 0) ratioX128 = (ratioX128 * 0xFFE5CACA7E10E4E61C3624EAA0941CD0) >> 128;
        if (x & 0x10 > 0) ratioX128 = (ratioX128 * 0xFFCB9843D60F6159C9DB58835C926644) >> 128;
        if (x & 0x20 > 0) ratioX128 = (ratioX128 * 0xFF973B41FA98C081472E6896DFB254C0) >> 128;
        if (x & 0x40 > 0) ratioX128 = (ratioX128 * 0xFF2EA16466C96A3843EC78B326B52861) >> 128;
        if (x & 0x80 > 0) ratioX128 = (ratioX128 * 0xFE5DEE046A99A2A811C461F1969C3053) >> 128;
        if (x & 0x100 > 0) ratioX128 = (ratioX128 * 0xFCBE86C7900A88AEDCFFC83B479AA3A4) >> 128;
        if (x & 0x200 > 0) ratioX128 = (ratioX128 * 0xF987A7253AC413176F2B074CF7815E54) >> 128;
        if (x & 0x400 > 0) ratioX128 = (ratioX128 * 0xF3392B0822B70005940C7A398E4B70F3) >> 128;
        if (x & 0x800 > 0) ratioX128 = (ratioX128 * 0xE7159475A2C29B7443B29C7FA6E889D9) >> 128;
        if (x & 0x1000 > 0) ratioX128 = (ratioX128 * 0xD097F3BDFD2022B8845AD8F792AA5825) >> 128;
        if (x & 0x2000 > 0) ratioX128 = (ratioX128 * 0xA9F746462D870FDF8A65DC1F90E061E5) >> 128;
        if (x & 0x4000 > 0) ratioX128 = (ratioX128 * 0x70D869A156D2A1B890BB3DF62BAF32F7) >> 128;
        if (x & 0x8000 > 0) ratioX128 = (ratioX128 * 0x31BE135F97D08FD981231505542FCFA6) >> 128;
        if (x & 0x10000 > 0) ratioX128 = (ratioX128 * 0x9AA508B5B7A84E1C677DE54F3E99BC9) >> 128;
        if (x & 0x20000 > 0) ratioX128 = (ratioX128 * 0x5D6AF8DEDB81196699C329225EE604) >> 128;
        if (x & 0x40000 > 0) ratioX128 = (ratioX128 * 0x2216E584F5FA1EA926041BEDFE98) >> 128;
        if (x & 0x80000 > 0) ratioX128 = (ratioX128 * 0x48A170391F7DC42444E8FA2) >> 128;
        // Stop computation here since |strike| < 2**20

        // square the result
        ratioX128 = (ratioX128 * ratioX128) / Q128;
        if (strike > 0) ratioX128 = type(uint256).max / ratioX128;
    }
}
