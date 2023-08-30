// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {BitMaps} from "src/core/BitMaps.sol";
import {MIN_STRIKE, MAX_STRIKE} from "src/core/math/StrikeMath.sol";

contract BitMapsFuzzTest is Test {
    using BitMaps for BitMaps.BitMap;

    BitMaps.BitMap private bitmap;

    function test_BitMaps_Set(uint24[8] calldata deltaStrikes) external {
        int24[8] memory strikes;
        int32 x = MIN_STRIKE;

        for (uint256 i = 0; i < strikes.length; i++) {
            x += int32(uint32(deltaStrikes[i]));
            vm.assume(x + 1 <= MAX_STRIKE);

            strikes[i] = int24(x);
        }

        for (uint256 i = 0; i < strikes.length; i++) {
            bitmap.set(strikes[i]);

            assertEq(bitmap.nextBelow(strikes[i] + 1), strikes[i]);
        }
    }
}
