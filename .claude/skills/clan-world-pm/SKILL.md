---
name: clan-world-pm
description: ClanWorld project management — milestones, labels, hackathon deadlines, cut priorities. Read when triaging issues, opening PRs, or making scope decisions.
---

# ClanWorld PM

Just-in-time reference for the orchestrator and any PM-style agent working in this repo. Heavier reference (decision rationale, demo strategy) lives in `docs/reference/prize-strategy.md`.

## Submissions calendar

| | Submission 1 | Submission 2 |
|---|---|---|
| Deadline | **2026-04-26 14:00 ET** (today) | **2026-05-05** |
| Track | World mini app hackathon | OpenAgents Track 2 (iNFT transfer demo) |
| Chain | World Chain Sepolia | Base Sepolia |
| Heartbeat | Foundry shell loop, 20s ticks | KeeperHub workflow, 60s ticks |
| Demo punchline | 8 demo moments running inside World App | clan iNFT mint → mid-game transfer → memory continuity |

## Milestones

Nine numbered milestones spanning both submissions:

| # | Name | Description |
|---|---|---|
| M0 | Foundation | Wave 0 scaffold + adapter interfaces + docs (Issue #1) |
| M1 | Core engine | `IClanWorld` impl + Foundry deploy + first heartbeat tx |
| M2 | S1 Integration | Convex schema + frontend wiring + 4 Elders + orchestrator |
| M3 | S1 Polish | Whisper UI + region polygon visuals + World mini app wrapper |
| M4 | S1 Shipped | Demo recording + submission upload + tag `s1-v0.1.0` |
| M5 | S2 Master Plan | Submission 2 master spec written; KeeperHub + 0G + AXL integration plan locked |
| M6 | S2 Integration | Base Sepolia redeploy + KeeperHub + 0G Storage KV + ERC-7857 iNFT minted |
| M7 | Track 2 Demo | Clan iNFT transfer flow with key handover + memory continuity verified |
| M8 | S2 Shipped | Demo recording + submission upload + tag `s2-v0.1.0` |

Issues should reference exactly one milestone. PRs auto-tick the milestone via `Closes #N`.

## Labels

Five axes; one value per axis per issue.

| Axis | Values |
|---|---|
| `track:` | `s1-world`, `s2-openagents`, `cross-cutting` |
| `priority:` | `p0-blocker`, `p1-must-fix`, `p2-should`, `p3-nice` |
| `status:` | `triage`, `ready`, `in-progress`, `blocked`, `review`, `done` |
| `type:` | `feat`, `bug`, `chore`, `docs`, `refactor`, `infra` |
| `scope:` | `web`, `server`, `orchestrator`, `contracts`, `agents`, `shared`, `ops`, `cross` |

Defaults on issue creation: `status:triage`, `priority:p2-should`. Promote to `priority:p1-must-fix` only if it blocks a milestone.

## Cut priorities

Time pressure is real. If we're behind at a runtime gate (H3 or H5 in `BUILD_PLAN.md`), cut in this order.

### Cut-if-behind (try first)

1. **Real Elders → mock Elders** driving canned moves (orchestrator emits orders directly).
2. **Pixi sprites → SVG region polygons** only.
3. **Live phone demo via World App → screen-recorded desktop demo.**

### Cut-if-desperate (after the above)

4. **Speech bubbles → text log feed.**
5. **Multiple Elders → 1 Elder + 3 hardcoded clans.**
6. **Cross-clan whispers → broadcast-only narration.**

### Never cut

- `IClanWorld` deployed on World Chain Sepolia.
- At least one real `heartbeat()` tx on testnet with a public tx hash.
- The 8 demo moments visible (even if scripted) — see `docs/planning/V1/01 Blockchain Game Spec/clanworld_v1_implementation_profile.md` §8.
- For Submission 2: live iNFT mint + transfer + key-authorization handover demonstrating memory continuity.

## Branch + commit conventions

- Branch: `feat/issue-N-short-desc` off `dev`.
- Commit format: `type(scope): desc (#N)`.
- One PR per issue. PR body includes `Closes #N`.
- Local 3-tier swarm review GREEN before opening PR.
- Full rules: `docs/conventions/gitflow.md`, `docs/conventions/pr-review.md`.

## When in doubt, ask

If scope ambiguity is blocking work, post a comment on the relevant issue tagging the orchestrator. Do NOT silently expand or shrink scope. The orchestrator owns scope decisions per `~/claudes-world` policy.
