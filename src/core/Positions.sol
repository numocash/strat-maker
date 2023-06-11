// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

library Positions {
    struct Position {
        uint256 liquidity;
    }

    function get(
        mapping(bytes32 => Position) storage positions,
        address owner,
        uint8 tier,
        int24 tick
    )
        internal
        view
        returns (Position storage positionInfo)
    {
        positionInfo = positions[keccak256(abi.encodePacked(owner, tier, tick))];
    }
}
