// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Pair} from "./Pair.sol";

/// @notice Deploy and lookup pairs
/// @author Robert Leifke and Kyle Scott
contract Factory {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PairCreated(address indexed token0, address indexed token1, address pair);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SameTokenError();

    error ZeroAddressError();

    error DeployedError();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @custom:team Potentially replace this with an address estimated and then check if deployed with
    /// estimatedAddress.code.length == 0
    mapping(address tokenA => mapping(address tokenB => address pair)) public getPair;

    /*//////////////////////////////////////////////////////////////
                           TEMPORARY STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Parameters {
        address token0;
        address token1;
    }

    Parameters public parameters;

    /*//////////////////////////////////////////////////////////////
                                  LOGIC
    //////////////////////////////////////////////////////////////*/

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert SameTokenError();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        if (token0 == address(0)) revert ZeroAddressError();
        if (getPair[token0][token1] != address(0)) revert DeployedError();

        parameters = Parameters({token0: token0, token1: token1});
        pair = address(new Pair{salt: keccak256(abi.encode(token0, token1)) }());

        delete parameters;

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;

        emit PairCreated(token0, token1, pair);
    }
}
