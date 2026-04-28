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
| `EVM_RPC` | 0G EVM RPC endpoint (default: `https://evmrpc.0g.ai`) |
| `INDEXER_RPC` | 0G Indexer RPC endpoint (default: `https://indexer-storage-turbo.0g.ai`) |
| `FLOW_CONTRACT` | 0G Flow contract address |
| `ELDER_MNEMONIC` | BIP39 mnemonic (12 or 24 words) |
| `ELDER_INDEX` | Elder index 1–4 |

Copy `.env.example` to `.env` and fill in the values.

**Note:** Write transactions require a funded wallet and deployed Flow contract. Wallet is derived from `ELDER_MNEMONIC` at BIP-44 path `m/44'/60'/0'/0/{ELDER_INDEX-1}`.

## Running

```bash
# Local fallback
ELDER_INDEX=1 npx tsx src/main.ts

# With 0G storage
OG_STORAGE_API_KEY=<key> OG_STREAM_ID=<id> ELDER_MNEMONIC="word1 ... word12" ELDER_INDEX=1 npx tsx src/main.ts
```

## Tests

```bash
pnpm test
```
