// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Pair} from "src/core/Pair.sol";

bytes32 constant INIT_CODE_HASH = keccak256(type(Pair).creationCode);

function computeAddress(address factory, address token0, address token1) pure returns (address pair) {
    return address(
        uint160(
            uint256(
                keccak256(
                    abi.encodePacked(hex"ff", factory, keccak256(abi.encode(token0, token1)), bytes32(INIT_CODE_HASH))
                )
            )
        )
    );
}
