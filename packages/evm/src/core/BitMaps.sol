// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {MIN_STRIKE} from "./math/StrikeMath.sol";

/// @title Bit Maps
/// @notice Manage a bit map where positive bits represent active strikes
/// @author Robert Leifke and Kyle Scott
library BitMaps {
    /// @notice Data structure of a three-level bitmap
    struct BitMap {
        uint256 level0;
        mapping(uint256 => uint256) level1;
        mapping(uint256 => uint256) level2;
    }

    /// @notice Recover the indicies into the data structure from a strike
    /// @custom:team Could mask level 2 index
    function _indices(int24 strike)
        internal
        pure
        returns (uint256 level0Index, uint256 level1Index, uint256 level2Index)
    {
        assembly {
            let index := sub(strike, MIN_STRIKE)
            level0Index := shr(16, index)
            level1Index := shr(8, index)
            level2Index := index
        }
    }

    /// @notice Turn on a bit in the bitmap
    function set(BitMap storage self, int24 strike) internal {
        (uint256 level0Index, uint256 level1Index, uint256 level2Index) = _indices(strike);

        self.level0 |= 1 << level0Index;
        self.level1[level0Index] |= 1 << (level1Index & 0xff);
        self.level2[level1Index] |= 1 << (level2Index & 0xff);
    }

    /// @notice Turn off a bit in the bitmap
    function unset(BitMap storage self, int24 strike) internal {
        (uint256 level0Index, uint256 level1Index, uint256 level2Index) = _indices(strike);

        self.level2[level1Index] &= ~(1 << (level2Index & 0xff));
        if (self.level2[level1Index] == 0) {
            self.level1[level0Index] &= ~(1 << (level1Index & 0xff));
            if (self.level1[level0Index] == 0) {
                self.level0 &= ~(1 << level0Index);
            }
        }
    }

    /// @notice Calculate the next highest flipped bit under `strike`
    /// @dev First search bits on the same level 2, then search bits on the same level 1, then search level 0
    function nextBelow(BitMap storage self, int24 strike) internal view returns (int24) {
        unchecked {
            (uint256 level0Index, uint256 level1Index, uint256 level2Index) = _indices(strike);

            uint256 _level2 = self.level2[level1Index] & ((1 << (level2Index & 0xff)) - 1);
            if (_level2 == 0) {
                uint256 _level1 = self.level1[level0Index] & ((1 << (level1Index & 0xff)) - 1);
                if (_level1 == 0) {
                    uint256 _level0 = self.level0 & ((1 << level0Index) - 1);
                    assert(_level0 != 0);

                    level0Index = _msb(_level0);
                    _level1 = self.level1[level0Index];
                }
                level1Index = (level0Index << 8) | _msb(_level1);
                _level2 = self.level2[level1Index];
            }

            return int24(int256((level1Index << 8) | _msb(_level2)) + MIN_STRIKE);
        }
    }

    /// @notice Recover the most significant bit
    function _msb(uint256 x) internal pure returns (uint8 r) {
        unchecked {
            assert(x > 0);
            if (x >= 0x100000000000000000000000000000000) {
                x >>= 128;
                r += 128;
            }
            if (x >= 0x10000000000000000) {
                x >>= 64;
                r += 64;
            }
            if (x >= 0x100000000) {
                x >>= 32;
                r += 32;
            }
            if (x >= 0x10000) {
                x >>= 16;
                r += 16;
            }
            if (x >= 0x100) {
                x >>= 8;
                r += 8;
            }
            if (x >= 0x10) {
                x >>= 4;
                r += 4;
            }
            if (x >= 0x4) {
                x >>= 2;
                r += 2;
            }
            if (x >= 0x2) r += 1;
        }
    }
}
