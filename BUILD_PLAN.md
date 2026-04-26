# BUILD_PLAN.md — Submission 1 Hail Mary (~6 hours)

Compressed plan for **Submission 1 only**. Submission 2 plan is written when S1 ships — placeholder at the bottom.

T-zero is Wave 0 commit. H6 = submission deadline today (2026-04-26 14:00 ET).

---

## 1. Integration Boundaries (the contract)

Every parallel stream talks through one of four adapter interfaces in `packages/shared/src/adapters/`. Stub-or-real factory pattern reads env vars. Switching modes is one flag flip.

| Interface | Purpose | Toggle |
|---|---|---|
| `IChainClient` | onchain read/write | `CLAN_WORLD_USE_STUB_CHAIN` |
| `IConvexClient` | Convex backend | `CLAN_WORLD_USE_STUB_CONVEX` |
| `IKeeper` | heartbeat driver | `KEEPER_MODE` (`foundry-loop` \| `keeperhub` \| `convex`) |
| `ILLMClient` | non-Elder LLM | `CLAN_WORLD_USE_STUB_LLM` |

**Factory rule:** consumers call the factory, never `new` the impls. Switching stubs/reals is one env flip per interface. Full pattern: `docs/conventions/adapter-interfaces.md`.

---

## 2. Decision Gates

### Resolved (per v4.5 alignment addendum)

- **One realm at a time.** S1 = World Chain Sepolia. S2 = Base Sepolia. Never both live.
- **Tick cadence:** S1 = 20s/Foundry loop. (S2 = 60s/KeeperHub.)
- **Heartbeat caller:** Foundry shell loop primary for S1. Convex `heartbeatCaller` cron is feature-flagged disaster fallback only.
- **Indexer trigger:** webhook-primary, 5s poll = safety net. Webhook payload is wake-up only (no `currentTick`).
- **Convex deployment:** single deployment, reconfigured between submissions.
- **No keys for Elder reasoning:** per-Elder Claude Code OAuth sessions. `ILLMClient` is for narrator/utility only.
- **Two-wallet model (S2):** treasury wallet offline-signed; agent wallets hot, capped, faucet-funded.

### Pending (to resolve before/during build)

- **World mini app integration scope** — does S1 require MiniKit auth/payments/share? World ID humanity at clan mint? Distribution path? **Resolution by H4** or fall back to "deps + README sentence" forever.
- **`IClanWorld` deploy script.** Does the existing interface deploy cleanly with our minimum-viable engine impl? **Resolution at H1 gate** or cut to a stub engine that only emits `TickAdvanced`.
- **Sealed inference (S2)** — not in scope for Submission 1. Defer.

---

## 3. Hour-by-Hour Timeline (Submission 1)

### H0–H1 — Wave 1: contracts on testnet

- **Goal:** `IClanWorld` deployed to World Chain Sepolia. Foundry deploy script works. `getCurrentTick()` returns 0.
- **Tasks:**
  - Implement minimum-viable engine in `packages/contracts/src/ClanWorld.sol` (heartbeat + tick storage + `TickAdvanced` event).
  - Write `script/Deploy.s.sol`.
  - Deploy. Save `ENGINE_ADDRESS` to `.env.local`.
- **Gate 1:** Contract on testnet, `cast call $ENGINE_ADDRESS "getCurrentTick()(uint256)"` returns 0.

### H1–H3 — Wave 2: Convex backend mock + frontend mock

- **Goal:** frontend renders 8 regions (mock data) end-to-end via Convex.
- **Tasks:**
  - `apps/server`: `convex init`, define schema (`worldSnapshot`, `regions`, `clans`), seed mock data, ship `getSnapshot` and `getClanFullView` queries.
  - `apps/web`: import `createConvexClient()`, subscribe to `getSnapshot`, render 8 SVG region polygons with mock clan-color fills, render clan list panel.
  - Frontend reads with `CLAN_WORLD_USE_STUB_CONVEX=false` against the dev Convex deployment (i.e., real Convex, mock data inside Convex).
- **Gate 2:** Frontend renders mock world with 8 regions and 8 clans. Subscribe-on-mutation works (edit a row in Convex dashboard, frontend updates live).

### H3–H4.5 — Wave 3: one Elder running, one real tx

- **Goal:** an Elder Claude Code session reads a `<situation>`, invokes `elder clan submit-orders`, a real tx hits chain.
- **Tasks:**
  - Implement `RealChainClient` (viem + ENGINE_ADDRESS) — at minimum `submitOrders` and `getCurrentTick`.
  - Implement `elder clan submit-orders` in `packages/agents/src/cli.ts`.
  - Implement `apps/orchestrator/src/main.ts` to spawn one Claude Code subprocess and pump a hardcoded `<situation>` block once.
  - Verify a real tx confirms on World Chain Sepolia with the agent wallet.
- **Gate 3:** Real tx on chain via mocked-Elder flow. Tx hash recorded.

### H4.5–H5.5 — Wave 4: 4 Elders + speech bubbles + World wrapper

- **Goal:** 4 Elders running, basic whisper/speech UI, World mini app wrapper visible.
- **Tasks:**
  - Spawn 4 Elders from orchestrator (config dirs + session IDs).
  - Frontend: whisper bubble component subscribed to `whispers` table.
  - Frontend: add `<MiniKitProvider>` shell (no real auth flow — the wrapper shows).
  - Update README with the World mini app sentence.
- **Gate 4 (soft):** 4 Elders alive, sending whispers. Frontend renders whisper bubbles. README + package mention world mini app.

### H5.5–H6 — Wave 5: demo recording + submission

- **Goal:** clean recording uploaded to hackathon platform.
- **Tasks:**
  - Record demo (phone via World App; backup is screen-record from desktop).
  - Verify the 8 demo moments (or as many as we have) are visible.
  - Upload to submission portal. Tag `s1-v0.1.0`.
- **Gate 5 (hard):** Submission uploaded.

---

## 4. Decision Gates (runtime)

### H3 gate — go / no-go

If `Gate 3` (real tx via Elder) hasn't fired by H3:

| Behind by | Cut |
|---|---|
| <30 min | Real Elders → mock Elders driving canned moves (orchestrator just emits orders) |
| 30–60 min | Above + Pixi → SVG region polygons only |
| >60 min | Above + cancel S1; ship as a Wave 1 demo recording without world-app wrapper |

### H5 gate — final go / no-go

If `Gate 4 (soft)` hasn't fired by H5:

- Real demo recording is required (Gate 5).
- If 4 Elders aren't running, scale down to 2 with hardcoded whispers.
- If World wrapper isn't visible, ship as a regular browser demo with a TODO note in submission body.

---

## 5. Guardrails

- **Time-box every task.** If a task takes >25 min over its slot estimate, **cut and use the stub.**
- **Commit at every gate.** Even partial work — branches must build.
- **Minimal tests only.** Happy-path + a few important error cases. No regression suites, no coverage chasing. Full rule: `docs/conventions/hackathon-rules.md`.
- **Env var simplicity.** ONE env var per concept, sensible defaults, no duplicates, no backwards-compat shims. Full rule: `docs/conventions/hackathon-rules.md`.
- **Cut if behind** (priority order):
  1. Real Elders → mock Elders (orchestrator emits canned orders).
  2. Pixi sprites → SVG region polygons only.
  3. Live phone demo via World App → screen-recorded desktop demo.
- **Never cut:**
  - `IClanWorld` deployed on World Chain Sepolia (dummy engine OK; real interface MUST be deployed).
  - At least one real `heartbeat()` tx on testnet (with tx hash visible).

---

## 6. Parallel Track Dependencies

```
H0 ─── H1 ─── H2 ─── H3 ─── H4 ─── H5 ─── H6
                                            └── submit
contracts ──Gate1──┐
                   ▼
backend         ───┴──Gate2──┐
                             ▼
frontend                  ───┴──── + world wrapper ─┐
                                                    ▼
agents ────── (independent, runs against stubs) ───── + 4 Elders ─Gate3,4─ recording
orchestrator ─                                     ─┘
keeper ────── (Foundry shell loop runs from H1)
```

- **Contracts blocks backend's real chain reads** (backend can run mock-only until H1 gate).
- **Backend blocks frontend's real subscriptions** (frontend can run on mock Convex until H3).
- **Agents track is independent until H3** — Elder + toolbelt code lands against stub `IChainClient` and `IConvexClient` while contracts and backend are still in flight.
- **Heartbeat keeper** runs from H1 onward, advancing tick every 20s, even with no agent activity.

The adapter interfaces are the wire that lets all 5 streams move forward in parallel. Without them, every stream blocks on every other stream.

---

## 7. Submission 2 (placeholder)

To be expanded after Submission 1 ships. Read order:
1. `docs/planning/V1/05 0G/clanworld_0g_battleplan_and_spec.md` — OpenAgents Track 2 strategy + 7-step plan
2. `docs/planning/V1/05 0G/clanworld_clan_memory_spec.md` — `ClanMemory` library
3. `docs/planning/V1/05 0G/clanworld_clan_identity_spec.md` — `ClanIdentity` library
4. `docs/planning/V1/05 0G/clanworld_inft_deployment_notes.md` — ERC-7857 deployment
5. `docs/planning/V1/04 AXL integration spec.pdf`
6. `docs/planning/V1/03 KeeperHub integration spec.pdf` + `docs/planning/V1/01 Blockchain Game Spec/clanworld v4 5 keeper integration spec.pdf`

S2 punchline: clan iNFT mint → in-game play → mid-game transfer to new owner → new owner inherits clan memory and reasoning. Chain switches from World Chain Sepolia to Base Sepolia. Heartbeat switches from Foundry loop to KeeperHub. Storage adds 0G Storage KV. Whispers add AXL.
