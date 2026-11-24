#!/usr/bin/env bash
# Swap a little Sepolia ETH for Lasna lREACT via an official faucet contract.
# Official rate: 1 ETH -> 100 lREACT, max 5 ETH per request.
# See https://dev.reactive.network/reactive-mainnet
#
# Usage:
#   ./scripts/request-lreact.sh              # Ethereum Sepolia faucet, 0.02 ETH
#   ./scripts/request-lreact.sh 0.01ether    # Ethereum Sepolia faucet, custom value
#   ./scripts/request-lreact.sh base         # Base Sepolia faucet, auto amount
#   ./scripts/request-lreact.sh base 0.001ether
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
: "${ETHEREUM_SEPOLIA_RPC:=https://ethereum-sepolia-rpc.publicnode.com}"
: "${LASNA_RPC:=https://lasna-rpc.rnk.dev/}"

ETH_SEPOLIA_FAUCET="0x9b9BB25f1A81078C544C829c5EB7822d747Cf434"
BASE_SEPOLIA_FAUCET="0x2afaFD298b23b62760711756088F75B7409f5967"

NETWORK="ethereum"
VALUE_ARG=""
if [[ "${1:-}" == "base" ]]; then
  NETWORK="base"
  VALUE_ARG="${2:-}"
else
  VALUE_ARG="${1:-}"
fi

if [[ "$NETWORK" == "base" ]]; then
  FAUCET="$BASE_SEPOLIA_FAUCET"
  RPC="$BASE_SEPOLIA_RPC"
  EXPECTED_CHAIN="84532"
  LABEL="Base Sepolia"
else
  FAUCET="$ETH_SEPOLIA_FAUCET"
  RPC="$ETHEREUM_SEPOLIA_RPC"
  EXPECTED_CHAIN="11155111"
  LABEL="Ethereum Sepolia"
fi

CHAIN="$(cast chain-id --rpc-url "$RPC")"
if [[ "$CHAIN" != "$EXPECTED_CHAIN" ]]; then
  echo "Refusing: $LABEL RPC is not chain $EXPECTED_CHAIN (got $CHAIN)." >&2
  exit 2
fi

ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
BAL="$(cast balance "$ADDR" --rpc-url "$RPC")"
if [[ -n "$VALUE_ARG" ]]; then
  VALUE="$(cast to-wei "$VALUE_ARG" 2>/dev/null || echo "$VALUE_ARG")"
  # If the user already passed wei, keep it.
  if [[ "$VALUE_ARG" =~ ^[0-9]+$ ]]; then
    VALUE="$VALUE_ARG"
  fi
else
  if [[ "$NETWORK" == "ethereum" ]]; then
    VALUE="20000000000000000" # 0.02 ETH, within the 0.01-0.02 guidance
  else
    VALUE="$(python3 -c "
bal = int('$BAL')
leave = 2 * 10**15
cap = 5 * 10**16
send = max(0, min(cap, (bal - leave) * 2 // 5))
print(send)
")"
  fi
fi

if [[ "$VALUE" == "0" ]]; then
  echo "Not enough $LABEL ETH on $ADDR to request lREACT (balance $BAL wei)." >&2
  exit 3
fi

echo "Requesting lREACT for $ADDR by sending $VALUE wei of $LABEL ETH to $FAUCET"
cast send "$FAUCET" "request(address)" "$ADDR" \
  --rpc-url "$RPC" \
  --private-key "$PRIVATE_KEY" \
  --value "$VALUE"
echo "Lasna balance now: $(cast balance "$ADDR" --rpc-url "$LASNA_RPC") wei"
