#!/usr/bin/env bash
# setup.sh — bootstrap AXL peer IDs for clans 1-4.
# Run after `docker compose up -d` and before test-whisper.sh.
# Writes infra/axl/.env with AXL_PEER_ID_* vars.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AXL_1_URL="${AXL_1_URL:-http://127.0.0.1:9002}"
AXL_2_URL="${AXL_2_URL:-http://127.0.0.1:9003}"

wait_for_node() {
  local url="$1" label="$2"
  echo "Waiting for $label at $url..."
  local i=0
  while ! curl -sf --max-time 5 "$url/topology" > /dev/null 2>&1; do
    i=$((i + 1))
    if [ $i -ge 30 ]; then
      echo "ERROR: $label did not become ready after 60s" >&2
      exit 1
    fi
    sleep 2
  done
  echo "$label is ready."
}

wait_for_node "$AXL_1_URL" "axl-1"
wait_for_node "$AXL_2_URL" "axl-2"

echo "Fetching peer IDs from /topology..."
CLAN1_PEER_ID=$(curl -sf --max-time 5 "$AXL_1_URL/topology" | jq -r '.our_public_key')
CLAN2_PEER_ID=$(curl -sf --max-time 5 "$AXL_2_URL/topology" | jq -r '.our_public_key')

if [ -z "$CLAN1_PEER_ID" ] || [ "$CLAN1_PEER_ID" = "null" ]; then
  echo "ERROR: could not read clan-1 peer ID from $AXL_1_URL/topology" >&2
  exit 1
fi
if [ -z "$CLAN2_PEER_ID" ] || [ "$CLAN2_PEER_ID" = "null" ]; then
  echo "ERROR: could not read clan-2 peer ID from $AXL_2_URL/topology" >&2
  exit 1
fi

echo "clan-1 peer ID: $CLAN1_PEER_ID"
echo "clan-2 peer ID: $CLAN2_PEER_ID"

# Write .env — clans 3+4 map to the same nodes for demo purposes;
# production deployments need one AXL node (and unique keypair) per clan.
cat > "$SCRIPT_DIR/.env" <<EOF
AXL_NETWORK_ID=testnet
AXL_API_KEY=local-dev-key
AXL_NODE_URL_CLAN_1=$AXL_1_URL
AXL_NODE_URL_CLAN_2=$AXL_2_URL
AXL_PEER_ID_CLAN_1=$CLAN1_PEER_ID
AXL_PEER_ID_CLAN_2=$CLAN2_PEER_ID
AXL_PEER_ID_CLAN_3=$CLAN1_PEER_ID
AXL_PEER_ID_CLAN_4=$CLAN2_PEER_ID
EOF

echo "Peer IDs written to $SCRIPT_DIR/.env"
