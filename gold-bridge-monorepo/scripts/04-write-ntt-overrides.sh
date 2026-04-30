#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

require_var SOLANA_RPC_URL
require_var BASE_RPC_URL
NTT_PROJECT_DIR="${NTT_PROJECT_DIR:-ntt}"
NTT_SOLANA_CHAIN="${NTT_SOLANA_CHAIN:-Solana}"
NTT_BASE_CHAIN="${NTT_BASE_CHAIN:-BaseSepolia}"

mkdir -p "$ROOT_DIR/$NTT_PROJECT_DIR"
cat > "$ROOT_DIR/$NTT_PROJECT_DIR/overrides.json" <<EOF
{
  "chains": {
    "$NTT_SOLANA_CHAIN": {
      "rpc": "$SOLANA_RPC_URL"
    },
    "$NTT_BASE_CHAIN": {
      "rpc": "$BASE_RPC_URL"
    }
  }
}
EOF

echo "Wrote $NTT_PROJECT_DIR/overrides.json"
