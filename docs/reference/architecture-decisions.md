# Architecture Decisions — ClanWorld

Validated decisions extracted from `docs/planning/V1/07 clanworld_v4_5_alignment_addendum.md`. The addendum is authoritative; if any of the prior 7 spec docs conflicts with it or with this file, this file wins. Update this file when a decision changes — don't update prior specs.

For decisions about specific seams, see `../conventions/adapter-interfaces.md` and the per-package AGENTS.md files.

---

## 1. One realm at a time

Submission 1 runs on World Chain Sepolia. Submission 2 runs on Base Sepolia. **They are never both live simultaneously.**

**Implications:**
- One frontend codebase, parameterized by chain config at build/deploy time.
- One Convex deployment, reconfigured between submissions (or two toggled by env var, also fine).
- One agent runner harness with chain-specific configs swapped in.
- One Makefile with per-chain deploy targets.
- **Zero cross-chain coordination logic** ever needed.

This contradicts the earlier reading of the keeper spec that suggested two parallel stacks. It is the correct simplification.

---

## 2. Tick cadence

| Submission | Chain | Cadence | Driver |
|---|---|---|---|
| Submission 1 (World) | World Chain Sepolia | **20s/tick** | Foundry shell loop |
| Submission 2 (Base) live demo | Base Sepolia | **60s/tick** | KeeperHub workflow |
| Local dev / testing on either chain | (any) | **20s/tick or faster** | Foundry shell loop |

**Why the difference:** KeeperHub's cron has a 1-minute floor. Foundry shell loop has no floor — `sleep 20` works fine. For S1 demo recording we want tight ticks; for S2's post-submission live demo, KeeperHub's 60s is the steady state.

**Side benefit at 60s:** Elders get **3× more thinking budget per tick**. Reasoning quality goes up.

The cadence is a single env var: `TICK_DURATION_MS`. Read by frontend, backend, agent runner, and keeper. Already specced.

---

## 3. Heartbeat caller — Foundry loop / KeeperHub primary, Convex cron is fallback only

Earlier backend spec made the Convex `heartbeatCaller` cron the primary mechanism. **It is now the disaster fallback.**

| Submission | Primary caller | Fallback |
|---|---|---|
| S1 (World, dev) | Foundry shell loop | Convex cron, off by default |
| S2 (Base, live) | KeeperHub workflow | Convex cron, off by default |
| S2 (Base, dev pre-submission) | Foundry shell loop | Convex cron, off by default |

**`HEARTBEAT_CALLER_ENABLED=false`** by default. Operators flip to `true` only if the primary keeper dies during demo. Per v4.5 §5.1 the contract is self-rate-limiting, so accidental double-fires are harmless.

The Convex code stays in the codebase for two reasons: (1) disaster recovery, (2) self-contained CI / smoke tests with no external keeper.

---

## 4. Indexer trigger — webhook-primary, 5s poll is safety net

Earlier backend spec described two indexer loops: state-poll (event-triggered) and event-poll (5s cron). The keeper spec adds a third signal: a **post-tick webhook** fired by the keeper after a successful `heartbeat()` tx confirms.

**The webhook is the primary trigger** for both loops. The 5s poll stays as a safety net.

**Flow:**
1. Keeper calls `heartbeat()`; tx confirms.
2. Keeper fires `POST /api/heartbeat-webhook` with `{chain, engineAddress, txHash, firedAtTs, source}`.
3. Convex HTTP action runs both event indexer (process logs since checkpoint) and state indexer (refresh snapshot tables).
4. 5s poll continues as fallback. If webhook arrived first, the poll is a no-op (idempotent).

**Why webhook-primary:** lower latency than 5s poll (~1s after tx confirmation), eliminates race between `TickAdvanced` event indexing and snapshot refresh.

---

## 5. Webhook payload — minimal

```json
{
  "chain": "base-sepolia" | "worldchain-sepolia",
  "engineAddress": "0x...",
  "txHash": "0x...",
  "firedAtTs": 1735689600,
  "source": "keeperhub" | "foundry-loop"
}
```

**Do NOT include `currentTick`.** Adding it requires an extra RPC read after tx confirmation — added latency, added failure mode. Convex re-derives `currentTick` from chain via its existing `getWorldSnapshot` call. The webhook is a wake-up signal, not authoritative game state.

**Webhook auth:** shared secret in `Authorization: Bearer <WEBHOOK_SHARED_SECRET>` header. Both keepers include it; Convex rejects requests without it.

**Webhook on revert:** per v4.5 §2.4, KeeperHub may fire even on revert. This is fine — the indexer is idempotent.

---

## 6. World mini app integration — thin wrapper for Submission 1

Per addendum §5.1, before frontend M5 the team needs to confirm:
- Does S1 require MiniKit SDK? Which surface area (auth/payments/share)?
- Does S1 require World ID verification? Where in UX?
- UI/UX requirements (viewport, navigation, theming)?
- Distribution: World App directory or direct URL?
- Specific onchain interaction (e.g., World ID humanity for clan mint)?

**Wave 0 stance:** install MiniKit + idkit deps, mention them in README, no real integration code. PM resolves the questions above before Wave 4.

---

## 7. ABI stability — `IClanWorld.sol` is sacred

The seam interface is set in `packages/contracts/src/IClanWorld.sol`. Any change to the interface forces lockstep updates across:
- `RealChainClient` impl (and its tests)
- `elder` CLI command surface
- Convex indexer event handlers
- Frontend chain reads

**Therefore:** changes to `IClanWorld.sol` require an ADR amendment + full team sign-off + review of all 6 spec docs for ripple effects.

---

## 8. No real funds in agent wallets

Agent (Elder) wallets are **hot-keys** holding only testnet faucet funds. Two-wallet model for S2:
- **Treasury wallet** — high-value ops, offline-signed.
- **Agent wallets** — hot, capped per-tick budget.

This model also applies to anyone running the demo locally with their own keys.

---

## 9. Convex deployment per realm (one or two — both fine)

Per addendum §1.3, **one Convex deployment** reconfigured between submissions is the simplest; **two deployments toggled by env var** is also acceptable. The stack reads `CONVEX_URL` from env — swap the URL between S1 and S2 prep.

---

## 10. KeeperHub absent in Submission 1

Submission 1 ships with **only** the Foundry shell loop driving heartbeat. KeeperHub integration is added in Submission 2 alongside the Base Sepolia redeploy. The `IKeeper` interface accommodates both, so the orchestrator code path is identical — just a different concrete impl.
