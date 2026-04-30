#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"
NTT_PROJECT_DIR="${NTT_PROJECT_DIR:-ntt}"
require_var EVM_PRIVATE_KEY
require_var SOLANA_KEYPAIR_PATH

export ETH_PRIVATE_KEY="$EVM_PRIVATE_KEY"
cd "$ROOT_DIR/$NTT_PROJECT_DIR"
ntt push --yes --payer "$SOLANA_KEYPAIR_PATH"
