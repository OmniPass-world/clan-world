# ClanWorld — AGENTS.md

Top-level instructions for any agent (human or LLM) working in this repo. Keep this file under 500 lines; deeper reference belongs in `docs/`.

## 1. Project Overview

ClanWorld is an autonomous strategy game. Eight regions, eight clans, each clan run by an LLM "Elder" agent. The world advances in fixed-duration ticks — every tick a heartbeat tx fires on chain, the world state advances, agents read `<situation>` blocks, decide, and submit orders before the next heartbeat.

The codebase is a **pnpm + Turborepo monorepo**. Six workspace packages today:

| Path | Name | Role |
|---|---|---|
| `apps/web/` | `@clan-world/web` | Vite + React frontend; wraps as a World mini app for Submission 1 |
| `apps/server/` | `@clan-world/server` | Convex backend (queries, mutations, indexer cron, webhook) |
| `apps/orchestrator/` | `@clan-world/orchestrator` | Spawns and pumps the 4 long-running Elder Claude Code sessions |
| `packages/contracts/` | `@clan-world/contracts` | Foundry project; `IClanWorld.sol` is the canonical seam |
| `packages/agents/` | `@clan-world/agents` | `elder` CLI toolbelt invoked by Elder sessions |
| `packages/shared/` | `@clan-world/shared` | TypeScript types + adapter interfaces consumed by every other workspace |

## 2. Hackathon Submissions Calendar

| | Submission 1 | Submission 2 |
|---|---|---|
| Deadline | **2026-04-26 14:00 ET** (today) | **2026-05-05** |
| Track | World mini app hackathon | OpenAgents Track 2 (iNFT transfer demo) |
| Chain | World Chain Sepolia | Base Sepolia |
| Heartbeat | Foundry shell loop, 20s ticks | KeeperHub workflow, 60s ticks |
| Stretch deps | MiniKit + World ID (thin wrapper) | 0G Storage KV, 0G iNFT (ERC-7857), AXL whispers, KeeperHub |

Submission 1 is a thin wrapper — MiniKit + idkit are listed as deps and mentioned in the README, but real integration is **out of scope for Wave 0**. See `docs/reference/prize-strategy.md`.

## 3. Gitflow Rules (light)

- `main` is sacred — only tagged release merges.
- `dev` is the integration branch — feature PRs target it.
- Feature branches: `feat/issue-N-short-desc`, branched off `dev`.
- Commits: conventional commits + issue ref → `type(scope): desc (#N)`.
- One PR closes one issue (`Closes #N` in the body).
- All 3 local reviewers (Claude subagent → Codex → Gemini flash) must be GREEN before opening a PR. Cloud is a single sanity pass per the cloud-thrift policy.
- Full rules: `docs/conventions/gitflow.md`.

## 4. Integration Boundaries (the contract)

Every parallel stream talks to its dependencies through one of four adapter interfaces in `packages/shared/src/adapters/`. Stubs and reals coexist; the factory chooses based on env vars.

| Interface | Stream owners | Stub flag | Real impl ETA |
|---|---|---|---|
| `IChainClient` | contracts → all | `CLAN_WORLD_USE_STUB_CHAIN=true` | Wave 1 |
| `IConvexClient` | backend → frontend, agents, orchestrator | `CLAN_WORLD_USE_STUB_CONVEX=true` | Wave 1 |
| `IKeeper` | ops → orchestrator | `KEEPER_MODE=foundry-loop\|keeperhub\|convex` | Wave 2 (foundry-loop), Wave 5 (keeperhub) |
| `ILLMClient` | agents → narrator/utility | `CLAN_WORLD_USE_STUB_LLM=true` | Submission 2 (ZeroG) |

Pattern + worked example: `docs/conventions/adapter-interfaces.md`.

## 5. Validated Architecture Decisions

Per `docs/planning/V1/07 clanworld_v4_5_alignment_addendum.md` (authoritative; supersedes prior specs).

| Decision | Choice | Rationale |
|---|---|---|
| Realms | One realm at a time (S1 World, S2 Base — never both live) | Cuts coordination story in half; one frontend, one Convex deployment |
| Tick cadence | 20s for S1 + dev, 60s for S2 KeeperHub | KeeperHub cron has 1-min floor; S1 wants tight demo |
| Heartbeat caller | Foundry loop primary (S1), KeeperHub (S2 live), Convex cron = disaster fallback | Foundry has no cadence floor; Convex stays for DR |
| Indexer trigger | Webhook-primary, 5s poll = safety net | Lower latency than 5s poll, eliminates race vs `TickAdvanced` |
| Webhook payload | Minimal: `{chain, engineAddress, txHash, firedAtTs, source}` — NO `currentTick` | Avoid extra RPC read; Convex re-derives from chain |
| World mini app integration | Thin wrapper for S1 (deps + README sentence); UX TBD pre-M5 | Optical signal sufficient; UX requirements not yet researched |
| Convex deployment | Single deployment, reconfigured between submissions (or two toggled by env var) | One realm at a time → no cross-chain logic ever needed |
| Heartbeat caller flag | `HEARTBEAT_CALLER_ENABLED=false` by default; on for DR | Per v4.5 §3.2 — multiple keepers are safe per §5.1 |

Full extraction: `docs/reference/architecture-decisions.md`.

## 6. Environment & Secrets

- `.env.template` at repo root lists every variable the system reads.
- Copy to `.env.local` (gitignored) and fill values. Never commit real secrets.
- Adapter factories read `CLAN_WORLD_USE_STUB_*` flags at runtime.
- Two-wallet model for Submission 2: agent wallets hold no real funds; treasury wallet is offline-signed only.
- For the do-box / shared host: per-package OAuth via Claude Code session, not API keys (per `~/claudes-world` ADR 0013).

## 7. Progressive Discovery Index

Start at the package-level `AGENTS.md` for whatever you're touching, then dive into `docs/` only when you need the deeper context.

**Per-package guides:**
- `apps/web/AGENTS.md` — frontend, Vite, region authoring
- `apps/server/AGENTS.md` — Convex setup, indexer, webhook
- `apps/orchestrator/AGENTS.md` — Elder session lifecycle, pumping `<situation>` blocks
- `packages/contracts/AGENTS.md` — Foundry workflow, deploy targets
- `packages/agents/AGENTS.md` — `elder` CLI toolbelt conventions
- `packages/shared/AGENTS.md` — types + adapter pattern

**Reference (`docs/reference/`):**
- `architecture-decisions.md` — every validated decision from the addendum
- `prize-strategy.md` — S1 thin wrapper rationale, S2 OpenAgents Track 2 punchline
- `sponsor-tech.md` — World SDK, 0G Storage, ERC-7857, AXL, KeeperHub notes

**Guides (`docs/guides/`):**
- `stream-contracts.md` — Foundry workflow, deploy script, typechain
- `stream-backend.md` — Convex setup, MOCK_MODE
- `stream-frontend.md` — Vite dev, region polygons, Pixi notes
- `stream-agents.md` — Elder boot, orchestrator, toolbelt CLI
- `stream-ops.md` — Makefile, demo-reset, agent funding

**Conventions (`docs/conventions/`):**
- `gitflow.md` — full gitflow-light rules
- `adapter-interfaces.md` — adapter pattern with worked `IChainClient` example
- `pr-review.md` — local 3-tier swarm review protocol

**Build plan:** `BUILD_PLAN.md` (Submission 1 hour-by-hour). Submission 2 plan written when S1 ships.

## 8. PR / Code Review

- One PR per issue. PR body must include `Closes #N`.
- Run the local 3-tier swarm before opening the PR (Claude subagent + Codex + Gemini flash). All three GREEN.
- Cloud reviewers (Copilot + Gemini Code Assist) are a single sanity pass at end-of-cycle. Don't cycle to re-confirm.
- Conventional commit messages, scope tagged: `feat(scope): …`, `fix(scope): …`, `docs(scope): …`, `chore(scope): …`.
- Hackathon discipline: speed > polish, but every gate commit must be on a branch that builds and typechecks.

## 9. Security

- **No real funds in agent wallets.** Agents transact with testnet faucet funds only.
- **Two-wallet model (S2):** treasury wallet for high-value ops is offline-signed; agent wallets are hot but capped.
- **No secrets in commits.** `.env*` files (except `.env.template` and `.env.example`) are gitignored.
- **Webhook auth:** keepers and Convex share a `WEBHOOK_SHARED_SECRET` header — do not log it.
- **World ID humanity verification:** at clan mint only (S2 if scoped); never as gating for read paths.
- **0G iNFT key custody (S2):** the iNFT transfer demo punchline depends on key authorization handover; treat the key blob as a secret artifact.
