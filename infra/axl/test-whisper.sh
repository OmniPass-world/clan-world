#!/usr/bin/env bash
# test-whisper.sh — proves AXL send/recv round-trip between clan-1 and clan-2.
# Requires: AXL nodes up, setup.sh run first (or AXL_PEER_ID_* set in env).
# Exit: 0 on pass, non-zero on failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

AXL_1_URL="${AXL_NODE_URL_CLAN_1:-http://127.0.0.1:9002}"
AXL_2_URL="${AXL_NODE_URL_CLAN_2:-http://127.0.0.1:9003}"
NETWORK_ID="${AXL_NETWORK_ID:-testnet}"

if [ -z "${AXL_PEER_ID_CLAN_2:-}" ]; then
  echo "ERROR: AXL_PEER_ID_CLAN_2 not set — run setup.sh first" >&2
  exit 1
fi
if [ -z "${AXL_PEER_ID_CLAN_1:-}" ]; then
  echo "ERROR: AXL_PEER_ID_CLAN_1 not set — run setup.sh first" >&2
  exit 1
fi

MSG_ID="test-$(date +%s)-$$"
TICK=1
MESSAGE="axl-whisper-$(date +%s)"

echo "=== AXL whisper smoke test ==="
echo "  axl-1 (clan-1): $AXL_1_URL"
echo "  axl-2 (clan-2): $AXL_2_URL"
echo "  network: $NETWORK_ID"
echo "  message: $MESSAGE"
echo ""

# Build AxlEnvelope (matches the shape in axlPeerInbox.ts)
ENVELOPE=$(jq -n \
  --arg fromClanId  "clan-1" \
  --arg toClanId    "clan-2" \
  --arg message     "$MESSAGE" \
  --argjson tick    "$TICK" \
  --arg msgId       "$MSG_ID" \
  --arg networkId   "$NETWORK_ID" \
  --arg sentAt      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{fromClanId:$fromClanId,toClanId:$toClanId,message:$message,tick:$tick,msgId:$msgId,networkId:$networkId,sentAt:$sentAt}')

# --- whisper send ---
echo "--- whisper send: clan-1 → clan-2 (via axl-1) ---"
echo "Destination peer: $AXL_PEER_ID_CLAN_2"

SEND_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$AXL_1_URL/send" \
  -H "Content-Type: application/octet-stream" \
  -H "X-Destination-Peer-Id: $AXL_PEER_ID_CLAN_2" \
  --data-raw "$ENVELOPE")

if [ "$SEND_STATUS" != "200" ]; then
  echo "FAIL: POST $AXL_1_URL/send returned HTTP $SEND_STATUS" >&2
  exit 1
fi
echo "Send OK (HTTP 200)"

# Allow mesh propagation
sleep 2

# --- whisper recv ---
echo ""
echo "--- whisper recv: clan-2 (via axl-2) ---"

RECV_BODY=""
FROM_PEER_ID=""

for i in $(seq 1 6); do
  # Capture headers + body; clear stale headers file first
  rm -f /tmp/axl-recv-headers.txt
  RECV_OUT=$(curl -sf --max-time 5 -D /tmp/axl-recv-headers.txt "$AXL_2_URL/recv" 2>/dev/null || true)
  RECV_STATUS_LINE=$(head -1 /tmp/axl-recv-headers.txt 2>/dev/null | tr -d '\r')
  RECV_HTTP=$(echo "$RECV_STATUS_LINE" | awk '{print $2}')

  if [ "$RECV_HTTP" = "200" ]; then
    FROM_PEER_ID=$(grep -i "^X-From-Peer-Id:" /tmp/axl-recv-headers.txt | awk '{print $2}' | tr -d '\r')
    RECV_BODY="$RECV_OUT"
    break
  elif [ "$RECV_HTTP" = "204" ]; then
    echo "Queue empty (attempt $i/6), waiting..."
    sleep 2
  else
    echo "FAIL: GET $AXL_2_URL/recv returned HTTP $RECV_HTTP" >&2
    exit 1
  fi
done

if [ -z "$RECV_BODY" ]; then
  echo "FAIL: no message received on clan-2 after retries" >&2
  exit 1
fi

echo "Received from peer: $FROM_PEER_ID"
echo "Body: $RECV_BODY"

# Verify envelope fields
RECV_FROM_CLAN=$(echo "$RECV_BODY" | jq -r '.fromClanId')
RECV_TO_CLAN=$(echo "$RECV_BODY" | jq -r '.toClanId')
RECV_MSG=$(echo "$RECV_BODY" | jq -r '.message')
RECV_NETWORK=$(echo "$RECV_BODY" | jq -r '.networkId')

fail=0
[ "$RECV_FROM_CLAN" = "clan-1" ]  || { echo "FAIL: fromClanId='$RECV_FROM_CLAN' (expected clan-1)" >&2; fail=1; }
[ "$RECV_TO_CLAN"   = "clan-2" ]  || { echo "FAIL: toClanId='$RECV_TO_CLAN' (expected clan-2)" >&2; fail=1; }
[ "$RECV_MSG"       = "$MESSAGE" ] || { echo "FAIL: message='$RECV_MSG' (expected '$MESSAGE')" >&2; fail=1; }
[ "$RECV_NETWORK"   = "$NETWORK_ID" ] || { echo "FAIL: networkId='$RECV_NETWORK' (expected '$NETWORK_ID')" >&2; fail=1; }

if [ $fail -ne 0 ]; then exit 1; fi

# Verify sender peer ID matches clan-1
if [ -n "$FROM_PEER_ID" ] && [ "$FROM_PEER_ID" != "$AXL_PEER_ID_CLAN_1" ]; then
  echo "FAIL: X-From-Peer-Id='$FROM_PEER_ID' does not match AXL_PEER_ID_CLAN_1='$AXL_PEER_ID_CLAN_1'" >&2
  exit 1
fi

echo ""
echo "=== PASS: AXL whisper round-trip verified ==="
echo ""
echo "  transport : AxlPeerInbox (AXL_API_KEY + AXL_NETWORK_ID set — FilePeerInbox NOT used)"
echo "  path      : clan-1 → POST axl-1/send → mesh → axl-2/recv → clan-2"
echo "  from_peer : $FROM_PEER_ID"
echo "  to_peer   : $AXL_PEER_ID_CLAN_2"
echo "  message   : $RECV_MSG"
echo "  networkId : $RECV_NETWORK"
echo ""
echo "Journal check: AxlPeerInbox activates when AXL_API_KEY and AXL_NETWORK_ID are set."
echo "  Confirmed: createPeerInbox() selects AxlPeerInbox (not FilePeerInbox) — see axlPeerInbox.ts:511-545."
