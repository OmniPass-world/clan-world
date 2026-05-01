#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required command on PATH: $name" >&2
    exit 1
  fi
}

extract_spl_decimals() {
  spl-token display "$SOLANA_TOKEN_MINT" --url "$SOLANA_RPC_URL" 2>/dev/null \
    | awk -F: '/Decimals/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }'
}

require_var SOLANA_TOKEN_MINT
require_var SOLANA_RPC_URL
require_var BASE_TOKEN_ADDRESS
require_var BASE_RPC_URL

NTT_PROJECT_DIR="${NTT_PROJECT_DIR:-ntt}"
NTT_SOLANA_CHAIN="${NTT_SOLANA_CHAIN:-Solana}"
NTT_BASE_CHAIN="${NTT_BASE_CHAIN:-BaseSepolia}"
EXPECTED_DECIMALS="${SOLANA_TOKEN_DECIMALS:-9}"
BASE_TOKEN_EXPECTED_PROXY="${BASE_TOKEN_EXPECTED_PROXY:-true}"
ADMIN_SLOT="0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
IMPLEMENTATION_SLOT="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
ZERO_WORD="0x0000000000000000000000000000000000000000000000000000000000000000"

require_command cast
require_command node
require_command spl-token
require_command ntt

BASE_NTT_MANAGER_ADDRESS="${BASE_NTT_MANAGER_ADDRESS:-$(node "$ROOT_DIR/scripts/07-print-ntt-addresses.mjs" --chain "$NTT_BASE_CHAIN" --field manager --raw)}"
SOLANA_NTT_MANAGER_ADDRESS="${SOLANA_NTT_MANAGER_ADDRESS:-$(node "$ROOT_DIR/scripts/07-print-ntt-addresses.mjs" --chain "$NTT_SOLANA_CHAIN" --field manager --raw)}"

if [[ -z "$BASE_NTT_MANAGER_ADDRESS" ]]; then
  echo "Could not determine Base NTT manager address." >&2
  exit 1
fi

if [[ -z "$SOLANA_NTT_MANAGER_ADDRESS" ]]; then
  echo "Could not determine Solana NTT manager address." >&2
  exit 1
fi

solana_decimals="$(extract_spl_decimals)"
if [[ "$solana_decimals" != "$EXPECTED_DECIMALS" ]]; then
  echo "Solana mint decimals mismatch: expected $EXPECTED_DECIMALS, got ${solana_decimals:-unknown}" >&2
  exit 1
fi

base_decimals="$(cast call "$BASE_TOKEN_ADDRESS" "decimals()(uint8)" --rpc-url "$BASE_RPC_URL")"
if [[ "$base_decimals" != "$EXPECTED_DECIMALS" ]]; then
  echo "Base token decimals mismatch: expected $EXPECTED_DECIMALS, got $base_decimals" >&2
  exit 1
fi

base_minter="$(cast call "$BASE_TOKEN_ADDRESS" "minter()(address)" --rpc-url "$BASE_RPC_URL")"
if [[ "${base_minter,,}" != "${BASE_NTT_MANAGER_ADDRESS,,}" ]]; then
  echo "Base token minter mismatch: expected $BASE_NTT_MANAGER_ADDRESS, got $base_minter" >&2
  exit 1
fi

if [[ "$BASE_TOKEN_EXPECTED_PROXY" == "true" ]]; then
  proxy_admin_word="$(cast storage "$BASE_TOKEN_ADDRESS" "$ADMIN_SLOT" --rpc-url "$BASE_RPC_URL")"
  implementation_word="$(cast storage "$BASE_TOKEN_ADDRESS" "$IMPLEMENTATION_SLOT" --rpc-url "$BASE_RPC_URL")"
  if [[ "$proxy_admin_word" == "$ZERO_WORD" || "$implementation_word" == "$ZERO_WORD" ]]; then
    echo "Base token does not look like an ERC-1967 transparent proxy: $BASE_TOKEN_ADDRESS" >&2
    exit 1
  fi
  proxy_admin="0x${proxy_admin_word: -40}"
  implementation="0x${implementation_word: -40}"
  proxy_admin_owner="$(cast call "$proxy_admin" "owner()(address)" --rpc-url "$BASE_RPC_URL")"
  token_owner="$(cast call "$BASE_TOKEN_ADDRESS" "owner()(address)" --rpc-url "$BASE_RPC_URL")"

  if [[ -n "${BASE_TIMELOCK_ADDRESS:-}" ]]; then
    if [[ "${proxy_admin_owner,,}" != "${BASE_TIMELOCK_ADDRESS,,}" ]]; then
      echo "ProxyAdmin owner mismatch: expected $BASE_TIMELOCK_ADDRESS, got $proxy_admin_owner" >&2
      exit 1
    fi
    if [[ "${token_owner,,}" != "${BASE_TIMELOCK_ADDRESS,,}" ]]; then
      echo "Token owner mismatch: expected $BASE_TIMELOCK_ADDRESS, got $token_owner" >&2
      exit 1
    fi
  fi
fi

if [[ ! -f "$ROOT_DIR/$NTT_PROJECT_DIR/deployment.json" ]]; then
  echo "Missing NTT deployment file: $ROOT_DIR/$NTT_PROJECT_DIR/deployment.json" >&2
  exit 1
fi

(
  cd "$ROOT_DIR/$NTT_PROJECT_DIR"
  ntt status
)

echo "Preflight passed:"
echo "  Solana mint $SOLANA_TOKEN_MINT decimals: $solana_decimals"
echo "  Solana NTT manager: $SOLANA_NTT_MANAGER_ADDRESS"
echo "  Base token $BASE_TOKEN_ADDRESS decimals: $base_decimals"
echo "  Base token minter: $base_minter"
if [[ "${BASE_TOKEN_EXPECTED_PROXY:-true}" == "true" ]]; then
  echo "  Base proxy admin: $proxy_admin"
  echo "  Base implementation: $implementation"
  echo "  Base proxy admin owner: $proxy_admin_owner"
  echo "  Base token owner: $token_owner"
fi
