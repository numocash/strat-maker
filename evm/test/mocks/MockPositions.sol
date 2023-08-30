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
        uint128 buffer
    )
        external
    {
        _mintDebt(to, token0, token1, scalingFactor, strike, selector, amount, buffer);
    }

    function burn(
        address from,
        bytes32 id,
        Engine.OrderType orderType,
        uint128 amount,
        uint128 amountBuffer
    )
        external
    {
        _burn(from, id, orderType, amount, amountBuffer);
    }
}
