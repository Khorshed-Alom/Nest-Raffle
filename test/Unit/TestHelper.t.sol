//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract RejectingReceiver {
    fallback() external payable {
        revert("Can't receive ETH");
    }

    receive() external payable {
        revert("Still can't receive ETH");
    }
}
