#!/bin/sh
set -e

KEYSTORE=/keystore
KEY_FILE="$KEYSTORE/private.pem"

# Generate ed25519 key if not present (persisted via volume)
if [ ! -f "$KEY_FILE" ]; then
  echo "[axl-entrypoint] generating ed25519 keypair..."
  openssl genpkey -algorithm ed25519 -out "$KEY_FILE"
  chmod 600 "$KEY_FILE"
fi

# Build node-config.json — peer with sibling node if AXL_PEER_ADDR is set
PEERS="[]"
if [ -n "${AXL_PEER_ADDR:-}" ]; then
  PEERS="[\"tls://$AXL_PEER_ADDR\"]"
fi

cat > "$KEYSTORE/node-config.json" <<EOF
{
  "PrivateKeyPath": "$KEY_FILE",
  "Peers": $PEERS,
  "Listen": [":9001"]
}
EOF

echo "[axl-entrypoint] starting AXL node (peers=$PEERS)..."
exec ./node -config "$KEYSTORE/node-config.json"
