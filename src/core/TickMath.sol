// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

uint256 constant Q128 = 0x100000000000000000000000000000000;

int24 constant MIN_TICK = -887_272;
int24 constant MAX_TICK = 887_272;

error InvalidTick();

/// @notice Calculates 1.0001^tick * 2^128
/**
 * @dev Uses binary decomposition of |tick|
 *
 * Let b_i = the i-th bit of x and b_i ∈ {0, 1}
 * Then  x = (b0 * 2^0) + (b1 * 2^1) + (b2 * 2^2) + ...
 * Thus, r = u^x
 *         = u^(b0 * 2^0) * u^(b1 * 2^1) * u^(b2 * 2^2) * ...
 *         = k0^b0 * k1^b1 * k2^b2 * ... (where k_i = u^(2^i))
 * We pre-compute k_i in script/TickMathScript.s.sol since u is a known constant. In practice, we use u = 1/1.0001 to
 * prevent overflow during the computation, then inverse the result at the end.
 */
/// @dev Modified from Uniswap (), and Muffin ()
/// @custom:team I believe these constants do not round correctly
function getRatioAtTick(int24 tick) pure returns (uint256 ratioX128) {
    unchecked {
        if (tick < MIN_TICK || tick > MAX_TICK) revert InvalidTick();

        uint256 x = uint256(uint24(tick < 0 ? -tick : tick));
        ratioX128 = Q128;

        if (x & 0x1 > 0) ratioX128 = (ratioX128 * 0xfff97272373d413259a407b06395f90f) >> 128;
        if (x & 0x2 > 0) ratioX128 = (ratioX128 * 0xfff2e50f5f656932ef1171c20d94409b) >> 128;
        if (x & 0x4 > 0) ratioX128 = (ratioX128 * 0xffe5caca7e10e4e61c349d88de59ee79) >> 128;
        if (x & 0x8 > 0) ratioX128 = (ratioX128 * 0xffcb9843d60f6159c9d84a0ffaab939b) >> 128;
        if (x & 0x10 > 0) ratioX128 = (ratioX128 * 0xff973b41fa98c08147284cf074e387d5) >> 128;
        if (x & 0x20 > 0) ratioX128 = (ratioX128 * 0xff2ea16466c96a3843e046662bb67727) >> 128;
        if (x & 0x40 > 0) ratioX128 = (ratioX128 * 0xfe5dee046a99a2a811ac114ac614ac9c) >> 128;
        if (x & 0x80 > 0) ratioX128 = (ratioX128 * 0xfcbe86c7900a88aedccf765871cd46e5) >> 128;
        if (x & 0x100 > 0) ratioX128 = (ratioX128 * 0xf987a7253ac413176ecb9e29f4d08c52) >> 128;
        if (x & 0x200 > 0) ratioX128 = (ratioX128 * 0xf3392b0822b7000593527a95f936c282) >> 128;
        if (x & 0x400 > 0) ratioX128 = (ratioX128 * 0xe7159475a2c29b7442512e1cbb578357) >> 128;
        if (x & 0x800 > 0) ratioX128 = (ratioX128 * 0xd097f3bdfd2022b881dcc82b04dd48c5) >> 128;
        if (x & 0x1000 > 0) ratioX128 = (ratioX128 * 0xa9f746462d870fdf86560b5c522cf05f) >> 128;
        if (x & 0x2000 > 0) ratioX128 = (ratioX128 * 0x70d869a156d2a1b88b568394a9e07f2b) >> 128;
        if (x & 0x4000 > 0) ratioX128 = (ratioX128 * 0x31be135f97d08fd97c61d38210d0ed17) >> 128;
        if (x & 0x8000 > 0) ratioX128 = (ratioX128 * 0x9aa508b5b7a84e1c49ed3ab387b721e) >> 128;
        if (x & 0x10000 > 0) ratioX128 = (ratioX128 * 0x5d6af8dedb811966760afd60167cf2) >> 128;
        if (x & 0x20000 > 0) ratioX128 = (ratioX128 * 0x2216e584f5fa1ea90bf2722b93a1) >> 128;
        if (x & 0x40000 > 0) ratioX128 = (ratioX128 * 0x48a170391f7dc423d5d34c2) >> 128;
        if (x & 0x80000 > 0) ratioX128 = (ratioX128 * 0x149b34ee7ac262) >> 128;
        // Stop computation here since |tick| < 2**20

        // Inverse r since base = 1/1.0001
        if (tick > 0) ratioX128 = type(uint256).max / ratioX128;
    }
}
