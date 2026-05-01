#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

require_var BASE_RPC_URL
require_var BASE_TOKEN_ADDRESS

ADMIN_SLOT="0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
IMPLEMENTATION_SLOT="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
ZERO_WORD="0x0000000000000000000000000000000000000000000000000000000000000000"

word_to_address() {
  local word="$1"
  echo "0x${word: -40}"
}

admin_word="$(cast storage "$BASE_TOKEN_ADDRESS" "$ADMIN_SLOT" --rpc-url "$BASE_RPC_URL")"
implementation_word="$(cast storage "$BASE_TOKEN_ADDRESS" "$IMPLEMENTATION_SLOT" --rpc-url "$BASE_RPC_URL")"

if [[ "$admin_word" == "$ZERO_WORD" || "$implementation_word" == "$ZERO_WORD" ]]; then
  echo "Base token does not look like an ERC-1967 transparent proxy: $BASE_TOKEN_ADDRESS" >&2
  exit 1
fi

proxy_admin="$(word_to_address "$admin_word")"
implementation="$(word_to_address "$implementation_word")"
owner="$(cast call "$BASE_TOKEN_ADDRESS" "owner()(address)" --rpc-url "$BASE_RPC_URL")"
minter="$(cast call "$BASE_TOKEN_ADDRESS" "minter()(address)" --rpc-url "$BASE_RPC_URL")"
decimals="$(cast call "$BASE_TOKEN_ADDRESS" "decimals()(uint8)" --rpc-url "$BASE_RPC_URL")"
proxy_admin_owner="$(cast call "$proxy_admin" "owner()(address)" --rpc-url "$BASE_RPC_URL")"

echo "Base GOLD proxy info"
echo "  proxy token: $BASE_TOKEN_ADDRESS"
echo "  implementation: $implementation"
echo "  proxy admin: $proxy_admin"
echo "  proxy admin owner: $proxy_admin_owner"
echo "  token owner: $owner"
echo "  token minter: $minter"
echo "  token decimals: $decimals"

if [[ -n "${BASE_TIMELOCK_ADDRESS:-}" ]]; then
  min_delay="$(cast call "$BASE_TIMELOCK_ADDRESS" "getMinDelay()(uint256)" --rpc-url "$BASE_RPC_URL")"
  echo "  timelock: $BASE_TIMELOCK_ADDRESS"
  echo "  timelock min delay seconds: $min_delay"
fi
