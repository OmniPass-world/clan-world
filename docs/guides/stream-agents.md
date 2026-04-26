# Stream: Agents (Elders + Orchestrator + Toolbelt)

How to work on `apps/orchestrator/` and `packages/agents/` together.

## Mental model

Four LLM "Elders" — one per clan. Each runs as a long-running Claude Code subprocess (`claude --print --resume <session-id>`). The orchestrator spawns them at boot, sends a `<situation>` block per tick, and the Elder responds by invoking the `elder` CLI to read state and submit orders.

```
┌────────────────────────────────────────────────────────┐
│ apps/orchestrator (one process)                        │
│   ├─ FoundryLoopKeeper (S1) or KeeperHubKeeper (S2)    │
│   ├─ tick pump                                         │
│   └─ 4× Elder subprocesses                             │
│       └─ each runs: claude --print --resume <sid>       │
│                       │                                 │
│                       └─ Bash → `elder world snapshot` │
│                                  `elder clan submit-orders` │
│                                  `elder whisper send`   │
└────────────────────────────────────────────────────────┘
```

## Boot sequence

(Wave 1+ implementation)

1. Orchestrator reads `ENGINE_ADDRESS`, `CONVEX_URL`, `TICK_DURATION_MS` from env.
2. Orchestrator creates 4 Claude Code config dirs at `~/.claude-clan-{1..4}/` (one per Elder, isolation per `~/claudes-world` ADR 0013).
3. Orchestrator spawns 4 `claude --print --resume <sid>` subprocesses with `CLAUDE_CONFIG_DIR` env override per Elder.
4. Each Elder receives a startup prompt establishing its clan identity + toolbelt instructions.
5. Orchestrator starts the heartbeat keeper (`createKeeper().start()`).
6. Tick pump begins.

## Per-tick flow

For each tick:

1. Orchestrator reads `WorldSnapshot` from Convex (`createConvexClient().getSnapshot()`).
2. Orchestrator formats a `<situation>` block per Elder with: current tick, their clan view, recent whispers, available regions, treasury.
3. Orchestrator writes the block to each Elder's stdin.
4. Each Elder thinks (budget = `agentThinkBudgetMs` ms) and invokes toolbelt commands via Bash:
   - `elder world snapshot`  — read latest snapshot
   - `elder clan view <clanId>` — read full clan view
   - `elder clan submit-orders <clanId> <ordersJsonFile>` — submit
   - `elder whisper send <fromClan> <toClan> <text>` — send a whisper
5. Orchestrator collects each Elder's submission. Force-cancels (sends `<deadline-passed>`) if the Elder runs over budget.
6. Heartbeat keeper fires `heartbeat()`; tx confirms; webhook fires; Convex re-indexes; loop.

## `elder` CLI conventions

- **stdout = JSON** (Elders parse).
- **stderr = human** (operators read).
- Exit 0 = success, nonzero = error.
- No interactive prompts — every input is argv or env var.
- Reads `CLAN_WORLD_CLAN_ID` from env by default; positional arg overrides.
- Idempotent reads and writes — submitting the same orders twice is a no-op, not a double-charge.

## Local dev — run one Elder

```bash
# build the toolbelt
pnpm --filter @clan-world/agents build
pnpm link --global

# verify
elder world snapshot

# spawn the orchestrator with stubs
CLAN_WORLD_USE_STUB_CHAIN=true \
CLAN_WORLD_USE_STUB_CONVEX=true \
  pnpm --filter @clan-world/orchestrator dev
```

For Submission 1 demo: 4 Elders, real chain, real Convex, Foundry loop heartbeat.

## Crash recovery

Elder Claude Code subprocesses persist transcript across restarts. On crash, orchestrator respawns with the same session ID — the Elder picks up where it left off. The orchestrator itself is stateless beyond a session ID file at `~/.clanworld/elder-sessions.json`.

## No API keys

Per `~/claudes-world` ADR 0013, agent reasoning happens via per-Elder Claude Code OAuth sessions, NOT via `ANTHROPIC_API_KEY`. Each `~/.claude-clan-{n}/` dir is a separately authenticated Claude install. The `ILLMClient` adapter is for non-Elder utility uses (narrator, analytics) — not for Elder reasoning.
