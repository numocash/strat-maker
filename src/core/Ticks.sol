// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Pairs} from "./Pairs.sol";

uint8 constant MAX_TIERS = 5;

library Ticks {
    struct Tick {
        uint256[MAX_TIERS] liquidity;
        int24 next0To1;
        int24 next1To0;
        uint8 reference0To1;
        uint8 reference1To0;
    }

    function getLiquidity(Tick storage self, uint8 tier) internal view returns (uint256 liquidity) {
        return self.liquidity[tier];
    }
}
