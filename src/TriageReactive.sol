// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {ITriageDesk} from "./ITriageDesk.sol";
import {TriageScore} from "./TriageScore.sol";

/// @title Lasna reactive clerk that scores origin ERC-20 logs and opens cases.
/// @notice Subscribes to Transfer and Approval on a specific origin token.
///         `react()` does real work (decode + score) before requesting an
///         authenticated callback to `TriageDesk` on the destination chain.
///         Ordinary mismatches return without reverting so the network is not
///         billed for a failed reactive transaction.
contract TriageReactive is AbstractReactive {
    error InvalidConfig();

    uint256 internal constant TRANSFER_TOPIC =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    uint256 internal constant APPROVAL_TOPIC =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    uint256 public immutable originChainId;
    address public immutable originToken;
    address public immutable desk;
    uint64 public immutable callbackGasLimit;
    uint256 public immutable largeTransfer;
    uint256 public immutable largeApproval;
    uint256 public immutable dust;

    event CaseRequested(
        uint8 kind,
        address indexed subject,
        address indexed counterparty,
        uint256 amount,
        uint8 score,
        uint256 originTxHash,
        uint256 originBlock
    );

    constructor(
        uint256 originChainId_,
        address originToken_,
        address desk_,
        uint64 callbackGasLimit_,
        uint256 largeTransfer_,
        uint256 largeApproval_,
        uint256 dust_
    ) payable AbstractReactive() {
        if (originChainId_ == 0 || originToken_ == address(0) || desk_ == address(0)) {
            revert InvalidConfig();
        }
        if (callbackGasLimit_ == 0) revert InvalidConfig();

        originChainId = originChainId_;
        originToken = originToken_;
        desk = desk_;
        callbackGasLimit = callbackGasLimit_;
        largeTransfer = largeTransfer_;
        largeApproval = largeApproval_;
        dust = dust_;

        // Specific origin chain + contract + topic0 (two subscriptions).
        SYSTEM.subscribe(
            originChainId_,
            originToken_,
            TRANSFER_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        SYSTEM.subscribe(
            originChainId_,
            originToken_,
            APPROVAL_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        if (log_.chainId != originChainId || log_.contractAddress != originToken) {
            return;
        }

        uint8 kind;
        if (log_.topic0 == TRANSFER_TOPIC) {
            kind = TriageScore.KIND_TRANSFER;
        } else if (log_.topic0 == APPROVAL_TOPIC) {
            kind = TriageScore.KIND_APPROVAL;
        } else {
            return;
        }

        address subject = address(uint160(log_.topic1));
        address counterparty = address(uint160(log_.topic2));
        uint256 amount = 0;
        if (log_.data.length >= 32) {
            amount = abi.decode(log_.data, (uint256));
        }

        uint8 scored = TriageScore.score(
            kind, subject, counterparty, amount, largeTransfer, largeApproval, dust
        );

        emit CaseRequested(
            kind, subject, counterparty, amount, scored, log_.txHash, log_.blockNumber
        );

        bytes memory payload = abi.encodeWithSelector(
            ITriageDesk.openCase.selector,
            address(0),
            kind,
            subject,
            counterparty,
            amount,
            scored,
            log_.chainId,
            log_.contractAddress,
            log_.txHash,
            log_.blockNumber
        );

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: originChainId,
                recipient: desk,
                gasLimit: callbackGasLimit,
                payload: payload
            })
        );
    }
}
