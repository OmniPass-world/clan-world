#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

require_var BASE_TOKEN_ADDRESS
require_var BASE_RPC_URL
require_var EVM_PRIVATE_KEY
NTT_BASE_CHAIN="${NTT_BASE_CHAIN:-BaseSepolia}"
TIMELOCK_EXECUTE_IMMEDIATELY="${TIMELOCK_EXECUTE_IMMEDIATELY:-false}"

if [[ -z "${BASE_NTT_MANAGER_ADDRESS:-}" ]]; then
  BASE_NTT_MANAGER_ADDRESS="$(node "$ROOT_DIR/scripts/07-print-ntt-addresses.mjs" --chain "$NTT_BASE_CHAIN" --field manager --raw)"
fi

if [[ -z "$BASE_NTT_MANAGER_ADDRESS" ]]; then
  echo "Could not determine BASE_NTT_MANAGER_ADDRESS." >&2
  exit 1
fi

if [[ -n "${BASE_TIMELOCK_ADDRESS:-}" ]]; then
  export TIMELOCK_TARGET_ADDRESS="$BASE_TOKEN_ADDRESS"
  export TIMELOCK_CALLDATA
  TIMELOCK_CALLDATA="$(cast calldata "setMinter(address)" "$BASE_NTT_MANAGER_ADDRESS")"

  "$ROOT_DIR/scripts/18-timelock-schedule.sh"
  if [[ "$TIMELOCK_EXECUTE_IMMEDIATELY" == "true" ]]; then
    "$ROOT_DIR/scripts/19-timelock-execute.sh"
    echo "Set Base GOLD minter to $BASE_NTT_MANAGER_ADDRESS"
  else
    echo "Minter handoff scheduled through timelock. Run pnpm timelock:execute after the delay."
    echo "Execute with:"
    echo "  TIMELOCK_TARGET_ADDRESS=$TIMELOCK_TARGET_ADDRESS TIMELOCK_CALLDATA=$TIMELOCK_CALLDATA pnpm timelock:execute"
  fi
else
  cast send "$BASE_TOKEN_ADDRESS" \
    "setMinter(address)" "$BASE_NTT_MANAGER_ADDRESS" \
    --private-key "$EVM_PRIVATE_KEY" \
    --rpc-url "$BASE_RPC_URL"
  echo "Set Base GOLD minter to $BASE_NTT_MANAGER_ADDRESS"
fi
