#!/usr/bin/env bash
# Mint, transfer, and approve on the deployed DemoToken so Lasna can react.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="/home/box/.foundry/bin:$PATH"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${PRIVATE_KEY:?Set PRIVATE_KEY in .env}"
: "${BASE_SEPOLIA_RPC:=https://sepolia.base.org}"

if [[ ! -f deployments/testnet.json ]]; then
  echo "Missing deployments/testnet.json — run scripts/deploy-testnet.sh first." >&2
  exit 1
fi

CHAIN="$(cast chain-id --rpc-url "$BASE_SEPOLIA_RPC")"
if [[ "$CHAIN" != "84532" ]]; then
  echo "Refusing: not Base Sepolia." >&2
  exit 2
fi

TOKEN="$(python3 -c "import json; print(json.load(open('deployments/testnet.json'))['baseSepolia']['demoToken'])")"
ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
COUNTERPARTY="0x3333333333333333333333333333333333333333"

extract_hash() {
  python3 -c 'import sys,re; t=sys.stdin.read(); m=re.search(r"transactionHash\s+(0x[0-9a-fA-F]{64})", t); print(m.group(1) if m else "")' <<< "$1"
}

echo "Minting 1,000,000 TRIAGE to $ADDR"
MINT_OUT="$(cast send "$TOKEN" "mint(address,uint256)" "$ADDR" 1000000000000000000000000 \
  --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PRIVATE_KEY")"
echo "$MINT_OUT"
MINT_TX="$(extract_hash "$MINT_OUT")"

echo "Routine transfer of 5 TRIAGE"
XFER_OUT="$(cast send "$TOKEN" "transfer(address,uint256)" "$COUNTERPARTY" 5000000000000000000 \
  --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PRIVATE_KEY")"
echo "$XFER_OUT"
XFER_TX="$(extract_hash "$XFER_OUT")"

echo "Large transfer of 1,000 TRIAGE"
LARGE_OUT="$(cast send "$TOKEN" "transfer(address,uint256)" "$COUNTERPARTY" 1000000000000000000000 \
  --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PRIVATE_KEY")"
echo "$LARGE_OUT"
LARGE_TX="$(extract_hash "$LARGE_OUT")"

echo "Unlimited approval to $COUNTERPARTY"
APPROVE_OUT="$(cast send "$TOKEN" "approve(address,uint256)" "$COUNTERPARTY" \
  115792089237316195423570985008687907853269984665640564039457584007913129639935 \
  --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PRIVATE_KEY")"
echo "$APPROVE_OUT"
APPROVE_TX="$(extract_hash "$APPROVE_OUT")"

python3 - "$TOKEN" "$ADDR" "$COUNTERPARTY" "$MINT_TX" "$XFER_TX" "$LARGE_TX" "$APPROVE_TX" << 'ENDJSON'
import json, sys
from pathlib import Path
token, addr, counterparty, mint_tx, xfer_tx, large_tx, approve_tx = sys.argv[1:]
payload = {
    "token": token,
    "from": addr,
    "counterparty": counterparty,
    "originTxs": {
        "mint": mint_tx,
        "routineTransfer": xfer_tx,
        "largeTransfer": large_tx,
        "unlimitedApproval": approve_tx,
    },
    "note": "These are origin-chain hashes only. After Lasna reacts, add the react and callback hashes to deployments/loop.json.",
}
Path("deployments/demo-events.json").write_text(json.dumps(payload, indent=2) + "\n")
print(json.dumps(payload, indent=2))
ENDJSON
