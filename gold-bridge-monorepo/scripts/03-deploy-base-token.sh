#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

require_var BASE_RPC_URL
require_var EVM_PRIVATE_KEY
require_var BASE_TOKEN_NAME
require_var BASE_TOKEN_SYMBOL
require_var EVM_TOKEN_OWNER
require_var EVM_INITIAL_MINTER

mkdir -p "$ROOT_DIR/artifacts"
cd "$ROOT_DIR/packages/contracts"

forge create --broadcast \
  --rpc-url "$BASE_RPC_URL" \
  --private-key "$EVM_PRIVATE_KEY" \
  src/GoldBridgeToken.sol:GoldBridgeToken \
  --constructor-args "$BASE_TOKEN_NAME" "$BASE_TOKEN_SYMBOL" "$EVM_INITIAL_MINTER" "$EVM_TOKEN_OWNER" \
  | tee "$ROOT_DIR/artifacts/base-token-deploy.log"

echo "Copy the deployed address into BASE_TOKEN_ADDRESS in .env."
