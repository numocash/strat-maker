// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Pair} from "./Pair.sol";

contract Factory {
    /*//////////////////////////////////////////////////////////////
                        EVENTS
    //////////////////////////////////////////////////////////////*/

    event PairCreated(address indexed tokenA, address indexed tokenB, int24 indexed tick, address pair);

    /*//////////////////////////////////////////////////////////////
                        ERRORS
    //////////////////////////////////////////////////////////////*/

    error SameTokenError();
    error ZeroAddressError();
    error DeployedError();

    /*//////////////////////////////////////////////////////////////
                        STORAGE
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
    }

    Parameters public parameters;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert SameTokenError();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddressError();
        if (getPair[token0][token1][0] != address(0)) revert DeployedError();

        parameters = Parameters(tokenA, tokenB, 0);

        //Error 
        pair = address(new Pair{salt: keccak256(abi.encode(token0, token1, 0)) }(token0, token1, 0));
        delete parameters;

        getPair[token0][token1][0] = pair;
        getPair[token1][token0][0] = pair;

        emit PairCreated(tokenA, tokenB, 0, pair);
    }
}