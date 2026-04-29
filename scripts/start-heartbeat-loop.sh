#!/usr/bin/env bash
# chmod +x scripts/start-heartbeat-loop.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Source .env.local from repo root if it exists
if [ -f .env.local ]; then
  set -a
  # shellcheck source=/dev/null
  source .env.local
  set +a
fi

# Validate required env vars
REQUIRED_VARS=(
  RPC_URL_PRIMARY
  CONVEX_DEPLOY_URL
  WEBHOOK_SHARED_SECRET
  DEPLOYER_PRIVATE_KEY
  CLAN_WORLD_CONTRACT_ADDRESS
)

missing=0
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: required env var $var is not set" >&2
    missing=1
  fi
done

if [ "$missing" -eq 1 ]; then
  echo ""
  echo "Usage: set the following env vars before running (or put them in .env.local):"
  for var in "${REQUIRED_VARS[@]}"; do
    echo "  $var"
  done
  exit 1
fi

echo "Starting heartbeat loop (interval: 65s; avoids on-chain 60s heartbeat guard)"
echo "  engine: $CLAN_WORLD_CONTRACT_ADDRESS"
echo "  rpc:    $RPC_URL_PRIMARY"
echo "  convex: $CONVEX_DEPLOY_URL"

while true; do
  heartbeat_stderr="$(mktemp)"
  if ! forge script packages/contracts/script/Heartbeat.s.sol \
    --root packages/contracts \
    --broadcast \
    --rpc-url "$RPC_URL_PRIMARY" \
    2> >(tee "$heartbeat_stderr" >&2); then
    if grep -qi "RateLimited" "$heartbeat_stderr"; then
      echo "heartbeat rate-limited; continuing" >&2
    else
      rm -f "$heartbeat_stderr"
      exit 1
    fi
  fi
  rm -f "$heartbeat_stderr"

  curl -sS --fail -X POST "$CONVEX_DEPLOY_URL/api/heartbeat-webhook" \
    -H "Authorization: Bearer $WEBHOOK_SHARED_SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"chain\":\"base-sepolia\",\"engineAddress\":\"$CLAN_WORLD_CONTRACT_ADDRESS\",\"firedAtTs\":$(date +%s),\"source\":\"foundry-loop\"}" \
    || echo "webhook POST failed (continuing)" >&2

  # 65s sleep avoids rate-limit collisions with on-chain 60s guard
  sleep 65
done
