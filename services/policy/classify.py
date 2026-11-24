"""Deterministic first-pass policy used by the running clerk.

The on-chain reactive contract already attaches a numeric score. This module
turns the opened case into a verdict the desk can store: a severity, an
action (record / watch / escalate), a stable policy id, and a rationale.

An optional language-model wrapper may rewrite the rationale, but the action
never depends on a paid API.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Optional

KIND_TRANSFER = 0
KIND_APPROVAL = 1

ACTION_RECORD = 0
ACTION_WATCH = 1
ACTION_ESCALATE = 2

ACTION_NAME = {
    ACTION_RECORD: "record",
    ACTION_WATCH: "watch",
    ACTION_ESCALATE: "escalate",
}
KIND_NAME = {KIND_TRANSFER: "transfer", KIND_APPROVAL: "approval"}

POLICY_ID = "heuristic-v1"
UNLIMITED_THRESHOLD = (1 << 128) - 1
ZERO_ADDRESS = "0x" + ("00" * 20)


def _addr(value: str) -> str:
    return (value or "").lower()


@dataclass(frozen=True)
class CaseView:
    case_id: int
    kind: int
    subject: str
    counterparty: str
    amount: int
    score: int


@dataclass(frozen=True)
class Verdict:
    case_id: int
    severity: int
    action: int
    policy_id: str
    rationale: str

    @property
    def action_name(self) -> str:
        return ACTION_NAME.get(self.action, str(self.action))

    @property
    def policy_id_bytes32(self) -> bytes:
        # keccak of the utf-8 policy id, computed lazily by the agent when needed
        return self.policy_id.encode("utf-8")


def classify(case: CaseView, *, large_transfer: int = 10**21, large_approval: int = 10**22) -> Verdict:
    """Return a verdict. Severity stays close to the on-chain score unless a
    named rule clearly dominates (unlimited approval, mint, dust)."""
    kind = case.kind
    amount = case.amount
    score = case.score
    subject = _addr(case.subject)
    counterparty = _addr(case.counterparty)
    kind_name = KIND_NAME.get(kind, f"kind-{kind}")

    if kind == KIND_APPROVAL and amount >= UNLIMITED_THRESHOLD:
        return Verdict(
            case_id=case.case_id,
            severity=max(score, 90),
            action=ACTION_ESCALATE,
            policy_id=POLICY_ID,
            rationale=(
                f"Unlimited {kind_name} ({amount}) from {subject} to spender "
                f"{counterparty}. This is the classic 'set and forget' foot-gun; "
                "escalate so the owner can revoke it."
            ),
        )

    if kind == KIND_APPROVAL and amount >= large_approval:
        return Verdict(
            case_id=case.case_id,
            severity=max(score, 70),
            action=ACTION_WATCH,
            policy_id=POLICY_ID,
            rationale=(
                f"Large {kind_name} of {amount} from {subject} to {counterparty}. "
                "Not unlimited, but large enough to watch."
            ),
        )

    if kind == KIND_TRANSFER and subject == ZERO_ADDRESS:
        return Verdict(
            case_id=case.case_id,
            severity=min(score, 20),
            action=ACTION_RECORD,
            policy_id=POLICY_ID,
            rationale=f"Mint of {amount} to {counterparty}. Recorded, not escalated.",
        )

    if kind == KIND_TRANSFER and counterparty == ZERO_ADDRESS:
        return Verdict(
            case_id=case.case_id,
            severity=max(score, 30),
            action=ACTION_RECORD,
            policy_id=POLICY_ID,
            rationale=f"Burn of {amount} from {subject}. Recorded.",
        )

    if kind == KIND_TRANSFER and amount >= large_transfer:
        return Verdict(
            case_id=case.case_id,
            severity=max(score, 75),
            action=ACTION_WATCH,
            policy_id=POLICY_ID,
            rationale=(
                f"Large transfer of {amount} from {subject} to {counterparty}. "
                "Watch for a follow-up drain or a linked approval."
            ),
        )

    if score >= 80:
        action = ACTION_ESCALATE
        note = "On-chain score is in the escalate band."
    elif score >= 60:
        action = ACTION_WATCH
        note = "On-chain score is in the watch band."
    else:
        action = ACTION_RECORD
        note = "Routine event; keep a record only."

    return Verdict(
        case_id=case.case_id,
        severity=score,
        action=action,
        policy_id=POLICY_ID,
        rationale=f"{kind_name.capitalize()} of {amount} from {subject} to {counterparty}. {note}",
    )


def maybe_rewrite_rationale(verdict: Verdict, rewriter: Optional[Callable[[Verdict], str]] = None) -> Verdict:
    """Optionally rewrite the rationale with an LLM. The action and severity stay."""
    if rewriter is None:
        return verdict
    rewritten = rewriter(verdict)
    if not rewritten or not isinstance(rewritten, str):
        return verdict
    return Verdict(
        case_id=verdict.case_id,
        severity=verdict.severity,
        action=verdict.action,
        policy_id=verdict.policy_id,
        rationale=rewritten.strip(),
    )
