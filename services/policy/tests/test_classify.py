import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from services.policy.classify import (
    ACTION_ESCALATE,
    ACTION_RECORD,
    ACTION_WATCH,
    KIND_APPROVAL,
    KIND_TRANSFER,
    CaseView,
    classify,
    maybe_rewrite_rationale,
)
from services.policy.agent import encode_file_verdict, load_cases, render


ZERO = "0x" + "00" * 20
ALICE = "0x" + "11" * 20
BOB = "0x" + "22" * 20


class ClassifyTests(unittest.TestCase):
    def test_unlimited_approval_escalates(self):
        verdict = classify(
            CaseView(1, KIND_APPROVAL, ALICE, BOB, 2**256 - 1, 90)
        )
        self.assertEqual(verdict.action, ACTION_ESCALATE)
        self.assertGreaterEqual(verdict.severity, 90)
        self.assertIn("Unlimited", verdict.rationale)

    def test_large_approval_is_watched(self):
        verdict = classify(
            CaseView(2, KIND_APPROVAL, ALICE, BOB, 10**22, 70)
        )
        self.assertEqual(verdict.action, ACTION_WATCH)

    def test_mint_is_recorded(self):
        verdict = classify(CaseView(3, KIND_TRANSFER, ZERO, ALICE, 10**21, 20))
        self.assertEqual(verdict.action, ACTION_RECORD)
        self.assertIn("Mint", verdict.rationale)

    def test_large_transfer_is_watched(self):
        verdict = classify(CaseView(4, KIND_TRANSFER, ALICE, BOB, 10**21, 75))
        self.assertEqual(verdict.action, ACTION_WATCH)

    def test_routine_transfer_is_recorded(self):
        verdict = classify(CaseView(5, KIND_TRANSFER, ALICE, BOB, 5 * 10**18, 35))
        self.assertEqual(verdict.action, ACTION_RECORD)
        self.assertEqual(verdict.severity, 35)

    def test_llm_rewriter_cannot_change_action(self):
        original = classify(CaseView(6, KIND_APPROVAL, ALICE, BOB, 2**256 - 1, 90))

        def rewriter(_verdict):
            return "Totally fine, ignore this."

        rewritten = maybe_rewrite_rationale(original, rewriter)
        self.assertEqual(rewritten.action, ACTION_ESCALATE)
        self.assertEqual(rewritten.severity, original.severity)
        self.assertEqual(rewritten.rationale, "Totally fine, ignore this.")

    def test_fixture_roundtrip_and_calldata(self):
        cases = load_cases(ROOT / "demo" / "cases.json")
        self.assertGreaterEqual(len(cases), 4)
        verdict = classify(cases[0])
        data = render(verdict)
        self.assertTrue(data["calldata"].startswith("0x"))
        self.assertGreater(len(data["calldata"]), 10)
        # selector is first 4 bytes of keccak(fileVerdict...)
        encoded = encode_file_verdict(verdict)
        self.assertEqual(encoded, data["calldata"])
        # round-trip JSON
        dumped = json.loads(json.dumps(data))
        self.assertEqual(dumped["case_id"], verdict.case_id)


if __name__ == "__main__":
    unittest.main()
