#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

NTT_PROJECT_DIR="${NTT_PROJECT_DIR:-ntt}"
require_var WORMHOLE_NETWORK
require_var TEST_TRANSFER_SOURCE_CHAIN
require_var TEST_TRANSFER_DESTINATION_CHAIN
require_var TEST_TRANSFER_AMOUNT
require_var TEST_TRANSFER_DESTINATION_ADDRESS

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

if [[ -n "${TEST_TRANSFER_DESTINATION_MSG_VALUE:-}" ]]; then
  args+=(--destination-msg-value "$TEST_TRANSFER_DESTINATION_MSG_VALUE")
fi

ntt "${args[@]}"
