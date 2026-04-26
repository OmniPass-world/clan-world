# Stream: Backend (Convex)

How to work on `apps/server/`.

## Setup

```bash
# from repo root
pnpm install

# log in to Convex (one-time)
npx convex login

# initialize the project (one-time per realm — Wave 1)
cd apps/server
npx convex init
```

The init step writes `CONVEX_DEPLOYMENT` and `CONVEX_URL` to `.env.local`. Both vars are read by the frontend, agents, and orchestrator via `IConvexClient`.

## Workflow

```bash
# from apps/server/
pnpm convex dev    # watcher: hot-reloads functions on save
```

Convex dev creates a per-developer "preview deployment". The S1 demo deployment is shared and lives in a separate Convex account — see operator runbook.

## MOCK_MODE

For dev without a deployed Convex backend:

```bash
CLAN_WORLD_USE_STUB_CONVEX=true pnpm --filter @clan-world/web dev
```

This makes `createConvexClient()` return `StubConvexClient` (mock data). Same flag the frontend reads.

## Indexer

(Wave 1+) Two complementary indexer paths, both idempotent:

1. **Webhook handler** — `convex/http/heartbeatWebhook.ts`. Triggered by the keeper after a successful `heartbeat()` tx. Re-runs both event log processing and state snapshot refresh.
2. **5s poll** — `convex/crons.ts`. Same internal mutations as the webhook path, just on a timer.

Both call the same internal action: `processSinceCheckpoint()`. Idempotent — repeated calls with no new logs are no-ops.

## Disaster heartbeat caller

`heartbeatCaller` cron is gated behind `HEARTBEAT_CALLER_ENABLED=true`. Off by default. Operators flip it on if Foundry loop or KeeperHub dies during demo.

## Deployment

```bash
# Submission 1
npx convex deploy --prod --deployment $S1_DEPLOYMENT

# Submission 2 (separate deployment, or reconfigure S1's)
npx convex deploy --prod --deployment $S2_DEPLOYMENT
```

## Schema

`convex/schema.ts` (Wave 1+) defines tables: `worldSnapshot`, `clanFullView`, `whispers`, `eventCheckpoints`, `tickHistory`. See `docs/planning/V1/02 Frontend Spec/clanworld_convex_backend_spec.md` for the full table list.
