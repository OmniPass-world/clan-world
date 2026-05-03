# 0G Mainnet Setup

Wires the runner's `ZeroGMemoryStore` to 0G mainnet, backed by the four elder wallets in `~/.secrets/clanworld-elder-wallets.json` (50 0G each).

## Files

| File | Purpose |
|---|---|
| `setup-env.sh` | Prints the 0G env block for one elder. Pipe into your shell or `.env.local`. |
| `smoke-test.ts` | Saves + recalls a key on 0G mainnet for all 4 elders. Exits non-zero on any failure. |

## Run the smoke test

```bash
pnpm tsx infra/0g/smoke-test.ts
```

Watch for `[ZeroGMemoryStore] save ok key=smoke-... txHash=0x... rootHash=0x...` lines — one per elder. The summary block at the end lists pass/fail per elder.

Each save costs a few cents of 0G (the `clanworld_inft_deployment_notes.md` cost model). 50 0G per elder covers the entire demo lifecycle.

## Wire the runner

In your `.env.local` at the monorepo root, set:

```
OG_STORAGE_ENABLED=true
ELDER_MNEMONIC=<from ~/.secrets/clanworld-elder-wallets.json key `mnemonic12`>
EVM_RPC=https://evmrpc.0g.ai
INDEXER_RPC=https://indexer-storage-turbo.0g.ai
FLOW_CONTRACT=0x62D4144dB0F0a6fBBaeb6296c785C71B3D57C526
```

`ELDER_INDEX` is set per-elder by the runner (it serves all 4 from one process). For a one-elder process you'd set `ELDER_INDEX=1..4`.

To hydrate the env from the secrets file:

```bash
eval "$(infra/0g/setup-env.sh 1)"   # elder 1
```

## What happens without these env vars

`createMemoryStore` falls back to `FileMemoryStore` (local JSON at `runtime/memory/elder-N.json`). Agents work — they just don't persist to 0G. The `[runner]` startup log distinguishes `memory=0G-KV` vs `memory=local-file`.

## Security

- Never commit `.env.local` (already in `.gitignore`)
- `setup-env.sh` writes to stdout only; never persists the mnemonic to disk
- The mnemonic is the *only* credential — 0G has no API key, despite the (now-renamed) `OG_STORAGE_ENABLED` flag implying otherwise

## Reference

- `packages/runner/src/zeroGMemoryStore.ts` — adapter implementation
- `docs/planning/V1/05 0G/clanworld_inft_deployment_notes.md` — cost model + faucet details
