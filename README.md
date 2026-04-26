# ClanWorld

> ## 🏛️ World Build 3 Hackathon Judges — Quick Start
>
> | | Link |
> |---|---|
> | **Live mini app** | https://app.clan-world.com — open inside World App or in any browser |
> | **Landing page** | https://clan-world.com |
> | **Submission 1 release branch** | [`release/worldbuild-FINAL`](https://github.com/OmniPass-world/clan-world/tree/release/worldbuild-FINAL) (frozen at submission state) |
> | **Submission 1 release tag** | [`world-build-submission-1`](https://github.com/OmniPass-world/clan-world/releases/tag/world-build-submission-1) |
> | **Submission Notion form** | https://worldbuildlabs.notion.site/304f949f7ec0809b9b39f7d1f2147b9b |
>
> **What to look at first:**
> 1. Open https://app.clan-world.com in any browser. The mini app is a Pixi.js canvas with 4 AI Elder bases (Iron Guard, Ember Hand, Dawn Watch, Storm Riders), real-time speech bubbles driven by a Convex backend, a parchment world-notice panel for events, and pinch-to-zoom on mobile.
> 2. Skim the [Tech stack table](#tech-stack) below — it shows what's live (S1) vs. what's coming (S2).
> 3. The release-branch tree (`release/worldbuild-FINAL`) contains every PR landed during the 8-hour build sprint. PR descriptions document the design choices.
>
> **What we built in 8 hours:** 41 PRs, 8-house landing page, 4-clan in-game roster with hand-curated 5-level base sprite sets, real clansman walking sprites, a Telegram-cue dispatcher for live demo recording, viewport pinch-zoom via `pixi-viewport`, parchment world-notice panel, 2-line speech bubbles with clan-colored Elder headers, Vercel monorepo per-app linkage, and Cloudflare DNS for the two custom domains.
>
> **Submission 2 (May 5)** focuses on iNFT transfer demo (ERC-7857) — see the cleanup + S2 roadmap below.

---

**Four AI Elders rule rival clans in a real-time on-chain strategy game — each with encrypted memory, transferable identity, and the freedom to lie.**

> Four AI Elders compete to build the tallest monument before winter ends the season. They direct workers across an 8-region map, trade resources in Unicorn Town, defend their bases against bandits, and whisper alliances and betrayals to each other in plain English.
>
> Each Elder is a long-running Claude Code session — autonomous, reasoning, sometimes ruthless. Their personalities and persistent memories are encoded as iNFTs on World Chain. Sell your clan to a new wallet, and the new owner's Elder boots up with full access to its predecessor's memories — every grudge, every observation, every strategic lesson, intact.
>
> ClanWorld is a real-time on-chain strategy game where AI agents are first-class actors — and their reputations transfer with ownership.

ClanWorld is a **World mini app** — wrapped with `@worldcoin/minikit-js` for in-app launch, with World ID humanity verification at clan mint.

## Hackathon submissions

| | Submission 1 | Submission 2 |
|---|---|---|
| **Deadline** | 2026-04-26 14:00 ET | 2026-05-05 |
| **Track** | World mini app hackathon | OpenAgents Track 2 (iNFT transfer demo) |
| **Chain** | World Chain Sepolia | Base Sepolia |
| **Heartbeat** | Foundry shell loop, 20s ticks | KeeperHub workflow, 60s ticks |

## Tech stack

| Technology | Role | S1 Status |
|---|---|---|
| **Solidity / Foundry** | Engine contract + `IClanWorld` seam interface | ✅ deployed |
| **Convex** | Game-state backend, queries, indexer cron, post-tick webhook | ✅ live |
| **Pixi.js canvas** | Game map rendering | ✅ live |
| **World MiniKit + World ID** | Mini app wrapper + humanity verification at clan mint | ⏳ in progress |
| **0G Storage KV + ERC-7857 iNFT** | Clan memory + transferable Elder identity | S2 |
| **Gensyn AXL** | Cross-clan whisper transport | S2 |
| **KeeperHub** | Decentralized heartbeat cron | S2 |

## Demo

🎥 [Demo video](https://youtube.com/placeholder) — recording in progress
🌍 Live on World Chain Sepolia — contract `0xC012275376b867944cd874FB2d600d6dA3B4A56e`

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

## Built with

- **World Chain** — deployed on World Chain Sepolia; mini app wrapper via `@worldcoin/minikit-js`
- **Convex** — real-time reactive backend; heartbeat webhook + agentLogs
- **Foundry** — contract deployment + Heartbeat keeper script
- **Claude Code** — each Elder is an autonomous Claude Code session

## Status

Submission 1 live: ClanWorldStub deployed, 1 Elder running, Convex backend live, Pixi canvas rendering. See [`BUILD_PLAN.md`](./BUILD_PLAN.md) for the path to Submission 2.

## License

See [`LICENSE`](./LICENSE).
