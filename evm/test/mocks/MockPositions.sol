// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Positions} from "src/core/Positions.sol";
import {Engine} from "src/core/Engine.sol";

contract MockPositions is Positions {
    function mintBiDirectional(
        address to,
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike,
        uint8 spread,
        uint128 amount
    )
        external
    {
        _mintBiDirectional(to, token0, token1, scalingFactor, strike, spread, amount);
    }

    function mintDebt(
        address to,
        address token0,
        address token1,
        uint8 scalingFactor,
        int24 strike,
        Engine.TokenSelector selector,
        uint128 amount,
        uint128 liquidityBuffer
    )
        external
    {
        _mintDebt(to, token0, token1, scalingFactor, strike, selector, amount, liquidityBuffer);
    }

    function burn(address from, bytes32 id, uint128 amount, Engine.OrderType orderType) external {
        _burn(from, id, amount, orderType);
    }
}
