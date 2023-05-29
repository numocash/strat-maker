// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
/* solhint-disable-next-line no-console */
import {console2} from "forge-std/console2.sol";

import {FullMath} from "src/core/FullMath.sol";
import {MAX_TICK, Q128} from "src/core/TickMath.sol";

contract TickMathScript is Script {
    uint256 constant u = 0x100068DB8BAC710CB295F000000000000; // 1.0001 as a Q128.128

    function run() external pure {
        uint256 u_i = u;

        /* solhint-disable-next-line no-console */
        console2.log("if (x & %x > 0) ratioX128 = (ratioX128 * %x) >> 128;", 1 << 0, type(uint256).max / u_i);

        for (uint8 i = 1; (1 << i) < uint24(MAX_TICK); i++) {
            u_i = FullMath.mulDivRoundingUp(u_i, u_i, Q128);

            /* solhint-disable-next-line no-console */
            console2.log("if (x & %x > 0) ratioX128 = (ratioX128 * %x) >> 128;", 1 << i, type(uint256).max / u_i);
        }
    }
}
