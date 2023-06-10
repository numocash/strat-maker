// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library BalanceLib {
    error FailedBalanceOf();

    function getBalance(address token) internal view returns (uint256) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        if (!success || data.length != 32) revert FailedBalanceOf();
        return abi.decode(data, (uint256));
    }
}
