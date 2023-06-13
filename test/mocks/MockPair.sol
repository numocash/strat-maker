// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Pairs, MAX_TIERS} from "src/core/Pairs.sol";
import {Positions} from "src/core/Positions.sol";
import {Ticks} from "src/core/Ticks.sol";

import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";

contract MockPair is Positions {
    using Pairs for Pairs.Pair;

    address private immutable token0;
    address private immutable token1;

    Pairs.Pair private pair;

    constructor(address _token0, address _token1, int24 tickInitial) {
        token0 = _token0;
        token1 = _token1;
        pair.initialize(tickInitial);
    }

    function addLiquidity(
        int24 tick,
        uint8 tier,
        uint256 liquidity
    )
        public
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = pair.updateLiquidity(tick, tier, int256(liquidity));

        _mint(msg.sender, dataID(abi.encode(Positions.ILRTADataID(token0, token1, tick, tier))), liquidity);

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = bytes32(uint256(uint160(token0)));
        ids[1] = bytes32(uint256(uint160(token1)));

        int256[] memory balanceChanges = new int256[](2);
        balanceChanges[0] = int256(amount0);
        balanceChanges[1] = int256(amount1);

        uint256 balance0Before = BalanceLib.getBalance(token0);
        uint256 balance1Before = BalanceLib.getBalance(token1);

        IExecuteCallback(msg.sender).executeCallback(ids, balanceChanges, bytes(""));

        if (BalanceLib.getBalance(token0) < balance0Before + amount0) revert();
        if (BalanceLib.getBalance(token1) < balance1Before + amount1) revert();
    }

    function removeLiquidity(
        int24 tick,
        uint8 tier,
        uint256 liquidity
    )
        public
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = pair.updateLiquidity(tick, tier, -int256(liquidity));

        SafeTransferLib.safeTransfer(token0, msg.sender, amount0);
        SafeTransferLib.safeTransfer(token1, msg.sender, amount1);

        _burn(msg.sender, dataID(abi.encode(Positions.ILRTADataID(token0, token1, tick, tier))), liquidity);
    }

    function swap(bool isToken0, int256 amountDesired) public returns (int256 amount0, int256 amount1) {
        (amount0, amount1) = pair.swap(isToken0, amountDesired);

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = bytes32(uint256(uint160(token0)));
        ids[1] = bytes32(uint256(uint160(token1)));

        int256[] memory balanceChanges = new int256[](2);
        balanceChanges[0] = amount0;
        balanceChanges[1] = amount1;

        if (isToken0 == (amountDesired > 0)) {
            if (amount1 < 0) SafeTransferLib.safeTransfer(token1, msg.sender, uint256(-amount1));
            uint256 balance0Before = BalanceLib.getBalance(token0);
            IExecuteCallback(msg.sender).executeCallback(ids, balanceChanges, bytes(""));
            if (BalanceLib.getBalance(token0) < balance0Before + uint256(amount0)) revert();
        } else {
            if (amount0 < 0) SafeTransferLib.safeTransfer(token0, msg.sender, uint256(-amount0));
            uint256 balance1Before = BalanceLib.getBalance(token1);
            IExecuteCallback(msg.sender).executeCallback(ids, balanceChanges, bytes(""));
            if (BalanceLib.getBalance(token1) < balance1Before + uint256(amount1)) revert();
        }
    }

    function getPair()
        external
        view
        returns (uint128[MAX_TIERS] memory compositions, int24 tickCurrent, int8 offset, uint8 initialized)
    {
        (compositions, tickCurrent, offset, initialized) =
            (pair.compositions, pair.tickCurrent, pair.offset, pair.initialized);
    }

    function getTick(int24 tick) external view returns (Ticks.Tick memory) {
        return pair.ticks[tick];
    }

    function getPosition(address owner, uint8 tier, int24 tick) external view returns (Positions.ILRTAData memory) {
        return _dataOf[owner][dataID(abi.encode(Positions.ILRTADataID(token0, token1, tick, tier)))];
    }
}
