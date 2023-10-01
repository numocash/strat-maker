// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Positions} from "src/core/Positions.sol";

contract MockPositions is Positions {
    function mint(address from, bytes32 id, uint128 amount) external {
        _mint(from, id, amount);
    }

    function burn(address from, bytes32 id, uint128 amount) external {
        _burn(from, id, amount);
    }
}
