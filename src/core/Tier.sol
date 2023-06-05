// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

library Tier {
    struct Info {
        uint256 liquidity;
    }

    function get(mapping(uint8 => Info) storage tiers, uint8 tierID) internal view returns (Info storage tierInfo) {
        tierInfo = tiers[tierID];
    }
}
