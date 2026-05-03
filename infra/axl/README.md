# AXL Docker Sidecar

Local Gensyn AXL node setup for elder-to-elder whisper testing.

## Quick start

```bash
cd infra/axl
docker compose up -d --build
bash setup.sh          # waits for nodes, writes .env with peer IDs
bash test-whisper.sh   # proves clan-1 → clan-2 round-trip via AXL
```

## Services

| Service | Host port | Role |
|---------|-----------|------|
| `axl-1` | 9002 | AXL sidecar for clan-1 |
| `axl-2` | 9003 | AXL sidecar for clan-2 |

## Environment variables

| Var | Description |
|-----|-------------|
| `AXL_NETWORK_ID` | Channel namespace (`testnet` by default) |
| `AXL_API_KEY` | Bearer token for managed-node auth (set to any non-empty value for local dev) |
| `AXL_NODE_URL` | Override node URL (default: `http://127.0.0.1:9002`) |
| `AXL_PEER_ID_CLAN_1` | ed25519 pubkey of clan-1's AXL node (populated by `setup.sh`) |
| `AXL_PEER_ID_CLAN_2` | ed25519 pubkey of clan-2's AXL node (populated by `setup.sh`) |

## How it works

Each AXL node has a unique ed25519 keypair (generated on first start, persisted in a named volume).
The setup script reads each node's public key from `GET /topology` (`our_public_key` field) and
writes them to `.env`.

The test script constructs an `AxlEnvelope` (the same JSON shape used by `AxlPeerInbox` in
`packages/runner/src/axlPeerInbox.ts`) and sends it via `POST /send` on axl-1, addressed to
clan-2's peer ID. It then polls `GET /recv` on axl-2 to confirm delivery and validates every
envelope field.

**AxlPeerInbox vs FilePeerInbox:** The runner selects `AxlPeerInbox` when both `AXL_API_KEY`
and `AXL_NETWORK_ID` are set. `test-whisper.sh` sets both, confirming the AXL transport path.
See `packages/runner/src/axlPeerInbox.ts:511` (`createPeerInbox`).

## Volumes

- `axl-1-keystore` — private key + node-config for clan-1's node
- `axl-2-keystore` — private key + node-config for clan-2's node

To reset identities: `docker compose down -v && docker compose up -d --build`

## Production notes

- Each clan needs its own AXL node with a unique keypair.
- For 4 elders, add `axl-3` and `axl-4` services and extend `setup.sh`.
- The `AXL_PEER_ADDR` env in the compose file points each node at its sibling; for real deployments
  use the Gensyn bootstrap peers from `node-config.json` defaults.
- AXL builds from source at `https://github.com/gensyn-ai/axl` — requires internet access during
  `docker compose build`.
