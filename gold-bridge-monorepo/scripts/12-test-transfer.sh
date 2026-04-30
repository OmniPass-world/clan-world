#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

NTT_PROJECT_DIR="${NTT_PROJECT_DIR:-ntt}"
require_var WORMHOLE_NETWORK
require_var EVM_PRIVATE_KEY
require_var TEST_TRANSFER_SOURCE_CHAIN
require_var TEST_TRANSFER_DESTINATION_CHAIN
require_var TEST_TRANSFER_AMOUNT
require_var TEST_TRANSFER_DESTINATION_ADDRESS

export ETH_PRIVATE_KEY="$EVM_PRIVATE_KEY"

cd "$ROOT_DIR/$NTT_PROJECT_DIR"
args=(
  token-transfer
  --network "$WORMHOLE_NETWORK"
  --source-chain "$TEST_TRANSFER_SOURCE_CHAIN"
  --destination-chain "$TEST_TRANSFER_DESTINATION_CHAIN"
  --amount "$TEST_TRANSFER_AMOUNT"
  --destination-address "$TEST_TRANSFER_DESTINATION_ADDRESS"
  --deployment-path ./deployment.json
)

if [[ "$TEST_TRANSFER_SOURCE_CHAIN" == "Solana" ]]; then
  require_var SOLANA_KEYPAIR_PATH
  args+=(--payer "$SOLANA_KEYPAIR_PATH")
fi

if [[ -n "${TEST_TRANSFER_DESTINATION_MSG_VALUE:-}" ]]; then
  args+=(--destination-msg-value "$TEST_TRANSFER_DESTINATION_MSG_VALUE")
fi

if [[ -n "${SOLANA_RPC_URL:-}" ]]; then
  args+=(--rpc "Solana=$SOLANA_RPC_URL")
fi

if [[ -n "${BASE_RPC_URL:-}" ]]; then
  args+=(--rpc "BaseSepolia=$BASE_RPC_URL")
fi

ntt "${args[@]}"
