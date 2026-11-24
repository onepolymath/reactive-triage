// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title Destination-side clerk desk that records cases opened by callbacks.
interface ITriageDesk {
    /// @notice Authenticated callback from the Lasna reactive contract.
    /// @dev The first argument is overwritten by the callback proxy with the
    ///      reactive contract address. Pass `address(0)` when encoding.
    function openCase(
        address sender_,
        uint8 kind_,
        address subject_,
        address counterparty_,
        uint256 amount_,
        uint8 score_,
        uint256 originChainId_,
        address originContract_,
        uint256 originTxHash_,
        uint256 originBlock_
    ) external;
}
