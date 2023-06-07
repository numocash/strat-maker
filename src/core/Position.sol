// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

library Position {
    struct Info {
        uint256 liquidity;
    }

    function get(
        mapping(bytes32 => Info) storage positions,
        address owner,
        uint8 tierID,
        int24 tickLower,
        int24 tickUpper
    )
        internal
        view
        returns (Info storage positionInfo)
    {
        positionInfo = positions[keccak256(abi.encodePacked(owner, tierID, tickLower, tickUpper))];
    }
}
