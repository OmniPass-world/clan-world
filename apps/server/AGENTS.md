# apps/server — AGENTS.md

Convex backend. Hosts game-state queries, the indexer cron, and the post-tick webhook. One Convex deployment per realm (one for S1 World Chain Sepolia, redeployed for S2 Base Sepolia).

## What this package does

- **Queries:** `getSnapshot`, `getClanFullView`, `subscribeWhispers` — the read surface for the frontend.
- **Mutations:** internal-only state writes from the indexer.
- **Indexer cron:** runs every 5s as a safety net; the primary trigger is the post-tick webhook (per addendum §4).
- **Post-tick webhook:** HTTP action at `/api/heartbeat-webhook` — re-runs both event indexer and state snapshot refresh.
- **Disaster `heartbeatCaller` cron:** feature-flagged off by default (`HEARTBEAT_CALLER_ENABLED`); flip on if Foundry loop or KeeperHub dies.

## Wave 0 status

A stub `convex/getSnapshot.ts` returns a mock `WorldSnapshot`. No actual Convex codegen has been run — the file imports from `@clan-world/shared` and compiles as plain TS. Wire `convex dev` in Wave 1.

## Key files

- `convex/getSnapshot.ts` — stub query, will become a real Convex query.
- `convex.json` — points the Convex bundler at `convex/`.
- `tsconfig.json` — extends root `tsconfig.base.json`; will include Convex codegen path once `convex dev` is run.

## Local conventions

- **MOCK_MODE flag:** the backend reads `CLAN_WORLD_USE_STUB_CHAIN=true` to short-circuit chain reads with mock data. Same flag the agents use; one toggle for the whole stack.
- **Webhook auth:** `WEBHOOK_SHARED_SECRET` in the `Authorization: Bearer …` header. Both keepers (Foundry loop, KeeperHub) include it.
- **Webhook is wake-up only.** Do NOT trust the payload's `currentTick` (it's not in the payload — re-derive from chain).
- **Indexer is idempotent.** Both webhook handler and 5s poll call the same internal mutation; double-fires are safe.

## How it interacts with adapters

- **`IChainClient`** — internal Convex action calls `createChainClient()` to read `engine.getCurrentTick()` and process logs since the last checkpoint.
- **`IConvexClient`** — N/A (this IS the Convex backend).
- **`IKeeper`** — N/A; the keeper lives in `apps/orchestrator` or as an external systemd timer.
- **`ILLMClient`** — used by the optional narrator function (S2) to summarize ticks.

## Running

```bash
pnpm --filter @clan-world/server dev   # placeholder; runs `convex dev` in Wave 1
```

See `docs/guides/stream-backend.md` for the Convex setup workflow (`pnpm convex dev`, deployment IDs, MOCK_MODE).
