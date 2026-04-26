# apps/orchestrator — AGENTS.md

Node app that supervises the 4 long-running Elder Claude Code sessions. One Elder per clan, each running as a `claude` CLI subprocess in `--print --resume` mode. The orchestrator pumps a `<situation>` block into stdin every tick, captures the Elder's tool-call output (via the `elder` CLI), and moves on.

## What this package does

- **Elder lifecycle:** spawn N Claude Code sessions, persist session IDs, restart on crash.
- **Tick pump:** read current tick from chain, format `<situation>` block from Convex snapshot, send to each Elder, await `elder clan submit-orders` toolbelt invocation.
- **Heartbeat coordination (S1):** runs the Foundry loop in-process or shells out to `scripts/start-heartbeat-loop.sh`.
- **Webhook fan-out:** posts to Convex webhook after each successful heartbeat tx.

## Wave 0 status

Stub `src/main.ts` logs `orchestrator starting (stub)` and exits. Real impl lands in Wave 3.

## Key files

- `src/main.ts` — entry point.
- (TBD) `src/elder.ts` — Claude Code subprocess wrapper.
- (TBD) `src/tick.ts` — per-tick coordination loop.
- (TBD) `src/heartbeat.ts` — Foundry loop driver.

## Local conventions

- **One process supervises all 4 Elders.** Per-Elder isolation is via `CLAUDE_CONFIG_DIR` env override (each Elder gets `~/.claude-clan-{id}/`).
- **No API keys for Elder reasoning.** Elders inherit OAuth from their per-Elder Claude Code config dirs.
- **Strict per-tick deadline.** `agentThinkBudgetMs` (12s for S1, 45s for S2) — orchestrator force-cancels and submits empty orders if an Elder doesn't return in time.
- **Crash recovery is "respawn with same session ID."** Claude Code preserves transcript on resume.

## How it interacts with adapters

- **`IChainClient`** — reads tick, fires heartbeat tx (until S2 hands that off to KeeperHub).
- **`IConvexClient`** — reads snapshot per tick, posts logs.
- **`IKeeper`** — orchestrator may instantiate `FoundryLoopKeeper` directly for S1 (in-process), or just monitor an external KeeperHub for S2.
- **`ILLMClient`** — used by the optional narrator (post-tick storyline summary). Elders don't go through this — they're full Claude Code sessions.

## Running

```bash
pnpm --filter @clan-world/orchestrator dev   # tsx watch
pnpm --filter @clan-world/orchestrator start # tsx (one-shot)
```

See `docs/guides/stream-agents.md` for the Elder boot sequence and per-Elder config setup.
