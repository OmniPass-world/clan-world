#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

require_var BASE_TOKEN_ADDRESS
require_var BASE_RPC_URL
require_var EVM_PRIVATE_KEY
NTT_BASE_CHAIN="${NTT_BASE_CHAIN:-BaseSepolia}"

if [[ -z "${BASE_NTT_MANAGER_ADDRESS:-}" ]]; then
  BASE_NTT_MANAGER_ADDRESS="$(node "$ROOT_DIR/scripts/07-print-ntt-addresses.mjs" --chain "$NTT_BASE_CHAIN" --field manager --raw)"
fi

if [[ -z "$BASE_NTT_MANAGER_ADDRESS" ]]; then
  echo "Could not determine BASE_NTT_MANAGER_ADDRESS." >&2
  exit 1
fi

cast send "$BASE_TOKEN_ADDRESS" \
  "setMinter(address)" "$BASE_NTT_MANAGER_ADDRESS" \
  --private-key "$EVM_PRIVATE_KEY" \
  --rpc-url "$BASE_RPC_URL"

echo "Set Base GOLD minter to $BASE_NTT_MANAGER_ADDRESS"
