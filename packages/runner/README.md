# @clan-world/runner

Elder tick-loop runner with pluggable memory adapter.

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

Required env vars:

| Variable | Description |
|---|---|
| `OG_STORAGE_API_KEY` | 0G API key — enables 0G backend |
| `OG_STREAM_ID` | KV stream ID scoped to this clan (UUID or hex address) |
| `OG_KV_RPC` | 0G KV RPC endpoint (default: `https://rpc-storage-testnet.0g.ai`) |
| `ELDER_N` | Elder index 1–4 |

Copy `.env.example` to `.env` and fill in the values.

**Note:** Write transactions require a funded wallet and deployed Flow contract. The current implementation includes a write stub (see `zeroGMemoryStore.ts` TODO comments) — reads via `KvClient` work fully. Production writes need `OG_WALLET_PRIVATE_KEY` + `OG_FLOW_CONTRACT`.

## Running

```bash
# Local fallback
ELDER_N=1 npx tsx src/main.ts

# With 0G storage
OG_STORAGE_API_KEY=<key> OG_STREAM_ID=<id> ELDER_N=1 npx tsx src/main.ts
```

## Tests

```bash
pnpm test
```
