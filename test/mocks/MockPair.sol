// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Engine} from "src/core/Engine.sol";
import {Pairs, NUM_SPREADS} from "src/core/Pairs.sol";
import {Positions} from "src/core/Positions.sol";
import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {mulDiv} from "src/core/math/FullMath.sol";
import {getAmount0Delta, getAmount1Delta, getAmountsForLiquidity, toInt256} from "src/core/math/LiquidityMath.sol";
import {balanceToLiquidity} from "src/core/math/PositionMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";

contract MockPair is Positions {
    using Pairs for Pairs.Pair;

    address private immutable token0;
    address private immutable token1;

    Pairs.Pair private pair;

    constructor(
        address _superSignature,
        address _token0,
        address _token1,
        int24 strikeInitial
    )
        Positions(_superSignature)
    {
        token0 = _token0;
        token1 = _token1;
        pair.initialize(strikeInitial);
    }

    function borrowLiquidity(
        int24 strike,
        Engine.TokenSelector selectorCollateral,
        uint256 amountDesiredCollateral,
        uint256 liquidityDebt
    )
        public
        returns (int256 amount0, int256 amount1)
    {
        pair.borrowLiquidity(strike, liquidityDebt);

        // calculate the the tokens that are borrowed
        if (strike > pair.cachedStrikeCurrent) {
            amount0 = -toInt256(getAmount0Delta(liquidityDebt, strike, false));
        } else {
            amount1 = -toInt256(getAmount1Delta(liquidityDebt));
        }

        // add collateral to account
        uint256 liquidityCollateral;
        if (selectorCollateral == Engine.TokenSelector.Token0) {
            amount0 += toInt256(amountDesiredCollateral);
        } else if (selectorCollateral == Engine.TokenSelector.Token1) {
            amount1 += toInt256(amountDesiredCollateral);
        } else {
            revert Engine.InvalidSelector();
        }

        // mint position to user
        _mintDebt(
            msg.sender,
            token0,
            token1,
            strike,
            selectorCollateral,
            liquidityDebt,
            pair.strikes[strike].liquidityGrowthX128,
            mulDiv(liquidityCollateral, Q128, liquidityDebt)
        );

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        int256[] memory tokenDeltas = new int256[](2);
        tokenDeltas[0] = amount0;
        tokenDeltas[1] = amount1;

        uint256 balance0Before = BalanceLib.getBalance(token0);
        uint256 balance1Before = BalanceLib.getBalance(token1);

        if (amount0 < 0) SafeTransferLib.safeTransfer(token0, msg.sender, uint256(-amount0));
        if (amount1 < 0) SafeTransferLib.safeTransfer(token1, msg.sender, uint256(-amount1));

        IExecuteCallback(msg.sender).executeCallback(
            IExecuteCallback.CallbackParams(
                tokens,
                tokenDeltas,
                new bytes32[](0),
                new uint256[](0),
                new Engine.OrderType[](0),
                new bytes[](0),
                bytes("")
            )
        );

        if (amount0 > 0 && BalanceLib.getBalance(token0) < balance0Before + uint256(amount0)) revert();
        if (amount1 > 0 && BalanceLib.getBalance(token1) < balance1Before + uint256(amount1)) revert();
    }

    function repayLiquidity(
        int24 strike,
        Engine.TokenSelector selectorCollateral,
        uint256 leverageRatioX128,
        uint256 liquidity
    )
        public
        returns (int256 amount0, int256 amount1)
    {
        pair.repayLiquidity(strike, liquidity);

        {
            (uint256 _amount0, uint256 _amount1) =
                getAmountsForLiquidity(pair, strike, pair.strikes[strike].activeSpread, liquidity, true);
            amount0 = int256(_amount0);
            amount1 = int256(_amount1);
        }

        {
            uint256 liquidityCollateral = mulDiv(liquidity, leverageRatioX128, Q128);
            if (selectorCollateral == Engine.TokenSelector.Token0) {
                amount0 -= toInt256(getAmount0Delta(liquidityCollateral, strike, false));
            } else {
                amount1 -= toInt256(getAmount1Delta(liquidityCollateral));
            }
        }

        {
            uint256 balance0Before = BalanceLib.getBalance(token0);
            uint256 balance1Before = BalanceLib.getBalance(token1);

            address[] memory tokens = new address[](2);
            tokens[0] = token0;
            tokens[1] = token1;

            int256[] memory tokenDeltas = new int256[](2);
            tokenDeltas[0] = amount0;
            tokenDeltas[1] = amount1;

            if (amount0 < 0) SafeTransferLib.safeTransfer(token0, msg.sender, uint256(-amount0));
            if (amount1 < 0) SafeTransferLib.safeTransfer(token1, msg.sender, uint256(-amount1));

            IExecuteCallback(msg.sender).executeCallback(
                IExecuteCallback.CallbackParams(
                    tokens,
                    tokenDeltas,
                    new bytes32[](0),
                    new uint256[](0),
                    new Engine.OrderType[](0),
                    new bytes[](0),
                    bytes("")
                )
            );

            if (amount0 > 0 && BalanceLib.getBalance(token0) < balance0Before + uint256(amount0)) revert();
            if (amount1 > 0 && BalanceLib.getBalance(token1) < balance1Before + uint256(amount1)) revert();
        }

        _burnDebt(
            address(this),
            token0,
            token1,
            strike,
            selectorCollateral,
            liquidity,
            pair.strikes[strike].liquidityGrowthX128,
            leverageRatioX128
        );
    }

    function addLiquidity(
        int24 strike,
        uint8 spread,
        uint256 balance
    )
        public
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 liquidity = balanceToLiquidity(pair, strike, spread, uint256(balance), true);
        (amount0, amount1) = getAmountsForLiquidity(pair, strike, spread, uint256(liquidity), true);

        pair.updateStrike(strike, spread, int256(balance), int256(liquidity));

        _mintBiDirectional(msg.sender, token0, token1, strike, spread, balance);

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        int256[] memory tokenDeltas = new int256[](2);
        tokenDeltas[0] = int256(amount0);
        tokenDeltas[1] = int256(amount1);

        uint256 balance0Before = BalanceLib.getBalance(token0);
        uint256 balance1Before = BalanceLib.getBalance(token1);

        IExecuteCallback(msg.sender).executeCallback(
            IExecuteCallback.CallbackParams(
                tokens,
                tokenDeltas,
                new bytes32[](0),
                new uint256[](0),
                new Engine.OrderType[](0),
                new bytes[](0),
                bytes("")
            )
        );

        if (BalanceLib.getBalance(token0) < balance0Before + amount0) revert();
        if (BalanceLib.getBalance(token1) < balance1Before + amount1) revert();
    }

    function removeLiquidity(
        int24 strike,
        uint8 spread,
        uint256 balance
    )
        public
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 liquidity = balanceToLiquidity(pair, strike, spread, uint256(balance), false);
        (amount0, amount1) = getAmountsForLiquidity(pair, strike, spread, uint256(liquidity), false);

        pair.updateStrike(strike, spread, -int256(balance), -int256(liquidity));
        SafeTransferLib.safeTransfer(token0, msg.sender, amount0);
        SafeTransferLib.safeTransfer(token1, msg.sender, amount1);

        _burnBiDirectional(msg.sender, token0, token1, strike, spread, balance);
    }

    function swap(bool isToken0, int256 amountDesired) public returns (int256 amount0, int256 amount1) {
        (amount0, amount1) = pair.swap(isToken0, amountDesired);

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        int256[] memory tokenDeltas = new int256[](2);
        tokenDeltas[0] = amount0;
        tokenDeltas[1] = amount1;

        if (isToken0 == (amountDesired > 0)) {
            if (amount1 < 0) SafeTransferLib.safeTransfer(token1, msg.sender, uint256(-amount1));
            uint256 balance0Before = BalanceLib.getBalance(token0);
            IExecuteCallback(msg.sender).executeCallback(
                IExecuteCallback.CallbackParams(
                    tokens,
                    tokenDeltas,
                    new bytes32[](0),
                    new uint256[](0),
                    new Engine.OrderType[](0),
                    new bytes[](0),
                    bytes("")
                )
            );
            if (BalanceLib.getBalance(token0) < balance0Before + uint256(amount0)) revert();
        } else {
            if (amount0 < 0) SafeTransferLib.safeTransfer(token0, msg.sender, uint256(-amount0));
            uint256 balance1Before = BalanceLib.getBalance(token1);
            IExecuteCallback(msg.sender).executeCallback(
                IExecuteCallback.CallbackParams(
                    tokens,
                    tokenDeltas,
                    new bytes32[](0),
                    new uint256[](0),
                    new Engine.OrderType[](0),
                    new bytes[](0),
                    bytes("")
                )
            );
            if (BalanceLib.getBalance(token1) < balance1Before + uint256(amount1)) revert();
        }
    }

    function getPair()
        external
        view
        returns (
            uint128[NUM_SPREADS] memory composition,
            int24[NUM_SPREADS] memory strikeCurrent,
            int24 cachedStrikeCurrent,
            uint8 initialized
        )
    {
        (composition, strikeCurrent, cachedStrikeCurrent, initialized) =
            (pair.composition, pair.strikeCurrent, pair.cachedStrikeCurrent, pair.initialized);
    }

    function getStrike(int24 strike) external view returns (Pairs.Strike memory) {
        return pair.strikes[strike];
    }

    function getPositionBiDirectional(
        address owner,
        int24 strike,
        uint8 spread
    )
        external
        view
        returns (uint256 balance)
    {
        return _dataOf[owner][_biDirectionalID(token0, token1, strike, spread)].balance;
    }

    function getPositionLimit(
        address owner,
        int24 strike,
        bool zeroToOne,
        uint256 liquidityGrowthLast
    )
        external
        view
        returns (uint256 balance)
    {
        return _dataOf[owner][_limitID(token0, token1, strike, zeroToOne, liquidityGrowthLast)].balance;
    }

    function getPositionDebt(
        address owner,
        int24 strike,
        Engine.TokenSelector selector
    )
        external
        view
        returns (uint256 balance, uint256 liquidity, uint256 liquidityGrowthX128Last, uint256 leverageRatioX128)
    {
        balance = _dataOf[owner][_debtID(token0, token1, strike, selector)].balance;
        Positions.DebtData memory debtData = _dataOfDebt(owner, token0, token1, strike, selector);

        return (balance, debtData.liquidity, debtData.liquidityGrowthX128Last, leverageRatioX128);
    }
}
