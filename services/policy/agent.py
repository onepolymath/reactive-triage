"""Watch CaseOpened events and file verdicts on TriageDesk.

The agent is part of the running system, not just a tool used to write the
contracts. It works with a local heuristic by default. Set OPENAI_API_KEY only
if you want a rewritten rationale; the action is decided before any API call.

Usage:
  python3 -m services.policy.agent --dry-run --cases demo/cases.json
  python3 -m services.policy.agent --rpc-url "$BASE_SEPOLIA_RPC" \\
      --desk 0x... --private-key "$PRIVATE_KEY"
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Iterable

# Allow `python3 services/policy/agent.py` and `python3 -m services.policy.agent`
ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from services.policy.classify import (  # noqa: E402
    POLICY_ID,
    CaseView,
    Verdict,
    classify,
    maybe_rewrite_rationale,
)

# fileVerdict(uint256,uint8,uint8,bytes32,string)
FILE_VERDICT_SELECTOR = "0xb3a1c119"  # placeholder; overwritten at runtime via keccak if needed

CASE_OPENED_TOPIC0 = None  # filled from keccak


def keccak256(data: bytes) -> bytes:
    """Keccak-256 without depending on pycryptodome, if pysha3/sha3 missing.

    Prefer the `sha3` package, then pysha3, then a tiny fallback via `pysha3`
    is not assumed. We try hashlib (won't work for keccak), then pysha3, then
    ask `cast` if it is on PATH.
    """
    try:
        from sha3 import keccak_256  # type: ignore

        return keccak_256(data).digest()
    except Exception:
        pass
    try:
        from Crypto.Hash import keccak  # type: ignore

        h = keccak.new(digest_bits=256)
        h.update(data)
        return h.digest()
    except Exception:
        pass
    # Fall back to `cast keccak`
    import subprocess

    proc = subprocess.run(
        ["cast", "keccak", "0x" + data.hex()],
        check=True,
        capture_output=True,
        text=True,
    )
    return bytes.fromhex(proc.stdout.strip().removeprefix("0x"))


def _hex(value: int, size: int = 32) -> str:
    return value.to_bytes(size, "big").hex()


def policy_id_bytes32(policy_id: str = POLICY_ID) -> bytes:
    return keccak256(policy_id.encode("utf-8"))


def encode_file_verdict(verdict: Verdict) -> str:
    """ABI-encode fileVerdict(...) with the official selector."""
    selector = keccak256(b"fileVerdict(uint256,uint8,uint8,bytes32,string)")[:4]
    rationale = verdict.rationale.encode("utf-8")
    # head: 5 args, last is dynamic (offset 160 = 0xa0)
    head = (
        _hex(verdict.case_id)
        + _hex(verdict.severity)
        + _hex(verdict.action)
        + policy_id_bytes32(verdict.policy_id).hex()
        + _hex(160)
    )
    tail = _hex(len(rationale)) + rationale.hex()
    pad = (32 - (len(rationale) % 32)) % 32
    tail += "00" * pad
    return "0x" + selector.hex() + head + tail


def case_from_dict(raw: dict[str, Any]) -> CaseView:
    return CaseView(
        case_id=int(raw["case_id"], 0) if isinstance(raw["case_id"], str) else int(raw["case_id"]),
        kind=int(raw["kind"]),
        subject=str(raw["subject"]),
        counterparty=str(raw["counterparty"]),
        amount=int(raw["amount"], 0) if isinstance(raw["amount"], str) else int(raw["amount"]),
        score=int(raw["score"]),
    )


def load_cases(path: Path) -> list[CaseView]:
    data = json.loads(path.read_text())
    if isinstance(data, dict) and "cases" in data:
        data = data["cases"]
    return [case_from_dict(item) for item in data]


def optional_llm_rewriter(verdict: Verdict) -> str:
    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not api_key:
        return verdict.rationale
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    body = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": (
                    "Rewrite the rationale for a blockchain policy verdict in two "
                    "short sentences. Do not change the recommended action. Do not "
                    "invent extra facts."
                ),
            },
            {"role": "user", "content": verdict.rationale},
        ],
        "temperature": 0.2,
        "max_tokens": 120,
    }
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        text = payload["choices"][0]["message"]["content"]
        return text.strip() or verdict.rationale
    except (urllib.error.URLError, KeyError, IndexError, TimeoutError):
        return verdict.rationale


def decide(case: CaseView, *, use_llm: bool) -> Verdict:
    verdict = classify(case)
    if use_llm:
        verdict = maybe_rewrite_rationale(verdict, optional_llm_rewriter)
    return verdict


def rpc(url: str, method: str, params: list[Any]) -> Any:
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    if "error" in payload:
        raise RuntimeError(payload["error"])
    return payload["result"]


def file_verdict_onchain(rpc_url: str, private_key: str, desk: str, verdict: Verdict) -> str:
    """Send fileVerdict using `cast send` so we do not store keys in Python longer than needed."""
    import subprocess

    policy_hex = "0x" + policy_id_bytes32(verdict.policy_id).hex()
    cmd = [
        "cast",
        "send",
        desk,
        "fileVerdict(uint256,uint8,uint8,bytes32,string)",
        str(verdict.case_id),
        str(verdict.severity),
        str(verdict.action),
        policy_hex,
        verdict.rationale,
        "--private-key",
        private_key,
        "--rpc-url",
        rpc_url,
    ]
    proc = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return proc.stdout.strip()


def render(verdict: Verdict) -> dict[str, Any]:
    return {
        "case_id": verdict.case_id,
        "severity": verdict.severity,
        "action": verdict.action,
        "action_name": verdict.action_name,
        "policy_id": verdict.policy_id,
        "rationale": verdict.rationale,
        "calldata": encode_file_verdict(verdict),
    }


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Triage policy clerk")
    parser.add_argument("--cases", type=Path, help="JSON fixture of opened cases")
    parser.add_argument("--dry-run", action="store_true", help="Print verdicts; do not send a transaction")
    parser.add_argument("--rpc-url", default=os.environ.get("BASE_SEPOLIA_RPC", "https://sepolia.base.org"))
    parser.add_argument("--desk", help="TriageDesk address")
    parser.add_argument("--private-key", default=os.environ.get("PRIVATE_KEY", ""))
    parser.add_argument("--use-llm", action="store_true", help="Rewrite rationales when OPENAI_API_KEY is set")
    parser.add_argument("--out", type=Path, help="Write verdicts JSON to this path")
    args = parser.parse_args(list(argv) if argv is not None else None)

    if not args.cases:
        parser.error("provide --cases path (use demo/cases.json for the fixture walkthrough)")

    cases = load_cases(args.cases)
    verdicts = [decide(case, use_llm=args.use_llm) for case in cases]
    rendered = [render(v) for v in verdicts]
    text = json.dumps(rendered, indent=2)
    print(text)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + "\n")

    if args.dry_run:
        return 0

    if not args.desk or not args.private_key:
        parser.error("on-chain filing requires --desk and --private-key (or PRIVATE_KEY)")

    for verdict in verdicts:
        print(file_verdict_onchain(args.rpc_url, args.private_key, args.desk, verdict), file=sys.stderr)
        time.sleep(0.5)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
