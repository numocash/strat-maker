// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import { Pair } from "./Pair.sol";

contract Factory {

    /*//////////////////////////////////////////////////////////////
                        ERRORS
    //////////////////////////////////////////////////////////////*/

  error SameTokenError();

  error ZeroAddressError();

  error TickZeroError();

  error DeployedError();

  error ScaleError();

    /*//////////////////////////////////////////////////////////////
                        STOARGE
    //////////////////////////////////////////////////////////////*/

    // Three-level mapping
    mapping(address => mapping(address => mapping(int24 => address))) public getPair;
    
    mapping(uint8 => int24) public tierAmountTick;

    /*//////////////////////////////////////////////////////////////
                        DEPLOYER STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Parameters {
        address token0;
        address token1;
        int24 tick;
        uint8 tier;
    }

    Parameters public parameters;

    function createPair(
        address token0,
        address token1,
        uint8 tier
    ) external returns (address pair) {
        if (token0 == token1) revert SameTokenError();
        if (token0 == address(0) || token1 == address(0)) revert ZeroAddressError();
        if (tierAmountTick[tier] != 0) revert TickZeroError();
        if (getPair[token0][token1][tier] != address(0)) revert DeployedError();

        parameters = Parameters({ token0: token0, token1: token1, tick: tick, tier: tier });

        pair = address(new Pair{ salt: keccak256(abi.encode(token0, token1, tier)) }());

        delete parameters;

        getPair[token0][token1][tier] = pair;

        // emit PairCreated(token0, token1, tick, tier, pair);
  }
}

