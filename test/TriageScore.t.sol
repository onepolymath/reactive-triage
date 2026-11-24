// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {TriageScore} from "../src/TriageScore.sol";

contract TriageScoreHarness {
    function score(
        uint8 kind_,
        address subject_,
        address counterparty_,
        uint256 amount_,
        uint256 largeTransfer_,
        uint256 largeApproval_,
        uint256 dust_
    ) external pure returns (uint8) {
        return TriageScore.score(
            kind_, subject_, counterparty_, amount_, largeTransfer_, largeApproval_, dust_
        );
    }

    function suggestedAction(uint8 score_) external pure returns (uint8) {
        return TriageScore.suggestedAction(score_);
    }
}

contract TriageScoreTest is Test {
    TriageScoreHarness internal harness;
    uint256 internal constant LARGE_TRANSFER = 1000 ether;
    uint256 internal constant LARGE_APPROVAL = 10_000 ether;
    uint256 internal constant DUST = 0.001 ether;

    function setUp() public {
        harness = new TriageScoreHarness();
    }

    function test_unlimitedApprovalScoresHigh() public view {
        assertEq(
            harness.score(
                TriageScore.KIND_APPROVAL,
                address(1),
                address(2),
                type(uint256).max,
                LARGE_TRANSFER,
                LARGE_APPROVAL,
                DUST
            ),
            90
        );
        assertEq(
            harness.score(
                TriageScore.KIND_APPROVAL,
                address(1),
                address(2),
                type(uint128).max,
                LARGE_TRANSFER,
                LARGE_APPROVAL,
                DUST
            ),
            90
        );
    }

    function test_largeApproval() public view {
        assertEq(
            harness.score(
                TriageScore.KIND_APPROVAL,
                address(1),
                address(2),
                LARGE_APPROVAL,
                LARGE_TRANSFER,
                LARGE_APPROVAL,
                DUST
            ),
            70
        );
    }

    function test_routineApproval() public view {
        assertEq(
            harness.score(
                TriageScore.KIND_APPROVAL,
                address(1),
                address(2),
                1 ether,
                LARGE_TRANSFER,
                LARGE_APPROVAL,
                DUST
            ),
            45
        );
    }

    function test_mintBurnDustAndLargeTransfer() public view {
        assertEq(
            harness.score(
                TriageScore.KIND_TRANSFER,
                address(0),
                address(1),
                5 ether,
                LARGE_TRANSFER,
                LARGE_APPROVAL,
                DUST
            ),
            20
        );
        assertEq(
            harness.score(
                TriageScore.KIND_TRANSFER,
                address(1),
                address(0),
                5 ether,
                LARGE_TRANSFER,
                LARGE_APPROVAL,
                DUST
            ),
            30
        );
        assertEq(
            harness.score(
                TriageScore.KIND_TRANSFER,
                address(1),
                address(2),
                DUST,
                LARGE_TRANSFER,
                LARGE_APPROVAL,
                DUST
            ),
            10
        );
        assertEq(
            harness.score(
                TriageScore.KIND_TRANSFER,
                address(1),
                address(2),
                LARGE_TRANSFER,
                LARGE_TRANSFER,
                LARGE_APPROVAL,
                DUST
            ),
            75
        );
        assertEq(
            harness.score(
                TriageScore.KIND_TRANSFER,
                address(1),
                address(2),
                5 ether,
                LARGE_TRANSFER,
                LARGE_APPROVAL,
                DUST
            ),
            35
        );
    }

    function test_suggestedActionBands() public view {
        assertEq(harness.suggestedAction(90), TriageScore.ACTION_ESCALATE);
        assertEq(harness.suggestedAction(80), TriageScore.ACTION_ESCALATE);
        assertEq(harness.suggestedAction(70), TriageScore.ACTION_WATCH);
        assertEq(harness.suggestedAction(60), TriageScore.ACTION_WATCH);
        assertEq(harness.suggestedAction(59), TriageScore.ACTION_RECORD);
        assertEq(harness.suggestedAction(0), TriageScore.ACTION_RECORD);
    }
}
