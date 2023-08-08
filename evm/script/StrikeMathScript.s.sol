// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
/* solhint-disable-next-line no-console */
import {console2} from "forge-std/console2.sol";

import {mulDiv, mulDivRoundingUp} from "src/core/math/FullMath.sol";
import {MAX_STRIKE, Q128} from "src/core/math/StrikeMath.sol";

contract StrikeMathScript is Script {
    uint256 constant u = 0x2001; // 2**13 + 1

    function run() external pure {
        uint256 u_i = u;

        /* solhint-disable-next-line no-console */
        console2.log(
            "if (x & %x > 0) ratioX128 = (ratioX128 * %x) >> 128;", 1, mulDivRoundingUp(2 ** (13 + 128), 1, u_i)
        );

        for (uint8 i = 1; (1 << i) < uint24(MAX_STRIKE); i++) {
            /* solhint-disable-next-line no-console */
            console2.log(
                "if (x & %x > 0) ratioX128 = (ratioX128 * %x) >> 128;",
                1 << i,
                mulDivRoundingUp(2 ** (128 + 13), 2 ** 13, u_i * u_i)
            );

            u_i = mulDiv(u_i, u_i, 2 ** 13);
        }
    }
}
