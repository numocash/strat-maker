// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

library Position {
    struct Info {
        uint256 liquidity;
        uint256 tickInside0Last;
        uint256 tickInside1Last;
        uint256 limitOrderTyper;
        uint256 settlementSnapshotID;
    }

    function get(mapping(bytes32 => Position) storage positions,
                    uint8 tierId,
                    int24 tickLower,
                    int24 tickUpper
                    ) internal view returns (Position storage position) {
        position = positions[keccak256(abi.encodePacked(tierId, tickLower, tickUpper))];
    }
}
