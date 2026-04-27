# @clan-world/runner

Elder tick-loop runner with pluggable memory and peer-inbox adapters.

## Memory adapter

The runner uses `IElderMemoryStore` for durable Elder memory across `/clear` context resets.

### Local file (default)

When `OG_STORAGE_API_KEY` is **not** set the runner uses `FileMemoryStore` — a local JSON file at:

```
~/.world/clanworld-runner/state/elder-{N}-memory.json
```

No extra config required.

### 0G iNFT storage (Phase 7)

When `OG_STORAGE_API_KEY` is set the runner uses `ZeroGMemoryStore`, backed by the [0G KV network](https://docs.0g.ai).

| Variable | Description |
|---|---|
| `OG_STORAGE_API_KEY` | 0G API key — enables 0G backend |
| `OG_STREAM_ID` | KV stream ID scoped to this clan (UUID or hex address) |
| `OG_KV_RPC` | 0G KV RPC endpoint (default: `https://rpc-storage-testnet.0g.ai`) |
| `ELDER_N` | Elder index 1–4 |

**Note:** Write transactions require a funded wallet and deployed Flow contract. The current implementation includes a write stub (see `zeroGMemoryStore.ts` TODO comments) — reads via `KvClient` work fully.

## Peer inbox adapter (Phase 8)

The runner uses `IElderPeerInbox` for Elder-to-Elder private messaging (clan diplomacy).

### File-based inbox (default)

When `AXL_API_KEY` is **not** set (or `AXL_NETWORK_ID` is empty), the runner uses `FilePeerInbox`:

- Messages stored as JSONL at `~/.world/clanworld-runner/state/peer-inbox/elder-{clanId}.jsonl`
- `send()` appends to the **recipient's** file; `inbox()` reads the caller's own file.
- Non-destructive reads: `inbox()` returns all messages without deleting them.
- No external services required.

### Gensyn AXL transport (Phase 8)

When both `AXL_API_KEY` and `AXL_NETWORK_ID` are set, the runner uses `AxlPeerInbox`:

- Talks to a **local AXL sidecar node** at `AXL_NODE_URL` (default `http://127.0.0.1:9002`).
- AXL is a Gensyn peer-to-peer transport layer ([docs](https://docs.gensyn.ai/tech/agent-exchange-layer)).
- **No official npm SDK** exists as of Phase 8; the runner uses AXL's HTTP REST API directly:
  - `POST /send` with `X-Destination-Peer-Id` header for outbound messages.
  - `GET /recv` for inbound queue polling (FIFO, drained on each `inbox()` call).
- Each clan's Elder has an **ed25519 keypair**; peer routing uses `AXL_PEER_ID_{CLAN_ID}` env vars.

| Variable | Description |
|---|---|
| `AXL_API_KEY` | Bearer token for managed AXL node auth. Enables AXL backend. |
| `AXL_NETWORK_ID` | Channel namespace, e.g. `"testnet"` or `"mainnet"`. Required with AXL_API_KEY. |
| `AXL_NODE_URL` | Local AXL node URL (default: `http://127.0.0.1:9002`) |
| `MY_CLAN_ID` | This Elder's clan ID (defaults to `ELDER_N` as string) |
| `AXL_PEER_ID_{CLAN_ID}` | AXL ed25519 pubkey for a peer clan. E.g. `AXL_PEER_ID_CLAN_IRON=abc...` |
| `ELDER_N` | Elder index 1–4 |

**AXL SDK blocked state (2026-04-27):** Gensyn does not publish an npm SDK for AXL. The runner
wraps the HTTP API directly via the `IAxlClient` interface (`src/axlPeerInbox.ts`).
When Gensyn ships `@gensyn/axl-sdk` (or equivalent), replace `AxlHttpClient` with the SDK
and update the two TODO comments in `axlPeerInbox.ts`.

**Fallback guarantee:** If either env var is missing the runner always falls back to `FilePeerInbox`
without throwing. Existing file-based flows are unaffected.

## Running

```bash
# Local fallback (memory + peer inbox both file-based)
ELDER_N=1 npx tsx src/main.ts

# With 0G memory
OG_STORAGE_API_KEY=<key> OG_STREAM_ID=<id> ELDER_N=1 npx tsx src/main.ts

# With AXL peer transport (requires running AXL node sidecar)
AXL_API_KEY=<key> AXL_NETWORK_ID=testnet MY_CLAN_ID=clan-iron \
  AXL_PEER_ID_CLAN_EMBER=<pubkey> ELDER_N=1 npx tsx src/main.ts

# Full Phase 7+8: 0G memory + AXL peer transport
OG_STORAGE_API_KEY=<key> OG_STREAM_ID=<id> \
  AXL_API_KEY=<key> AXL_NETWORK_ID=testnet MY_CLAN_ID=clan-iron \
  AXL_PEER_ID_CLAN_EMBER=<pubkey> ELDER_N=1 npx tsx src/main.ts
```

Copy `.env.example` to `.env` and fill in values.

## Tests

```bash
pnpm test
```

Tests cover both fallback (file-based) and mocked AXL paths. No AXL node or credentials are required to run the test suite.
