// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Pairs} from "./Pairs.sol";

uint8 constant MAX_SPREADS = 5;

library Strikes {
    struct Strike {
        uint256[MAX_SPREADS] liquidity;
        int24 next0To1;
        int24 next1To0;
        uint8 reference0To1;
        uint8 reference1To0;
    }

    function getLiquidity(Strike storage self, uint8 spread) internal view returns (uint256 liquidity) {
        return self.liquidity[spread];
    }
}
