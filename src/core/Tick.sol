// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

library Tick {
    struct Info {
        uint256 liquidityGross;
        uint256 liquidityNet;
    }

    function get(
        mapping(bytes32 => Info) storage ticks,
        uint8 tierID,
        int24 tick
    )
        internal
        view
        returns (Info storage tickInfo)
    {
        tickInfo = ticks[keccak256(abi.encodePacked(tierID, tick))];
    }
}
