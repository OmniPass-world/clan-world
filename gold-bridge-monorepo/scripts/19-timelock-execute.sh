#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

require_var BASE_RPC_URL
require_var EVM_PRIVATE_KEY
require_var BASE_TIMELOCK_ADDRESS
require_var TIMELOCK_TARGET_ADDRESS
require_var TIMELOCK_CALLDATA

ZERO_BYTES32="0x0000000000000000000000000000000000000000000000000000000000000000"
TIMELOCK_VALUE="${TIMELOCK_VALUE:-0}"
TIMELOCK_PREDECESSOR="${TIMELOCK_PREDECESSOR:-$ZERO_BYTES32}"
TIMELOCK_SALT="${TIMELOCK_SALT:-$ZERO_BYTES32}"

operation_id="$(cast call "$BASE_TIMELOCK_ADDRESS" \
  "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" \
  "$TIMELOCK_TARGET_ADDRESS" \
  "$TIMELOCK_VALUE" \
  "$TIMELOCK_CALLDATA" \
  "$TIMELOCK_PREDECESSOR" \
  "$TIMELOCK_SALT" \
  --rpc-url "$BASE_RPC_URL")"

cast send "$BASE_TIMELOCK_ADDRESS" \
  "execute(address,uint256,bytes,bytes32,bytes32)" \
  "$TIMELOCK_TARGET_ADDRESS" \
  "$TIMELOCK_VALUE" \
  "$TIMELOCK_CALLDATA" \
  "$TIMELOCK_PREDECESSOR" \
  "$TIMELOCK_SALT" \
  --private-key "$EVM_PRIVATE_KEY" \
  --rpc-url "$BASE_RPC_URL"

echo "Executed timelock operation:"
echo "  id: $operation_id"
echo "  target: $TIMELOCK_TARGET_ADDRESS"
echo "  calldata: $TIMELOCK_CALLDATA"
