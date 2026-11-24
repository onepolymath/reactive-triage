#!/usr/bin/env bash
# Deploy DemoToken + TriageDesk to Base Sepolia and TriageReactive to Lasna.
# Refuses mainnet RPCs and any chain id other than the two official testnets.
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

: "${PRIVATE_KEY:?Set PRIVATE_KEY in .env (throwaway testnet key only)}"
: "${BASE_SEPOLIA_RPC:=https://sepolia.base.org}"
: "${LASNA_RPC:=https://lasna-rpc.rnk.dev/}"

assert_chain() {
  local rpc="$1" expected="$2" label="$3"
  local got
  got="$(cast chain-id --rpc-url "$rpc")"
  if [[ "$got" != "$expected" ]]; then
    echo "Refusing to deploy: $label RPC reported chain id $got (expected $expected testnet)." >&2
    echo "This project deploys only to Base Sepolia (84532) and Lasna (5318007)." >&2
    exit 2
  fi
}

assert_chain "$BASE_SEPOLIA_RPC" "84532" "Base Sepolia"
assert_chain "$LASNA_RPC" "5318007" "Lasna"

ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
echo "Deployer: $ADDR"

BASE_BAL="$(cast balance "$ADDR" --rpc-url "$BASE_SEPOLIA_RPC")"
LASNA_BAL="$(cast balance "$ADDR" --rpc-url "$LASNA_RPC")"
echo "Base Sepolia balance (wei): $BASE_BAL"
echo "Lasna balance (wei):        $LASNA_BAL"

if [[ "$BASE_BAL" == "0" || "$LASNA_BAL" == "0" ]]; then
  echo >&2
  echo "Not deploying: the throwaway deployer needs faucet funds on both testnets." >&2
  echo "  1. Fund $ADDR with Base Sepolia ETH from a free faucet." >&2
  echo "  2. Swap a little of that ETH for lREACT via scripts/request-lreact.sh" >&2
  echo "     (sends Base Sepolia ETH to 0x2afaFD298b23b62760711756088F75B7409f5967)." >&2
  echo "If a faucet requires a captcha or login, stop and complete it yourself." >&2
  exit 3
fi

CALLBACK_PROXY="0x476F44b11F5C942c58f4c8E3d0300E5710743585"
GAS_LIMIT=400000
LARGE_TRANSFER=1000000000000000000000
LARGE_APPROVAL=10000000000000000000000
DUST=1000000000000000
CLERK="${CLERK:-$ADDR}"

BASE_NONCE="$(cast nonce "$ADDR" --rpc-url "$BASE_SEPOLIA_RPC")"
LASNA_NONCE="$(cast nonce "$ADDR" --rpc-url "$LASNA_RPC")"
TOKEN_ADDR="$(cast compute-address "$ADDR" --nonce "$BASE_NONCE" | awk '{print $NF}')"
DESK_ADDR="$(cast compute-address "$ADDR" --nonce $((BASE_NONCE + 1)) | awk '{print $NF}')"
REACTIVE_ADDR="$(cast compute-address "$ADDR" --nonce "$LASNA_NONCE" | awk '{print $NF}')"

echo "Predicted DemoToken:      $TOKEN_ADDR"
echo "Predicted TriageDesk:     $DESK_ADDR"
echo "Predicted TriageReactive: $REACTIVE_ADDR"

DESK_VALUE="$(python3 -c "bal=int('$BASE_BAL'); print(max(bal//10, 0) if bal>0 else 0)")"
REACTIVE_VALUE="$(python3 -c "bal=int('$LASNA_BAL'); print(max(bal//2, 0) if bal>0 else 0)")"

echo "Deploying DemoToken on Base Sepolia..."
TOKEN_OUT="$(forge create src/DemoToken.sol:DemoToken \
  --rpc-url "$BASE_SEPOLIA_RPC" \
  --private-key "$PRIVATE_KEY" \
  --broadcast --json)"
TOKEN_DEPLOYED="$(python3 -c "import json,sys; print(json.load(sys.stdin)['deployedTo'])" <<<"$TOKEN_OUT")"
TOKEN_TX="$(python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])" <<<"$TOKEN_OUT")"

echo "Deploying TriageDesk on Base Sepolia..."
DESK_OUT="$(forge create src/TriageDesk.sol:TriageDesk \
  --rpc-url "$BASE_SEPOLIA_RPC" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --value "$DESK_VALUE" \
  --json \
  --constructor-args "$CALLBACK_PROXY" "$REACTIVE_ADDR" "$CLERK")"
DESK_DEPLOYED="$(python3 -c "import json,sys; print(json.load(sys.stdin)['deployedTo'])" <<<"$DESK_OUT")"
DESK_TX="$(python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])" <<<"$DESK_OUT")"

echo "Deploying TriageReactive on Lasna..."
REACT_OUT="$(forge create src/TriageReactive.sol:TriageReactive \
  --rpc-url "$LASNA_RPC" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --value "$REACTIVE_VALUE" \
  --priority-gas-price 2gwei \
  --gas-price 250gwei \
  --timeout 180 \
  --json \
  --constructor-args 84532 "$TOKEN_DEPLOYED" "$DESK_DEPLOYED" "$GAS_LIMIT" "$LARGE_TRANSFER" "$LARGE_APPROVAL" "$DUST")"
REACT_DEPLOYED="$(python3 -c "import json,sys; print(json.load(sys.stdin)['deployedTo'])" <<<"$REACT_OUT")"
REACT_TX="$(python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])" <<<"$REACT_OUT")"

mkdir -p deployments
python3 - "$ADDR" "$CLERK" "$CALLBACK_PROXY" "$TOKEN_DEPLOYED" "$TOKEN_TX" "$DESK_DEPLOYED" "$DESK_TX" "$REACT_DEPLOYED" "$REACT_TX" << 'ENDJSON'
import json, sys
from pathlib import Path
from datetime import datetime, timezone
addr, clerk, proxy, token, token_tx, desk, desk_tx, reactive, reactive_tx = sys.argv[1:]
payload = {
    "network": "testnet-only",
    "deployer": addr,
    "clerk": clerk,
    "baseSepolia": {
        "chainId": 84532,
        "rpc": "https://sepolia.base.org",
        "explorer": "https://sepolia.basescan.org",
        "callbackProxy": proxy,
        "demoToken": token,
        "demoTokenTx": token_tx,
        "triageDesk": desk,
        "triageDeskTx": desk_tx,
    },
    "lasna": {
        "chainId": 5318007,
        "rpc": "https://lasna-rpc.rnk.dev/",
        "explorer": "https://lasna.reactscan.net",
        "triageReactive": reactive,
        "triageReactiveTx": reactive_tx,
    },
    "writtenAt": datetime.now(timezone.utc).isoformat(),
}
Path("deployments/testnet.json").write_text(json.dumps(payload, indent=2) + "\n")
print(json.dumps(payload, indent=2))
ENDJSON

echo
echo "Wrote deployments/testnet.json"
echo "Next: mint / approve / transfer with scripts/emit-demo-events.sh, then run the policy agent."
