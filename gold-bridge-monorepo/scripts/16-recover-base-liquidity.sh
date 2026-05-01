#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

require_var WORMHOLE_NETWORK
require_var EVM_PRIVATE_KEY
require_var BASE_RPC_URL
require_var BASE_TOKEN_ADDRESS
require_var RECOVERY_DESTINATION_SOLANA_ADDRESS
require_var RECOVERY_AMOUNT

NTT_PROJECT_DIR="${NTT_PROJECT_DIR:-ntt}"
NTT_BASE_CHAIN="${NTT_BASE_CHAIN:-BaseSepolia}"
NTT_SOLANA_CHAIN="${NTT_SOLANA_CHAIN:-Solana}"
RECOVERY_EXECUTE="${RECOVERY_EXECUTE:-false}"
TEST_TRANSFER_DESTINATION_MSG_VALUE="${TEST_TRANSFER_DESTINATION_MSG_VALUE:-10000000}"

export ETH_PRIVATE_KEY="$EVM_PRIVATE_KEY"

if [[ ! -f "$ROOT_DIR/$NTT_PROJECT_DIR/deployment.json" ]]; then
  echo "Missing NTT deployment file: $ROOT_DIR/$NTT_PROJECT_DIR/deployment.json" >&2
  exit 1
fi

holder_address="$(cast wallet address --private-key "$EVM_PRIVATE_KEY")"
current_balance="$(cast call "$BASE_TOKEN_ADDRESS" "balanceOf(address)(uint256)" "$holder_address" --rpc-url "$BASE_RPC_URL")"

echo "Base liquidity recovery preview"
echo "  holder: $holder_address"
echo "  Base token: $BASE_TOKEN_ADDRESS"
echo "  current raw balance: $current_balance"
echo "  recovery amount: $RECOVERY_AMOUNT GOLD"
echo "  destination Solana address: $RECOVERY_DESTINATION_SOLANA_ADDRESS"
echo "  source/destination: $NTT_BASE_CHAIN -> $NTT_SOLANA_CHAIN"

if [[ "$RECOVERY_EXECUTE" != "true" ]]; then
  echo
  echo "Dry run only. Set RECOVERY_EXECUTE=true to submit the bridge transfer."
  exit 0
fi

cd "$ROOT_DIR/$NTT_PROJECT_DIR"
args=(
  token-transfer
  --network "$WORMHOLE_NETWORK"
  --source-chain "$NTT_BASE_CHAIN"
  --destination-chain "$NTT_SOLANA_CHAIN"
  --amount "$RECOVERY_AMOUNT"
  --destination-address "$RECOVERY_DESTINATION_SOLANA_ADDRESS"
  --destination-msg-value "$TEST_TRANSFER_DESTINATION_MSG_VALUE"
  --deployment-path ./deployment.json
)

if [[ -n "${BASE_RPC_URL:-}" ]]; then
  args+=(--rpc "$NTT_BASE_CHAIN=$BASE_RPC_URL")
fi

if [[ -n "${SOLANA_RPC_URL:-}" ]]; then
  args+=(--rpc "$NTT_SOLANA_CHAIN=$SOLANA_RPC_URL")
fi

ntt "${args[@]}"
