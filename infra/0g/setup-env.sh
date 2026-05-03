#!/usr/bin/env bash
# Print the 0G env block for one elder. Pipe into your shell or .env.local.
#
# Usage:
#   infra/0g/setup-env.sh 1                 # print elder 1 env to stdout
#   infra/0g/setup-env.sh 1 >> .env.local   # append elder 1 env to .env.local
#   eval "$(infra/0g/setup-env.sh 1)"       # export into current shell
#
# Reads mnemonic from ~/.secrets/clanworld-elder-wallets.json — never writes
# the mnemonic to disk except via your own redirection. Reject if elder index
# is not 1..4.
set -euo pipefail

ELDER_INDEX="${1:-}"
if [[ ! "$ELDER_INDEX" =~ ^[1-4]$ ]]; then
  echo "usage: $0 <elder-index 1..4>" >&2
  exit 1
fi

SECRETS="${HOME}/.secrets/clanworld-elder-wallets.json"
if [[ ! -f "$SECRETS" ]]; then
  echo "secrets file not found: $SECRETS" >&2
  exit 1
fi

MNEMONIC="$(jq -r '.mnemonic12' "$SECRETS")"
if [[ -z "$MNEMONIC" || "$MNEMONIC" == "null" ]]; then
  echo "secrets file missing mnemonic12 key" >&2
  exit 1
fi

cat <<ENV
export OG_STORAGE_ENABLED=true
export ELDER_MNEMONIC='$MNEMONIC'
export ELDER_INDEX=$ELDER_INDEX
export EVM_RPC=https://evmrpc.0g.ai
export INDEXER_RPC=https://indexer-storage-turbo.0g.ai
export FLOW_CONTRACT=0x62D4144dB0F0a6fBBaeb6296c785C71B3D57C526
ENV
