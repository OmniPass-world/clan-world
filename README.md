# ClanWorld

Eight regions. Eight clans. Eight LLM "Elder" agents reasoning, fighting, and bargaining in real time. The world advances in fixed-duration ticks; every tick a heartbeat tx fires on chain, the engine resolves moves, and the agents decide what to do next.

ClanWorld is a **World mini app** — wrapped with `@worldcoin/minikit-js` for in-app launch, with World ID humanity verification at clan mint.

## Hackathon submissions

| | Submission 1 | Submission 2 |
|---|---|---|
| **Deadline** | 2026-04-26 14:00 ET | 2026-05-05 |
| **Track** | World mini app hackathon | OpenAgents Track 2 (iNFT transfer demo) |
| **Chain** | World Chain Sepolia | Base Sepolia |
| **Heartbeat** | Foundry shell loop, 20s ticks | KeeperHub workflow, 60s ticks |

## Tech stack

- **Solidity / Foundry** — engine contract + `IClanWorld` seam interface
- **Convex** — game-state backend, queries, indexer cron, post-tick webhook
- **Vite + React** — frontend (Wave 0); **Pixi** for the canvas (Wave 2+)
- **World MiniKit + World ID** — Submission 1 mini app wrapper + humanity verification
- **0G Storage KV + ERC-7857 iNFT** — Submission 2 clan memory + identity
- **Gensyn AXL** — Submission 2 cross-clan whisper transport
- **KeeperHub** — Submission 2 decentralized heartbeat cron

## Quick start

```bash
# install
corepack enable && corepack prepare pnpm@10.28.1 --activate
pnpm install

# typecheck the whole monorepo
pnpm run typecheck

# run frontend with stubs (no backend or chain needed)
CLAN_WORLD_USE_STUB_CONVEX=true CLAN_WORLD_USE_STUB_CHAIN=true \
  pnpm --filter @clan-world/web dev
```

## Project structure

```
apps/
  web/          @clan-world/web         — Vite + React frontend (World mini app)
  server/       @clan-world/server      — Convex backend
  orchestrator/ @clan-world/orchestrator — Elder session manager + heartbeat keeper

packages/
  contracts/    @clan-world/contracts   — Solidity (Foundry); IClanWorld seam
  agents/       @clan-world/agents      — `elder` CLI toolbelt
  shared/       @clan-world/shared      — types + adapter interfaces

docs/
  reference/    architecture decisions, prize strategy, sponsor tech
  guides/       per-stream how-tos
  conventions/  gitflow, adapter pattern, PR review

BUILD_PLAN.md   hour-by-hour plan for Submission 1 hail mary
AGENTS.md       top-level instructions for any agent working in this repo
```

See [`AGENTS.md`](./AGENTS.md) for the full agent-facing instructions and discovery index.

## Running services

For Submission 1 dev (one realm, World Chain Sepolia, 20s ticks):

```bash
# 1. start Convex backend (per dev preview)
pnpm --filter @clan-world/server dev

# 2. start frontend
pnpm --filter @clan-world/web dev

# 3. start the orchestrator (spawns 4 Elders + Foundry heartbeat loop)
pnpm --filter @clan-world/orchestrator dev
```

For full demo run with real chain + Convex, fill `.env.local` from `.env.template` and unset all `CLAN_WORLD_USE_STUB_*` flags.

## Status

Wave 0 — scaffold + docs. See [`BUILD_PLAN.md`](./BUILD_PLAN.md) for the path to Submission 1.

## License

See [`LICENSE`](./LICENSE).
