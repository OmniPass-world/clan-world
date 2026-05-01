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
