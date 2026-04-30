#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

require_var BASE_TOKEN_ADDRESS
require_var EVM_PRIVATE_KEY
NTT_PROJECT_DIR="${NTT_PROJECT_DIR:-ntt}"
NTT_BASE_CHAIN="${NTT_BASE_CHAIN:-BaseSepolia}"

export ETH_PRIVATE_KEY="$EVM_PRIVATE_KEY"
export BASESCAN_API_KEY="${BASESCAN_API_KEY:-${BASE_SCAN_API_KEY:-}}"
export BASE_SCAN_API_KEY="${BASE_SCAN_API_KEY:-${BASESCAN_API_KEY:-}}"

cd "$ROOT_DIR/$NTT_PROJECT_DIR"
args=(add-chain "$NTT_BASE_CHAIN" --latest --mode burning --token "$BASE_TOKEN_ADDRESS" --yes)
if optional_bool_true "${NTT_SKIP_VERIFY:-false}"; then
  args+=(--skip-verify)
fi
ntt "${args[@]}"
