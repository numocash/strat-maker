// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Accounts} from "src/core/Accounts.sol";
import {Engine} from "src/core/Engine.sol";
import {Router} from "src/periphery/Router.sol";

contract RouteTest is Test {
    Router private router;

    bool private flag;
    uint256 private amount;

    function execute(
        address,
        Engine.CommandInput[] calldata,
        uint256,
        uint256,
        bytes calldata
    )
        external
        payable
        returns (Accounts.Account memory account)
    {
        flag = true;
        amount = msg.value;

        return account;
    }

    function setUp() external {
        router = new Router(payable(address(this)), address(0));
    }

    function test_Route() external {
        vm.pauseGasMetering();

        Router.RouteParams memory routeParams;

        vm.resumeGasMetering();

        router.route(routeParams);

        vm.pauseGasMetering();

        assertEq(flag, true);
        assertEq(amount, 0);

        delete flag;
        delete amount;

        vm.resumeGasMetering();
    }

    function test_Router_Ether() external {
        vm.pauseGasMetering();

        Router.RouteParams memory routeParams;

        vm.deal(address(this), 1e18);

        vm.resumeGasMetering();

        router.route{value: 1e18}(routeParams);

        vm.pauseGasMetering();

        assertEq(flag, true);
        assertEq(amount, 1e18);

        delete flag;
        delete amount;

        vm.resumeGasMetering();
    }
}
