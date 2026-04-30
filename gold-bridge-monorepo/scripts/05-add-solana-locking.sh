#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

require_var SOLANA_TOKEN_MINT
require_var SOLANA_KEYPAIR_PATH
NTT_PROJECT_DIR="${NTT_PROJECT_DIR:-ntt}"
NTT_SOLANA_CHAIN="${NTT_SOLANA_CHAIN:-Solana}"
NTT_SOLANA_PROGRAM_KEYPAIR="${NTT_SOLANA_PROGRAM_KEYPAIR:-keys/ntt-gold-program.json}"
NTT_SOLANA_PRIORITY_FEE="${NTT_SOLANA_PRIORITY_FEE:-50000}"

cd "$ROOT_DIR"
mkdir -p "$(dirname "$NTT_SOLANA_PROGRAM_KEYPAIR")"
if [[ ! -f "$NTT_SOLANA_PROGRAM_KEYPAIR" ]]; then
  solana-keygen new --no-bip39-passphrase -o "$NTT_SOLANA_PROGRAM_KEYPAIR"
fi

cd "$ROOT_DIR/$NTT_PROJECT_DIR"
args=(add-chain "$NTT_SOLANA_CHAIN" --latest --mode locking --token "$SOLANA_TOKEN_MINT" --payer "$SOLANA_KEYPAIR_PATH" --program-key "$ROOT_DIR/$NTT_SOLANA_PROGRAM_KEYPAIR")
if [[ -n "$NTT_SOLANA_PRIORITY_FEE" ]]; then
  args+=(--solana-priority-fee "$NTT_SOLANA_PRIORITY_FEE")
fi
ntt "${args[@]}"
