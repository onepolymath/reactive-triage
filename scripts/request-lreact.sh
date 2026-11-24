#!/usr/bin/env bash
# Swap a little Base Sepolia ETH for Lasna lREACT via the official faucet contract.
# Official rate: 1 ETH -> 100 lREACT, max 5 ETH per request.
# See https://dev.reactive.network/reactive-mainnet
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
: "${LASNA_RPC:=https://lasna-rpc.rnk.dev/}"

FAUCET="0x2afaFD298b23b62760711756088F75B7409f5967"
CHAIN="$(cast chain-id --rpc-url "$BASE_SEPOLIA_RPC")"
if [[ "$CHAIN" != "84532" ]]; then
  echo "Refusing: Base Sepolia RPC is not chain 84532 (got $CHAIN)." >&2
  exit 2
fi

ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
BAL="$(cast balance "$ADDR" --rpc-url "$BASE_SEPOLIA_RPC")"
VALUE="${1:-}"
if [[ -z "$VALUE" ]]; then
  VALUE="$(python3 -c "
bal = int('$BAL')
leave = 2 * 10**15
cap = 5 * 10**16
send = max(0, min(cap, (bal - leave) * 2 // 5))
print(send)
")"
fi

if [[ "$VALUE" == "0" ]]; then
  echo "Not enough Base Sepolia ETH on $ADDR to request lREACT (balance $BAL wei)." >&2
  exit 3
fi

echo "Requesting lREACT for $ADDR by sending $VALUE wei of Base Sepolia ETH to $FAUCET"
cast send "$FAUCET" "request(address)" "$ADDR" \
  --rpc-url "$BASE_SEPOLIA_RPC" \
  --private-key "$PRIVATE_KEY" \
  --value "$VALUE"
echo "Lasna balance now: $(cast balance "$ADDR" --rpc-url "$LASNA_RPC") wei"
