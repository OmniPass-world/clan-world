# @clan-world/runner

ClanWorld runner daemon — drives 4 Elder Claude Code sessions through the
per-tick reasoning loop. Memory and peer-inbox layers are pluggable.

## What it does

```
loop:
  chainTick = pollChainTick(convex)
  if chainTick > lastProcessedTick:
    parallel for elder in 1..4:
      block = composeSituationBlock(elder, chainTick, ...)
      tmux send-keys -t elder-N -l "$block" + Enter
    settle window (~90s) — Elders read, reason, submit orders
    heartbeat() on-chain (rate-limit aware, Cycle A)
    lastProcessedTick = chainTick
  sleep pollInterval
```

The runner is the **only** writer of situation blocks into Elder sessions. It
satisfies four seam interfaces from `@clan-world/agents/seams`:

| Seam                  | Impl                       | Notes                                              |
| --------------------- | -------------------------- | -------------------------------------------------- |
| `IRunnerInbox`        | `TmuxRunnerInbox`          | `tmux send-keys -l` + paste block + Enter         |
| `IElderMemoryStore`   | `FileMemoryStore` / `ZeroGMemoryStore` | Local JSON or 0G KV (see Memory adapter below) |
| `IElderPeerInbox`     | `FilePeerInbox` / `AxlPeerInbox` | JSONL per recipient clan or Gensyn AXL transport |
| `IHeartbeatCaller`    | `RunnerCastHeartbeat`      | viem `writeContract`, dedicated runner wallet     |

## Run it

```bash
# 1. Provision a fresh runner wallet (NEVER reuse an Elder key) and fund it
#    with Base Sepolia ETH.
export RUNNER_PRIVATE_KEY=0x...
export CLAN_WORLD_CONTRACT_ADDRESS=0xC012275376b867944cd874FB2d600d6dA3B4A56e
export RPC_URL_PRIMARY=https://base-sepolia.g.alchemy.com/v2/...
export CONVEX_URL=https://...convex.cloud   # optional; runner idles without it

# 2. Make sure 4 tmux sessions exist with Elder Claude Code already attached:
#    elder-1, elder-2, elder-3, elder-4

# 3. Start the daemon:
pnpm --filter @clan-world/runner start
```

## Env vars

See [`.env.example`](./.env.example). `pnpm start` loads the repo-root
`.env.local`; other launchers can provide the same vars through `process.env`.

## State directory

Default: `~/.world/clanworld-runner/state/`. Layout:

```
elder-1-memory.json          ← FileMemoryStore (when no 0G)
elder-2-memory.json
elder-3-memory.json
elder-4-memory.json

elder-1-last-tick.txt        ← TmuxRunnerInbox idempotency marker
elder-2-last-tick.txt
…

elder-1-ack.flag             ← Set by `elder ack-clear` from Elder side
…

peer-inbox/
  elder-1.jsonl              ← FilePeerInbox; one file per recipient clan
  elder-2.jsonl
  axl-journal-clan-iron.jsonl  ← AxlPeerInbox crash-durability journal (when AXL set)
  …
```

## Stub mode

- If `CONVEX_URL` is unset, `createConvexClient()` hands back a stub returning
  `{ tick: 0, ... }`. The tick loop interprets this as "no real chain state"
  and idles (logs a warning at boot).
- If `RUNNER_PRIVATE_KEY` is missing, the daemon refuses to start.

## systemd

Template unit file: [`clanworld-runner.service`](./clanworld-runner.service).
Install with:

```bash
mkdir -p ~/.config/systemd/user
cp packages/runner/clanworld-runner.service ~/.config/systemd/user/
mkdir -p ~/.config/clanworld-runner
cp packages/runner/.env.example ~/.config/clanworld-runner/runner.env
chmod 600 ~/.config/clanworld-runner/runner.env
# edit runner.env, then:
systemctl --user daemon-reload
systemctl --user enable --now clanworld-runner.service
```

## Memory adapter

The runner uses `IElderMemoryStore` for durable Elder memory across `/clear` context resets.

### Local file (default)

When `OG_STORAGE_ENABLED` is **not** set the runner uses `FileMemoryStore` — a local JSON file at:

```
~/.world/clanworld-runner/state/elder-{N}-memory.json
```

No extra config required.

### 0G iNFT storage (Phase 7)

When `OG_STORAGE_ENABLED` is set the runner uses `ZeroGMemoryStore`, backed by the [0G KV network](https://docs.0g.ai).

Required env vars:

| Variable | Description |
|---|---|
| `OG_STORAGE_ENABLED` | Feature flag — set to any non-empty value to enable the 0G backend (real auth comes from `ELDER_MNEMONIC`) |
| `OG_STREAM_ID` | Optional shared KV stream ID override |
| `OG_STREAM_ID_CLAN_<id>` | Optional per-clan KV stream ID override |
| `EVM_RPC` | 0G EVM RPC endpoint (default: `https://evmrpc.0g.ai`) |
| `INDEXER_RPC` | 0G Indexer RPC endpoint (default: `https://indexer-storage-turbo.0g.ai`) |
| `FLOW_CONTRACT` | 0G Flow contract address |
| `ELDER_MNEMONIC` | BIP39 mnemonic (12 or 24 words) |
| `ELDER_INDEX` | Elder index 1–4 |

**Note:** Write transactions require a funded wallet and deployed Flow contract. Wallet is derived from `ELDER_MNEMONIC` at BIP-44 path `m/44'/60'/0'/0/{ELDER_INDEX-1}`.

## Peer inbox adapter (Phase 8)

The runner uses `IElderPeerInbox` for Elder-to-Elder private messaging (clan diplomacy).

### File-based inbox (default)

When `AXL_API_KEY` is **not** set (or `AXL_NETWORK_ID` is empty), the runner uses `FilePeerInbox`:

- Messages stored as JSONL at `~/.world/clanworld-runner/state/peer-inbox/elder-{recipient}.jsonl`
- `send()` appends to the **recipient's** file; `inbox()` reads the caller's own file.
- Non-destructive reads: `inbox()` returns all messages without deleting them.
- Wire format is back-compat with the Elder CLI's `peer whisper`/`peer inbox` commands.
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
| `ELDER_N` | Elder index 1–4 (single-elder mode only; full runner iterates internally) |

**AXL SDK blocked state (2026-04-27):** Gensyn does not publish an npm SDK for AXL. The runner
wraps the HTTP API directly via the `IAxlClient` interface (`src/axlPeerInbox.ts`).
When Gensyn ships `@gensyn/axl-sdk` (or equivalent), replace `AxlHttpClient` with the SDK
and update the two TODO comments in `axlPeerInbox.ts`.

**Fallback guarantee:** If either env var is missing the runner always falls back to `FilePeerInbox`
without throwing. Existing file-based flows are unaffected.

## Tests

```bash
pnpm test
```

Tests cover both fallback (file-based) and mocked-adapter paths. No AXL node, 0G credentials, or live mnemonic are required to run the test suite.

## Known TODOs

- `pollChainTick` reads the full snapshot — switch to a dedicated
  `getCurrentTick` Convex query once it exists.
- Heartbeat rate-limit detection re-reads `getWorldState()` after a revert.
  When a typed `HeartbeatTooSoon` custom error lands in the contract ABI,
  upgrade `RunnerCastHeartbeat.callHeartbeat` to decode it directly.
- AXL: persist the in-memory dedup `Set` into `IElderMemoryStore` so cross-restart
  exactly-once is achievable.
