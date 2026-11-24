// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {ITriageDesk} from "./ITriageDesk.sol";
import {TriageScore} from "./TriageScore.sol";

/// @title Destination clerk that stores cases and policy verdicts.
/// @notice Lives on Base Sepolia. Only the configured Reactive contract, via
///         the official callback proxy, can open cases. A designated policy
///         clerk (the off-chain agent in this repo) files verdicts.
contract TriageDesk is AbstractCallback, ITriageDesk {
    error NotOwner();
    error NotClerk();
    error ZeroAddress();
    error UnknownCase(uint256 caseId);
    error VerdictAlreadyFiled(uint256 caseId);
    error InvalidAction(uint8 action);

    event ClerkUpdated(address indexed clerk);
    event CaseOpened(
        uint256 indexed caseId,
        uint8 kind,
        address indexed subject,
        address indexed counterparty,
        uint256 amount,
        uint8 score,
        uint256 originChainId,
        address originContract,
        uint256 originTxHash,
        uint256 originBlock
    );
    event VerdictFiled(
        uint256 indexed caseId,
        uint8 severity,
        uint8 action,
        bytes32 policyId,
        bytes32 rationaleHash,
        string rationale
    );
    event AlertRaised(
        uint256 indexed caseId,
        address indexed subject,
        address indexed counterparty,
        uint8 kind,
        uint256 amount,
        uint8 severity,
        string rationale
    );

    struct Case {
        bool opened;
        bool verdictFiled;
        uint8 kind;
        uint8 score;
        uint8 severity;
        uint8 action;
        address subject;
        address counterparty;
        uint256 amount;
        uint256 originChainId;
        address originContract;
        uint256 originTxHash;
        uint256 originBlock;
        bytes32 policyId;
        bytes32 rationaleHash;
    }

    address public owner;
    address public clerk;
    uint256 public caseCount;
    mapping(uint256 => Case) public cases;

    /// @notice Convenience accessor so clients and tests can load a case as a struct.
    function getCase(uint256 caseId_) external view returns (Case memory) {
        return cases[caseId_];
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyClerk() {
        if (msg.sender != clerk) revert NotClerk();
        _;
    }

    constructor(IPayable callbackProxy_, address callbackSender_, address clerk_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        if (address(callbackProxy_) == address(0) || callbackSender_ == address(0)) {
            revert ZeroAddress();
        }
        owner = msg.sender;
        clerk = clerk_ == address(0) ? msg.sender : clerk_;
        emit ClerkUpdated(clerk);
    }

    function setClerk(address clerk_) external onlyOwner {
        if (clerk_ == address(0)) revert ZeroAddress();
        clerk = clerk_;
        emit ClerkUpdated(clerk_);
    }

    /// @inheritdoc ITriageDesk
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
    ) external onlyServiceProvider onlyCallbackSender(sender_) {
        uint256 id = ++caseCount;
        Case storage c = cases[id];
        c.opened = true;
        c.kind = kind_;
        c.score = score_;
        c.subject = subject_;
        c.counterparty = counterparty_;
        c.amount = amount_;
        c.originChainId = originChainId_;
        c.originContract = originContract_;
        c.originTxHash = originTxHash_;
        c.originBlock = originBlock_;

        emit CaseOpened(
            id,
            kind_,
            subject_,
            counterparty_,
            amount_,
            score_,
            originChainId_,
            originContract_,
            originTxHash_,
            originBlock_
        );
    }

    /// @notice Files the running policy agent's verdict for an open case.
    /// @dev The rationale string is emitted (and hashed in storage) so a demo
    ///      can show why the agent escalated without a separate database.
    function fileVerdict(
        uint256 caseId_,
        uint8 severity_,
        uint8 action_,
        bytes32 policyId_,
        string calldata rationale_
    ) external onlyClerk {
        if (action_ > TriageScore.ACTION_ESCALATE) revert InvalidAction(action_);

        Case storage c = cases[caseId_];
        if (!c.opened) revert UnknownCase(caseId_);
        if (c.verdictFiled) revert VerdictAlreadyFiled(caseId_);

        c.verdictFiled = true;
        c.severity = severity_;
        c.action = action_;
        c.policyId = policyId_;
        c.rationaleHash = keccak256(bytes(rationale_));

        emit VerdictFiled(caseId_, severity_, action_, policyId_, c.rationaleHash, rationale_);

        if (action_ == TriageScore.ACTION_ESCALATE) {
            emit AlertRaised(
                caseId_, c.subject, c.counterparty, c.kind, c.amount, severity_, rationale_
            );
        }
    }
}
