// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";

/// @notice Stateless system-contract mock. Tests `vm.etch` its bytecode at
///         `0x8888…8888` so `AbstractReactive` talks to it. No storage is
///         used because `etch` copies code only; results are observed via events.
contract MockSystem is ISystemContract {
    event Subscribed(
        uint256 chainId,
        address contractAddress,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3
    );
    event Unsubscribed(
        uint256 chainId,
        address contractAddress,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3
    );
    event CallbackRequested(uint256 chainId, address recipient, uint64 gasLimit, bytes payload);

    receive() external payable {}

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external {
        emit Subscribed(chainId_, contract_, topic0_, topic1_, topic2_, topic3_);
    }

    function unsubscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external {
        emit Unsubscribed(chainId_, contract_, topic0_, topic1_, topic2_, topic3_);
    }

    function requestCallback(CallbackVersion, bytes memory) external {}

    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external {
        emit CallbackRequested(
            config_.chainId, config_.recipient, config_.gasLimit, config_.payload
        );
    }
}
