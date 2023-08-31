// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {Pairs} from "src/core/Pairs.sol";
import {Positions, debtID} from "src/core/Positions.sol";

import {getAmounts} from "src/core/math/LiquidityMath.sol";
import {Q128} from "src/core/math/StrikeMath.sol";

contract RepayLiquidityTest is Test, Engine {
    using Accounts for Accounts.Account;
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    function test_RepayLiquidity_LiquidityAccruedZero() external {}

    function test_RepayLiquidity_LiquidityAccrued() external {}

    function test_RepayLiquidity_RepayLiquidityGrowthZero() external {}

    function test_RepayLiquidity_RepayLiquidityGrowth() external {}

    function test_RepayLiquidity_InvalidAmountDesired() external {}

    function test_RepayLiquidity_AmountsScaleZero() external {}

    function test_RepayLiquidity_AmountsScale() external {}
}
