// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title On-chain first-pass scoring for Transfer and Approval events.
/// @notice Pure helpers used by the Lasna reactive contract so the callback
///         already carries a useful severity, not just a raw log replay.
library TriageScore {
    uint8 internal constant KIND_TRANSFER = 0;
    uint8 internal constant KIND_APPROVAL = 1;

    uint8 internal constant ACTION_RECORD = 0;
    uint8 internal constant ACTION_WATCH = 1;
    uint8 internal constant ACTION_ESCALATE = 2;

    /// @notice Approvals at or above this amount are treated as unlimited.
    uint256 internal constant UNLIMITED_THRESHOLD = type(uint128).max;

    function score(
        uint8 kind_,
        address subject_,
        address counterparty_,
        uint256 amount_,
        uint256 largeTransfer_,
        uint256 largeApproval_,
        uint256 dust_
    ) internal pure returns (uint8) {
        if (kind_ == KIND_APPROVAL) {
            if (amount_ >= UNLIMITED_THRESHOLD) {
                return 90;
            }
            if (amount_ >= largeApproval_) {
                return 70;
            }
            return 45;
        }

        // Transfer
        if (subject_ == address(0)) {
            return 20; // mint
        }
        if (counterparty_ == address(0)) {
            return 30; // burn
        }
        if (dust_ > 0 && amount_ <= dust_) {
            return 10;
        }
        if (amount_ >= largeTransfer_) {
            return 75;
        }
        return 35;
    }

    function suggestedAction(uint8 score_) internal pure returns (uint8) {
        if (score_ >= 80) {
            return ACTION_ESCALATE;
        }
        if (score_ >= 60) {
            return ACTION_WATCH;
        }
        return ACTION_RECORD;
    }
}
