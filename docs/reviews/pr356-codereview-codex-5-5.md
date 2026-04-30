Reading additional input from stdin...
OpenAI Codex v0.125.0 (research preview)
--------
workdir: /tmp/wt-superswarm-356
model: gpt-5.5
provider: openai
approval: never
sandbox: read-only
reasoning effort: high
reasoning summaries: none
session id: 019dde23-61ff-7482-93e9-ff9d1efc4e1f
--------
user
Read the prompt and content from stdin. Use parallel tool calls aggressively to verify file:line refs, audit fidelity, and Path A defensibility against the actual code at origin/dev-phase-5-economy. Output the full review to stdout in the requested markdown format.

<stdin>
You are a senior staff engineer doing the FINAL pre-merge review for a doc-only PR that establishes authoritative spec language for the ClanWorld hackathon.

PR: docs(spec): v4.6 Phase 5 economy alignment addendum (Path A)
Head SHA: 732120b
Branch: feat/issue-352-phase5b-alignment-addendum → dev-phase-5b-spec-alignment
Source audit: docs/reviews/pr193-spec-compliance-uat.md (PR #342, on branch docs/spec-audit-phase-5)

## Your task

This is DOC-ONLY (no code changes). Path A canonization — declares the as-built batched-action economy as canonical spec, defers v4-style continuous mechanics to milestone #25 post-hackathon.

Focus your review on:

1. **Audit fidelity** — does the doc accurately reflect the 14 substantial drifts from the PR #193 spec-compliance UAT report? Spot-check 5-7 drift items and verify the doc's canonical value matches the actual code at HEAD `9b67414f87ab6c83cf848fbe8a8bd7e3dcc03218` (origin/dev-phase-5-economy).

2. **File:line accuracy** — the doc cites file:line refs like `IClanWorld.sol:50, 54`, `ClanWorld.sol:493`. Verify these match the actual repo state at the cited commit. Use `git show origin/dev-phase-5-economy:packages/contracts/src/...` to check.

3. **Path A defensibility** — is the rationale for ratifying impl-as-canonical sound? Counter-arguments that the v4 spec should win? Phase 3-4 inheritance argument, batched-action lock-in argument, hackathon timeline argument — are they accurate?

4. **Cross-phase load-bearing language** — does any spec language in this addendum affect downstream phases?
   - P6 market: yield rates determine market price calibration. Does the addendum's per-batch yield language create downstream ambiguity?
   - P9 bandit: loot-value getter (`quoteLootValueRaw/Settled`) consumes Phase-5 vault state. Does the addendum keep the vault interface stable?
   - P10 winter: §9 declares wood burn / upkeep multiplier / wheat WinterLocked as DEFERRED. Is that consistent with PR #341 v4.6 bandit redesign which also deferred winter mechanics?

5. **Decision boxing** — the doc bakes 4 decisions (same-tick starvation, 10e18 wood cap, ×2 multiplicative wood crit, per-batch yields). Are these the right decisions? Counter-recommendations?

6. **Doc structural quality** — mirrors v4.6 bandit redesign template? All required sections (status/read-order/purpose/audience, why-this-doc, scope, lifecycle, yields, carry caps, starvation, deferred, authoritative-as-of)?

USE PARALLEL TOOL CALLS aggressively. You have full repo read access at the worktree. Read the audit doc + the doc under review + the actual contract source. Don't just skim the diff.

## Output format (write entire review to stdout)

# Phase Super-Swarm Review — PR #356 (head 732120b) — Phase 5B v4.6 economy alignment addendum

## SUMMARY
2-4 sentences: overall verdict (CLEAN | NEEDS_FIXES), top concerns, merge recommendation.

## HIGH severity findings
(spec inaccuracies, file:line refs that don't match HEAD, drift items mis-described, Path A rationale that fails on review.)

## MEDIUM severity findings
(structural quality issues, missing sections, ambiguous decision rationale.)

## LOW severity findings
(typos, minor wording, cross-link improvements, file as follow-up.)

## Cross-cutting observations
(themes across the doc — Path A coherence, downstream impact, alternative phrasings.)

If clean, say "CLEAN — no findings" under each section.

DOC + DIFF + AUDIT FOLLOW BELOW.
---

## DOC UNDER REVIEW (full content of docs/planning/clanworld_v4_6_phase5_economy_alignment.md):

# ClanWorld v4.6 Addendum — Phase 5 Economy Alignment (Path A: as-built canonization)

**Status:** Authoritative addendum, scoped to Phase 5 gathering / deposit / economy mechanics
**Read order:** This doc supersedes the gathering-yield and economy-rate language in `clanworld_v4_spec.md` §3.10, §4.3–4.13, `clanworld_v4_1_addendum.md` A5–A6, A10, and the economy-related constants in `clanworld_v4_2_state_schema_interface_spec.md` §5. When implementers or UAT runners find disagreement on yield rates, carry caps, or starvation semantics, this doc wins.
**Purpose:** Canonize the as-built Phase 5 batched-action economy as the authoritative Phase 5 ruleset for the hackathon submission, and explicitly enumerate the v4 mechanics that diverged as DEFERRED-TO-RESTORATION.
**Audience:** Reviewers, UAT runners against the contract on World Chain Sepolia / Base Sepolia, future restoration work.

---

## 0. Why this doc exists — Path A decision (Liam, 2026-04-30)

A spec-vs-impl audit by Claude Opus 4.7 (1M ctx) — the "PR #193 spec-compliance UAT" report at [`docs/reviews/pr193-spec-compliance-uat.md`](../reviews/pr193-spec-compliance-uat.md) — confirmed that the Phase 5 economy implementation diverges from the v4 spec on 14 substantial mechanics. The core structural divergence is **action lifecycle**: the v4 spec modeled gathering as a continuous tick-by-tick yield loop ("resolve tick-by-tick until stopped or blocked"); the implementation uses a **batched-action model** where each gather submission yields a single batch (4 ticks of work) and then terminates, requiring a new submission with cooldown.

Two interpretive paths were available:

- **Path A (chosen)** — declare the implementation canonical, write this addendum as the new authoritative ruleset, defer the v4-specific mechanics to a post-hackathon restoration milestone.
- **Path B (rejected for hackathon timeline)** — declare the v4 spec canonical, treat the implementation as drift, rewrite the gathering pipeline to continuous per-tick semantics.

Path A was selected because:
1. The batched-action model is deeply structural — the `getActionDuration / executesAtTick / settlesAtTick` mission shape was locked in Phases 3–4 (merged PRs #181/#183). Phase 5 inherits and extends it; reverting would invalidate downstream phases.
2. The hackathon timeline makes a gathering pipeline rewrite (Path B) untenable — multi-day lift for Phase 5.2–5.4, with regression risk across Phase 6–9.
3. The as-built code is internally consistent and well-tested for its own batched semantics. The multi-round super-swarm and per-issue PR pipeline already validated it.
4. Per-action yield magnitudes (4 ticks × yield_per_tick) are calibrated to the batched duty cycle, and can be rebalanced post-hackathon under restoration without touching architecture.

This doc canonizes the as-built mechanics. The 14 drift items are tracked as deferred-to-restoration on GH issue [#352](https://github.com/OmniPass-world/clan-world/issues/352) under the `spec-v4-restoration-post-hackathon` GH milestone (#25) for later evaluation.

---

## 1. Scope of this addendum

**In scope:** gathering mechanics (wood, iron, fish, wheat), deposit, carry caps, upkeep, starvation, wheat plot lifecycle, starting vault — as implemented in:

- `packages/contracts/src/ClanWorld.sol` — gather helpers, `_doDeposit`, `_applyUpkeep`, wheat plot regrow, starvation flag
- `packages/contracts/src/IClanWorld.sol` — economy constants, `Clan` struct vault fields, `WheatPlot` struct, carry fields
- `packages/contracts/test/Gathering.t.sol`, `ClanWorld.t.sol` — codified behavior

**Out of scope:** all non-economy mechanics. Bandit interactions with vault state (loot value getter — see `clanworld_v4_6_bandit_phase9_redesign.md`), winter mechanics (deferred — §9), market mechanics (Phase 6), deaths (Phase 10), gold/blueprint payouts. The rest of the v4 spec remains canonical unless overridden by a later addendum.

**Authoritative as of HEAD:** `9b67414f87ab6c83cf848fbe8a8bd7e3dcc03218` (origin/dev-phase-5-economy, the HEAD against which the spec-compliance UAT was run).

---

## 2. As-built batched-action lifecycle

### 2.1 Action model

The v4 spec (§3.10) described gathering as a **continuous** action: "resolve tick-by-tick until stopped or blocked." The implementation uses a **batched-action model**:

- Every gather action has `getActionDuration = 4` — the mission `settlesAtTick = actionStartTick + 4`.
- `_settleMissionForClansman` calls `_resolveAction` only when `tick >= settlesAtTick` — i.e., 4 ticks after the action starts.
- At resolution, the gather helper credits `YIELD_PER_TICK × 4` to the clansman's carry in one atomic call, then `_completeMission` terminates the mission.
- The worker transitions to WAITING. To gather again, the Elder must submit a new `ChopWood` (or equivalent) mission, subject to cooldown.

**There is no continuous per-tick yield loop.** One gather submission = one batch = one settlement.

### 2.2 Gather mission lifecycle (canonical)

```
Submit gather order
  → validation: worker reachable + carry not already full + target region correct
  → action stamp: actionStartTick = currentTick, settlesAtTick = currentTick + 4
  → cooldown stamp on submission (A5)
per tick: _settleMissionForClansman runs
  → if tick < settlesAtTick: noop (traveling or waiting for batch to complete)
  → if tick >= settlesAtTick: resolve batch
      → gather helper called once
      → yield = YIELD_PER_TICK × 4 (± crit/RNG modifier per §3)
      → yield clamped to remaining carry capacity
      → if carry already at cap: _completeMission immediately (no yield)
      → carry += yield; emit ResourcesGathered
      → _completeMission → worker WAITING
```

**After _completeMission:** worker is WAITING at gather region. Elder must travel home + deposit + submit new gather, or submit gather again from the same region (subject to cooldown).

### 2.3 Deposit lifecycle

Deposit is a **single-tick action** per spec §3.10 (unchanged by this addendum):

- `DEPOSIT_DURATION_TICKS = 1`
- Worker must be at own clan's `baseRegion`
- Atomically transfers all 4 carry resources to vault in one settlement
- Empty-carry deposit is a silent no-op (no event emitted)
- `ResourcesDeposited` event emitted on non-empty deposit with per-resource deltas + `atTick`

### 2.4 Cooldown semantics (A5 unchanged)

Per `clanworld_v4_1_addendum.md` A5 (unchanged): every successful mission submission starts cooldown (`cooldownEndsAtTs`). This applies to gather + deposit. A clansman whose cooldown is active cannot accept a new mission submission. This means the effective gather duty cycle is: **4 ticks ON + cooldown-period OFF per batch**.

---

## 3. Per-action yields — canonical as-built values

### 3.1 Wood (Forest)

| Property | As-built canonical | Source |
|---|---|---|
| Base yield per batch | `WOOD_YIELD_PER_TICK × 4 = 1e18 × 4 = 4e18` | `IClanWorld.sol:50, 54`; `ClanWorld.sol:493` |
| Crit chance | `WOOD_CRIT_BPS = 1000` (10%) | `IClanWorld.sol:55` |
| Crit effect | multiply yield × 2 → **8e18 on crit** | `ClanWorld.sol:495-497` |
| RNG domain key | `keccak256(abi.encode("wood_crit", tickSeed, clansmanId, missionNonce, tick))` | `ClanWorld.sol:494` |
| Region | `REGION_FOREST` | — |

**Ratified design decisions:**
- **Crit shape is ×2 multiplicative** (not +1e18 additive as in v4 §4.7). Rationale: the as-built multiplier is simpler, internally consistent, and already tested. Restoring additive crit is tracked as item #4 in §10.
- **Wood yield per tick is 1e18** (half of v4 spec's 2e18). Yield rate drift is a consequence of the batched model: 1e18/tick × 4-tick batch = 4e18 per submission. Restoration to 2e18/tick per spec is tracked as item #2 in §10.

### 3.2 Iron (Mountains)

| Property | As-built canonical | Source |
|---|---|---|
| Base yield per batch | `IRON_YIELD_PER_TICK × 4 = 1.25e17 × 4 = 5e17 = 0.5e18` | `IClanWorld.sol:57-58`; `ClanWorld.sol:524` |
| Gold bonus chance | `GOLD_FROM_IRON_BPS = 200` (2%) | `IClanWorld.sol:59` |
| Gold bonus amount | `GOLD_FROM_IRON_AMOUNT = 1e18` | `IClanWorld.sol:60` |
| Gold bonus roll cadence | **once per batch call** (not once per tick) | `ClanWorld.sol:539-548` |
| RNG domain key | `keccak256(abi.encode("iron_gold_bonus", ...))` | `ClanWorld.sol:543` |
| Region | `REGION_MOUNTAINS` | — |

**Ratified design decisions:**
- **Gold bonus rolls once per 4-tick batch** (not once per action tick). Sustained gold-bonus opportunity rate = 2% per batch vs spec's 2%/tick. Restoring per-tick roll cadence is tracked as item #6 in §10.
- **Iron per-tick rate is 0.125e18** (¼ of spec's 0.5e18/tick). Restoration tracked as item #5.

### 3.3 Fish — Docks (West/East Docks)

| Property | As-built canonical | Source |
|---|---|---|
| Hit chance | `FISH_DOCKS_BPS = 2500` (25%) | `IClanWorld.sol:65` |
| Yield on hit | `FISH_YIELD_PER_TICK × 4 = 25e16 × 4 = 1e18` | `IClanWorld.sol:63`; `ClanWorld.sol:563-578` |
| Yield on miss | 0 | — |
| Roll cadence | **once per batch call** | `ClanWorld.sol:563-578` |
| RNG domain key | `keccak256(abi.encode("fish_roll", ...))` | `ClanWorld.sol:564` |
| Regions | `REGION_WEST_DOCKS`, `REGION_EAST_DOCKS` | — |

**Sustained expected value per batch:** 25% × 1e18 = 0.25e18 fish per batch.

**Ratified design decision:** Roll cadence is once per batch (not once per action tick). Restoration tracked as item #7.

### 3.4 Fish — Deep Sea

| Property | As-built canonical | Source |
|---|---|---|
| Hit chance | `FISH_DEEP_BPS = 7500` (75%) | `IClanWorld.sol:66` |
| Yield on hit | `FISH_YIELD_PER_TICK × 4 = 25e16 × 4 = 1e18` | `IClanWorld.sol:63`; `ClanWorld.sol:594-609` |
| Yield on miss | 0 | — |
| Roll cadence | once per batch call | `ClanWorld.sol:594-609` |
| RNG domain key | `keccak256(abi.encode("fish_roll", ...))` | `ClanWorld.sol:595` |
| Region | `REGION_DEEP_SEA` | — |

**Sustained expected value per batch:** 75% × 1e18 = 0.75e18 fish per batch.

### 3.5 Wheat (West/East Farms)

| Property | As-built canonical | Source |
|---|---|---|
| Base yield per batch | `WHEAT_YIELD_PER_TICK × 4 = 5e18 × 4 = 20e18` | `IClanWorld.sol:62`; `ClanWorld.sol:646` |
| Regions | `REGION_WEST_FARMS` (plot 0), `REGION_EAST_FARMS` (plot 1) | `ClanWorld.sol:626-637` |
| Plot depletion | yield clamped to `plot.remainingWheat`; plot enters Regrowing when `remainingWheat == 0` | `ClanWorld.sol:648-659` |

**Ratified design decision:** Wheat per-tick rate is 5e18 (¼ of spec's 20e18/tick per continuous model). Restoration tracked as item #9.

---

## 4. Per-resource carry caps — canonical as-built values

These supersede the carry cap values in `clanworld_v4_spec.md` §4.3 and `clanworld_v4_2_state_schema_interface_spec.md` §5.

| Resource | Spec value (deprecated) | As-built canonical | Source |
|---|---|---|---|
| Wood | 15e18 | **10e18** (`WOOD_CAP = CLANSMAN_CARRY_CAP = 10e18`) | `IClanWorld.sol:43-44` |
| Iron | 5e18 | **5e18** | `IClanWorld.sol:45` ✅ unchanged |
| Wheat | 40e18 | **40e18** | `IClanWorld.sol:46` ✅ unchanged |
| Fish | 8e18 | **8e18** | `IClanWorld.sol:47` ✅ unchanged |

**Ratified design decision:** Wood carry cap is **10e18**, not 15e18. `WOOD_CAP` is aliased to the generic `WOOD_CAP = CLANSMAN_CARRY_CAP` constant (10e18). Restoring to spec's 15e18 is tracked as item #10 in §10.

**Carry enforcement mechanics (unchanged from spec):** each gather helper enforces the per-resource cap independently. Yield is clamped to `cap - currentCarry` if it would overflow. If carry is already at cap when resolution fires, the mission terminates immediately (no yield credited). This matches spec §4.8.

---

## 5. Upkeep and starvation semantics

### 5.1 Per-tick upkeep

Per living clansman per tick (unchanged from spec):

| Resource | Rate | Source |
|---|---|---|
| Wheat | `WHEAT_UPKEEP_PER_CLANSMAN = 1e18` | `IClanWorld.sol:69` |
| Fish | `FISH_UPKEEP_PER_CLANSMAN = 1e17` | `IClanWorld.sol:70` |

Upkeep applies only when `clan.livingClansmen > 0`. If the vault cannot fully satisfy the wheat or fish demand, the respective vault field is drained to 0 (not negative).

Execution order in `_settleClan` (per tick): `_applyUpkeep` → wheat-plot regrow → per-clansman mission settlement. Upkeep fires before any mission resolution in that tick, which means same-tick deposit cannot rescue that tick's upkeep (A6 compliant).

### 5.2 Starvation onset — same-tick ratification

**Ratified design decision:** starvation activates on the **same tick** as the upkeep failure (not the "next tick" specified in v4 §4.11).

v4 §4.11 states: "If the vault cannot satisfy both wheat and fish demands in full, **starvation status begins on the next tick**." The implementation sets `clan.starvationStartsAtTick = tick` (i.e., the current tick) inside `_applyUpkeep`, and derives `_isStarving = starvationStartsAtTick != 0 && starvationStartsAtTick <= currentTick`. This means `_isStarving == true` at the end of the tick the upkeep fails.

**Rationale for ratifying same-tick:** simpler state derivation; defenders contributing 0 takes effect immediately on the failure tick (cleaner UX for players — starvation is visible at the tick where it happens, not one tick later). Restoration to next-tick semantics is tracked as item #14 in §10.

### 5.3 Starvation effects (unchanged from spec, A10)

While `_isStarving == true`:

- All gather outputs are reduced by 50% (`yield = yield / 2` applied in wood/iron/fish-docks/fish-deep/wheat helpers before carry assignment)
- Defense contribution = 0 (starving clans are ineligible for `_resolveBanditAttack` defender path)
- No death from starvation outside winter (summer starvation = debuff only, matches A10)

Note: wheat plot depletion uses the post-halving yield value when calculating `plot.remainingWheat -= yield`, so the plot drains at the same rate as carry accumulation (no double-deduct bug).

### 5.4 Starvation recovery

Starvation clears in the same `_applyUpkeep` tick where the vault CAN satisfy both wheat + fish in full: `if (!starving && clan.starvationStartsAtTick != 0) clan.starvationStartsAtTick = 0`. Recovery is immediate (same tick as successful upkeep payment).

---

## 6. Wheat plot lifecycle

| State | Condition | Behavior |
|---|---|---|
| `Harvestable` | `remainingWheat > 0` | Clansman can harvest; yield clamped to min(20e18, remainingWheat) per batch |
| `Regrowing` | `remainingWheat == 0` | No harvest; regrow timer: `regrowUntilTick = tick + WHEAT_PLOT_REGROW_TICKS` |
| `WinterLocked` | Winter active (see §9) | **Not wired in impl** — enum value declared, behavior deferred |

**Regrow → Harvestable:** when `tick >= regrowUntilTick`, the per-tick `_settleClan` loop resets the plot: `state = Harvestable; remainingWheat = 100e18`.

**Starting state per `mintClan`:** both West and East Farms start `Harvestable` at 100e18.

`WHEAT_PLOT_REGROW_TICKS` is the canonical regrow duration. Both plots (`targetRegion == REGION_WEST_FARMS` → `plotIdx = 0`, `targetRegion == REGION_EAST_FARMS` → `plotIdx = 1`) follow identical mechanics.

---

## 7. Deposit mechanics (unchanged from spec)

| Property | Value | Source |
|---|---|---|
| Duration | `DEPOSIT_DURATION_TICKS = 1` (single-tick action) | `ClanWorld.sol:77, 1804-1806` |
| Location requirement | worker at own `clan.baseRegion` | `ClanWorld.sol:670-674, 1611-1614` |
| Transfer semantics | all 4 carry resources → vault atomically; carry fields zeroed | `ClanWorld.sol:682-695` |
| Empty-carry behavior | silent no-op, no event | `ClanWorld.sol:675-680` |
| Event | `ResourcesDeposited(clanId, woodDelta, ironDelta, wheatDelta, fishDelta, atTick)` | `IClanWorld.sol:541-549` |
| Error on wrong region | `ERR_NOT_AT_HOMEBASE` | `IClanWorld.sol:171` |

---

## 8. Starting vault and gold (§12.4, §12.5 — unchanged from spec)

| Field | Value | Source |
|---|---|---|
| `vaultWood` | 20e18 | `ClanWorld.sol:1037` |
| `vaultIron` | 0 | `ClanWorld.sol:1038` |
| `vaultWheat` | 20e18 | `ClanWorld.sol:1039` |
| `vaultFish` | 2e18 | `ClanWorld.sol:1040` |
| `goldBalance` | 3e18 | `ClanWorld.sol:1034` |

---

## 9. Winter mechanics — deferred (Phase 5.6 / Phase 7)

The following winter mechanics are declared in constants but **not wired in the implementation**. They are explicitly out of scope for Phase 5B and will be implemented under Phase 5.6 (starvation upkeep) and Phase 7 (winter season):

| Mechanic | v4 spec rule | Impl status | Constant declared |
|---|---|---|---|
| Winter wheat plot lockdown (§7.4) | plots enter `WinterLocked` at winter start; no harvest | NOT IMPLEMENTED — `_gatherWheat` does not check `winterActive`; `WinterLocked` enum value is dead | `WheatPlotState.WinterLocked` in `IClanWorld.sol:125` |
| Winter upkeep 2× (§7.3) | wheat + fish consumption doubles during winter | NOT IMPLEMENTED — `_applyUpkeep` uses flat rate regardless of `winterActive` | `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` in `IClanWorld.sol` (unused) |
| Winter wood burn (§7.3) | 1e18 wood per base per tick during winter | NOT IMPLEMENTED — `_applyUpkeep` does not touch `vaultWood`; no winter check | `WINTER_WOOD_BURN_PER_BASE = 1e18` in `IClanWorld.sol:71` (unused) |
| WinterLocked → Regrowing at winter end (v4_2 §7.4) | on winter end, locked plots → Regrowing | NOT IMPLEMENTED | — |

**Behavior during winter (as-built):** Gathering and deposit work exactly as described in §2–§7 above, regardless of whether winter is active. Upkeep rates are flat (non-doubled). Wood burn does not fire.

---

## 10. Deferred to v4-restoration milestone (`spec-v4-restoration-post-hackathon`)

The following 14 drift items are tracked for evaluation under the `spec-v4-restoration-post-hackathon` GH milestone (#25) and the umbrella tracking issue [#352](https://github.com/OmniPass-world/clan-world/issues/352). Restoration is conditional on post-hackathon evaluation.

| # | v4 spec mechanic | As-built behavior | Restoration cost (rough) |
|---|---|---|---|
| 1 | **Continuous tick-by-tick yield** (§3.10) — gather resolves once per tick, looping until stopped or blocked | Batched: 1 gather submission = 4-tick batch = 1 settlement; mission terminates after each batch | Large — requires reworking the mission lifecycle for gather actions; touches `getActionDuration`, `_resolveAction`, cooldown semantics for continuous actions |
| 2 | **Wood base yield 2e18/tick** (§4.7) — 2e18 per action tick (with continuous model) | 1e18/tick × 4 = 4e18/batch in batched model | Tiny constant change — but only meaningful after item #1 restores continuous model |
| 3 | **Wood crit chance 20%** (§4.7) | `WOOD_CRIT_BPS = 1000` (10%) | Tiny — 1 constant |
| 4 | **Wood crit shape additive +1e18** (§4.7) — crit ADDS +1e18 → total 3e18/tick | Crit DOUBLES yield → 8e18/batch | Small — modify crit branch in `_gatherWood` |
| 5 | **Iron base yield 0.5e18/tick** (§4.7) | 0.125e18/tick × 4 = 0.5e18/batch | Tiny constant — but meaningful only after #1 |
| 6 | **Iron gold bonus per-tick roll** (§4.7) — roll at every action tick | Rolls once per 4-tick batch call | Small — loop the roll or roll once per tick in continuous model |
| 7 | **Fish docks 25%/tick × 1e18** (§4.7) | 25% per batch call × 1e18 | Tiny constant — meaningful after #1 |
| 8 | **Fish deep sea 75%/tick × 1e18** (§4.7) | 75% per batch call × 1e18 | Tiny constant — meaningful after #1 |
| 9 | **Wheat harvest rate 20e18/tick** (§4.9) | 5e18/tick × 4 = 20e18/batch | Tiny constant — meaningful after #1 |
| 10 | **Wood carry cap 15e18** (§4.3) | `WOOD_CAP = CLANSMAN_CARRY_CAP = 10e18` | Tiny — 1 constant in `IClanWorld.sol:43-44` (alias decoupling required) |
| 11 | **Winter wheat plot lockdown** (§7.4) — plots enter `WinterLocked` at winter start; no harvest | `WinterLocked` enum state declared, not wired | Small–Medium — wire winter-start heartbeat to set plot state; add check in `_gatherWheat`; wire winter-end → Regrowing |
| 12 | **Winter upkeep 2× multiplier** (§7.3) — wheat + fish consumption doubles in winter | Flat rate; `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` declared, unused | Small — multiply upkeep by `WINTER_UPKEEP_MULTIPLIER_BPS` when `winterActive` in `_applyUpkeep` |
| 13 | **Winter wood burn 1e18/base/tick** (§7.3) | Not implemented; `WINTER_WOOD_BURN_PER_BASE = 1e18` declared, unused | Small — add wood burn branch in `_applyUpkeep` when `winterActive` |
| 14 | **Starvation onset next-tick** (§4.11) — starvation begins on the tick after upkeep failure | Starvation activates same tick as failure (`starvationStartsAtTick = tick`) | Small — change to `starvationStartsAtTick = tick + 1`; audit consumers for off-by-one |

Items 11–13 partially overlap with Phase 5.6 (starvation upkeep) and Phase 7 (winter season) scope. Those phases will address them regardless.

---

## 11. Constants — as-built canonical values

These supersede the economy-related constants in `clanworld_v4_2_state_schema_interface_spec.md` §5 for the listed entries.

| Constant | Spec value (deprecated) | As-built canonical | Source |
|---|---|---|---|
| `WOOD_YIELD_PER_TICK` | 2e18 (implied by continuous) | **1e18** | `IClanWorld.sol:50` |
| `WOOD_CRIT_BONUS` | +1e18 additive | **×2 multiplicative (no separate constant)** | `ClanWorld.sol:495-497` |
| `WOOD_CRIT_BPS` | 2000 (20%) | **1000 (10%)** | `IClanWorld.sol:55` |
| `WOOD_CAP` | 15e18 | **10e18 (= `CLANSMAN_CARRY_CAP`)** | `IClanWorld.sol:43-44` |
| `IRON_YIELD_PER_TICK` | 5e17 (implied by continuous) | **1.25e17** | `IClanWorld.sol:57` |
| `GOLD_FROM_IRON_BPS` | 200 (2%) | **200 (2%)** ✅ unchanged | `IClanWorld.sol:59` |
| `GOLD_FROM_IRON_AMOUNT` | 1e18 | **1e18** ✅ unchanged | `IClanWorld.sol:60` |
| `FISH_DOCKS_BPS` | 2500 (25%) | **2500 (25%)** ✅ unchanged | `IClanWorld.sol:65` |
| `FISH_DEEP_BPS` | 7500 (75%) | **7500 (75%)** ✅ unchanged | `IClanWorld.sol:66` |
| `FISH_YIELD_PER_TICK` | 1e18 (implied by continuous) | **25e16 (= 2.5e17)** | `IClanWorld.sol:63` |
| `WHEAT_YIELD_PER_TICK` | 20e18 (implied by continuous) | **5e18** | `IClanWorld.sol:62` |
| `WHEAT_CAP` | 40e18 | **40e18** ✅ unchanged | `IClanWorld.sol:46` |
| `IRON_CAP` | 5e18 | **5e18** ✅ unchanged | `IClanWorld.sol:45` |
| `FISH_CAP` | 8e18 | **8e18** ✅ unchanged | `IClanWorld.sol:47` |
| `WHEAT_UPKEEP_PER_CLANSMAN` | 1e18 | **1e18** ✅ unchanged | `IClanWorld.sol:69` |
| `FISH_UPKEEP_PER_CLANSMAN` | 1e17 | **1e17** ✅ unchanged | `IClanWorld.sol:70` |
| `WINTER_UPKEEP_MULTIPLIER_BPS` | 20000 (2×) | **20000 (declared, unused — see §9)** | `IClanWorld.sol` |
| `WINTER_WOOD_BURN_PER_BASE` | 1e18 | **1e18 (declared, unused — see §9)** | `IClanWorld.sol:71` |

---

## 12. UAT runners — what to expect

When running interactive UAT against this contract, **expect the as-built mechanics (this addendum), not v4 §3.10 / §4.3–4.13**. Specifically:

- ✅ Each gather order yields one batch (4 ticks of work) and terminates. Worker enters WAITING. To gather more, submit a new order after cooldown.
- ✅ Wood: 4e18 per batch base, 8e18 on crit (10% chance) — NOT 2e18/tick continuous
- ✅ Iron: 0.5e18 per batch, 2% chance of +1e18 gold bonus per batch — NOT 0.5e18/tick continuous
- ✅ Fish docks: 25% × 1e18 per batch — NOT 25% × 1e18/tick
- ✅ Fish deep sea: 75% × 1e18 per batch — NOT 75% × 1e18/tick
- ✅ Wheat: 20e18 per batch — NOT 20e18/tick continuous
- ✅ Wood carry cap is 10e18 (NOT 15e18)
- ✅ Starvation activates on the SAME TICK as upkeep failure (NOT next tick)
- ✅ Wheat plots remain harvestable during winter (WinterLocked NOT wired)
- ✅ Winter upkeep doubling NOT active; flat upkeep rates apply year-round
- ✅ Winter wood burn NOT active

If a UAT scenario expects v4-spec continuous yields, per-tick rates, or winter lockdown behavior, it will fail against this contract. Use this addendum as the oracle.

---

## 13. References

- **Spec-compliance UAT report:** [`docs/reviews/pr193-spec-compliance-uat.md`](../reviews/pr193-spec-compliance-uat.md) — full mechanic-by-mechanic table, test-coverage gap analysis, UAT scenario predictions
- **Path A precedent (bandit mechanics):** [`docs/planning/clanworld_v4_6_bandit_phase9_redesign.md`](./clanworld_v4_6_bandit_phase9_redesign.md)
- **Source v4 docs being superseded for economy mechanics:**
  - `clanworld_v4_spec.md` §3.10, §4.3–4.13, §7.3–7.5, §12.4–12.5
  - `clanworld_v4_1_addendum.md` A5, A6, A10
  - `clanworld_v4_2_state_schema_interface_spec.md` §5 (economy constants listed in §11 above)
  - `clanworld_v4_3_schema_patch.md` E (RNG domain keys — fully matched, unchanged), L (starvationStartsAtTick — matched)
- **Implementation HEAD canonized by this addendum:** `9b67414f87ab6c83cf848fbe8a8bd7e3dcc03218`
- **Restoration tracking:** GH milestone `spec-v4-restoration-post-hackathon` (#25) and tracking issue [#352](https://github.com/OmniPass-world/clan-world/issues/352)

## AUDIT SOURCE (docs/reviews/pr193-spec-compliance-uat.md from docs/spec-audit-phase-5 branch):

# PR #193 Spec-Compliance UAT — `dev-phase-5-economy`

**Reviewer:** Claude Opus 4.7 (1M ctx) — static spec-compliance pass
**HEAD:** `9b67414f87ab6c83cf848fbe8a8bd7e3dcc03218` (origin/dev-phase-5-economy)
**Date:** 2026-04-30
**Method:** read spec docs → walk impl → no test execution
**Template:** mirrors `docs/reviews/pr194-spec-compliance-uat.md` (Phase 9 audit)

> Scope: does the gathering / deposit / economy implementation in `packages/contracts/src/ClanWorld.sol` (HEAD = phase 5.1 + phase 5.5 sub-issues only) match the documented v4 spec ruleset? PR #193 is OPEN against `dev-merge` and bundles only Phase 5.1 (wood gathering) and Phase 5.5 (deposit). Phase 5.2 (iron), 5.3 (fishing), 5.4 (wheat plot lifecycle), and 5.6 (starvation upkeep) are listed as PENDING in the PR body — but the impl already wires up iron/fish/wheat/upkeep code paths because Phase 4 + Phase 5.1 needed the action-resolution skeleton. We audit what is on the branch HEAD, not the sub-issue split, because that is the actual `dev-merge` payload.

---

## 1. Spec sources read

| Doc | Phase-5-relevant sections |
|---|---|
| `docs/planning/clanworld_v4_spec.md` | §3 (mission model, action categories, per-tick local settlement order); §3.7–3.8 (terminal states, deposit-with-empty-cargo); §4.2–4.13 (resources, carry caps, vault model, deposit rule, gathering yields, gather overflow, wheat plots, consumption, starvation trigger, starvation effects, lazy starvation tracking); §6.9 (loot-value formula — same getter Phase 5 must serve to bandits); §7.3–7.5 (winter upkeep doubling, winter wood burn, winter wheat lockdown); §12.4–12.5 (starting vault + gold) |
| `docs/planning/clanworld_v4_1_addendum.md` | A5 (cooldown on every accepted submission, including gather+deposit); A6 (winter just-in-time logistics — vault upkeep applies BEFORE deposit in same tick); A10 (summer starvation effects: 50% gather + 0 defense, no death); A11 (clansman-granular drop split — touches gathering only insofar as defenders gain loot, not Phase-5-direct) |
| `docs/planning/clanworld_v4_2_state_schema_interface_spec.md` | §5 constants (`WOOD_CAP/IRON_CAP/WHEAT_CAP/FISH_CAP`, `WOOD_BASE_YIELD=2e18`, `WOOD_CRIT_BONUS=1e18`, `WOOD_CRIT_BPS=2000`, `IRON_BASE_YIELD=5e17`, `GOLD_FROM_IRON_BPS=200`, `FISH_DOCKS_BPS=2500`, `FISH_DEEP_BPS=7500`, `WHEAT_UPKEEP_PER_CLANSMAN=1e18`, `FISH_UPKEEP_PER_CLANSMAN=1e17`, `WINTER_WOOD_BURN_PER_BASE=1e18`); §7.3 Clan struct (vault fields, `starvationStartsAtTick`, `starvingCached`); §7.4 WheatPlot; §7.5 Clansman carry fields; §8.1–8.2 mission shape + DefendBase persistence (touches only deposit/gather lifecycle indirectly); §9.1–9.2 raw + derived getters (notably `quoteLootValueRaw/Settled` consume Phase 5 vault state) |
| `docs/planning/clanworld_v4_3_schema_patch.md` | E (domain-separated RNG keys: `wood_crit`, `iron_gold_bonus`, `fish_roll`); H (loot value getter split: raw vs settled); K (`ERR_NOT_ENOUGH_GOLD`, `ERR_CARRY_FULL`); L (starvation cache cleanup: prefer `starvationStartsAtTick` over `starvingCached`) |

**Authoritative ruleset:** v4 spec + v4_1 addendum (controls on conflict) + v4_2 schema + v4_3 patches. The v4_5 alignment addendum is silent on Phase-5 economy mechanics (it covers tick cadence, heartbeat caller, indexer, submission lifecycle).

Key spec assertions extracted (one-line each):
- **§3.10** gathering actions are **continuous**: "resolve tick-by-tick until stopped or blocked"
- **§3.10** deposit is a **single-tick action**: "begin once the clansman has arrived, occupy one full action tick, resolve at the closing heartbeat"
- **§3.14** per-tick local settlement order: upkeep → starvation flag → travel → continuous action → single-tick action effects → terminal checks
- **§4.3** per-clansman carry caps: wood 15e18, iron 5e18, wheat 40e18, fish 8e18
- **§4.5** vault is the only resource pool that counts for upkeep / construction / bandit targeting
- **§4.6** deposit requires worker at own homebase + `deposit_resources` action
- **§4.7 Wood (Forest):** base 2e18 per action tick, 20% crit, +1e18 crit bonus → 2e18 OR 3e18 per tick
- **§4.7 Iron (Mountains):** base 0.5e18 per action tick, 2% chance of +1e18 gold bonus
- **§4.7 Fish docks (W/E):** 25% chance of 1e18 fish per action tick
- **§4.7 Fish deep sea:** 75% chance of 1e18 fish per action tick
- **§4.8** clamp yield to remaining carry capacity; on full → mission terminates + WAITING at end of tick
- **§4.9** wheat plot starts at 100e18, harvest rate 20e18 per action tick, regrow 4 ticks
- **§4.10** consumption per tick: 1e18 wheat + 0.1e18 fish per living clansman
- **§4.11** if vault cannot satisfy → starvation begins **next tick**
- **§4.12** while starving: gather output ÷2, defense → 0; outside winter no death
- **§4.14** bandit-drop loot above carry cap is burned (Phase 9 surface; no Phase 5 conflict)
- **§7.3** winter doubles wheat + fish consumption AND adds 1e18 wood-burn per base per tick
- **§7.4** during winter: wheat plots locked, no harvest
- **A6** winter upkeep applies BEFORE same-tick deposit lands → carry doesn't save you that tick
- **A10** summer starvation = 50% gather + 0 defense, no death
- **§12.4** starting vault: 20e18 wood, 20e18 wheat, 2e18 fish, 0e18 iron
- **§12.5** starting gold: 3e18 (per impl line 1034 comment "v4 spec §12.5"; spec text accessible)

---

## 2. Mechanic-by-mechanic verification

| Mechanic | Spec says | Code does | File:line | Verdict |
|---|---|---|---|---|
| **Continuous-action tick semantics (§3.10)** | gather actions yield once per tick, continuously, until stopped | gather actions have `getActionDuration = 4`; `_settleMissionForClansman` only calls `_resolveAction` when `tick >= settlesAtTick` (i.e. after 4 ticks elapse from `actionStartTick`); on each resolution the gather helpers credit `YIELD_PER_TICK * duration = 4 * YIELD_PER_TICK` to carry, then `_completeMission` (not continuous) | `ClanWorld.sol:341-344, 1796-1801, 478-665` | ❌ DRIFT — fundamentally not continuous. One gather order = one settlement = one batched yield, then mission ends + worker returns to WAITING. To gather more the Elder must submit a new mission (which incurs cooldown per A5). |
| **Per-clansman wood cap (§4.3, v4_2 §5)** | 15e18 | `WOOD_CAP = CLANSMAN_CARRY_CAP = 10e18` | `IClanWorld.sol:43-44` | ❌ DRIFT — 33% lower than spec |
| **Per-clansman iron cap (§4.3)** | 5e18 | `IRON_CAP = 5e18` | `IClanWorld.sol:45` | ✅ MATCHES |
| **Per-clansman wheat cap (§4.3)** | 40e18 | `WHEAT_CAP = 40e18` | `IClanWorld.sol:46` | ✅ MATCHES |
| **Per-clansman fish cap (§4.3)** | 8e18 | `FISH_CAP = 8e18` | `IClanWorld.sol:47` | ✅ MATCHES |
| **Per-resource carry cap enforcement (§4.8)** | each resource has independent cap; clamp to remaining | wood gather only enforces `CLANSMAN_CARRY_CAP` against `cs.carryWood` (no cross-resource accounting). Iron / wheat / fish gather check the per-resource cap. Code comment in `IClanWorld.sol:43`: "only enforced for wood gather" | `IClanWorld.sol:43`, `ClanWorld.sol:487, 519, 559, 590, 621` | ⚠️ DRIFT — comment is misleading (other resources DO check per-resource caps); but `WOOD_CAP` aliasing to a generic `CLANSMAN_CARRY_CAP` (10e18) and applying only to wood is structurally fragile if Phase 5.x adds aggregate-carry rules later |
| **Wood base yield (§4.7)** | 2e18 wood per action tick | `WOOD_YIELD_PER_TICK = 1e18`; per-call yield = `1e18 × 4 = 4e18` (because action duration = 4 ticks). **Net per-tick rate = 1e18, half of spec's 2e18.** | `IClanWorld.sol:50, 54`, `ClanWorld.sol:493` | ❌ DRIFT — sustained per-tick wood rate is half of spec |
| **Wood crit chance (§4.7)** | 20% | `WOOD_CRIT_BPS = 1000` (= 10%) | `IClanWorld.sol:55` | ❌ DRIFT — half of spec |
| **Wood crit shape (§4.7)** | crit ADDS `+1e18` (additive) → total 3e18 (or 2e18 base) | impl multiplies yield `*= 2` → on crit = `8e18` per call (not `2e18 + 1e18 = 3e18` per tick equivalent) | `ClanWorld.sol:495-497` | ❌ DRIFT — wrong math shape AND wrong magnitude (impl crit DOUBLES, spec crit adds 50% of base on top) |
| **Iron base yield (§4.7)** | 0.5e18 per action tick | `IRON_YIELD_PER_TICK = 1.25e17`; per-call yield = `1.25e17 × 4 = 5e17 = 0.5e18`. **Net per-tick rate = 0.125e18, ¼ of spec's 0.5e18.** | `IClanWorld.sol:57-58`, `ClanWorld.sol:524` | ❌ DRIFT — sustained per-tick iron rate is ¼ of spec |
| **Iron gold bonus chance (§4.7)** | 2% | `GOLD_FROM_IRON_BPS = 200` | `IClanWorld.sol:59` | ✅ MATCHES |
| **Iron gold bonus amount (§4.7)** | 1e18 gold | `GOLD_FROM_IRON_AMOUNT = 1e18` | `IClanWorld.sol:60` | ✅ MATCHES |
| **Iron gold bonus rolled per call vs per tick** | spec implies per action tick (continuous) | impl rolls once per call (i.e. once per 4 ticks) | `ClanWorld.sol:539-548` | ❌ DRIFT — bonus opportunity rate is ¼ of spec (combined with the per-tick rate drift = ¼ overall iron-gold yield) |
| **Fish docks rate (§4.7)** | 25% chance of 1e18 fish per action tick | `FISH_DOCKS_BPS = 2500`; on success yield = `25e16 × 4 = 1e18` per call. Roll happens once per call. **Sustained rate = 25% × 1e18 / 4 ticks = 0.0625e18 per tick, ¼ of spec's 0.25e18 per tick.** | `IClanWorld.sol:65, 63`, `ClanWorld.sol:563-578` | ❌ DRIFT — sustained fish-docks rate is ¼ of spec |
| **Fish deep sea rate (§4.7)** | 75% chance of 1e18 fish per action tick | `FISH_DEEP_BPS = 7500`; same shape. **Sustained = 0.1875e18 per tick, ¼ of spec's 0.75e18 per tick.** | `IClanWorld.sol:66, 63`, `ClanWorld.sol:594-609` | ❌ DRIFT — sustained fish-deep rate is ¼ of spec |
| **Wheat harvest rate (§4.9)** | 20e18 per action tick | `WHEAT_YIELD_PER_TICK = 5e18`; per-call yield = `5e18 × 4 = 20e18`. **Sustained per-tick = 5e18, ¼ of spec's 20e18.** | `IClanWorld.sol:62`, `ClanWorld.sol:646` | ❌ DRIFT — sustained wheat rate is ¼ of spec |
| **Domain-separated RNG keys (v4.3 E)** | use `wood_crit`, `iron_gold_bonus`, `fish_roll` keys | exact strings used: `keccak256(abi.encode("wood_crit", tickSeed, clansmanId, missionNonce, tick))`, `"iron_gold_bonus"`, `"fish_roll"` | `ClanWorld.sol:494, 543, 564, 595` | ✅ MATCHES |
| **Gather clamp on carry overflow (§4.8)** | yield clamped to remaining capacity; full → mission terminates + WAITING at end of same tick | `if (yield > remaining) yield = remaining`; `if (cs.carryX >= CAP) _completeMission`. Mission terminates + worker WAITING at end of tick. | `ClanWorld.sol:500-507, 526-536, 571-578, 602-609, 648-664` | ✅ MATCHES |
| **Gather pre-check on carry already full** | not explicit; implied by "mission terminates naturally" | wood/fish/wheat/iron each guard with `if (carry >= cap) _completeMission; return;` BEFORE rolling/crediting | `ClanWorld.sol:487-490, 519-523, 559-563, 590-594, 621-625` | ✅ MATCHES (defensive, spec-compatible) |
| **Wheat plot region check** | wheat plot 0 = West Farms, 1 = East Farms | `_gatherWheat` reads `m.targetRegion`, maps `REGION_WEST_FARMS → plotIdx 0`, `REGION_EAST_FARMS → plotIdx 1`, completes mission on any other region | `ClanWorld.sol:626-637` | ✅ MATCHES |
| **Wheat plot regrow trigger (§4.9)** | when `remainingWheat == 0`, plot enters Regrowing state; regrow duration 4 ticks | `if (plot.remainingWheat == 0) plot.state = Regrowing; plot.regrowUntilTick = tick + WHEAT_PLOT_REGROW_TICKS;` | `ClanWorld.sol:656-659` | ✅ MATCHES |
| **Wheat plot regrow completion (§4.9)** | on regrow complete → reset to 100e18 + Harvestable | `_settleClan` per-tick: `if (Regrowing && tick >= regrowUntilTick) state = Harvestable; remainingWheat = 100e18;` | `ClanWorld.sol:376-383` | ✅ MATCHES |
| **Wheat plot starting state** | start harvestable with 100e18 | `mintClan` sets both plots `state: Harvestable, remainingWheat: 100e18` | `ClanWorld.sol:1043-1054` | ✅ MATCHES |
| **Winter wheat plot lockdown (§7.4)** | "during winter: wheat plots are unavailable; harvesting wheat is not allowed" | NOT IMPLEMENTED. `_gatherWheat` does not check `_world.winterActive`. `_settleClan` per-tick wheat-plot regrow loop has no `WinterLocked` transition. | `ClanWorld.sol:376-383, 612-665` | ❌ MISSING — wheat plots remain harvestable during winter |
| **WheatPlotState enum has WinterLocked** | yes (v4_2 §7.4) | enum has 3 states: `Harvestable, Regrowing, WinterLocked` | `IClanWorld.sol:123-127` | ⚠️ PARTIAL — schema present, behavior absent (dead enum value) |
| **Per-clansman vault upkeep order (§3.14)** | order: 1. upkeep, 2. starvation flag, 3. travel, 4. continuous, 5. single-tick effects, 6. terminal | `_settleClan` does: 1. `_applyUpkeep(tick)` → 2. wheat-plot regrow → 3-6. for each clansman `_settleMissionForClansman` (which combines travel + ACTING + resolve in one inline loop). Starvation flag is set inside `_applyUpkeep`. **Same order as spec for upkeep + starvation, but plot regrow happens BEFORE traveling/acting.** | `ClanWorld.sol:371-389, 397-425` | ⚠️ DRIFT — plot regrow inserted between upkeep and travel; not strictly spec-mandated, but plot state could change mid-tick relative to clansman action. Functionally OK because actions resolve on `tick >= settlesAtTick` boundary, not mid-tick. |
| **Wheat upkeep amount (§4.10)** | 1e18 per living clansman per tick | `WHEAT_UPKEEP_PER_CLANSMAN = 1e18` | `IClanWorld.sol:69` | ✅ MATCHES |
| **Fish upkeep amount (§4.10)** | 0.1e18 per living clansman per tick | `FISH_UPKEEP_PER_CLANSMAN = 1e17` | `IClanWorld.sol:70` | ✅ MATCHES |
| **Upkeep applies only when livingClansmen > 0 (§4.10)** | "These costs apply only if the clan has living clansmen" | `if (clan.livingClansmen == 0) return;` early return in `_applyUpkeep` | `ClanWorld.sol:398` | ✅ MATCHES |
| **Insufficient food → vault drained to 0 (§4.11 implication)** | spec doesn't dictate but reasonable | `if (hadEnoughWheat) clan.vaultWheat -= wheatNeeded; else clan.vaultWheat = 0;` (same for fish) | `ClanWorld.sol:406-415` | ✅ MATCHES (defensible) |
| **Starvation flag set on next tick (§4.11)** | "starvation status begins on the **next tick**" | `if (starving) clan.starvationStartsAtTick = tick;` (i.e. on the SAME tick as the failure, not next tick); reading code uses `_isStarving = starvationStartsAtTick != 0 && starvationStartsAtTick <= currentTick` so a clan starving as of `tick T` reports `_isStarving == true` IMMEDIATELY at tick T | `ClanWorld.sol:418-419, 428-430` | ❌ DRIFT — starvation activates same tick as failure, not next tick. Spec §4.11 is explicit: "starvation status begins on the **next tick**." |
| **Starving gather reduction 50% (§4.12, A10)** | "all gathering outputs are reduced by 50%" | `if (starving) yield = yield / 2;` in wood/iron/fish-docks/fish-deep/wheat | `ClanWorld.sol:499, 525, 570, 601, 647` | ✅ MATCHES |
| **Starvation recovery (§4.12)** | "Starvation remains active until a later clan settlement determines that required food supply is again sustainable" | `if (!starving && clan.starvationStartsAtTick != 0) clan.starvationStartsAtTick = 0;` (clears flag once vault can pay both wheat+fish in same tick) | `ClanWorld.sol:421-424` | ✅ MATCHES |
| **No summer starvation death (§4.12, A10)** | death only via winter cold-damage path | `_applyUpkeep` does not kill clansmen; upkeep failure only flips starvation flag | `ClanWorld.sol:397-425` | ✅ MATCHES |
| **`starvingCached` removal (v4.3 L)** | "remove `starvingCached` in favor of deriving starvation from canonical state" | `Clan` struct does NOT have `starvingCached` field (only `starvationStartsAtTick`). v4.3 §L compliance achieved. | `IClanWorld.sol:234-258` | ✅ MATCHES (schema fix already adopted) |
| **Winter wheat consumption multiplier (§7.3)** | 2× during winter | NOT IMPLEMENTED. `_applyUpkeep` uses flat `WHEAT_UPKEEP_PER_CLANSMAN` regardless of `_world.winterActive` | `ClanWorld.sol:400-401` | ❌ MISSING — Phase 5.6 surface but constant `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` exists unused |
| **Winter fish consumption multiplier (§7.3)** | 2× during winter | NOT IMPLEMENTED — same as wheat | `ClanWorld.sol:400-401` | ❌ MISSING |
| **Winter wood burn (§7.3)** | 1e18 wood per base per tick during winter | NOT IMPLEMENTED. `_applyUpkeep` does not touch `vaultWood` and does not check `winterActive`. Constant `WINTER_WOOD_BURN_PER_BASE = 1e18` declared but unused. | `IClanWorld.sol:71`, `ClanWorld.sol:397-425` | ❌ MISSING — dead constant |
| **Winter wheat plot lockdown (§7.4)** | plots become unavailable during winter | NOT IMPLEMENTED (already flagged above) | (no code) | ❌ MISSING |
| **Winter cold damage / wall collapse (§7.5, alluded by v4_1 A10)** | not Phase-5 directly but coupled | NOT IMPLEMENTED — `Clan.coldDamage` field is reset to 0 but never incremented anywhere in this branch | `ClanWorld.sol:1033`, `IClanWorld.sol:249` | ❌ MISSING (Phase-5.6 / Phase-7-winter scope; flagged for context) |
| **Wheat-plot WinterLocked transition at winter start (v4_2 §7.4)** | "at winter start: plots enter `WinterLocked`" | NOT IMPLEMENTED — heartbeat does not set plot state to `WinterLocked`; the enum value is dead. | `ClanWorld.sol:376-383, 1043-1054` | ❌ MISSING |
| **Wheat-plot WinterLocked → Regrowing at winter end (v4_2 §7.4)** | "at winter end: `WinterLocked → Regrowing`" | NOT IMPLEMENTED | (no code) | ❌ MISSING |
| **Just-in-time logistics (A6 — winter case)** | "carried resources do not save a base from upkeep until they are actually deposited" | settlement order is 1. upkeep, 2. plot regrow, 3-6. clansmen. Deposit resolves in step 3-6 (well after upkeep), so a same-tick deposit doesn't rescue upkeep — matches A6 even though winter wood burn isn't applied yet. | `ClanWorld.sol:371-389` | ✅ MATCHES (architecturally; void of winter wood burn impl) |
| **Deposit requires homebase (§4.6)** | worker must be at own homebase | `_validateAction` for `DepositResources`: `if (gotoRegion != clan.baseRegion) return ERR_NOT_AT_HOMEBASE`; `_doDeposit` runtime guard: `if (cs.currentRegion != clan.baseRegion) _completeMission; return;` | `ClanWorld.sol:1611-1614, 670-674` | ✅ MATCHES |
| **Deposit moves all carried resources (§4.6 implied)** | all carried → all to vault | `clan.vaultWood += cs.carryWood; ... cs.carryWood = 0; ...` for all 4 resources atomically | `ClanWorld.sol:682-695` | ✅ MATCHES |
| **Deposit empty cargo (§3.7)** | "arrives to deposit with empty cargo" → enters WAITING (silently OK) | `if (!hasAnything) _completeMission; return;` (silent no-op, no event) | `ClanWorld.sol:675-680` | ✅ MATCHES |
| **Deposit duration is single-tick action (§3.10)** | "single-tick actions occupy one full action tick" | `DEPOSIT_DURATION_TICKS = 1` | `ClanWorld.sol:77, 1804-1806` | ✅ MATCHES |
| **`ResourcesDeposited` event** | required for indexer; spec implicit | emitted on non-empty deposit with 4 deltas + tick (uint64 atTick after R1 fix) | `ClanWorld.sol:697`, `IClanWorld.sol:541-549` | ✅ MATCHES |
| **`ResourcesGathered` event** | required for indexer; spec implicit | emitted from each gather helper | `ClanWorld.sol:503, 532, 574, 605, 654`, `IClanWorld.sol:530-540` | ✅ MATCHES |
| **Cooldown applies on every accepted submission (A5)** | "Every successful mission submission starts cooldown" | gather mission completion sets `cs.cooldownEndsAtTs` (verified by `test_chopWoodAppliesCooldownPostSettle`); submission path also stamps cooldown | `Gathering.t.sol:124-133` (test); submission path elsewhere | ✅ MATCHES |
| **Loot value getter raw (v4.3 H)** | reads committed vault only | `quoteLootValueRaw` (impl elsewhere — Phase-9 already verified ✅ in pr194 audit) | (out of Phase-5 diff) | ✅ MATCHES (cross-phase consumer) |
| **Loot value getter settled (v4.3 H)** | settles to current tick | `quoteLootValueSettled` (impl elsewhere) | (out of Phase-5 diff) | ✅ MATCHES |
| **Starting vault (§12.4)** | 20e18 wood, 0 iron, 20e18 wheat, 2e18 fish | `mintClan`: `vaultWood = 20e18; vaultIron = 0; vaultWheat = 20e18; vaultFish = 2e18` | `ClanWorld.sol:1037-1040` | ✅ MATCHES |
| **Starting gold (§12.5)** | 3e18 gold | `clan.goldBalance = 3e18` | `ClanWorld.sol:1034` | ✅ MATCHES |
| **`ERR_CARRY_FULL` constant (v4.3 K)** | added to status codes | declared in `StatusCode` enum | `IClanWorld.sol:187` | ✅ MATCHES (declared; usage in market path, not Phase-5 critical) |
| **`ERR_NOT_ENOUGH_GOLD` constant (v4.3 K)** | added | declared | `IClanWorld.sol:186` | ✅ MATCHES |
| **`ERR_NOT_AT_HOMEBASE` for deposit** | spec-implied + gemini-CA r1 finding required | added in R1 fix; deposit returns this code on wrong region | `IClanWorld.sol:171`, `ClanWorld.sol:1613` | ✅ MATCHES |

---

### Summary of mechanic verification

| Verdict | Count |
|---|---|
| ✅ MATCHES | 28 |
| ⚠️ DRIFT (close-but-different) | 3 |
| ❌ DRIFT/MISSING (significant) | 14 |

**The implementation has correctly wired the deposit pipeline, the gather → carry → vault flow, the wheat-plot regrow cycle, the starvation accounting skeleton, and all RNG domain keys. The drift cluster is concentrated in two places: (1) yield rates per-tick are 1/2 to 1/4 of spec because gather actions are batched-not-continuous, with each batch paying spec's per-tick value × 4-tick action duration as a one-shot, then ending the mission; (2) every winter mechanic (wood burn, upkeep doubling, plot lockdown, cold damage) is unwired — Phase 5.6 starvation upkeep work has explicitly NOT been implemented yet and Phase 7 winter is downstream.**

The starvation-tick-of-onset off-by-one is a real but small bug.

---

## 3. Test coverage gap analysis

### What IS tested (from `Gathering.t.sol` + `ClanWorld.t.sol`)

Gather (Phase 5.1):
- `test_chopWoodAtForestYieldsBaseTimesActionDuration` — wood yield = `WOOD_YIELD_PER_TICK × 4`
- `test_chopWoodCritDistributionAcrossSeeds` — 100-trial crit distribution check (3-20 crits expected, ≈10%)
- `test_chopWoodClampsToCarryCap` — yield clamped when starting near full
- `test_chopWoodAppliesCooldownPostSettle` — cooldown engaged on completion
- `test_mineIronYieldsIronBaseYield` — iron yield matches `IRON_BASE_YIELD = 5e17`
- `test_fishDocksYieldsOneEther_onSuccessfulRoll` — fish docks payout = 1e18 on successful roll

Deposit (Phase 5.5):
- `test_settlement_depositAddsToVault` — full settlement loop: gather iron → travel home → deposit → vault increments
- `test_depositResources_woodCarryMovesToVaultAndClears` — happy path single-resource
- `test_depositResources_emptyCarryNoopsWithoutEvent` — empty deposit silent + no event
- `test_depositResources_multipleTypesMoveTogether` — atomic multi-resource transfer
- `test_depositResources_requiresHomeRegion` — wrong region → `ERR_NOT_AT_HOMEBASE`
- `test_depositResources_eventHasCorrectDeltas` — exact 4-resource deltas in event
- `test_depositResources_eventAtTickIsSettleTick` — event `atTick` is settlement tick (not 0 or submission)

ABI / R1 fixes:
- ABI parity check via `check-abi` script (regression guard)
- `ResourcesDeposited` event signature uint64 atTick (post-R1)
- `ERR_NOT_AT_HOMEBASE` regression guarded

### What is NOT tested (keyed by criticality)

#### MUST-COVER (bug-class blockers — but most are EITHER spec-drift OR phase-5.6/7 not yet shipped)

| Scenario | Why critical | Phase split |
|---|---|---|
| **Starvation onset at next-tick boundary (§4.11)** | Direct spec contradiction. Test should assert: tick T → upkeep fails → at end of tick T `_isStarving == false`; at start of tick T+1 `_isStarving == true`. Current impl flips immediately at tick T. | Phase 5.6 (starvation upkeep) — but constant declared in 5.0; impl already wires the wrong semantics |
| **Continuous gathering across multiple action ticks (§3.10)** | Spec says continuous tick-by-tick yield. Test should verify 8 ticks of gathering → 8 × yield, no mission-end / cooldown reset between yields. Current impl ends mission after one batched pay-out → forces re-submit + cooldown. | Phase 5.1 (impl is fundamentally batched not continuous) |
| **Wood per-tick rate matches §4.7 (2e18/tick)** | Sustained wood income. Test should run many ticks of continuous wood gather and assert per-tick rate. Currently: 1e18/tick (half spec) AND batched. | Phase 5.1 |
| **Crit shape (additive +1e18 vs multiplicative ×2)** | Game balance. No test asserts that crit value = base + 1e18; current test allows `cs.carryWood == baseYield * 2` which reflects impl, not spec. | Phase 5.1 |
| **Iron per-tick rate matches §4.7 (0.5e18/tick)** | Sustained iron income. Currently 0.125e18/tick (¼ spec). | Phase 5.2 (not-yet-shipped, but impl ships) |
| **Fish per-tick rate matches §4.7 (1e18/tick at p)** | Same. Currently 0.25e18/tick (¼ spec). | Phase 5.3 (not-yet-shipped, but impl ships) |
| **Wheat per-tick rate matches §4.9 (20e18/tick)** | Same. Currently 5e18/tick (¼ spec). | Phase 5.4 (not-yet-shipped, but impl ships) |
| **Winter wheat plot lockdown (§7.4)** | Plot must enter `WinterLocked` at winter start. Zero tests. | Phase 5.4 / Phase 7 winter |
| **Winter upkeep 2× multiplier (§7.3)** | Vault drains twice as fast. Zero tests; constant `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` declared and unused. | Phase 5.6 / Phase 7 |
| **Winter wood burn (§7.3, 1e18/base/tick)** | Critical economy mechanic. Zero tests; constant declared and unused. | Phase 5.6 / Phase 7 |
| **Wood carry cap = 15e18 (spec, §4.3)** | Test asserts cap at `CLANSMAN_CARRY_CAP = 10e18` which is wrong per spec. | Phase 5.1 |

#### SHOULD-COVER (production-plausible edge cases)

| Scenario | Why |
|---|---|
| **Gather during winter still pays out (no spec lockdown for non-wheat)** | Spec only locks wheat plots in winter; wood/iron/fish should still work. No test. |
| **Starvation recovery transition** | Test: vault drained → starving → fill vault → next-tick upkeep → starvation cleared. Code path exists but no test. |
| **Multi-clansman per-tick upkeep scaling** | 4 clansmen → upkeep = 4 × 1e18 wheat + 4 × 0.1e18 fish per tick. Implicit in `test_settlement_depositAddsToVault` but not asserted directly. |
| **Wheat-plot regrow boundary** | Plot drained at tick T → regrowUntilTick = T+4 → at tick T+4 settles to Harvestable + 100e18. Behavior implemented but not unit-tested. |
| **Starving wheat harvester gets 50% on plot** | Plot.remainingWheat decrement matches yield (clamped + halved). No test. Risk: plot drains TWICE as fast in starvation if impl decrements by un-halved yield. **NEEDS REVIEW** — see `ClanWorld.sol:646-652`: `yield = base; if (starving) yield /= 2; if (yield > remaining) yield = remaining; if (yield > plot.remainingWheat) yield = plot.remainingWheat; cs.carryWheat += yield; plot.remainingWheat -= yield;` ✅ same `yield` decrements both — OK. Confirm with test. |
| **Fish docks vs deep sea probability separation** | Different `BPS` constants. Only one test for docks; deep-sea has no per-tick test. |
| **Iron gold bonus when gold token uninitialized** | `clan.goldBalance += goldBonus` always works; but what if treasury is zero-address? Probably fine because gold is internal balance, not token. Confirm. |
| **Mission cooldown resets even on rejected gather** | Per A5: rejected submissions do NOT start cooldown. Test that `submitClanOrders` with `ChopWood` + `gotoRegion = Mountains` returns ERR + does NOT cooldown. Likely covered indirectly elsewhere. |

#### NICE-TO-HAVE

- Starting vault values per `mintClan` exactly match §12.4
- Starting gold balance exactly matches §12.5 (3e18)
- Wheat plot starting state (Harvestable + 100e18) per spec
- Gather invariant: `ResourcesGathered` event totals over a season equal `vault delta + carry delta + burn`
- Reorg-safety: settlement is idempotent if invoked twice for same clan / same tick

**Headline gap count:** 11 MUST-COVER, 8 SHOULD-COVER, 5 NICE-TO-HAVE. About half of MUST-COVER are spec-drift findings (current impl is internally consistent but doesn't match spec). The other half are in-flight Phase 5.6 / Phase 7 winter scope that is intentionally out of PR #193.

---

## 4. Potential UAT scenarios (if Liam runs interactive scenarios)

### Scenario 1 — Continuous gathering vs batched
**Setup:** Send a clansman to Forest with `ChopWood`. Do nothing else. Run heartbeat for 12 ticks.
**Expected per spec:** Worker chops 12 ticks × 2e18 = 24e18 wood (clamped to carry cap of 15e18 → mission terminates around tick 7-8 when cap is reached).
**Actual per impl:** Worker chops 1 batch of 4 ticks = 4e18 wood, mission ends at tick (start + travel + 4), worker enters WAITING. NO further wood. To get more wood, Elder must re-submit (incurs 60s cooldown).
**He should verify:** check `cs.state == WAITING` after one gather batch; check `cs.carryWood == 4e18` not `12e18-or-15e18`. Verify by submitting a second `ChopWood` and observing the cooldown error if submitted within 60s.

### Scenario 2 — Yield rate parity check (wood)
**Setup:** Send 4 clansmen all to Forest with `ChopWood`. Measure total wood produced over 60 ticks (1 minute of game time).
**Expected per spec:** 4 × 2e18/tick × 60 ticks = 480e18 wood per minute (modulo carry cap re-cycles back to deposit).
**Actual per impl:** Each clansman's gather mission lasts 4 ticks for 4e18, then 60-second cooldown (= 60 ticks at 1tick/sec wait — different mapping if tick != 1 second). Realistic over-1-minute output assuming round-trip: 4e18 wood × 4 clansmen × ~3 cycles = ~48e18, an order of magnitude lower.
**He should verify:** observe vault wood after a 1-minute window and compare to 480e18 (spec) vs ≤50e18 (impl). This is the single most important UAT scenario for Phase 5 economy because the entire build/upgrade economy is calibrated against spec yield rates.

### Scenario 3 — Wood carry cap divergence
**Setup:** Send a clansman to Forest with `ChopWood` for 8 batches (= 32 ticks of gathering).
**Expected per spec:** Carry caps at 15e18 wood; mission terminates when cap is reached.
**Actual per impl:** Carry caps at `CLANSMAN_CARRY_CAP = 10e18`; mission terminates 33% earlier than spec.
**He should verify:** look at `getClansman(N).carryWood` post-completion — should be 15e18 per spec, will be 10e18 per impl.

### Scenario 4 — Starvation onset off-by-one
**Setup:** Single clan, drain vault to 0 wheat + 0 fish via `transferVaultResource` to another clan. Run heartbeat for 1 tick.
**Expected per spec:** End of tick T: clan reports `_isStarving == false`. Start of tick T+1: clan reports `_isStarving == true` (next-tick onset per §4.11).
**Actual per impl:** End of tick T (after `_applyUpkeep` runs): clan reports `_isStarving == true` immediately. Off-by-one.
**He should verify:** call `getDerivedClanState` immediately after the tick T heartbeat; impl shows `isStarving = true` whereas spec wants `isStarving = false` for tick T.

### Scenario 5 — Crit shape divergence
**Setup:** Force a wood crit by iterating prevrandao seeds. Inspect carry.
**Expected per spec:** carry = 2e18 (base × 4 ticks if continuous, but spec is per-tick) → crit per tick adds +1e18. Total per tick on crit = 3e18. Over 4 ticks at full crit = 12e18.
**Actual per impl:** crit at the once-per-call boundary doubles `yield = WOOD_YIELD_PER_TICK × 4 = 4e18` to 8e18.
**He should verify:** `test_chopWoodCritDistributionAcrossSeeds` test currently asserts `cs.carryWood == baseYield * 2` (= 8e18) on crit. Spec says it should be `baseYield + 1e18 × 4 = 8e18`? Wait — the spec says crit ADDS +1e18 per tick. So per 4-tick batch a permanent-crit would be 4 × 3e18 = 12e18. Impl gives 8e18 with a single roll. Different probability semantics AND different magnitude.

### Scenario 6 — Wheat plot continues during winter
**Setup:** Wait until tick 100 (= winter start per `mintClan` constructor `winterStartsAtTick = 100`). Submit `HarvestWheat` to West Farms during winter.
**Expected per spec:** mission rejected OR completes with 0 yield; plot state = `WinterLocked`.
**Actual per impl:** mission accepts, plot still Harvestable, yields normal 20e18 wheat. Winter wood burn doesn't fire (also missing).
**He should verify:** call `getWheatPlots(clanId)` during winter — both plots will report `state = Harvestable` (impl) instead of `WinterLocked` (spec).

### Scenario 7 — Winter upkeep 2× multiplier missing
**Setup:** Run heartbeat to tick 100 (winter start). Have a 4-clansman clan with vault wheat = 8e18 (just enough for 2 ticks of summer upkeep at 4 × 1e18 = 4e18 / tick).
**Expected per spec:** winter doubles upkeep → 4 × 2e18 = 8e18 wheat / tick → vault drained in ONE tick → starving by tick 102.
**Actual per impl:** still 4e18 / tick → vault lasts 2 ticks → starving by tick 103. Plus no wood-burn either.
**He should verify:** `getClan(clanId).vaultWheat` after one tick of winter — should drop by 8e18 per spec, will drop by 4e18 per impl.

### Scenario 8 — Cooldown blocks continuous-feeling gather
**Setup:** Send clansman to Forest, ChopWood, wait for completion. Immediately re-submit.
**Expected per spec:** continuous gathering should not require Elder to re-submit at all (worker keeps going until cap or interruption).
**Actual per impl:** worker is WAITING at end of batch. Re-submit must wait for 60-second cooldown (per A5 + impl). Effective gather duty cycle is 4 ticks ON / 60+ ticks OFF.
**He should verify:** time the round-trip: `submitClanOrders(ChopWood)` → wait completion → `submitClanOrders(ChopWood)` again → observe `OrderResult.status == ERR_COOLDOWN_ACTIVE`. This is a fundamental impl-vs-spec lifecycle divergence.

---

## 5. UAT verdict

**SPEC DRIFT IS SUBSTANTIAL — RECOMMEND PATH A (RATIFY IMPL AS-IS, UPDATE SPEC) BEFORE LIAM UAT.**

The Phase 5 implementation is internally consistent and well-tested for the impl's batched-action design, but it differs from the v4 spec in three structural ways:

1. **Action lifecycle:** spec = continuous tick-by-tick yield; impl = batched 4-tick action then mission ends + cooldown. This is a deeply-baked architectural decision (every gather and the upkeep cycle assume batched semantics) and matches the Mission struct's `executesAtTick / settlesAtTick` shape. The same batched model was used in Phase 3-4 mission framework. Reverting to continuous would touch the entire mission engine, not just gather code.

2. **Yield-rate calibration:** in steady-state per-tick, sustained yield is **half spec for wood and one-quarter spec for iron / fish / wheat**. Combined with the 60-second cooldown between submissions, total resource throughput is roughly an order of magnitude lower than spec. Whether this is correct depends on whether the spec was calibrated assuming continuous or batched gameplay — if batched is canonical, the spec yield numbers need rescaling, not the impl.

3. **Wood carry cap:** 10e18 vs spec's 15e18. Fixable in one line.

4. **Winter mechanics absent:** wood burn, upkeep doubling, wheat plot lockdown — all unwired. Phase 5.6 / Phase 7 are explicitly downstream, but the constants exist so far in `IClanWorld.sol` that they are effectively dead code right now.

5. **Starvation off-by-one:** flag activates at end of failure-tick instead of start of next tick. One-line fix (`starvationStartsAtTick = tick + 1`), but consumers (e.g. defenders contributing 0 in `_resolveBanditAttack`) would change behavior, so worth a careful regression test.

**Two interpretive paths for Liam:**

**Path A — Ratify impl as canonical, update spec:** Phase 5 has clearly evolved into a batched-action economy where yield calibration is geared to action-size × duty-cycle, not per-tick continuous flow. Drafting `clanworld_v4_6_phase5_economy_alignment.md` documenting (a) batched-action semantics, (b) recalibrated per-action yields equivalent to spec per-action-tick numbers, (c) the 10e18 wood cap, (d) starvation-tick semantics — formalizes the as-built. Phase 5.6 / Phase 7 winter mechanics still need impl per the same addendum or separate Phase-7 ticket.

**Path B — Spec is canonical, impl has drifted:** the gathering pipeline must be reworked into truly continuous per-tick yield. This is a significant lift — the action-resolution model (`getActionDuration / executesAtTick / settlesAtTick`) was designed for batched single-shot actions like `BuildWall`, `DepositResources`, `MarketBuy`. Making `ChopWood / HarvestWheat / etc.` actually continuous would require either (a) changing `getActionDuration` to 1 for gather actions and looping each tick, OR (b) introducing a new continuous-action lifecycle separate from the single-tick batch.

**Recommended next step (before Liam runs UAT):** Liam decides Path A or Path B with knowledge that the cloud reviewers have already reviewed and approved the impl as internally consistent (5 reviewers, 1 R1 fix-round landed = `9b67414`). The R1 round did NOT include a spec-vs-impl alignment pass — it caught ABI bugs and per-tick yield migration parity bugs (= migration was done correctly, but only matches the impl's old shape, not the spec).

**Cleanly merge-able as-is?** Functionally yes (impl is well-tested for what it does and ABI is stable). But **only if the team explicitly accepts the spec-impl drift** OR queues the spec rewrite as Phase 5.5.5 / `spec-v4-restoration-post-hackathon` follow-up.

The cloud reviewers' assessment is correct **internal to the impl's own design**. The super-swarm did not run a spec-vs-impl alignment pass (consistent with the same gap on PR #194 / Phase 9). For Phase 5 the gap is more salient because the economy yield calibration directly drives every UI / playtest / leaderboard number; players running UAT will compare against the published spec.

---

## 6. Path A / Path B recommendation

**Recommendation: Path A — ratify impl, draft v4.6 economy alignment addendum.**

Reasoning:
- Phase 3-4 already accepted the batched action model in PR #181 / #183 merges. Phase 5 inherits and extends it; reverting now would invalidate Phase 3-4 fix-rounds.
- The hackathon rules doc (`docs/conventions/hackathon-rules.md`) acknowledges short timelines; spec recalibration is faster than impl rewrite at this stage.
- Cloud reviewers + the in-flight super-swarm have already greenlit the impl design.
- **Drift count:**
  - **Trivial drift (1):** `WOOD_CAP = 10e18` vs spec 15e18 — orchestrator can fix directly, one line in `IClanWorld.sol`. (Optional — Path A may ratify 10e18.)
  - **Substantial drift (13):** continuous-vs-batched action lifecycle, wood crit shape, all four per-tick yield rates, starvation onset tick, winter wheat lockdown, winter upkeep multiplier, winter wood burn, wheat WinterLocked transitions (start + end), cold damage path. All require either an impl rewrite (Path B) or spec acceptance (Path A).

If Path A is approved: file a single `clanworld_v4_6_phase5_economy_alignment.md` ADR draft and proceed to UAT against the new spec. Phase 5.6 (starvation upkeep) and Phase 7 (winter) remain open issues that will need to address the missing winter mechanics regardless of A or B.

If Path B is approved: file `spec-v4-restoration-post-hackathon` umbrella issue with 13 substantial drifts as sub-issues; defer implementation until after the hackathon ship.

---

## Appendix A — Files inspected

- `packages/contracts/src/ClanWorld.sol` (2127 lines, full — Phase 5 HEAD)
- `packages/contracts/src/IClanWorld.sol` (785 lines — constants library + structs + events + interface)
- `packages/contracts/test/Gathering.t.sol` (209 lines)
- `packages/contracts/test/ClanWorld.t.sol` (deposit-related + settlement tests, 2141 lines, partial read)
- `docs/planning/clanworld_v4_spec.md` §3, §4, §7.3-7.5, §12.4-12.5
- `docs/planning/clanworld_v4_1_addendum.md` A5, A6, A10, A11
- `docs/planning/clanworld_v4_2_state_schema_interface_spec.md` §3-§9
- `docs/planning/clanworld_v4_3_schema_patch.md` E, H, K, L
- `docs/planning/clanworld_v4_5_alignment_addendum.md` (no Phase-5 content — confirmed silent)

## Appendix B — What I deliberately did NOT do

- Run `forge test` (per UAT brief: static analysis only)
- Re-litigate prior-reviewer findings already adjudicated in `pr193-synthesis.md` and the gemini-CA r1 fix-round on `9ccf94a`
- Audit Phase-5.2 / 5.3 / 5.4 / 5.6 sub-issues separately (HEAD bundles all of them via Phase 4 inheritance — audited as one)
- File any GitHub issues
- Edit any code in `~/code/clan-world/`

## DIFF:

diff --git a/docs/planning/clanworld_v4_6_phase5_economy_alignment.md b/docs/planning/clanworld_v4_6_phase5_economy_alignment.md
new file mode 100644
index 0000000..f2b5098
--- /dev/null
+++ b/docs/planning/clanworld_v4_6_phase5_economy_alignment.md
@@ -0,0 +1,357 @@
+# ClanWorld v4.6 Addendum — Phase 5 Economy Alignment (Path A: as-built canonization)
+
+**Status:** Authoritative addendum, scoped to Phase 5 gathering / deposit / economy mechanics
+**Read order:** This doc supersedes the gathering-yield and economy-rate language in `clanworld_v4_spec.md` §3.10, §4.3–4.13, `clanworld_v4_1_addendum.md` A5–A6, A10, and the economy-related constants in `clanworld_v4_2_state_schema_interface_spec.md` §5. When implementers or UAT runners find disagreement on yield rates, carry caps, or starvation semantics, this doc wins.
+**Purpose:** Canonize the as-built Phase 5 batched-action economy as the authoritative Phase 5 ruleset for the hackathon submission, and explicitly enumerate the v4 mechanics that diverged as DEFERRED-TO-RESTORATION.
+**Audience:** Reviewers, UAT runners against the contract on World Chain Sepolia / Base Sepolia, future restoration work.
+
+---
+
+## 0. Why this doc exists — Path A decision (Liam, 2026-04-30)
+
+A spec-vs-impl audit by Claude Opus 4.7 (1M ctx) — the "PR #193 spec-compliance UAT" report at [`docs/reviews/pr193-spec-compliance-uat.md`](../reviews/pr193-spec-compliance-uat.md) — confirmed that the Phase 5 economy implementation diverges from the v4 spec on 14 substantial mechanics. The core structural divergence is **action lifecycle**: the v4 spec modeled gathering as a continuous tick-by-tick yield loop ("resolve tick-by-tick until stopped or blocked"); the implementation uses a **batched-action model** where each gather submission yields a single batch (4 ticks of work) and then terminates, requiring a new submission with cooldown.
+
+Two interpretive paths were available:
+
+- **Path A (chosen)** — declare the implementation canonical, write this addendum as the new authoritative ruleset, defer the v4-specific mechanics to a post-hackathon restoration milestone.
+- **Path B (rejected for hackathon timeline)** — declare the v4 spec canonical, treat the implementation as drift, rewrite the gathering pipeline to continuous per-tick semantics.
+
+Path A was selected because:
+1. The batched-action model is deeply structural — the `getActionDuration / executesAtTick / settlesAtTick` mission shape was locked in Phases 3–4 (merged PRs #181/#183). Phase 5 inherits and extends it; reverting would invalidate downstream phases.
+2. The hackathon timeline makes a gathering pipeline rewrite (Path B) untenable — multi-day lift for Phase 5.2–5.4, with regression risk across Phase 6–9.
+3. The as-built code is internally consistent and well-tested for its own batched semantics. The multi-round super-swarm and per-issue PR pipeline already validated it.
+4. Per-action yield magnitudes (4 ticks × yield_per_tick) are calibrated to the batched duty cycle, and can be rebalanced post-hackathon under restoration without touching architecture.
+
+This doc canonizes the as-built mechanics. The 14 drift items are tracked as deferred-to-restoration on GH issue [#352](https://github.com/OmniPass-world/clan-world/issues/352) under the `spec-v4-restoration-post-hackathon` GH milestone (#25) for later evaluation.
+
+---
+
+## 1. Scope of this addendum
+
+**In scope:** gathering mechanics (wood, iron, fish, wheat), deposit, carry caps, upkeep, starvation, wheat plot lifecycle, starting vault — as implemented in:
+
+- `packages/contracts/src/ClanWorld.sol` — gather helpers, `_doDeposit`, `_applyUpkeep`, wheat plot regrow, starvation flag
+- `packages/contracts/src/IClanWorld.sol` — economy constants, `Clan` struct vault fields, `WheatPlot` struct, carry fields
+- `packages/contracts/test/Gathering.t.sol`, `ClanWorld.t.sol` — codified behavior
+
+**Out of scope:** all non-economy mechanics. Bandit interactions with vault state (loot value getter — see `clanworld_v4_6_bandit_phase9_redesign.md`), winter mechanics (deferred — §9), market mechanics (Phase 6), deaths (Phase 10), gold/blueprint payouts. The rest of the v4 spec remains canonical unless overridden by a later addendum.
+
+**Authoritative as of HEAD:** `9b67414f87ab6c83cf848fbe8a8bd7e3dcc03218` (origin/dev-phase-5-economy, the HEAD against which the spec-compliance UAT was run).
+
+---
+
+## 2. As-built batched-action lifecycle
+
+### 2.1 Action model
+
+The v4 spec (§3.10) described gathering as a **continuous** action: "resolve tick-by-tick until stopped or blocked." The implementation uses a **batched-action model**:
+
+- Every gather action has `getActionDuration = 4` — the mission `settlesAtTick = actionStartTick + 4`.
+- `_settleMissionForClansman` calls `_resolveAction` only when `tick >= settlesAtTick` — i.e., 4 ticks after the action starts.
+- At resolution, the gather helper credits `YIELD_PER_TICK × 4` to the clansman's carry in one atomic call, then `_completeMission` terminates the mission.
+- The worker transitions to WAITING. To gather again, the Elder must submit a new `ChopWood` (or equivalent) mission, subject to cooldown.
+
+**There is no continuous per-tick yield loop.** One gather submission = one batch = one settlement.
+
+### 2.2 Gather mission lifecycle (canonical)
+
+```
+Submit gather order
+  → validation: worker reachable + carry not already full + target region correct
+  → action stamp: actionStartTick = currentTick, settlesAtTick = currentTick + 4
+  → cooldown stamp on submission (A5)
+per tick: _settleMissionForClansman runs
+  → if tick < settlesAtTick: noop (traveling or waiting for batch to complete)
+  → if tick >= settlesAtTick: resolve batch
+      → gather helper called once
+      → yield = YIELD_PER_TICK × 4 (± crit/RNG modifier per §3)
+      → yield clamped to remaining carry capacity
+      → if carry already at cap: _completeMission immediately (no yield)
+      → carry += yield; emit ResourcesGathered
+      → _completeMission → worker WAITING
+```
+
+**After _completeMission:** worker is WAITING at gather region. Elder must travel home + deposit + submit new gather, or submit gather again from the same region (subject to cooldown).
+
+### 2.3 Deposit lifecycle
+
+Deposit is a **single-tick action** per spec §3.10 (unchanged by this addendum):
+
+- `DEPOSIT_DURATION_TICKS = 1`
+- Worker must be at own clan's `baseRegion`
+- Atomically transfers all 4 carry resources to vault in one settlement
+- Empty-carry deposit is a silent no-op (no event emitted)
+- `ResourcesDeposited` event emitted on non-empty deposit with per-resource deltas + `atTick`
+
+### 2.4 Cooldown semantics (A5 unchanged)
+
+Per `clanworld_v4_1_addendum.md` A5 (unchanged): every successful mission submission starts cooldown (`cooldownEndsAtTs`). This applies to gather + deposit. A clansman whose cooldown is active cannot accept a new mission submission. This means the effective gather duty cycle is: **4 ticks ON + cooldown-period OFF per batch**.
+
+---
+
+## 3. Per-action yields — canonical as-built values
+
+### 3.1 Wood (Forest)
+
+| Property | As-built canonical | Source |
+|---|---|---|
+| Base yield per batch | `WOOD_YIELD_PER_TICK × 4 = 1e18 × 4 = 4e18` | `IClanWorld.sol:50, 54`; `ClanWorld.sol:493` |
+| Crit chance | `WOOD_CRIT_BPS = 1000` (10%) | `IClanWorld.sol:55` |
+| Crit effect | multiply yield × 2 → **8e18 on crit** | `ClanWorld.sol:495-497` |
+| RNG domain key | `keccak256(abi.encode("wood_crit", tickSeed, clansmanId, missionNonce, tick))` | `ClanWorld.sol:494` |
+| Region | `REGION_FOREST` | — |
+
+**Ratified design decisions:**
+- **Crit shape is ×2 multiplicative** (not +1e18 additive as in v4 §4.7). Rationale: the as-built multiplier is simpler, internally consistent, and already tested. Restoring additive crit is tracked as item #4 in §10.
+- **Wood yield per tick is 1e18** (half of v4 spec's 2e18). Yield rate drift is a consequence of the batched model: 1e18/tick × 4-tick batch = 4e18 per submission. Restoration to 2e18/tick per spec is tracked as item #2 in §10.
+
+### 3.2 Iron (Mountains)
+
+| Property | As-built canonical | Source |
+|---|---|---|
+| Base yield per batch | `IRON_YIELD_PER_TICK × 4 = 1.25e17 × 4 = 5e17 = 0.5e18` | `IClanWorld.sol:57-58`; `ClanWorld.sol:524` |
+| Gold bonus chance | `GOLD_FROM_IRON_BPS = 200` (2%) | `IClanWorld.sol:59` |
+| Gold bonus amount | `GOLD_FROM_IRON_AMOUNT = 1e18` | `IClanWorld.sol:60` |
+| Gold bonus roll cadence | **once per batch call** (not once per tick) | `ClanWorld.sol:539-548` |
+| RNG domain key | `keccak256(abi.encode("iron_gold_bonus", ...))` | `ClanWorld.sol:543` |
+| Region | `REGION_MOUNTAINS` | — |
+
+**Ratified design decisions:**
+- **Gold bonus rolls once per 4-tick batch** (not once per action tick). Sustained gold-bonus opportunity rate = 2% per batch vs spec's 2%/tick. Restoring per-tick roll cadence is tracked as item #6 in §10.
+- **Iron per-tick rate is 0.125e18** (¼ of spec's 0.5e18/tick). Restoration tracked as item #5.
+
+### 3.3 Fish — Docks (West/East Docks)
+
+| Property | As-built canonical | Source |
+|---|---|---|
+| Hit chance | `FISH_DOCKS_BPS = 2500` (25%) | `IClanWorld.sol:65` |
+| Yield on hit | `FISH_YIELD_PER_TICK × 4 = 25e16 × 4 = 1e18` | `IClanWorld.sol:63`; `ClanWorld.sol:563-578` |
+| Yield on miss | 0 | — |
+| Roll cadence | **once per batch call** | `ClanWorld.sol:563-578` |
+| RNG domain key | `keccak256(abi.encode("fish_roll", ...))` | `ClanWorld.sol:564` |
+| Regions | `REGION_WEST_DOCKS`, `REGION_EAST_DOCKS` | — |
+
+**Sustained expected value per batch:** 25% × 1e18 = 0.25e18 fish per batch.
+
+**Ratified design decision:** Roll cadence is once per batch (not once per action tick). Restoration tracked as item #7.
+
+### 3.4 Fish — Deep Sea
+
+| Property | As-built canonical | Source |
+|---|---|---|
+| Hit chance | `FISH_DEEP_BPS = 7500` (75%) | `IClanWorld.sol:66` |
+| Yield on hit | `FISH_YIELD_PER_TICK × 4 = 25e16 × 4 = 1e18` | `IClanWorld.sol:63`; `ClanWorld.sol:594-609` |
+| Yield on miss | 0 | — |
+| Roll cadence | once per batch call | `ClanWorld.sol:594-609` |
+| RNG domain key | `keccak256(abi.encode("fish_roll", ...))` | `ClanWorld.sol:595` |
+| Region | `REGION_DEEP_SEA` | — |
+
+**Sustained expected value per batch:** 75% × 1e18 = 0.75e18 fish per batch.
+
+### 3.5 Wheat (West/East Farms)
+
+| Property | As-built canonical | Source |
+|---|---|---|
+| Base yield per batch | `WHEAT_YIELD_PER_TICK × 4 = 5e18 × 4 = 20e18` | `IClanWorld.sol:62`; `ClanWorld.sol:646` |
+| Regions | `REGION_WEST_FARMS` (plot 0), `REGION_EAST_FARMS` (plot 1) | `ClanWorld.sol:626-637` |
+| Plot depletion | yield clamped to `plot.remainingWheat`; plot enters Regrowing when `remainingWheat == 0` | `ClanWorld.sol:648-659` |
+
+**Ratified design decision:** Wheat per-tick rate is 5e18 (¼ of spec's 20e18/tick per continuous model). Restoration tracked as item #9.
+
+---
+
+## 4. Per-resource carry caps — canonical as-built values
+
+These supersede the carry cap values in `clanworld_v4_spec.md` §4.3 and `clanworld_v4_2_state_schema_interface_spec.md` §5.
+
+| Resource | Spec value (deprecated) | As-built canonical | Source |
+|---|---|---|---|
+| Wood | 15e18 | **10e18** (`WOOD_CAP = CLANSMAN_CARRY_CAP = 10e18`) | `IClanWorld.sol:43-44` |
+| Iron | 5e18 | **5e18** | `IClanWorld.sol:45` ✅ unchanged |
+| Wheat | 40e18 | **40e18** | `IClanWorld.sol:46` ✅ unchanged |
+| Fish | 8e18 | **8e18** | `IClanWorld.sol:47` ✅ unchanged |
+
+**Ratified design decision:** Wood carry cap is **10e18**, not 15e18. `WOOD_CAP` is aliased to the generic `WOOD_CAP = CLANSMAN_CARRY_CAP` constant (10e18). Restoring to spec's 15e18 is tracked as item #10 in §10.
+
+**Carry enforcement mechanics (unchanged from spec):** each gather helper enforces the per-resource cap independently. Yield is clamped to `cap - currentCarry` if it would overflow. If carry is already at cap when resolution fires, the mission terminates immediately (no yield credited). This matches spec §4.8.
+
+---
+
+## 5. Upkeep and starvation semantics
+
+### 5.1 Per-tick upkeep
+
+Per living clansman per tick (unchanged from spec):
+
+| Resource | Rate | Source |
+|---|---|---|
+| Wheat | `WHEAT_UPKEEP_PER_CLANSMAN = 1e18` | `IClanWorld.sol:69` |
+| Fish | `FISH_UPKEEP_PER_CLANSMAN = 1e17` | `IClanWorld.sol:70` |
+
+Upkeep applies only when `clan.livingClansmen > 0`. If the vault cannot fully satisfy the wheat or fish demand, the respective vault field is drained to 0 (not negative).
+
+Execution order in `_settleClan` (per tick): `_applyUpkeep` → wheat-plot regrow → per-clansman mission settlement. Upkeep fires before any mission resolution in that tick, which means same-tick deposit cannot rescue that tick's upkeep (A6 compliant).
+
+### 5.2 Starvation onset — same-tick ratification
+
+**Ratified design decision:** starvation activates on the **same tick** as the upkeep failure (not the "next tick" specified in v4 §4.11).
+
+v4 §4.11 states: "If the vault cannot satisfy both wheat and fish demands in full, **starvation status begins on the next tick**." The implementation sets `clan.starvationStartsAtTick = tick` (i.e., the current tick) inside `_applyUpkeep`, and derives `_isStarving = starvationStartsAtTick != 0 && starvationStartsAtTick <= currentTick`. This means `_isStarving == true` at the end of the tick the upkeep fails.
+
+**Rationale for ratifying same-tick:** simpler state derivation; defenders contributing 0 takes effect immediately on the failure tick (cleaner UX for players — starvation is visible at the tick where it happens, not one tick later). Restoration to next-tick semantics is tracked as item #14 in §10.
+
+### 5.3 Starvation effects (unchanged from spec, A10)
+
+While `_isStarving == true`:
+
+- All gather outputs are reduced by 50% (`yield = yield / 2` applied in wood/iron/fish-docks/fish-deep/wheat helpers before carry assignment)
+- Defense contribution = 0 (starving clans are ineligible for `_resolveBanditAttack` defender path)
+- No death from starvation outside winter (summer starvation = debuff only, matches A10)
+
+Note: wheat plot depletion uses the post-halving yield value when calculating `plot.remainingWheat -= yield`, so the plot drains at the same rate as carry accumulation (no double-deduct bug).
+
+### 5.4 Starvation recovery
+
+Starvation clears in the same `_applyUpkeep` tick where the vault CAN satisfy both wheat + fish in full: `if (!starving && clan.starvationStartsAtTick != 0) clan.starvationStartsAtTick = 0`. Recovery is immediate (same tick as successful upkeep payment).
+
+---
+
+## 6. Wheat plot lifecycle
+
+| State | Condition | Behavior |
+|---|---|---|
+| `Harvestable` | `remainingWheat > 0` | Clansman can harvest; yield clamped to min(20e18, remainingWheat) per batch |
+| `Regrowing` | `remainingWheat == 0` | No harvest; regrow timer: `regrowUntilTick = tick + WHEAT_PLOT_REGROW_TICKS` |
+| `WinterLocked` | Winter active (see §9) | **Not wired in impl** — enum value declared, behavior deferred |
+
+**Regrow → Harvestable:** when `tick >= regrowUntilTick`, the per-tick `_settleClan` loop resets the plot: `state = Harvestable; remainingWheat = 100e18`.
+
+**Starting state per `mintClan`:** both West and East Farms start `Harvestable` at 100e18.
+
+`WHEAT_PLOT_REGROW_TICKS` is the canonical regrow duration. Both plots (`targetRegion == REGION_WEST_FARMS` → `plotIdx = 0`, `targetRegion == REGION_EAST_FARMS` → `plotIdx = 1`) follow identical mechanics.
+
+---
+
+## 7. Deposit mechanics (unchanged from spec)
+
+| Property | Value | Source |
+|---|---|---|
+| Duration | `DEPOSIT_DURATION_TICKS = 1` (single-tick action) | `ClanWorld.sol:77, 1804-1806` |
+| Location requirement | worker at own `clan.baseRegion` | `ClanWorld.sol:670-674, 1611-1614` |
+| Transfer semantics | all 4 carry resources → vault atomically; carry fields zeroed | `ClanWorld.sol:682-695` |
+| Empty-carry behavior | silent no-op, no event | `ClanWorld.sol:675-680` |
+| Event | `ResourcesDeposited(clanId, woodDelta, ironDelta, wheatDelta, fishDelta, atTick)` | `IClanWorld.sol:541-549` |
+| Error on wrong region | `ERR_NOT_AT_HOMEBASE` | `IClanWorld.sol:171` |
+
+---
+
+## 8. Starting vault and gold (§12.4, §12.5 — unchanged from spec)
+
+| Field | Value | Source |
+|---|---|---|
+| `vaultWood` | 20e18 | `ClanWorld.sol:1037` |
+| `vaultIron` | 0 | `ClanWorld.sol:1038` |
+| `vaultWheat` | 20e18 | `ClanWorld.sol:1039` |
+| `vaultFish` | 2e18 | `ClanWorld.sol:1040` |
+| `goldBalance` | 3e18 | `ClanWorld.sol:1034` |
+
+---
+
+## 9. Winter mechanics — deferred (Phase 5.6 / Phase 7)
+
+The following winter mechanics are declared in constants but **not wired in the implementation**. They are explicitly out of scope for Phase 5B and will be implemented under Phase 5.6 (starvation upkeep) and Phase 7 (winter season):
+
+| Mechanic | v4 spec rule | Impl status | Constant declared |
+|---|---|---|---|
+| Winter wheat plot lockdown (§7.4) | plots enter `WinterLocked` at winter start; no harvest | NOT IMPLEMENTED — `_gatherWheat` does not check `winterActive`; `WinterLocked` enum value is dead | `WheatPlotState.WinterLocked` in `IClanWorld.sol:125` |
+| Winter upkeep 2× (§7.3) | wheat + fish consumption doubles during winter | NOT IMPLEMENTED — `_applyUpkeep` uses flat rate regardless of `winterActive` | `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` in `IClanWorld.sol` (unused) |
+| Winter wood burn (§7.3) | 1e18 wood per base per tick during winter | NOT IMPLEMENTED — `_applyUpkeep` does not touch `vaultWood`; no winter check | `WINTER_WOOD_BURN_PER_BASE = 1e18` in `IClanWorld.sol:71` (unused) |
+| WinterLocked → Regrowing at winter end (v4_2 §7.4) | on winter end, locked plots → Regrowing | NOT IMPLEMENTED | — |
+
+**Behavior during winter (as-built):** Gathering and deposit work exactly as described in §2–§7 above, regardless of whether winter is active. Upkeep rates are flat (non-doubled). Wood burn does not fire.
+
+---
+
+## 10. Deferred to v4-restoration milestone (`spec-v4-restoration-post-hackathon`)
+
+The following 14 drift items are tracked for evaluation under the `spec-v4-restoration-post-hackathon` GH milestone (#25) and the umbrella tracking issue [#352](https://github.com/OmniPass-world/clan-world/issues/352). Restoration is conditional on post-hackathon evaluation.
+
+| # | v4 spec mechanic | As-built behavior | Restoration cost (rough) |
+|---|---|---|---|
+| 1 | **Continuous tick-by-tick yield** (§3.10) — gather resolves once per tick, looping until stopped or blocked | Batched: 1 gather submission = 4-tick batch = 1 settlement; mission terminates after each batch | Large — requires reworking the mission lifecycle for gather actions; touches `getActionDuration`, `_resolveAction`, cooldown semantics for continuous actions |
+| 2 | **Wood base yield 2e18/tick** (§4.7) — 2e18 per action tick (with continuous model) | 1e18/tick × 4 = 4e18/batch in batched model | Tiny constant change — but only meaningful after item #1 restores continuous model |
+| 3 | **Wood crit chance 20%** (§4.7) | `WOOD_CRIT_BPS = 1000` (10%) | Tiny — 1 constant |
+| 4 | **Wood crit shape additive +1e18** (§4.7) — crit ADDS +1e18 → total 3e18/tick | Crit DOUBLES yield → 8e18/batch | Small — modify crit branch in `_gatherWood` |
+| 5 | **Iron base yield 0.5e18/tick** (§4.7) | 0.125e18/tick × 4 = 0.5e18/batch | Tiny constant — but meaningful only after #1 |
+| 6 | **Iron gold bonus per-tick roll** (§4.7) — roll at every action tick | Rolls once per 4-tick batch call | Small — loop the roll or roll once per tick in continuous model |
+| 7 | **Fish docks 25%/tick × 1e18** (§4.7) | 25% per batch call × 1e18 | Tiny constant — meaningful after #1 |
+| 8 | **Fish deep sea 75%/tick × 1e18** (§4.7) | 75% per batch call × 1e18 | Tiny constant — meaningful after #1 |
+| 9 | **Wheat harvest rate 20e18/tick** (§4.9) | 5e18/tick × 4 = 20e18/batch | Tiny constant — meaningful after #1 |
+| 10 | **Wood carry cap 15e18** (§4.3) | `WOOD_CAP = CLANSMAN_CARRY_CAP = 10e18` | Tiny — 1 constant in `IClanWorld.sol:43-44` (alias decoupling required) |
+| 11 | **Winter wheat plot lockdown** (§7.4) — plots enter `WinterLocked` at winter start; no harvest | `WinterLocked` enum state declared, not wired | Small–Medium — wire winter-start heartbeat to set plot state; add check in `_gatherWheat`; wire winter-end → Regrowing |
+| 12 | **Winter upkeep 2× multiplier** (§7.3) — wheat + fish consumption doubles in winter | Flat rate; `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` declared, unused | Small — multiply upkeep by `WINTER_UPKEEP_MULTIPLIER_BPS` when `winterActive` in `_applyUpkeep` |
+| 13 | **Winter wood burn 1e18/base/tick** (§7.3) | Not implemented; `WINTER_WOOD_BURN_PER_BASE = 1e18` declared, unused | Small — add wood burn branch in `_applyUpkeep` when `winterActive` |
+| 14 | **Starvation onset next-tick** (§4.11) — starvation begins on the tick after upkeep failure | Starvation activates same tick as failure (`starvationStartsAtTick = tick`) | Small — change to `starvationStartsAtTick = tick + 1`; audit consumers for off-by-one |
+
+Items 11–13 partially overlap with Phase 5.6 (starvation upkeep) and Phase 7 (winter season) scope. Those phases will address them regardless.
+
+---
+
+## 11. Constants — as-built canonical values
+
+These supersede the economy-related constants in `clanworld_v4_2_state_schema_interface_spec.md` §5 for the listed entries.
+
+| Constant | Spec value (deprecated) | As-built canonical | Source |
+|---|---|---|---|
+| `WOOD_YIELD_PER_TICK` | 2e18 (implied by continuous) | **1e18** | `IClanWorld.sol:50` |
+| `WOOD_CRIT_BONUS` | +1e18 additive | **×2 multiplicative (no separate constant)** | `ClanWorld.sol:495-497` |
+| `WOOD_CRIT_BPS` | 2000 (20%) | **1000 (10%)** | `IClanWorld.sol:55` |
+| `WOOD_CAP` | 15e18 | **10e18 (= `CLANSMAN_CARRY_CAP`)** | `IClanWorld.sol:43-44` |
+| `IRON_YIELD_PER_TICK` | 5e17 (implied by continuous) | **1.25e17** | `IClanWorld.sol:57` |
+| `GOLD_FROM_IRON_BPS` | 200 (2%) | **200 (2%)** ✅ unchanged | `IClanWorld.sol:59` |
+| `GOLD_FROM_IRON_AMOUNT` | 1e18 | **1e18** ✅ unchanged | `IClanWorld.sol:60` |
+| `FISH_DOCKS_BPS` | 2500 (25%) | **2500 (25%)** ✅ unchanged | `IClanWorld.sol:65` |
+| `FISH_DEEP_BPS` | 7500 (75%) | **7500 (75%)** ✅ unchanged | `IClanWorld.sol:66` |
+| `FISH_YIELD_PER_TICK` | 1e18 (implied by continuous) | **25e16 (= 2.5e17)** | `IClanWorld.sol:63` |
+| `WHEAT_YIELD_PER_TICK` | 20e18 (implied by continuous) | **5e18** | `IClanWorld.sol:62` |
+| `WHEAT_CAP` | 40e18 | **40e18** ✅ unchanged | `IClanWorld.sol:46` |
+| `IRON_CAP` | 5e18 | **5e18** ✅ unchanged | `IClanWorld.sol:45` |
+| `FISH_CAP` | 8e18 | **8e18** ✅ unchanged | `IClanWorld.sol:47` |
+| `WHEAT_UPKEEP_PER_CLANSMAN` | 1e18 | **1e18** ✅ unchanged | `IClanWorld.sol:69` |
+| `FISH_UPKEEP_PER_CLANSMAN` | 1e17 | **1e17** ✅ unchanged | `IClanWorld.sol:70` |
+| `WINTER_UPKEEP_MULTIPLIER_BPS` | 20000 (2×) | **20000 (declared, unused — see §9)** | `IClanWorld.sol` |
+| `WINTER_WOOD_BURN_PER_BASE` | 1e18 | **1e18 (declared, unused — see §9)** | `IClanWorld.sol:71` |
+
+---
+
+## 12. UAT runners — what to expect
+
+When running interactive UAT against this contract, **expect the as-built mechanics (this addendum), not v4 §3.10 / §4.3–4.13**. Specifically:
+
+- ✅ Each gather order yields one batch (4 ticks of work) and terminates. Worker enters WAITING. To gather more, submit a new order after cooldown.
+- ✅ Wood: 4e18 per batch base, 8e18 on crit (10% chance) — NOT 2e18/tick continuous
+- ✅ Iron: 0.5e18 per batch, 2% chance of +1e18 gold bonus per batch — NOT 0.5e18/tick continuous
+- ✅ Fish docks: 25% × 1e18 per batch — NOT 25% × 1e18/tick
+- ✅ Fish deep sea: 75% × 1e18 per batch — NOT 75% × 1e18/tick
+- ✅ Wheat: 20e18 per batch — NOT 20e18/tick continuous
+- ✅ Wood carry cap is 10e18 (NOT 15e18)
+- ✅ Starvation activates on the SAME TICK as upkeep failure (NOT next tick)
+- ✅ Wheat plots remain harvestable during winter (WinterLocked NOT wired)
+- ✅ Winter upkeep doubling NOT active; flat upkeep rates apply year-round
+- ✅ Winter wood burn NOT active
+
+If a UAT scenario expects v4-spec continuous yields, per-tick rates, or winter lockdown behavior, it will fail against this contract. Use this addendum as the oracle.
+
+---
+
+## 13. References
+
+- **Spec-compliance UAT report:** [`docs/reviews/pr193-spec-compliance-uat.md`](../reviews/pr193-spec-compliance-uat.md) — full mechanic-by-mechanic table, test-coverage gap analysis, UAT scenario predictions
+- **Path A precedent (bandit mechanics):** [`docs/planning/clanworld_v4_6_bandit_phase9_redesign.md`](./clanworld_v4_6_bandit_phase9_redesign.md)
+- **Source v4 docs being superseded for economy mechanics:**
+  - `clanworld_v4_spec.md` §3.10, §4.3–4.13, §7.3–7.5, §12.4–12.5
+  - `clanworld_v4_1_addendum.md` A5, A6, A10
+  - `clanworld_v4_2_state_schema_interface_spec.md` §5 (economy constants listed in §11 above)
+  - `clanworld_v4_3_schema_patch.md` E (RNG domain keys — fully matched, unchanged), L (starvationStartsAtTick — matched)
+- **Implementation HEAD canonized by this addendum:** `9b67414f87ab6c83cf848fbe8a8bd7e3dcc03218`
+- **Restoration tracking:** GH milestone `spec-v4-restoration-post-hackathon` (#25) and tracking issue [#352](https://github.com/OmniPass-world/clan-world/issues/352)
</stdin>
warning: Codex could not find bubblewrap on PATH. Install bubblewrap with your OS package manager. See the sandbox prerequisites: https://developers.openai.com/codex/concepts/sandboxing#prerequisites. Codex will use the vendored bubblewrap in the meantime.
codex
I’ll treat this as a read-only review pass and verify against the actual branch/commit rather than trusting the pasted doc. I’m going to pull the relevant doc, audit, and contract slices in parallel first, then I’ll emit the requested markdown review.
exec
/bin/bash -lc "rg --files | rg '("'^docs/(planning|reviews)/|''^packages/contracts/src/|''^packages/contracts/test/)'"'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
packages/contracts/src/ClanWorld.sol
packages/contracts/src/ClanWorldStub.sol
packages/contracts/src/IClanWorld.sol
packages/contracts/src/MinimalERC20.sol
packages/contracts/src/StubPool.sol
packages/contracts/src/lib/RNG.sol
packages/contracts/src/util/ReentrancyGuard.sol
packages/contracts/test/ClanWorld.t.sol
packages/contracts/test/ClanWorldStub.t.sol
packages/contracts/test/DefendBase.t.sol
packages/contracts/test/Gathering.t.sol
packages/contracts/test/HeartbeatOrdering.t.sol
packages/contracts/test/MissionTiming.t.sol
packages/contracts/test/RNG.t.sol
packages/contracts/test/Reentrancy.t.sol
docs/reviews/pr132-review-claude-opus.md
docs/reviews/pr133-review-claude-opus.md
docs/reviews/pr136-review-claude-opus.md
docs/reviews/pr137-review-claude-opus.md
docs/reviews/pr356-codereview-codex-5-5.md
docs/reviews/pr356-codereview-opus-4-7.md
docs/reviews/pr356-codereview-gemini-3-1-pro.md
docs/planning/CANONICAL_SPEC.md
docs/planning/ClanWorldCockpit_BrainstormingMock.jsx
docs/planning/DEMO_DRIFT.md
docs/planning/V1.zip
docs/planning/battleplan-v1.txt
docs/planning/clanworld 0g battleplan and spec.pdf
docs/planning/clanworld axl integration spec.pdf
docs/planning/clanworld v4 5 keeper integration spec.pdf
docs/planning/clanworld_numbered_implementation_plan.md
docs/planning/clanworld_v1_implementation_profile.md
docs/planning/clanworld_v4_1_addendum.md
docs/planning/clanworld_v4_2_state_schema_interface_spec.md
docs/planning/clanworld_v4_3_schema_patch.md
docs/planning/clanworld_v4_4_ui_indexer_getters.md
docs/planning/clanworld_v4_5_alignment_addendum.md
docs/planning/clanworld_v4_6_phase5_economy_alignment.md
docs/planning/clanworld_v4_spec.md
docs/planning/phase-3-test-spec.md

exec
/bin/bash -lc 'git rev-parse --verify origin/dev-phase-5-economy && git rev-parse --verify HEAD && git branch --show-current' in /tmp/wt-superswarm-356
 succeeded in 0ms:
9b67414f87ab6c83cf848fbe8a8bd7e3dcc03218
732120bfc57a44a5af9c60a8735dc67c34dd2f00

exec
/bin/bash -lc 'git status --short --branch' in /tmp/wt-superswarm-356
 succeeded in 152ms:
## HEAD (no branch)
?? docs/reviews/pr356-codereview-codex-5-5.md
?? docs/reviews/pr356-codereview-gemini-3-1-pro.md
?? docs/reviews/pr356-codereview-opus-4-7.md

codex
The worktree is detached at `732120b`, and `origin/dev-phase-5-economy` resolves to the cited `9b67414f...`, so the basic review target is lined up. Next I’m checking the cited line ranges directly from that origin commit, especially the economy constants and gather/deposit helpers.
exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/IClanWorld.sol | nl -ba | sed -n '35,75p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
    35	    uint64 internal constant BANDIT_CAMP_TICKS = 3;
    36	    uint64 internal constant BANDIT_REST_TICKS = 2;
    37	    uint8 internal constant BANDIT_MAX_ATTACK_ATTEMPTS = 6;
    38	
    39	    // Clansman cadence
    40	    uint64 internal constant CLANSMAN_COOLDOWN_SECONDS = 60;
    41	
    42	    // Carry caps (per clansman)
    43	    uint256 internal constant CLANSMAN_CARRY_CAP = 10e18; // only enforced for wood gather
    44	    uint256 internal constant WOOD_CAP = CLANSMAN_CARRY_CAP;
    45	    uint256 internal constant IRON_CAP = 5e18;
    46	    uint256 internal constant WHEAT_CAP = 40e18;
    47	    uint256 internal constant FISH_CAP = 8e18;
    48	
    49	    // Gathering yields
    50	    uint256 internal constant WOOD_YIELD_PER_TICK = 1e18;
    51	    uint256 internal constant WOOD_BASE_YIELD = WOOD_YIELD_PER_TICK;
    52	    /// @dev Crit effect is multiplicative (yield *= 2), not additive. This constant is the added amount when viewed
    53	    ///      as base + bonus, but the implementation uses `yield *= 2` for clarity.
    54	    uint256 internal constant WOOD_CRIT_BONUS = WOOD_YIELD_PER_TICK;
    55	    uint16 internal constant WOOD_CRIT_BPS = 1000; // 10%
    56	
    57	    uint256 internal constant IRON_BASE_YIELD = 5e17; // 0.5e18 — total per call (= IRON_YIELD_PER_TICK * 4)
    58	    uint256 internal constant IRON_YIELD_PER_TICK = IRON_BASE_YIELD / 4; // 1.25e17
    59	    uint16 internal constant GOLD_FROM_IRON_BPS = 200; // 2%
    60	    uint256 internal constant GOLD_FROM_IRON_AMOUNT = 1e18;
    61	
    62	    uint256 internal constant WHEAT_YIELD_PER_TICK = 5e18; // 20e18 total / 4 ticks
    63	    uint256 internal constant FISH_YIELD_PER_TICK = 25e16; // 1e18 total / 4 ticks
    64	
    65	    uint16 internal constant FISH_DOCKS_BPS = 2500; // 25%
    66	    uint16 internal constant FISH_DEEP_BPS = 7500; // 75%
    67	
    68	    // Upkeep
    69	    uint256 internal constant WHEAT_UPKEEP_PER_CLANSMAN = 1e18;
    70	    uint256 internal constant FISH_UPKEEP_PER_CLANSMAN = 1e17; // 0.1
    71	    uint256 internal constant WINTER_WOOD_BURN_PER_BASE = 1e18;
    72	    uint16 internal constant WINTER_UPKEEP_MULTIPLIER_BPS = 20000; // 2x
    73	
    74	    // Wheat plots
    75	    uint64 internal constant WHEAT_PLOT_REGROW_TICKS = 4;

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/IClanWorld.sol | nl -ba | sed -n '118,130p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   118	    ATTACKING,
   119	    DEFEATED,
   120	    ESCAPED
   121	}
   122	
   123	enum WheatPlotState {
   124	    Harvestable,
   125	    Regrowing,
   126	    WinterLocked
   127	}
   128	
   129	enum ResourceType {
   130	    Wood,

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/IClanWorld.sol | nl -ba | sed -n '160,190p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   160	    OK,
   161	    ERR_CLAN_DEAD,
   162	    ERR_CLAN_NOT_OWNED,
   163	    ERR_CLANSMAN_DEAD,
   164	    ERR_INVALID_CLANSMAN,
   165	    ERR_INVALID_REGION,
   166	    ERR_INVALID_ACTION,
   167	    ERR_INVALID_TARGET,
   168	    ERR_COOLDOWN_ACTIVE,
   169	    ERR_NOT_WAITING,
   170	    ERR_NOT_IN_UNICORN_TOWN,
   171	    ERR_NOT_AT_HOMEBASE,
   172	    ERR_NOT_AT_TARGET_BASE,
   173	    ERR_NOT_DEFENDABLE,
   174	    ERR_MISSING_RESOURCES,
   175	    ERR_EMPTY_CARGO,
   176	    ERR_PLOT_NOT_READY,
   177	    ERR_PLOT_EMPTY,
   178	    ERR_MARKET_ZERO_AMOUNT,
   179	    ERR_MARKET_UNSUPPORTED_TOKEN,
   180	    ERR_IMMEDIATE_MARKET_NOT_ELIGIBLE,
   181	    ERR_MARKET_BUY_OVER_CAPACITY,
   182	    ERR_MARKET_BUY_MAX_GOLD_EXCEEDED,
   183	    ERR_WORLD_TICK_MISMATCH,
   184	    ERR_NO_ACTIVE_BANDIT,
   185	    ERR_SEASON_ENDED,
   186	    ERR_NOT_ENOUGH_GOLD,
   187	    ERR_CARRY_FULL
   188	}
   189	
   190	// =============================================================================

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/IClanWorld.sol | nl -ba | sed -n '225,260p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   225	    address goldToken;
   226	    address blueprintToken;
   227	
   228	    address woodGoldPool;
   229	    address wheatGoldPool;
   230	    address fishGoldPool;
   231	    address ironGoldPool;
   232	}
   233	
   234	struct Clan {
   235	    uint32 clanId;
   236	    uint256 iftTokenId;
   237	    address owner;
   238	    ClanState clanState;
   239	
   240	    uint8 baseRegion;
   241	    uint8 baseLevel;
   242	    uint8 wallLevel;
   243	    uint8 monumentLevel;
   244	    uint8 livingClansmen;
   245	
   246	    uint64 lastSettledTick;
   247	    uint64 starvationStartsAtTick; // 0 = none
   248	
   249	    uint16 coldDamage; // resets to 0 at winter end
   250	
   251	    uint256 goldBalance;
   252	    uint256 blueprintBalance;
   253	
   254	    uint256 vaultWood;
   255	    uint256 vaultIron;
   256	    uint256 vaultWheat;
   257	    uint256 vaultFish;
   258	}
   259	
   260	struct WheatPlot {

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/IClanWorld.sol | nl -ba | sed -n '526,552p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   526	    event MissionCompleted(uint32 indexed clanId, uint32 indexed clansmanId, uint64 missionNonce, ActionType action);
   527	    event WorkerArrived(uint32 indexed clanId, uint32 indexed clansmanId, uint8 region, uint64 tick);
   528	
   529	    // ----- gathering / vault movement -----
   530	    event ResourcesGathered(
   531	        uint32 indexed clanId,
   532	        uint32 indexed clansmanId,
   533	        ActionType action,
   534	        uint256 woodGained,
   535	        uint256 ironGained,
   536	        uint256 wheatGained,
   537	        uint256 fishGained,
   538	        uint256 goldBonus,
   539	        uint64 atTick
   540	    );
   541	    event ResourcesDeposited(
   542	        uint32 indexed clanId,
   543	        uint32 indexed clansmanId,
   544	        uint256 woodDelta,
   545	        uint256 ironDelta,
   546	        uint256 wheatDelta,
   547	        uint256 fishDelta,
   548	        uint64 atTick
   549	    );
   550	
   551	    // ----- building -----
   552	    event WallLevelChanged(uint32 indexed clanId, uint8 oldLevel, uint8 newLevel, uint64 atTick);

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '70,82p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
    70	    // per-clan clansman list: clanId => clansmanId[]
    71	    mapping(uint32 => uint32[]) private _clanClansmanIds;
    72	
    73	    // =========================================================================
    74	    // CONSTANTS — Wheat harvest rate (not in IClanWorld constants)
    75	    // =========================================================================
    76	
    77	    uint64 private constant DEPOSIT_DURATION_TICKS = 1;
    78	    /// @dev Caps market queue work per heartbeat; overflow is deferred to the next tick.
    79	    uint256 public constant MAX_MARKET_ACTIONS_PER_TICK = 32;
    80	
    81	    // =========================================================================
    82	    // CONSTRUCTOR

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '335,430p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   335	
   336	            if (m.action == ActionType.DefendBase) continue; // persistent defender mission
   337	
   338	            // Path 3: ACTING at/past settlesAtTick → resolve
   339	            if (cs.state == ClansmanState.ACTING && tick >= m.settlesAtTick) {
   340	                _resolveAction(clan, cs, m, clanId, tick, tickSeed);
   341	                if (m.active && getActionDuration(m.action) > 0) {
   342	                    _completeMission(cs, m);
   343	                }
   344	            }
   345	
   346	            // If mission completed during this tick, stop iterating
   347	            if (!m.active) break;
   348	        }
   349	    }
   350	
   351	    /// @dev Lazy settlement of a clan forward to currentTick.
   352	    ///      Mutates storage. Called before order submission and by public settleClan().
   353	    function _settleClan(uint32 clanId) internal {
   354	        Clan storage clan = _clans[clanId];
   355	        if (clan.clanId == 0) return;
   356	
   357	        uint64 curTick = _world.currentTick;
   358	        uint64 fromTick = clan.lastSettledTick;
   359	        if (fromTick >= curTick) return;
   360	
   361	        // Cap ticks settled per call to prevent block gas limit issues
   362	        uint64 maxSettleTicks = 200;
   363	        if (curTick > fromTick + maxSettleTicks) {
   364	            curTick = fromTick + maxSettleTicks;
   365	        }
   366	
   367	        uint32[] storage clansmanIds = _clanClansmanIds[clanId];
   368	
   369	        // Settle tick by tick from fromTick to curTick - 1
   370	        // (curTick is still open; we settle through the last closed tick)
   371	        for (uint64 tick = fromTick; tick < curTick; tick++) {
   372	            // 1. Apply upkeep for this tick
   373	            _applyUpkeep(clan, tick);
   374	
   375	            // 2. Wheat plot regrow check (lazy, per tick)
   376	            for (uint256 pi = 0; pi < 2; pi++) {
   377	                WheatPlot storage plot = _wheatPlots[clanId][pi];
   378	                if (plot.state == WheatPlotState.Regrowing && tick >= plot.regrowUntilTick) {
   379	                    plot.state = WheatPlotState.Harvestable;
   380	                    plot.remainingWheat = ClanWorldConstants.WHEAT_PLOT_STARTING_WHEAT;
   381	                    plot.regrowUntilTick = 0;
   382	                }
   383	            }
   384	
   385	            // 3. Advance each clansman (single-tick range: [tick, tick+1))
   386	            for (uint256 i = 0; i < clansmanIds.length; i++) {
   387	                Clansman storage cs = _clansmen[clansmanIds[i]];
   388	                _settleMissionForClansman(clan, cs, clanId, tick, tick + 1);
   389	            }
   390	        }
   391	
   392	        clan.lastSettledTick = curTick;
   393	        emit ClanSettled(clanId, curTick);
   394	    }
   395	
   396	    /// @dev Apply one tick of upkeep. Marks starvation if insufficient food.
   397	    function _applyUpkeep(Clan storage clan, uint64 tick) internal {
   398	        if (clan.livingClansmen == 0) return;
   399	
   400	        uint256 wheatNeeded = uint256(clan.livingClansmen) * ClanWorldConstants.WHEAT_UPKEEP_PER_CLANSMAN;
   401	        uint256 fishNeeded = uint256(clan.livingClansmen) * ClanWorldConstants.FISH_UPKEEP_PER_CLANSMAN;
   402	
   403	        bool hadEnoughWheat = clan.vaultWheat >= wheatNeeded;
   404	        bool hadEnoughFish = clan.vaultFish >= fishNeeded;
   405	
   406	        if (hadEnoughWheat) {
   407	            clan.vaultWheat -= wheatNeeded;
   408	        } else {
   409	            clan.vaultWheat = 0;
   410	        }
   411	        if (hadEnoughFish) {
   412	            clan.vaultFish -= fishNeeded;
   413	        } else {
   414	            clan.vaultFish = 0;
   415	        }
   416	
   417	        bool starving = !hadEnoughWheat || !hadEnoughFish;
   418	        if (starving && clan.starvationStartsAtTick == 0) {
   419	            clan.starvationStartsAtTick = tick;
   420	            emit ClanStarvationChanged(clan.clanId, true, tick);
   421	        } else if (!starving && clan.starvationStartsAtTick != 0) {
   422	            clan.starvationStartsAtTick = 0;
   423	            emit ClanStarvationChanged(clan.clanId, false, tick);
   424	        }
   425	    }
   426	
   427	    /// @dev Check if a clan is currently starving (lazy read).
   428	    function _isStarving(Clan storage clan) internal view returns (bool) {
   429	        return clan.starvationStartsAtTick != 0 && clan.starvationStartsAtTick <= _world.currentTick;
   430	    }

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '478,665p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   478	    function _gatherWood(
   479	        Clan storage, // clan (unused — no clan-level mutation in wood gather)
   480	        Clansman storage cs,
   481	        Mission storage m,
   482	        uint32 clanId,
   483	        uint64 tick,
   484	        bool starving,
   485	        bytes32 tickSeed
   486	    ) internal {
   487	        if (cs.carryWood >= ClanWorldConstants.CLANSMAN_CARRY_CAP) {
   488	            _completeMission(cs, m);
   489	            return;
   490	        }
   491	
   492	        uint256 remaining = ClanWorldConstants.CLANSMAN_CARRY_CAP - cs.carryWood;
   493	        uint256 yield = ClanWorldConstants.WOOD_YIELD_PER_TICK * uint256(getActionDuration(ActionType.ChopWood));
   494	        bytes32 woodRng = keccak256(abi.encode("wood_crit", tickSeed, cs.clansmanId, m.nonce, tick));
   495	        if (uint256(woodRng) % 10000 < ClanWorldConstants.WOOD_CRIT_BPS) {
   496	            yield *= 2;
   497	        }
   498	
   499	        if (starving) yield = yield / 2;
   500	        if (yield > remaining) yield = remaining;
   501	        cs.carryWood += yield;
   502	
   503	        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.ChopWood, yield, 0, 0, 0, 0, tick);
   504	
   505	        if (cs.carryWood >= ClanWorldConstants.CLANSMAN_CARRY_CAP) {
   506	            _completeMission(cs, m);
   507	        }
   508	    }
   509	
   510	    function _gatherIron(
   511	        Clan storage clan,
   512	        Clansman storage cs,
   513	        Mission storage m,
   514	        uint32 clanId,
   515	        uint64 tick,
   516	        bool starving,
   517	        bytes32 tickSeed
   518	    ) internal {
   519	        uint256 remaining = ClanWorldConstants.IRON_CAP - cs.carryIron;
   520	        if (remaining == 0) {
   521	            _completeMission(cs, m);
   522	            return;
   523	        }
   524	        uint256 yield = ClanWorldConstants.IRON_YIELD_PER_TICK * uint256(getActionDuration(ActionType.MineIron));
   525	        if (starving) yield = yield / 2;
   526	        if (yield > remaining) yield = remaining;
   527	        cs.carryIron += yield;
   528	
   529	        // Gold bonus roll — scoped to reduce stack depth
   530	        uint256 goldBonus = _rollIronGoldBonus(clan, cs.clansmanId, m.nonce, tick, tickSeed);
   531	
   532	        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.MineIron, 0, yield, 0, 0, goldBonus, tick);
   533	
   534	        if (cs.carryIron >= ClanWorldConstants.IRON_CAP) {
   535	            _completeMission(cs, m);
   536	        }
   537	    }
   538	
   539	    function _rollIronGoldBonus(Clan storage clan, uint32 clansmanId, uint64 nonce, uint64 tick, bytes32 tickSeed)
   540	        internal
   541	        returns (uint256 goldBonus)
   542	    {
   543	        bytes32 goldRng = keccak256(abi.encode("iron_gold_bonus", tickSeed, clansmanId, nonce, tick));
   544	        if (uint256(goldRng) % 10000 < ClanWorldConstants.GOLD_FROM_IRON_BPS) {
   545	            goldBonus = ClanWorldConstants.GOLD_FROM_IRON_AMOUNT;
   546	            clan.goldBalance += goldBonus;
   547	        }
   548	    }
   549	
   550	    function _gatherFishDocks(
   551	        Clan storage,
   552	        Clansman storage cs,
   553	        Mission storage m,
   554	        uint32 clanId,
   555	        uint64 tick,
   556	        bool starving,
   557	        bytes32 tickSeed
   558	    ) internal {
   559	        uint256 remaining = ClanWorldConstants.FISH_CAP - cs.carryFish;
   560	        if (remaining == 0) {
   561	            _completeMission(cs, m);
   562	            return;
   563	        }
   564	        bytes32 fishRng = keccak256(abi.encode("fish_roll", tickSeed, cs.clansmanId, m.nonce, tick));
   565	        uint256 fishRoll = uint256(fishRng) % 10000;
   566	        uint256 yield = 0;
   567	        if (fishRoll < ClanWorldConstants.FISH_DOCKS_BPS) {
   568	            yield = ClanWorldConstants.FISH_YIELD_PER_TICK * uint256(getActionDuration(ActionType.FishDocks));
   569	        }
   570	        if (starving) yield = yield / 2;
   571	        if (yield > remaining) yield = remaining;
   572	        if (yield > 0) {
   573	            cs.carryFish += yield;
   574	            emit ResourcesGathered(clanId, cs.clansmanId, ActionType.FishDocks, 0, 0, 0, yield, 0, tick);
   575	        }
   576	        if (cs.carryFish >= ClanWorldConstants.FISH_CAP) {
   577	            _completeMission(cs, m);
   578	        }
   579	    }
   580	
   581	    function _gatherFishDeepSea(
   582	        Clan storage,
   583	        Clansman storage cs,
   584	        Mission storage m,
   585	        uint32 clanId,
   586	        uint64 tick,
   587	        bool starving,
   588	        bytes32 tickSeed
   589	    ) internal {
   590	        uint256 remaining = ClanWorldConstants.FISH_CAP - cs.carryFish;
   591	        if (remaining == 0) {
   592	            _completeMission(cs, m);
   593	            return;
   594	        }
   595	        bytes32 fishRng = keccak256(abi.encode("fish_roll", tickSeed, cs.clansmanId, m.nonce, tick));
   596	        uint256 fishRoll = uint256(fishRng) % 10000;
   597	        uint256 yield = 0;
   598	        if (fishRoll < ClanWorldConstants.FISH_DEEP_BPS) {
   599	            yield = ClanWorldConstants.FISH_YIELD_PER_TICK * uint256(getActionDuration(ActionType.FishDeepSea));
   600	        }
   601	        if (starving) yield = yield / 2;
   602	        if (yield > remaining) yield = remaining;
   603	        if (yield > 0) {
   604	            cs.carryFish += yield;
   605	            emit ResourcesGathered(clanId, cs.clansmanId, ActionType.FishDeepSea, 0, 0, 0, yield, 0, tick);
   606	        }
   607	        if (cs.carryFish >= ClanWorldConstants.FISH_CAP) {
   608	            _completeMission(cs, m);
   609	        }
   610	    }
   611	
   612	    function _gatherWheat(
   613	        Clan storage,
   614	        /* clan — unused but kept positional for callsite parity */
   615	        Clansman storage cs,
   616	        Mission storage m,
   617	        uint32 clanId,
   618	        uint64 tick,
   619	        bool starving
   620	    ) internal {
   621	        uint256 remaining = ClanWorldConstants.WHEAT_CAP - cs.carryWheat;
   622	        if (remaining == 0) {
   623	            _completeMission(cs, m);
   624	            return;
   625	        }
   626	        // Determine plot index from region
   627	        uint8 region = m.targetRegion;
   628	        uint256 plotIdx;
   629	        if (region == ClanWorldConstants.REGION_WEST_FARMS) {
   630	            plotIdx = 0;
   631	        } else if (region == ClanWorldConstants.REGION_EAST_FARMS) {
   632	            plotIdx = 1;
   633	        } else {
   634	            // Wrong region — complete (no harvest)
   635	            _completeMission(cs, m);
   636	            return;
   637	        }
   638	
   639	        WheatPlot storage plot = _wheatPlots[clanId][plotIdx];
   640	        if (plot.state != WheatPlotState.Harvestable || plot.remainingWheat == 0) {
   641	            // Plot not ready — worker waits
   642	            _completeMission(cs, m);
   643	            return;
   644	        }
   645	
   646	        uint256 yield = ClanWorldConstants.WHEAT_YIELD_PER_TICK * uint256(getActionDuration(ActionType.HarvestWheat));
   647	        if (starving) yield = yield / 2;
   648	        if (yield > remaining) yield = remaining;
   649	        if (yield > plot.remainingWheat) yield = plot.remainingWheat;
   650	
   651	        cs.carryWheat += yield;
   652	        plot.remainingWheat -= yield;
   653	
   654	        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.HarvestWheat, 0, 0, yield, 0, 0, tick);
   655	
   656	        if (plot.remainingWheat == 0) {
   657	            plot.state = WheatPlotState.Regrowing;
   658	            plot.regrowUntilTick = tick + ClanWorldConstants.WHEAT_PLOT_REGROW_TICKS;
   659	        }
   660	
   661	        if (cs.carryWheat >= ClanWorldConstants.WHEAT_CAP || plot.remainingWheat == 0) {
   662	            _completeMission(cs, m);
   663	        }
   664	        // else continuous
   665	    }

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '670,700p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   670	        // Must be at homebase region
   671	        if (cs.currentRegion != clan.baseRegion) {
   672	            _completeMission(cs, m);
   673	            return;
   674	        }
   675	        bool hasAnything = cs.carryWood > 0 || cs.carryIron > 0 || cs.carryWheat > 0 || cs.carryFish > 0;
   676	        if (!hasAnything) {
   677	            // Empty deposits are silent no-ops; no zero-delta event for indexers to process.
   678	            _completeMission(cs, m);
   679	            return;
   680	        }
   681	
   682	        uint256 woodDelta = cs.carryWood;
   683	        uint256 ironDelta = cs.carryIron;
   684	        uint256 wheatDelta = cs.carryWheat;
   685	        uint256 fishDelta = cs.carryFish;
   686	
   687	        clan.vaultWood += woodDelta;
   688	        clan.vaultIron += ironDelta;
   689	        clan.vaultWheat += wheatDelta;
   690	        clan.vaultFish += fishDelta;
   691	
   692	        cs.carryWood = 0;
   693	        cs.carryIron = 0;
   694	        cs.carryWheat = 0;
   695	        cs.carryFish = 0;
   696	
   697	        emit ResourcesDeposited(clanId, cs.clansmanId, woodDelta, ironDelta, wheatDelta, fishDelta, tick);
   698	        _completeMission(cs, m);
   699	    }
   700	

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '1028,1056p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
  1028	        clan.wallLevel = 0;
  1029	        clan.monumentLevel = 0;
  1030	        clan.livingClansmen = 4;
  1031	        clan.lastSettledTick = _world.currentTick;
  1032	        clan.starvationStartsAtTick = 0;
  1033	        clan.coldDamage = 0;
  1034	        clan.goldBalance = 3e18; // starter gold per v4 spec §12.5
  1035	        clan.blueprintBalance = 0;
  1036	        // Starting vault per v4 spec §12.4
  1037	        clan.vaultWood = 20e18;
  1038	        clan.vaultIron = 0;
  1039	        clan.vaultWheat = 20e18;
  1040	        clan.vaultFish = 2e18;
  1041	
  1042	        // Wheat plots
  1043	        _wheatPlots[clanId][0] = WheatPlot({
  1044	            state: WheatPlotState.Harvestable,
  1045	            region: ClanWorldConstants.REGION_WEST_FARMS,
  1046	            remainingWheat: ClanWorldConstants.WHEAT_PLOT_STARTING_WHEAT,
  1047	            regrowUntilTick: 0
  1048	        });
  1049	        _wheatPlots[clanId][1] = WheatPlot({
  1050	            state: WheatPlotState.Harvestable,
  1051	            region: ClanWorldConstants.REGION_EAST_FARMS,
  1052	            remainingWheat: ClanWorldConstants.WHEAT_PLOT_STARTING_WHEAT,
  1053	            regrowUntilTick: 0
  1054	        });
  1055	
  1056	        // Create 4 clansmen

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '1598,1620p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
  1598	            closedTick, commitSequence, clanId, clansmanId, _treasury.goldToken, token, actualGoldIn, amountOut
  1599	        );
  1600	    }
  1601	
  1602	    function _validateAction(Clan storage clan, Clansman storage cs, ClanOrder calldata order, uint8 gotoRegion)
  1603	        internal
  1604	        view
  1605	        returns (StatusCode)
  1606	    {
  1607	        ActionType action = order.action;
  1608	
  1609	        if (action == ActionType.None) return StatusCode.ERR_INVALID_ACTION;
  1610	
  1611	        // DepositResources: must go to homebase
  1612	        if (action == ActionType.DepositResources) {
  1613	            if (gotoRegion != clan.baseRegion) return StatusCode.ERR_NOT_AT_HOMEBASE;
  1614	        }
  1615	
  1616	        // BuildWall / UpgradeBase / UpgradeMonument: must go to homebase
  1617	        if (action == ActionType.BuildWall || action == ActionType.UpgradeBase || action == ActionType.UpgradeMonument)
  1618	        {
  1619	            if (gotoRegion != clan.baseRegion) return StatusCode.ERR_NOT_AT_HOMEBASE;
  1620	        }

exec
/bin/bash -lc "git show HEAD:docs/planning/clanworld_v4_6_phase5_economy_alignment.md | nl -ba | sed -n '1,220p'" in /tmp/wt-superswarm-356
exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '1788,1810p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
  1788	    {
  1789	        Mission memory m = _missions[clansmanId];
  1790	        if (!m.active || _clansmen[clansmanId].clanId != clanId) {
  1791	            return (0, 0, 0);
  1792	        }
  1793	        return (m.submittedAtTick, m.executesAtTick, m.settlesAtTick);
  1794	    }
  1795	
  1796	    function getActionDuration(ActionType action) public pure override returns (uint64) {
  1797	        if (
  1798	            action == ActionType.ChopWood || action == ActionType.MineIron || action == ActionType.FishDocks
  1799	                || action == ActionType.FishDeepSea || action == ActionType.HarvestWheat
  1800	        ) {
  1801	            return 4;
  1802	        }
  1803	
  1804	        if (action == ActionType.DepositResources) {
  1805	            return DEPOSIT_DURATION_TICKS;
  1806	        }
  1807	
  1808	        if (
  1809	            action == ActionType.BuildWall || action == ActionType.UpgradeBase || action == ActionType.UpgradeMonument
  1810	                || action == ActionType.MarketBuy || action == ActionType.MarketSell

 succeeded in 0ms:
     1	# ClanWorld v4.6 Addendum — Phase 5 Economy Alignment (Path A: as-built canonization)
     2	
     3	**Status:** Authoritative addendum, scoped to Phase 5 gathering / deposit / economy mechanics
     4	**Read order:** This doc supersedes the gathering-yield and economy-rate language in `clanworld_v4_spec.md` §3.10, §4.3–4.13, `clanworld_v4_1_addendum.md` A5–A6, A10, and the economy-related constants in `clanworld_v4_2_state_schema_interface_spec.md` §5. When implementers or UAT runners find disagreement on yield rates, carry caps, or starvation semantics, this doc wins.
     5	**Purpose:** Canonize the as-built Phase 5 batched-action economy as the authoritative Phase 5 ruleset for the hackathon submission, and explicitly enumerate the v4 mechanics that diverged as DEFERRED-TO-RESTORATION.
     6	**Audience:** Reviewers, UAT runners against the contract on World Chain Sepolia / Base Sepolia, future restoration work.
     7	
     8	---
     9	
    10	## 0. Why this doc exists — Path A decision (Liam, 2026-04-30)
    11	
    12	A spec-vs-impl audit by Claude Opus 4.7 (1M ctx) — the "PR #193 spec-compliance UAT" report at [`docs/reviews/pr193-spec-compliance-uat.md`](../reviews/pr193-spec-compliance-uat.md) — confirmed that the Phase 5 economy implementation diverges from the v4 spec on 14 substantial mechanics. The core structural divergence is **action lifecycle**: the v4 spec modeled gathering as a continuous tick-by-tick yield loop ("resolve tick-by-tick until stopped or blocked"); the implementation uses a **batched-action model** where each gather submission yields a single batch (4 ticks of work) and then terminates, requiring a new submission with cooldown.
    13	
    14	Two interpretive paths were available:
    15	
    16	- **Path A (chosen)** — declare the implementation canonical, write this addendum as the new authoritative ruleset, defer the v4-specific mechanics to a post-hackathon restoration milestone.
    17	- **Path B (rejected for hackathon timeline)** — declare the v4 spec canonical, treat the implementation as drift, rewrite the gathering pipeline to continuous per-tick semantics.
    18	
    19	Path A was selected because:
    20	1. The batched-action model is deeply structural — the `getActionDuration / executesAtTick / settlesAtTick` mission shape was locked in Phases 3–4 (merged PRs #181/#183). Phase 5 inherits and extends it; reverting would invalidate downstream phases.
    21	2. The hackathon timeline makes a gathering pipeline rewrite (Path B) untenable — multi-day lift for Phase 5.2–5.4, with regression risk across Phase 6–9.
    22	3. The as-built code is internally consistent and well-tested for its own batched semantics. The multi-round super-swarm and per-issue PR pipeline already validated it.
    23	4. Per-action yield magnitudes (4 ticks × yield_per_tick) are calibrated to the batched duty cycle, and can be rebalanced post-hackathon under restoration without touching architecture.
    24	
    25	This doc canonizes the as-built mechanics. The 14 drift items are tracked as deferred-to-restoration on GH issue [#352](https://github.com/OmniPass-world/clan-world/issues/352) under the `spec-v4-restoration-post-hackathon` GH milestone (#25) for later evaluation.
    26	
    27	---
    28	
    29	## 1. Scope of this addendum
    30	
    31	**In scope:** gathering mechanics (wood, iron, fish, wheat), deposit, carry caps, upkeep, starvation, wheat plot lifecycle, starting vault — as implemented in:
    32	
    33	- `packages/contracts/src/ClanWorld.sol` — gather helpers, `_doDeposit`, `_applyUpkeep`, wheat plot regrow, starvation flag
    34	- `packages/contracts/src/IClanWorld.sol` — economy constants, `Clan` struct vault fields, `WheatPlot` struct, carry fields
    35	- `packages/contracts/test/Gathering.t.sol`, `ClanWorld.t.sol` — codified behavior
    36	
    37	**Out of scope:** all non-economy mechanics. Bandit interactions with vault state (loot value getter — see `clanworld_v4_6_bandit_phase9_redesign.md`), winter mechanics (deferred — §9), market mechanics (Phase 6), deaths (Phase 10), gold/blueprint payouts. The rest of the v4 spec remains canonical unless overridden by a later addendum.
    38	
    39	**Authoritative as of HEAD:** `9b67414f87ab6c83cf848fbe8a8bd7e3dcc03218` (origin/dev-phase-5-economy, the HEAD against which the spec-compliance UAT was run).
    40	
    41	---
    42	
    43	## 2. As-built batched-action lifecycle
    44	
    45	### 2.1 Action model
    46	
    47	The v4 spec (§3.10) described gathering as a **continuous** action: "resolve tick-by-tick until stopped or blocked." The implementation uses a **batched-action model**:
    48	
    49	- Every gather action has `getActionDuration = 4` — the mission `settlesAtTick = actionStartTick + 4`.
    50	- `_settleMissionForClansman` calls `_resolveAction` only when `tick >= settlesAtTick` — i.e., 4 ticks after the action starts.
    51	- At resolution, the gather helper credits `YIELD_PER_TICK × 4` to the clansman's carry in one atomic call, then `_completeMission` terminates the mission.
    52	- The worker transitions to WAITING. To gather again, the Elder must submit a new `ChopWood` (or equivalent) mission, subject to cooldown.
    53	
    54	**There is no continuous per-tick yield loop.** One gather submission = one batch = one settlement.
    55	
    56	### 2.2 Gather mission lifecycle (canonical)
    57	
    58	```
    59	Submit gather order
    60	  → validation: worker reachable + carry not already full + target region correct
    61	  → action stamp: actionStartTick = currentTick, settlesAtTick = currentTick + 4
    62	  → cooldown stamp on submission (A5)
    63	per tick: _settleMissionForClansman runs
    64	  → if tick < settlesAtTick: noop (traveling or waiting for batch to complete)
    65	  → if tick >= settlesAtTick: resolve batch
    66	      → gather helper called once
    67	      → yield = YIELD_PER_TICK × 4 (± crit/RNG modifier per §3)
    68	      → yield clamped to remaining carry capacity
    69	      → if carry already at cap: _completeMission immediately (no yield)
    70	      → carry += yield; emit ResourcesGathered
    71	      → _completeMission → worker WAITING
    72	```
    73	
    74	**After _completeMission:** worker is WAITING at gather region. Elder must travel home + deposit + submit new gather, or submit gather again from the same region (subject to cooldown).
    75	
    76	### 2.3 Deposit lifecycle
    77	
    78	Deposit is a **single-tick action** per spec §3.10 (unchanged by this addendum):
    79	
    80	- `DEPOSIT_DURATION_TICKS = 1`
    81	- Worker must be at own clan's `baseRegion`
    82	- Atomically transfers all 4 carry resources to vault in one settlement
    83	- Empty-carry deposit is a silent no-op (no event emitted)
    84	- `ResourcesDeposited` event emitted on non-empty deposit with per-resource deltas + `atTick`
    85	
    86	### 2.4 Cooldown semantics (A5 unchanged)
    87	
    88	Per `clanworld_v4_1_addendum.md` A5 (unchanged): every successful mission submission starts cooldown (`cooldownEndsAtTs`). This applies to gather + deposit. A clansman whose cooldown is active cannot accept a new mission submission. This means the effective gather duty cycle is: **4 ticks ON + cooldown-period OFF per batch**.
    89	
    90	---
    91	
    92	## 3. Per-action yields — canonical as-built values
    93	
    94	### 3.1 Wood (Forest)
    95	
    96	| Property | As-built canonical | Source |
    97	|---|---|---|
    98	| Base yield per batch | `WOOD_YIELD_PER_TICK × 4 = 1e18 × 4 = 4e18` | `IClanWorld.sol:50, 54`; `ClanWorld.sol:493` |
    99	| Crit chance | `WOOD_CRIT_BPS = 1000` (10%) | `IClanWorld.sol:55` |
   100	| Crit effect | multiply yield × 2 → **8e18 on crit** | `ClanWorld.sol:495-497` |
   101	| RNG domain key | `keccak256(abi.encode("wood_crit", tickSeed, clansmanId, missionNonce, tick))` | `ClanWorld.sol:494` |
   102	| Region | `REGION_FOREST` | — |
   103	
   104	**Ratified design decisions:**
   105	- **Crit shape is ×2 multiplicative** (not +1e18 additive as in v4 §4.7). Rationale: the as-built multiplier is simpler, internally consistent, and already tested. Restoring additive crit is tracked as item #4 in §10.
   106	- **Wood yield per tick is 1e18** (half of v4 spec's 2e18). Yield rate drift is a consequence of the batched model: 1e18/tick × 4-tick batch = 4e18 per submission. Restoration to 2e18/tick per spec is tracked as item #2 in §10.
   107	
   108	### 3.2 Iron (Mountains)
   109	
   110	| Property | As-built canonical | Source |
   111	|---|---|---|
   112	| Base yield per batch | `IRON_YIELD_PER_TICK × 4 = 1.25e17 × 4 = 5e17 = 0.5e18` | `IClanWorld.sol:57-58`; `ClanWorld.sol:524` |
   113	| Gold bonus chance | `GOLD_FROM_IRON_BPS = 200` (2%) | `IClanWorld.sol:59` |
   114	| Gold bonus amount | `GOLD_FROM_IRON_AMOUNT = 1e18` | `IClanWorld.sol:60` |
   115	| Gold bonus roll cadence | **once per batch call** (not once per tick) | `ClanWorld.sol:539-548` |
   116	| RNG domain key | `keccak256(abi.encode("iron_gold_bonus", ...))` | `ClanWorld.sol:543` |
   117	| Region | `REGION_MOUNTAINS` | — |
   118	
   119	**Ratified design decisions:**
   120	- **Gold bonus rolls once per 4-tick batch** (not once per action tick). Sustained gold-bonus opportunity rate = 2% per batch vs spec's 2%/tick. Restoring per-tick roll cadence is tracked as item #6 in §10.
   121	- **Iron per-tick rate is 0.125e18** (¼ of spec's 0.5e18/tick). Restoration tracked as item #5.
   122	
   123	### 3.3 Fish — Docks (West/East Docks)
   124	
   125	| Property | As-built canonical | Source |
   126	|---|---|---|
   127	| Hit chance | `FISH_DOCKS_BPS = 2500` (25%) | `IClanWorld.sol:65` |
   128	| Yield on hit | `FISH_YIELD_PER_TICK × 4 = 25e16 × 4 = 1e18` | `IClanWorld.sol:63`; `ClanWorld.sol:563-578` |
   129	| Yield on miss | 0 | — |
   130	| Roll cadence | **once per batch call** | `ClanWorld.sol:563-578` |
   131	| RNG domain key | `keccak256(abi.encode("fish_roll", ...))` | `ClanWorld.sol:564` |
   132	| Regions | `REGION_WEST_DOCKS`, `REGION_EAST_DOCKS` | — |
   133	
   134	**Sustained expected value per batch:** 25% × 1e18 = 0.25e18 fish per batch.
   135	
   136	**Ratified design decision:** Roll cadence is once per batch (not once per action tick). Restoration tracked as item #7.
   137	
   138	### 3.4 Fish — Deep Sea
   139	
   140	| Property | As-built canonical | Source |
   141	|---|---|---|
   142	| Hit chance | `FISH_DEEP_BPS = 7500` (75%) | `IClanWorld.sol:66` |
   143	| Yield on hit | `FISH_YIELD_PER_TICK × 4 = 25e16 × 4 = 1e18` | `IClanWorld.sol:63`; `ClanWorld.sol:594-609` |
   144	| Yield on miss | 0 | — |
   145	| Roll cadence | once per batch call | `ClanWorld.sol:594-609` |
   146	| RNG domain key | `keccak256(abi.encode("fish_roll", ...))` | `ClanWorld.sol:595` |
   147	| Region | `REGION_DEEP_SEA` | — |
   148	
   149	**Sustained expected value per batch:** 75% × 1e18 = 0.75e18 fish per batch.
   150	
   151	### 3.5 Wheat (West/East Farms)
   152	
   153	| Property | As-built canonical | Source |
   154	|---|---|---|
   155	| Base yield per batch | `WHEAT_YIELD_PER_TICK × 4 = 5e18 × 4 = 20e18` | `IClanWorld.sol:62`; `ClanWorld.sol:646` |
   156	| Regions | `REGION_WEST_FARMS` (plot 0), `REGION_EAST_FARMS` (plot 1) | `ClanWorld.sol:626-637` |
   157	| Plot depletion | yield clamped to `plot.remainingWheat`; plot enters Regrowing when `remainingWheat == 0` | `ClanWorld.sol:648-659` |
   158	
   159	**Ratified design decision:** Wheat per-tick rate is 5e18 (¼ of spec's 20e18/tick per continuous model). Restoration tracked as item #9.
   160	
   161	---
   162	
   163	## 4. Per-resource carry caps — canonical as-built values
   164	
   165	These supersede the carry cap values in `clanworld_v4_spec.md` §4.3 and `clanworld_v4_2_state_schema_interface_spec.md` §5.
   166	
   167	| Resource | Spec value (deprecated) | As-built canonical | Source |
   168	|---|---|---|---|
   169	| Wood | 15e18 | **10e18** (`WOOD_CAP = CLANSMAN_CARRY_CAP = 10e18`) | `IClanWorld.sol:43-44` |
   170	| Iron | 5e18 | **5e18** | `IClanWorld.sol:45` ✅ unchanged |
   171	| Wheat | 40e18 | **40e18** | `IClanWorld.sol:46` ✅ unchanged |
   172	| Fish | 8e18 | **8e18** | `IClanWorld.sol:47` ✅ unchanged |
   173	
   174	**Ratified design decision:** Wood carry cap is **10e18**, not 15e18. `WOOD_CAP` is aliased to the generic `WOOD_CAP = CLANSMAN_CARRY_CAP` constant (10e18). Restoring to spec's 15e18 is tracked as item #10 in §10.
   175	
   176	**Carry enforcement mechanics (unchanged from spec):** each gather helper enforces the per-resource cap independently. Yield is clamped to `cap - currentCarry` if it would overflow. If carry is already at cap when resolution fires, the mission terminates immediately (no yield credited). This matches spec §4.8.
   177	
   178	---
   179	
   180	## 5. Upkeep and starvation semantics
   181	
   182	### 5.1 Per-tick upkeep
   183	
   184	Per living clansman per tick (unchanged from spec):
   185	
   186	| Resource | Rate | Source |
   187	|---|---|---|
   188	| Wheat | `WHEAT_UPKEEP_PER_CLANSMAN = 1e18` | `IClanWorld.sol:69` |
   189	| Fish | `FISH_UPKEEP_PER_CLANSMAN = 1e17` | `IClanWorld.sol:70` |
   190	
   191	Upkeep applies only when `clan.livingClansmen > 0`. If the vault cannot fully satisfy the wheat or fish demand, the respective vault field is drained to 0 (not negative).
   192	
   193	Execution order in `_settleClan` (per tick): `_applyUpkeep` → wheat-plot regrow → per-clansman mission settlement. Upkeep fires before any mission resolution in that tick, which means same-tick deposit cannot rescue that tick's upkeep (A6 compliant).
   194	
   195	### 5.2 Starvation onset — same-tick ratification
   196	
   197	**Ratified design decision:** starvation activates on the **same tick** as the upkeep failure (not the "next tick" specified in v4 §4.11).
   198	
   199	v4 §4.11 states: "If the vault cannot satisfy both wheat and fish demands in full, **starvation status begins on the next tick**." The implementation sets `clan.starvationStartsAtTick = tick` (i.e., the current tick) inside `_applyUpkeep`, and derives `_isStarving = starvationStartsAtTick != 0 && starvationStartsAtTick <= currentTick`. This means `_isStarving == true` at the end of the tick the upkeep fails.
   200	
   201	**Rationale for ratifying same-tick:** simpler state derivation; defenders contributing 0 takes effect immediately on the failure tick (cleaner UX for players — starvation is visible at the tick where it happens, not one tick later). Restoration to next-tick semantics is tracked as item #14 in §10.
   202	
   203	### 5.3 Starvation effects (unchanged from spec, A10)
   204	
   205	While `_isStarving == true`:
   206	
   207	- All gather outputs are reduced by 50% (`yield = yield / 2` applied in wood/iron/fish-docks/fish-deep/wheat helpers before carry assignment)
   208	- Defense contribution = 0 (starving clans are ineligible for `_resolveBanditAttack` defender path)
   209	- No death from starvation outside winter (summer starvation = debuff only, matches A10)
   210	
   211	Note: wheat plot depletion uses the post-halving yield value when calculating `plot.remainingWheat -= yield`, so the plot drains at the same rate as carry accumulation (no double-deduct bug).
   212	
   213	### 5.4 Starvation recovery
   214	
   215	Starvation clears in the same `_applyUpkeep` tick where the vault CAN satisfy both wheat + fish in full: `if (!starving && clan.starvationStartsAtTick != 0) clan.starvationStartsAtTick = 0`. Recovery is immediate (same tick as successful upkeep payment).
   216	
   217	---
   218	
   219	## 6. Wheat plot lifecycle
   220	

exec
/bin/bash -lc "git show HEAD:docs/planning/clanworld_v4_6_phase5_economy_alignment.md | nl -ba | sed -n '221,380p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   221	| State | Condition | Behavior |
   222	|---|---|---|
   223	| `Harvestable` | `remainingWheat > 0` | Clansman can harvest; yield clamped to min(20e18, remainingWheat) per batch |
   224	| `Regrowing` | `remainingWheat == 0` | No harvest; regrow timer: `regrowUntilTick = tick + WHEAT_PLOT_REGROW_TICKS` |
   225	| `WinterLocked` | Winter active (see §9) | **Not wired in impl** — enum value declared, behavior deferred |
   226	
   227	**Regrow → Harvestable:** when `tick >= regrowUntilTick`, the per-tick `_settleClan` loop resets the plot: `state = Harvestable; remainingWheat = 100e18`.
   228	
   229	**Starting state per `mintClan`:** both West and East Farms start `Harvestable` at 100e18.
   230	
   231	`WHEAT_PLOT_REGROW_TICKS` is the canonical regrow duration. Both plots (`targetRegion == REGION_WEST_FARMS` → `plotIdx = 0`, `targetRegion == REGION_EAST_FARMS` → `plotIdx = 1`) follow identical mechanics.
   232	
   233	---
   234	
   235	## 7. Deposit mechanics (unchanged from spec)
   236	
   237	| Property | Value | Source |
   238	|---|---|---|
   239	| Duration | `DEPOSIT_DURATION_TICKS = 1` (single-tick action) | `ClanWorld.sol:77, 1804-1806` |
   240	| Location requirement | worker at own `clan.baseRegion` | `ClanWorld.sol:670-674, 1611-1614` |
   241	| Transfer semantics | all 4 carry resources → vault atomically; carry fields zeroed | `ClanWorld.sol:682-695` |
   242	| Empty-carry behavior | silent no-op, no event | `ClanWorld.sol:675-680` |
   243	| Event | `ResourcesDeposited(clanId, woodDelta, ironDelta, wheatDelta, fishDelta, atTick)` | `IClanWorld.sol:541-549` |
   244	| Error on wrong region | `ERR_NOT_AT_HOMEBASE` | `IClanWorld.sol:171` |
   245	
   246	---
   247	
   248	## 8. Starting vault and gold (§12.4, §12.5 — unchanged from spec)
   249	
   250	| Field | Value | Source |
   251	|---|---|---|
   252	| `vaultWood` | 20e18 | `ClanWorld.sol:1037` |
   253	| `vaultIron` | 0 | `ClanWorld.sol:1038` |
   254	| `vaultWheat` | 20e18 | `ClanWorld.sol:1039` |
   255	| `vaultFish` | 2e18 | `ClanWorld.sol:1040` |
   256	| `goldBalance` | 3e18 | `ClanWorld.sol:1034` |
   257	
   258	---
   259	
   260	## 9. Winter mechanics — deferred (Phase 5.6 / Phase 7)
   261	
   262	The following winter mechanics are declared in constants but **not wired in the implementation**. They are explicitly out of scope for Phase 5B and will be implemented under Phase 5.6 (starvation upkeep) and Phase 7 (winter season):
   263	
   264	| Mechanic | v4 spec rule | Impl status | Constant declared |
   265	|---|---|---|---|
   266	| Winter wheat plot lockdown (§7.4) | plots enter `WinterLocked` at winter start; no harvest | NOT IMPLEMENTED — `_gatherWheat` does not check `winterActive`; `WinterLocked` enum value is dead | `WheatPlotState.WinterLocked` in `IClanWorld.sol:125` |
   267	| Winter upkeep 2× (§7.3) | wheat + fish consumption doubles during winter | NOT IMPLEMENTED — `_applyUpkeep` uses flat rate regardless of `winterActive` | `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` in `IClanWorld.sol` (unused) |
   268	| Winter wood burn (§7.3) | 1e18 wood per base per tick during winter | NOT IMPLEMENTED — `_applyUpkeep` does not touch `vaultWood`; no winter check | `WINTER_WOOD_BURN_PER_BASE = 1e18` in `IClanWorld.sol:71` (unused) |
   269	| WinterLocked → Regrowing at winter end (v4_2 §7.4) | on winter end, locked plots → Regrowing | NOT IMPLEMENTED | — |
   270	
   271	**Behavior during winter (as-built):** Gathering and deposit work exactly as described in §2–§7 above, regardless of whether winter is active. Upkeep rates are flat (non-doubled). Wood burn does not fire.
   272	
   273	---
   274	
   275	## 10. Deferred to v4-restoration milestone (`spec-v4-restoration-post-hackathon`)
   276	
   277	The following 14 drift items are tracked for evaluation under the `spec-v4-restoration-post-hackathon` GH milestone (#25) and the umbrella tracking issue [#352](https://github.com/OmniPass-world/clan-world/issues/352). Restoration is conditional on post-hackathon evaluation.
   278	
   279	| # | v4 spec mechanic | As-built behavior | Restoration cost (rough) |
   280	|---|---|---|---|
   281	| 1 | **Continuous tick-by-tick yield** (§3.10) — gather resolves once per tick, looping until stopped or blocked | Batched: 1 gather submission = 4-tick batch = 1 settlement; mission terminates after each batch | Large — requires reworking the mission lifecycle for gather actions; touches `getActionDuration`, `_resolveAction`, cooldown semantics for continuous actions |
   282	| 2 | **Wood base yield 2e18/tick** (§4.7) — 2e18 per action tick (with continuous model) | 1e18/tick × 4 = 4e18/batch in batched model | Tiny constant change — but only meaningful after item #1 restores continuous model |
   283	| 3 | **Wood crit chance 20%** (§4.7) | `WOOD_CRIT_BPS = 1000` (10%) | Tiny — 1 constant |
   284	| 4 | **Wood crit shape additive +1e18** (§4.7) — crit ADDS +1e18 → total 3e18/tick | Crit DOUBLES yield → 8e18/batch | Small — modify crit branch in `_gatherWood` |
   285	| 5 | **Iron base yield 0.5e18/tick** (§4.7) | 0.125e18/tick × 4 = 0.5e18/batch | Tiny constant — but meaningful only after #1 |
   286	| 6 | **Iron gold bonus per-tick roll** (§4.7) — roll at every action tick | Rolls once per 4-tick batch call | Small — loop the roll or roll once per tick in continuous model |
   287	| 7 | **Fish docks 25%/tick × 1e18** (§4.7) | 25% per batch call × 1e18 | Tiny constant — meaningful after #1 |
   288	| 8 | **Fish deep sea 75%/tick × 1e18** (§4.7) | 75% per batch call × 1e18 | Tiny constant — meaningful after #1 |
   289	| 9 | **Wheat harvest rate 20e18/tick** (§4.9) | 5e18/tick × 4 = 20e18/batch | Tiny constant — meaningful after #1 |
   290	| 10 | **Wood carry cap 15e18** (§4.3) | `WOOD_CAP = CLANSMAN_CARRY_CAP = 10e18` | Tiny — 1 constant in `IClanWorld.sol:43-44` (alias decoupling required) |
   291	| 11 | **Winter wheat plot lockdown** (§7.4) — plots enter `WinterLocked` at winter start; no harvest | `WinterLocked` enum state declared, not wired | Small–Medium — wire winter-start heartbeat to set plot state; add check in `_gatherWheat`; wire winter-end → Regrowing |
   292	| 12 | **Winter upkeep 2× multiplier** (§7.3) — wheat + fish consumption doubles in winter | Flat rate; `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` declared, unused | Small — multiply upkeep by `WINTER_UPKEEP_MULTIPLIER_BPS` when `winterActive` in `_applyUpkeep` |
   293	| 13 | **Winter wood burn 1e18/base/tick** (§7.3) | Not implemented; `WINTER_WOOD_BURN_PER_BASE = 1e18` declared, unused | Small — add wood burn branch in `_applyUpkeep` when `winterActive` |
   294	| 14 | **Starvation onset next-tick** (§4.11) — starvation begins on the tick after upkeep failure | Starvation activates same tick as failure (`starvationStartsAtTick = tick`) | Small — change to `starvationStartsAtTick = tick + 1`; audit consumers for off-by-one |
   295	
   296	Items 11–13 partially overlap with Phase 5.6 (starvation upkeep) and Phase 7 (winter season) scope. Those phases will address them regardless.
   297	
   298	---
   299	
   300	## 11. Constants — as-built canonical values
   301	
   302	These supersede the economy-related constants in `clanworld_v4_2_state_schema_interface_spec.md` §5 for the listed entries.
   303	
   304	| Constant | Spec value (deprecated) | As-built canonical | Source |
   305	|---|---|---|---|
   306	| `WOOD_YIELD_PER_TICK` | 2e18 (implied by continuous) | **1e18** | `IClanWorld.sol:50` |
   307	| `WOOD_CRIT_BONUS` | +1e18 additive | **×2 multiplicative (no separate constant)** | `ClanWorld.sol:495-497` |
   308	| `WOOD_CRIT_BPS` | 2000 (20%) | **1000 (10%)** | `IClanWorld.sol:55` |
   309	| `WOOD_CAP` | 15e18 | **10e18 (= `CLANSMAN_CARRY_CAP`)** | `IClanWorld.sol:43-44` |
   310	| `IRON_YIELD_PER_TICK` | 5e17 (implied by continuous) | **1.25e17** | `IClanWorld.sol:57` |
   311	| `GOLD_FROM_IRON_BPS` | 200 (2%) | **200 (2%)** ✅ unchanged | `IClanWorld.sol:59` |
   312	| `GOLD_FROM_IRON_AMOUNT` | 1e18 | **1e18** ✅ unchanged | `IClanWorld.sol:60` |
   313	| `FISH_DOCKS_BPS` | 2500 (25%) | **2500 (25%)** ✅ unchanged | `IClanWorld.sol:65` |
   314	| `FISH_DEEP_BPS` | 7500 (75%) | **7500 (75%)** ✅ unchanged | `IClanWorld.sol:66` |
   315	| `FISH_YIELD_PER_TICK` | 1e18 (implied by continuous) | **25e16 (= 2.5e17)** | `IClanWorld.sol:63` |
   316	| `WHEAT_YIELD_PER_TICK` | 20e18 (implied by continuous) | **5e18** | `IClanWorld.sol:62` |
   317	| `WHEAT_CAP` | 40e18 | **40e18** ✅ unchanged | `IClanWorld.sol:46` |
   318	| `IRON_CAP` | 5e18 | **5e18** ✅ unchanged | `IClanWorld.sol:45` |
   319	| `FISH_CAP` | 8e18 | **8e18** ✅ unchanged | `IClanWorld.sol:47` |
   320	| `WHEAT_UPKEEP_PER_CLANSMAN` | 1e18 | **1e18** ✅ unchanged | `IClanWorld.sol:69` |
   321	| `FISH_UPKEEP_PER_CLANSMAN` | 1e17 | **1e17** ✅ unchanged | `IClanWorld.sol:70` |
   322	| `WINTER_UPKEEP_MULTIPLIER_BPS` | 20000 (2×) | **20000 (declared, unused — see §9)** | `IClanWorld.sol` |
   323	| `WINTER_WOOD_BURN_PER_BASE` | 1e18 | **1e18 (declared, unused — see §9)** | `IClanWorld.sol:71` |
   324	
   325	---
   326	
   327	## 12. UAT runners — what to expect
   328	
   329	When running interactive UAT against this contract, **expect the as-built mechanics (this addendum), not v4 §3.10 / §4.3–4.13**. Specifically:
   330	
   331	- ✅ Each gather order yields one batch (4 ticks of work) and terminates. Worker enters WAITING. To gather more, submit a new order after cooldown.
   332	- ✅ Wood: 4e18 per batch base, 8e18 on crit (10% chance) — NOT 2e18/tick continuous
   333	- ✅ Iron: 0.5e18 per batch, 2% chance of +1e18 gold bonus per batch — NOT 0.5e18/tick continuous
   334	- ✅ Fish docks: 25% × 1e18 per batch — NOT 25% × 1e18/tick
   335	- ✅ Fish deep sea: 75% × 1e18 per batch — NOT 75% × 1e18/tick
   336	- ✅ Wheat: 20e18 per batch — NOT 20e18/tick continuous
   337	- ✅ Wood carry cap is 10e18 (NOT 15e18)
   338	- ✅ Starvation activates on the SAME TICK as upkeep failure (NOT next tick)
   339	- ✅ Wheat plots remain harvestable during winter (WinterLocked NOT wired)
   340	- ✅ Winter upkeep doubling NOT active; flat upkeep rates apply year-round
   341	- ✅ Winter wood burn NOT active
   342	
   343	If a UAT scenario expects v4-spec continuous yields, per-tick rates, or winter lockdown behavior, it will fail against this contract. Use this addendum as the oracle.
   344	
   345	---
   346	
   347	## 13. References
   348	
   349	- **Spec-compliance UAT report:** [`docs/reviews/pr193-spec-compliance-uat.md`](../reviews/pr193-spec-compliance-uat.md) — full mechanic-by-mechanic table, test-coverage gap analysis, UAT scenario predictions
   350	- **Path A precedent (bandit mechanics):** [`docs/planning/clanworld_v4_6_bandit_phase9_redesign.md`](./clanworld_v4_6_bandit_phase9_redesign.md)
   351	- **Source v4 docs being superseded for economy mechanics:**
   352	  - `clanworld_v4_spec.md` §3.10, §4.3–4.13, §7.3–7.5, §12.4–12.5
   353	  - `clanworld_v4_1_addendum.md` A5, A6, A10
   354	  - `clanworld_v4_2_state_schema_interface_spec.md` §5 (economy constants listed in §11 above)
   355	  - `clanworld_v4_3_schema_patch.md` E (RNG domain keys — fully matched, unchanged), L (starvationStartsAtTick — matched)
   356	- **Implementation HEAD canonized by this addendum:** `9b67414f87ab6c83cf848fbe8a8bd7e3dcc03218`
   357	- **Restoration tracking:** GH milestone `spec-v4-restoration-post-hackathon` (#25) and tracking issue [#352](https://github.com/OmniPass-world/clan-world/issues/352)

exec
/bin/bash -lc 'git diff --stat origin/dev-phase-5b-spec-alignment...HEAD' in /tmp/wt-superswarm-356
 succeeded in 0ms:
 .../clanworld_v4_6_phase5_economy_alignment.md     | 357 +++++++++++++++++++++
 1 file changed, 357 insertions(+)

codex
The cited file:line refs mostly line up against `9b67414f`, and the yield tables are faithful on the main rates. I’m doing a second pass on the trickier assertions now: cooldown timing, winter wording, market/bandit downstream surfaces, and whether any “unchanged from spec” labels accidentally canonize more than intended.
exec
/bin/bash -lc 'git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | rg -n "cooldownEndsAtTs|ERR_COOLDOWN|_completeMission|submit"' in /tmp/wt-superswarm-356
 succeeded in 0ms:
342:                    _completeMission(cs, m);
467:            // Scheduled market actions: already enqueued at submitClanOrders time.
470:            _completeMission(cs, m);
488:            _completeMission(cs, m);
506:            _completeMission(cs, m);
521:            _completeMission(cs, m);
535:            _completeMission(cs, m);
561:            _completeMission(cs, m);
577:            _completeMission(cs, m);
592:            _completeMission(cs, m);
608:            _completeMission(cs, m);
623:            _completeMission(cs, m);
635:            _completeMission(cs, m);
642:            _completeMission(cs, m);
662:            _completeMission(cs, m);
672:            _completeMission(cs, m);
678:            _completeMission(cs, m);
698:        _completeMission(cs, m);
711:            _completeMission(cs, m);
727:        _completeMission(cs, m);
856:    function _completeMission(Clansman storage cs, Mission storage m) internal {
858:        cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
1064:            cs.cooldownEndsAtTs = 0;
1080:    function submitClanOrders(uint32 clanId, ClanOrder[] calldata orders)
1092:        // (_settleClan caps at 200 ticks per call; submitting into a partially-settled clan corrupts invariants)
1102:                        cooldownEndsAtTs: 0,
1165:                result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
1172:        if (block.timestamp < cs.cooldownEndsAtTs) {
1173:            result.status = StatusCode.ERR_COOLDOWN_ACTIVE;
1174:            result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
1231:        cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
1261:        result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
1272:        m.submittedAtTick = _world.currentTick;
1382:            // Note: _completeMission sets m.active=false during settlement (by design), so we
1787:        returns (uint64 submitted, uint64 executes, uint64 settles)
1793:        return (m.submittedAtTick, m.executesAtTick, m.settlesAtTick);

exec
/bin/bash -lc "git show HEAD:docs/planning/clanworld_v4_6_bandit_phase9_redesign.md | nl -ba | sed -n '1,220p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
fatal: path 'docs/planning/clanworld_v4_6_bandit_phase9_redesign.md' does not exist in 'HEAD'

exec
/bin/bash -lc 'git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | rg -n "quoteLootValue|vaultWood|vaultIron|vaultWheat|vaultFish|winterActive|WINTER|Market|price|yield"' in /tmp/wt-superswarm-356
 succeeded in 0ms:
14:    MarketExecutionMode,
23:    ScheduledMarketAction,
36:    MarketState,
60:    mapping(uint64 => ScheduledMarketAction[]) private _scheduledMarketActions; // keyed by tick
92:        // First winter: last WINTER_DURATION_TICKS of first TICKS_PER_WINTER_CYCLE cycle
95:            ClanWorldConstants.TICKS_PER_WINTER_CYCLE - ClanWorldConstants.WINTER_DURATION_TICKS; // = 100
96:        _world.winterEndsAtTick = ClanWorldConstants.TICKS_PER_WINTER_CYCLE; // = 110
97:        _world.winterActive = false;
403:        bool hadEnoughWheat = clan.vaultWheat >= wheatNeeded;
404:        bool hadEnoughFish = clan.vaultFish >= fishNeeded;
407:            clan.vaultWheat -= wheatNeeded;
409:            clan.vaultWheat = 0;
412:            clan.vaultFish -= fishNeeded;
414:            clan.vaultFish = 0;
466:        } else if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
493:        uint256 yield = ClanWorldConstants.WOOD_YIELD_PER_TICK * uint256(getActionDuration(ActionType.ChopWood));
496:            yield *= 2;
499:        if (starving) yield = yield / 2;
500:        if (yield > remaining) yield = remaining;
501:        cs.carryWood += yield;
503:        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.ChopWood, yield, 0, 0, 0, 0, tick);
524:        uint256 yield = ClanWorldConstants.IRON_YIELD_PER_TICK * uint256(getActionDuration(ActionType.MineIron));
525:        if (starving) yield = yield / 2;
526:        if (yield > remaining) yield = remaining;
527:        cs.carryIron += yield;
532:        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.MineIron, 0, yield, 0, 0, goldBonus, tick);
566:        uint256 yield = 0;
568:            yield = ClanWorldConstants.FISH_YIELD_PER_TICK * uint256(getActionDuration(ActionType.FishDocks));
570:        if (starving) yield = yield / 2;
571:        if (yield > remaining) yield = remaining;
572:        if (yield > 0) {
573:            cs.carryFish += yield;
574:            emit ResourcesGathered(clanId, cs.clansmanId, ActionType.FishDocks, 0, 0, 0, yield, 0, tick);
597:        uint256 yield = 0;
599:            yield = ClanWorldConstants.FISH_YIELD_PER_TICK * uint256(getActionDuration(ActionType.FishDeepSea));
601:        if (starving) yield = yield / 2;
602:        if (yield > remaining) yield = remaining;
603:        if (yield > 0) {
604:            cs.carryFish += yield;
605:            emit ResourcesGathered(clanId, cs.clansmanId, ActionType.FishDeepSea, 0, 0, 0, yield, 0, tick);
646:        uint256 yield = ClanWorldConstants.WHEAT_YIELD_PER_TICK * uint256(getActionDuration(ActionType.HarvestWheat));
647:        if (starving) yield = yield / 2;
648:        if (yield > remaining) yield = remaining;
649:        if (yield > plot.remainingWheat) yield = plot.remainingWheat;
651:        cs.carryWheat += yield;
652:        plot.remainingWheat -= yield;
654:        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.HarvestWheat, 0, 0, yield, 0, 0, tick);
687:        clan.vaultWood += woodDelta;
688:        clan.vaultIron += ironDelta;
689:        clan.vaultWheat += wheatDelta;
690:        clan.vaultFish += fishDelta;
754:        if (clan.vaultWood < woodCost || clan.vaultIron < ironCost) return false;
756:        clan.vaultWood -= woodCost;
757:        clan.vaultIron -= ironCost;
790:        if (clan.vaultWood < woodCost || clan.vaultIron < ironCost || clan.vaultWheat < wheatCost) return false;
792:        clan.vaultWood -= woodCost;
793:        clan.vaultIron -= ironCost;
794:        clan.vaultWheat -= wheatCost;
840:            clan.vaultWood < woodCost || clan.vaultWheat < wheatCost || clan.vaultIron < ironCost
844:        clan.vaultWood -= woodCost;
845:        clan.vaultWheat -= wheatCost;
846:        clan.vaultIron -= ironCost;
895:        _executeScheduledMarketActions(closedTick);
946:            _world.winterActive = false;
947:            _world.winterStartsAtTick = _world.seasonStartTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE
948:                - ClanWorldConstants.WINTER_DURATION_TICKS;
949:            _world.winterEndsAtTick = _world.seasonStartTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE;
954:            !_world.winterActive && newTick >= _world.winterStartsAtTick
957:            _world.winterActive = true;
960:        if (_world.winterActive && newTick >= _world.winterEndsAtTick) {
961:            _world.winterActive = false;
964:            uint64 nextWinterStart = _world.winterEndsAtTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE
965:                - ClanWorldConstants.WINTER_DURATION_TICKS;
966:            uint64 nextWinterEnd = _world.winterEndsAtTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE;
1037:        clan.vaultWood = 20e18;
1038:        clan.vaultIron = 0;
1039:        clan.vaultWheat = 20e18;
1040:        clan.vaultFish = 2e18;
1237:        if (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell) {
1238:            _enqueueScheduledMarketAction(clanId, order, cs.clansmanId, ctx.arrivalTick, ctx.newNonce);
1284:        m.marketMode = (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell)
1285:            ? MarketExecutionMode.Scheduled
1286:            : MarketExecutionMode.None;
1293:    function _enqueueScheduledMarketAction(
1300:        ScheduledMarketAction memory sma = ScheduledMarketAction({
1311:        _scheduledMarketActions[executeAtTick].push(sma);
1312:        emit ScheduledMarketActionCommitted(
1364:    function _executeScheduledMarketActions(uint64 tick) internal {
1365:        ScheduledMarketAction[] storage actions = _scheduledMarketActions[tick];
1372:            ScheduledMarketAction storage sma = actions[i];
1377:                emit MarketActionFailed(sma.clanId, sma.clansmanId, sma.action, StatusCode.ERR_INVALID_CLANSMAN);
1386:                emit MarketActionFailed(sma.clanId, sma.clansmanId, sma.action, StatusCode.ERR_INVALID_ACTION);
1390:            if (sma.action == ActionType.MarketSell) {
1391:                try this._executeMarketSellExternal(
1397:                    emit MarketActionFailed(sma.clanId, sma.clansmanId, sma.action, StatusCode.ERR_INVALID_ACTION);
1399:            } else if (sma.action == ActionType.MarketBuy) {
1400:                try this._executeMarketBuyExternal(
1412:                    emit MarketActionFailed(sma.clanId, sma.clansmanId, sma.action, StatusCode.ERR_INVALID_ACTION);
1418:            ScheduledMarketAction[] storage nextActions = _scheduledMarketActions[tick + 1];
1424:            _sortScheduledMarketActionsByCommitSequence(nextActions);
1427:        delete _scheduledMarketActions[tick];
1430:    function _sortScheduledMarketActionsByCommitSequence(ScheduledMarketAction[] storage actions) internal {
1432:            ScheduledMarketAction memory key = actions[i];
1442:    /// @dev External wrapper for _executeMarketSell — enables try/catch from heartbeat loop.
1443:    function _executeMarketSellExternal(
1452:        _executeMarketSell(closedTick, clanId, clansmanId, token, amount, commitSequence);
1455:    /// @dev External wrapper for _executeMarketBuy — enables try/catch from heartbeat loop.
1456:    function _executeMarketBuyExternal(
1466:        _executeMarketBuy(closedTick, clanId, clansmanId, token, amountOut, maxGoldIn, commitSequence);
1481:            clan.vaultWood += amount;
1485:            clan.vaultIron += amount;
1489:            clan.vaultWheat += amount;
1493:            clan.vaultFish += amount;
1501:            if (clan.vaultWood < amount) return false;
1502:            clan.vaultWood -= amount;
1506:            if (clan.vaultIron < amount) return false;
1507:            clan.vaultIron -= amount;
1511:            if (clan.vaultWheat < amount) return false;
1512:            clan.vaultWheat -= amount;
1516:            if (clan.vaultFish < amount) return false;
1517:            clan.vaultFish -= amount;
1524:    function _executeMarketSell(
1533:            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketSell, StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN);
1538:            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketSell, StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN);
1544:            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketSell, StatusCode.ERR_MISSING_RESOURCES);
1551:        emit ScheduledMarketActionExecuted(
1557:    function _executeMarketBuy(
1567:            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketBuy, StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN);
1572:            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketBuy, StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN);
1582:            emit MarketActionFailed(
1583:                clanId, clansmanId, ActionType.MarketBuy, StatusCode.ERR_MARKET_BUY_MAX_GOLD_EXCEEDED
1588:            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketBuy, StatusCode.ERR_NOT_ENOUGH_GOLD);
1597:        emit ScheduledMarketActionExecuted(
1655:        // MarketBuy/MarketSell: must target Unicorn Town
1656:        if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
1673:            // Market orders are always enqueued for the arrivalTick FIFO queue.
1810:                || action == ActionType.MarketBuy || action == ActionType.MarketSell
1849:    function getScheduledMarketActionsForTick(uint64 tick)
1853:        returns (ScheduledMarketAction[] memory)
1855:        return _scheduledMarketActions[tick];
1943:    function quoteLootValueRaw(uint32 clanId) external view override returns (uint256) {
1947:    function quoteLootValueSettled(uint32 clanId) external view override returns (uint256) {
1954:        return clan.vaultWood + clan.vaultWheat + clan.vaultFish * 2 + clan.vaultIron * 4;
1989:            winterActive: _world.winterActive,
2045:    function getMarketState() external view override returns (MarketState memory) {
2046:        return MarketState({
2052:            currentTickQueue: _scheduledMarketActions[_world.currentTick],
2053:            nextTickQueue: _scheduledMarketActions[_world.currentTick + 1]

exec
/bin/bash -lc 'git show HEAD:docs/planning/clanworld_v4_6_bandit_phase9_redesign.md | rg -n "winter|Winter|defer|deferred|quoteLoot|loot|Phase 5|vault"' in /tmp/wt-superswarm-356
 exited 1 in 0ms:
fatal: path 'docs/planning/clanworld_v4_6_bandit_phase9_redesign.md' does not exist in 'HEAD'

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/test/Gathering.t.sol | nl -ba | sed -n '1,220p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
     1	// SPDX-License-Identifier: MIT
     2	pragma solidity ^0.8.34;
     3	
     4	import {Test} from "forge-std/Test.sol";
     5	import {ClanWorld} from "../src/ClanWorld.sol";
     6	import {
     7	    ClanWorldConstants,
     8	    ActionType,
     9	    ClansmanState,
    10	    StatusCode,
    11	    Clansman,
    12	    Mission,
    13	    ClanFullView,
    14	    ClanOrder,
    15	    OrderResult
    16	} from "../src/IClanWorld.sol";
    17	
    18	contract GatheringHarness is ClanWorld {
    19	    function setCarryWood(uint32 csId, uint256 wood) external {
    20	        _clansmen[csId].carryWood = wood;
    21	    }
    22	}
    23	
    24	contract GatheringTest is Test {
    25	    GatheringHarness world;
    26	    address elder = address(0xA1);
    27	
    28	    function setUp() public {
    29	        world = new GatheringHarness();
    30	    }
    31	
    32	    function _advanceTick() internal {
    33	        vm.warp(world.getWorldState().nextHeartbeatAtTs);
    34	        world.heartbeat();
    35	    }
    36	
    37	    function _advanceUntilCurrentTick(uint64 targetTick) internal {
    38	        while (world.getWorldState().currentTick < targetTick) {
    39	            _advanceTick();
    40	        }
    41	    }
    42	
    43	    function _mintClan() internal returns (uint32 clanId) {
    44	        vm.prank(elder);
    45	        (clanId,) = world.mintClan(elder);
    46	    }
    47	
    48	    function _firstCs(uint32 clanId) internal view returns (uint32) {
    49	        ClanFullView memory view_ = world.getClanFullView(clanId);
    50	        return view_.clansmen[0].clansman.clansman.clansmanId;
    51	    }
    52	
    53	    function _submitChopWood(uint32 clanId, uint32 csId) internal returns (OrderResult[] memory) {
    54	        ClanOrder[] memory orders = new ClanOrder[](1);
    55	        orders[0] = ClanOrder({
    56	            clansmanId: csId,
    57	            gotoRegion: ClanWorldConstants.REGION_FOREST,
    58	            action: ActionType.ChopWood,
    59	            targetClanId: 0,
    60	            marketToken: address(0),
    61	            marketAmount: 0,
    62	            maxGoldIn: 0
    63	        });
    64	
    65	        vm.prank(elder);
    66	        return world.submitClanOrders(clanId, orders);
    67	    }
    68	
    69	    function _settleChopWood(uint32 clanId, uint32 csId) internal returns (Clansman memory) {
    70	        OrderResult[] memory result = _submitChopWood(clanId, csId);
    71	        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "chop wood accepted");
    72	
    73	        Mission memory mission = world.getActiveMission(csId);
    74	        _advanceUntilCurrentTick(mission.settlesAtTick + 1);
    75	        world.settleClan(clanId);
    76	        return world.getClansman(csId);
    77	    }
    78	
    79	    function test_chopWoodAtForestYieldsBaseTimesActionDuration() public {
    80	        vm.prevrandao(bytes32(uint256(2)));
    81	        uint32 clanId = _mintClan();
    82	        uint32 csId = _firstCs(clanId);
    83	
    84	        Clansman memory cs = _settleChopWood(clanId, csId);
    85	
    86	        uint256 expected = ClanWorldConstants.WOOD_YIELD_PER_TICK * world.getActionDuration(ActionType.ChopWood);
    87	        assertEq(cs.carryWood, expected, "base wood yield");
    88	    }
    89	
    90	    function test_chopWoodCritDistributionAcrossSeeds() public {
    91	        uint256 baseYield = ClanWorldConstants.WOOD_YIELD_PER_TICK * world.getActionDuration(ActionType.ChopWood);
    92	        uint256 critCount = 0;
    93	        world = new GatheringHarness();
    94	        uint256 cleanState = vm.snapshotState();
    95	
    96	        for (uint256 i = 0; i < 100; i++) {
    97	            assertTrue(vm.revertToState(cleanState), "reset gathering world");
    98	            vm.prevrandao(bytes32(uint256(i + 10_000)));
    99	            uint32 clanId = _mintClan();
   100	            uint32 csId = _firstCs(clanId);
   101	
   102	            Clansman memory cs = _settleChopWood(clanId, csId);
   103	            if (cs.carryWood == baseYield * 2) {
   104	                critCount++;
   105	            } else {
   106	                assertEq(cs.carryWood, baseYield, "non-crit yield");
   107	            }
   108	        }
   109	
   110	        assertGe(critCount, 3, "crit count too low");
   111	        assertLe(critCount, 20, "crit count too high");
   112	    }
   113	
   114	    function test_chopWoodClampsToCarryCap() public {
   115	        uint32 clanId = _mintClan();
   116	        uint32 csId = _firstCs(clanId);
   117	        world.setCarryWood(csId, ClanWorldConstants.CLANSMAN_CARRY_CAP - 1e18);
   118	
   119	        Clansman memory cs = _settleChopWood(clanId, csId);
   120	
   121	        assertEq(cs.carryWood, ClanWorldConstants.CLANSMAN_CARRY_CAP, "wood carry cap");
   122	    }
   123	
   124	    function test_chopWoodAppliesCooldownPostSettle() public {
   125	        uint32 clanId = _mintClan();
   126	        uint32 csId = _firstCs(clanId);
   127	
   128	        Clansman memory cs = _settleChopWood(clanId, csId);
   129	
   130	        assertEq(uint8(cs.state), uint8(ClansmanState.WAITING), "mission completed");
   131	        assertFalse(world.getActiveMission(csId).active, "mission inactive");
   132	        assertGt(cs.cooldownEndsAtTs, block.timestamp, "cooldown starts on settlement");
   133	    }
   134	
   135	    // -------------------------------------------------------------------------
   136	    // Per-tick yield parity tests (H2): confirm per-tick constants × duration
   137	    // produce the same per-call totals as the old flat yields.
   138	    // -------------------------------------------------------------------------
   139	
   140	    function _submitOrder(uint32 clanId, uint32 csId, uint8 region, ActionType action)
   141	        internal
   142	        returns (OrderResult[] memory)
   143	    {
   144	        ClanOrder[] memory orders = new ClanOrder[](1);
   145	        orders[0] = ClanOrder({
   146	            clansmanId: csId,
   147	            gotoRegion: region,
   148	            action: action,
   149	            targetClanId: 0,
   150	            marketToken: address(0),
   151	            marketAmount: 0,
   152	            maxGoldIn: 0
   153	        });
   154	        vm.prank(elder);
   155	        return world.submitClanOrders(clanId, orders);
   156	    }
   157	
   158	    function _settleOrder(uint32 clanId, uint32 csId, uint8 region, ActionType action)
   159	        internal
   160	        returns (Clansman memory)
   161	    {
   162	        OrderResult[] memory result = _submitOrder(clanId, csId, region, action);
   163	        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "order accepted");
   164	        Mission memory mission = world.getActiveMission(csId);
   165	        _advanceUntilCurrentTick(mission.settlesAtTick + 1);
   166	        world.settleClan(clanId);
   167	        return world.getClansman(csId);
   168	    }
   169	
   170	    // Iron: IRON_YIELD_PER_TICK * duration = IRON_BASE_YIELD = 5e17
   171	    function test_mineIronYieldsIronBaseYield() public {
   172	        // Use prevrandao that avoids gold-bonus path (or just check carryIron)
   173	        vm.prevrandao(bytes32(uint256(1)));
   174	        uint32 clanId = _mintClan();
   175	        uint32 csId = _firstCs(clanId);
   176	
   177	        Clansman memory cs = _settleOrder(clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);
   178	
   179	        uint256 expectedYield =
   180	            ClanWorldConstants.IRON_YIELD_PER_TICK * uint256(world.getActionDuration(ActionType.MineIron));
   181	        assertEq(expectedYield, ClanWorldConstants.IRON_BASE_YIELD, "constant parity: per-tick*duration == base");
   182	        assertEq(cs.carryIron, expectedYield, "iron yield equals IRON_BASE_YIELD");
   183	    }
   184	
   185	    // Fish (docks): when roll succeeds, yield = FISH_YIELD_PER_TICK * duration = 1e18
   186	    function test_fishDocksYieldsOneEther_onSuccessfulRoll() public {
   187	        // prevrandao 1 → fishRoll = keccak256("fish_roll",...) % 10000 < 2500 (25%)
   188	        // Try multiple seeds until we get a hit
   189	        uint256 cleanState = vm.snapshotState();
   190	        bool hit = false;
   191	        for (uint256 seed = 1; seed < 100; seed++) {
   192	            vm.revertToState(cleanState);
   193	            vm.prevrandao(bytes32(seed));
   194	            uint32 clanId = _mintClan();
   195	            uint32 csId = _firstCs(clanId);
   196	            Clansman memory cs =
   197	                _settleOrder(clanId, csId, ClanWorldConstants.REGION_WEST_DOCKS, ActionType.FishDocks);
   198	            if (cs.carryFish > 0) {
   199	                uint256 expectedYield =
   200	                    ClanWorldConstants.FISH_YIELD_PER_TICK * uint256(world.getActionDuration(ActionType.FishDocks));
   201	                assertEq(expectedYield, 1e18, "constant parity: per-tick*duration == 1e18");
   202	                assertEq(cs.carryFish, expectedYield, "fish docks yield equals 1e18 on success");
   203	                hit = true;
   204	                break;
   205	            }
   206	        }
   207	        assertTrue(hit, "did not get a fish roll hit in 100 seeds");
   208	    }
   209	}

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '850,865p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   850	        clan.monumentLevel = nextLevel;
   851	        emit MonumentLevelChanged(clanId, old, nextLevel, tick);
   852	        return true;
   853	    }
   854	
   855	    /// @dev Complete a mission: set worker to WAITING, set cooldown, mark mission inactive, emit event.
   856	    function _completeMission(Clansman storage cs, Mission storage m) internal {
   857	        cs.state = ClansmanState.WAITING;
   858	        cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
   859	        m.active = false;
   860	        emit MissionCompleted(_clans[cs.clanId].clanId, cs.clansmanId, m.nonce, m.action);
   861	    }
   862	
   863	    // =========================================================================
   864	    // WORLD PROGRESSION
   865	    // =========================================================================

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '1080,1275p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
  1080	    function submitClanOrders(uint32 clanId, ClanOrder[] calldata orders)
  1081	        external
  1082	        override
  1083	        nonReentrant
  1084	        returns (OrderResult[] memory results)
  1085	    {
  1086	        Clan storage clan = _clans[clanId];
  1087	        require(clan.clanId != 0, "ClanWorld: clan not found");
  1088	        require(clan.owner == msg.sender, "ClanWorld: not clan owner");
  1089	        require(clan.clanState == ClanState.ACTIVE, "ClanWorld: clan dead");
  1090	
  1091	        // Guard: if clan is more than 200 ticks behind, caller must call settleClan() first
  1092	        // (_settleClan caps at 200 ticks per call; submitting into a partially-settled clan corrupts invariants)
  1093	        // ERR_MUST_SETTLE_FIRST not in StatusCode enum — using ERR_INVALID_ACTION as the closest proxy
  1094	        {
  1095	            uint64 lastSettled = _clans[clanId].lastSettledTick;
  1096	            if (_world.currentTick > lastSettled + 200) {
  1097	                results = new OrderResult[](orders.length);
  1098	                for (uint256 i = 0; i < orders.length; i++) {
  1099	                    results[i] = OrderResult({
  1100	                        clansmanId: orders[i].clansmanId,
  1101	                        status: StatusCode.ERR_INVALID_ACTION,
  1102	                        cooldownEndsAtTs: 0,
  1103	                        missionNonce: 0
  1104	                    });
  1105	                }
  1106	                return results;
  1107	            }
  1108	        }
  1109	
  1110	        // Lazy settle before processing orders
  1111	        _settleClan(clanId);
  1112	
  1113	        results = new OrderResult[](orders.length);
  1114	
  1115	        for (uint256 i = 0; i < orders.length; i++) {
  1116	            results[i] = _processOrder(clanId, clan, orders[i]);
  1117	        }
  1118	
  1119	        return results;
  1120	    }
  1121	
  1122	    struct OrderCtx {
  1123	        uint8 gotoRegion;
  1124	        uint8 fromRegion;
  1125	        bool isNoop;
  1126	        uint8 travelTicks;
  1127	        uint64 arrivalTick;
  1128	        uint64 newNonce;
  1129	        uint32 targetClanId;
  1130	        bool wasActive;
  1131	        uint64 oldNonce;
  1132	    }
  1133	
  1134	    function _processOrder(uint32 clanId, Clan storage clan, ClanOrder calldata order)
  1135	        internal
  1136	        returns (OrderResult memory result)
  1137	    {
  1138	        result.clansmanId = order.clansmanId;
  1139	
  1140	        // Validate clansman
  1141	        Clansman storage cs = _clansmen[order.clansmanId];
  1142	        if (cs.clansmanId == 0 || cs.clanId != clanId) {
  1143	            result.status = StatusCode.ERR_INVALID_CLANSMAN;
  1144	            return result;
  1145	        }
  1146	        if (cs.state == ClansmanState.DEAD) {
  1147	            result.status = StatusCode.ERR_CLANSMAN_DEAD;
  1148	            return result;
  1149	        }
  1150	
  1151	        if (order.action == ActionType.DefendBase) {
  1152	            StatusCode defendErr = _validateDefendBaseOrder(clan, order, order.gotoRegion);
  1153	            if (defendErr != StatusCode.OK) {
  1154	                result.status = defendErr;
  1155	                return result;
  1156	            }
  1157	
  1158	            uint32 defendTargetClanId = order.targetClanId == 0 ? clanId : order.targetClanId;
  1159	            Mission storage currentM = _missions[order.clansmanId];
  1160	            if (
  1161	                currentM.active && currentM.action == ActionType.DefendBase && currentM.targetRegion == order.gotoRegion
  1162	                    && currentM.targetClanId == defendTargetClanId
  1163	            ) {
  1164	                result.status = StatusCode.OK;
  1165	                result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
  1166	                result.missionNonce = currentM.nonce;
  1167	                return result;
  1168	            }
  1169	        }
  1170	
  1171	        // Cooldown check
  1172	        if (block.timestamp < cs.cooldownEndsAtTs) {
  1173	            result.status = StatusCode.ERR_COOLDOWN_ACTIVE;
  1174	            result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
  1175	            result.missionNonce = cs.lastMissionNonce;
  1176	            return result;
  1177	        }
  1178	
  1179	        OrderCtx memory ctx;
  1180	        ctx.fromRegion = cs.currentRegion;
  1181	        ctx.gotoRegion = order.gotoRegion;
  1182	        ctx.targetClanId =
  1183	            order.action == ActionType.DefendBase && order.targetClanId == 0 ? clanId : order.targetClanId;
  1184	
  1185	        // NOOP bypass: treat 0 as "stay here"; DefendBase requires explicit home region.
  1186	        ctx.isNoop = order.action != ActionType.DefendBase
  1187	            && (ctx.gotoRegion == ClanWorldConstants.REGION_NOOP || ctx.gotoRegion == ctx.fromRegion);
  1188	        if (ctx.isNoop) {
  1189	            ctx.gotoRegion = ctx.fromRegion;
  1190	        }
  1191	
  1192	        // Validate target region (1-8 or 0=noop)
  1193	        if (ctx.gotoRegion > 8) {
  1194	            result.status = StatusCode.ERR_INVALID_REGION;
  1195	            return result;
  1196	        }
  1197	
  1198	        // Validate action
  1199	        StatusCode actionErr = _validateAction(clan, cs, order, ctx.gotoRegion);
  1200	        if (actionErr != StatusCode.OK) {
  1201	            result.status = actionErr;
  1202	            return result;
  1203	        }
  1204	
  1205	        // Capture existing mission state
  1206	        Mission storage existingM = _missions[order.clansmanId];
  1207	        ctx.wasActive = existingM.active;
  1208	        ctx.oldNonce = existingM.nonce;
  1209	
  1210	        // Compute travel from the clansman's current region to the order target.
  1211	        ctx.travelTicks = _travelTicks(ctx.fromRegion, ctx.gotoRegion);
  1212	        ctx.arrivalTick = _addTicksClamped(_world.currentTick, uint64(ctx.travelTicks));
  1213	
  1214	        // New nonce
  1215	        ctx.newNonce = cs.lastMissionNonce + 1;
  1216	        cs.lastMissionNonce = ctx.newNonce;
  1217	
  1218	        // Install mission via helper to keep stack shallow
  1219	        _installMission(existingM, order, cs, ctx);
  1220	
  1221	        // Update clansman state
  1222	        if (ctx.travelTicks > 0) {
  1223	            cs.state = ClansmanState.TRAVELING;
  1224	        } else {
  1225	            // NOOP / same-region: no traveling state per v4.3 §A
  1226	            cs.state = ClansmanState.ACTING;
  1227	            cs.currentRegion = ctx.gotoRegion;
  1228	        }
  1229	
  1230	        // Start cooldown
  1231	        cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
  1232	
  1233	        _clearDefender(cs.clansmanId);
  1234	
  1235	        // v4.2 §8 L758: "executes at heartbeat closing tick T" where T = arrivalTick.
  1236	        // executeAtTick = arrivalTick (not arrivalTick+1).
  1237	        if (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell) {
  1238	            _enqueueScheduledMarketAction(clanId, order, cs.clansmanId, ctx.arrivalTick, ctx.newNonce);
  1239	        }
  1240	
  1241	        if (order.action == ActionType.DefendBase && ctx.travelTicks == 0) {
  1242	            _registerDefender(ctx.gotoRegion, clanId, cs.clansmanId);
  1243	        }
  1244	
  1245	        if (ctx.wasActive) {
  1246	            emit MissionInterrupted(clanId, order.clansmanId, ctx.oldNonce, ctx.newNonce);
  1247	        }
  1248	
  1249	        emit MissionAssigned(
  1250	            clanId,
  1251	            order.clansmanId,
  1252	            ctx.newNonce,
  1253	            order.action,
  1254	            ctx.fromRegion,
  1255	            ctx.gotoRegion,
  1256	            _world.currentTick,
  1257	            ctx.arrivalTick
  1258	        );
  1259	
  1260	        result.status = StatusCode.OK;
  1261	        result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
  1262	        result.missionNonce = ctx.newNonce;
  1263	        return result;
  1264	    }
  1265	
  1266	    function _installMission(Mission storage m, ClanOrder calldata order, Clansman storage cs, OrderCtx memory ctx)
  1267	        internal
  1268	    {
  1269	        m.active = true;
  1270	        m.nonce = ctx.newNonce;
  1271	        m.clansmanId = cs.clansmanId;
  1272	        m.submittedAtTick = _world.currentTick;
  1273	        m.executesAtTick = ctx.arrivalTick;
  1274	        m.settlesAtTick = order.action == ActionType.DefendBase
  1275	            ? type(uint64).max

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '1938,1958p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
  1938	        }
  1939	        travelTicks = _travelTicks(srcRegion, dstRegion);
  1940	        path = _buildPath(srcRegion, dstRegion);
  1941	    }
  1942	
  1943	    function quoteLootValueRaw(uint32 clanId) external view override returns (uint256) {
  1944	        return _lootValueRaw(_clans[clanId]);
  1945	    }
  1946	
  1947	    function quoteLootValueSettled(uint32 clanId) external view override returns (uint256) {
  1948	        // Phase 1: return raw value (no simulation)
  1949	        return _lootValueRaw(_clans[clanId]);
  1950	    }
  1951	
  1952	    /// @dev Compute loot value per v4 spec §6.9: wood=1, wheat=1, fish=2, iron=4 points.
  1953	    function _lootValueRaw(Clan memory clan) internal pure returns (uint256) {
  1954	        return clan.vaultWood + clan.vaultWheat + clan.vaultFish * 2 + clan.vaultIron * 4;
  1955	    }
  1956	
  1957	    // =========================================================================
  1958	    // UI INDEXER AGGREGATOR GETTERS

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '932,970p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   932	        }
   933	    }
   934	
   935	    /// @dev Resolve world events for the tick that was just closed.
   936	    ///      Uses closedTick+1 as the equivalent of the old `newTick` for transition checks.
   937	    function _resolveWorldEvents(uint64 closedTick) internal {
   938	        uint64 newTick = closedTick + 1;
   939	
   940	        // --- season boundary ---
   941	        if (newTick >= _world.seasonEndTick) {
   942	            _world.currentSeasonNumber += 1;
   943	            _world.seasonStartTick = _world.seasonEndTick;
   944	            _world.seasonEndTick = _world.seasonStartTick + ClanWorldConstants.SEASON_DURATION_TICKS;
   945	            // reset winter timers for new season
   946	            _world.winterActive = false;
   947	            _world.winterStartsAtTick = _world.seasonStartTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE
   948	                - ClanWorldConstants.WINTER_DURATION_TICKS;
   949	            _world.winterEndsAtTick = _world.seasonStartTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE;
   950	        }
   951	
   952	        // --- winter transitions (timer only; mechanics = Phase 10) ---
   953	        if (
   954	            !_world.winterActive && newTick >= _world.winterStartsAtTick
   955	                && _world.winterStartsAtTick < _world.seasonEndTick
   956	        ) {
   957	            _world.winterActive = true;
   958	            emit WinterStarted(newTick);
   959	        }
   960	        if (_world.winterActive && newTick >= _world.winterEndsAtTick) {
   961	            _world.winterActive = false;
   962	            emit WinterEnded(newTick);
   963	            // schedule next winter cycle within this season
   964	            uint64 nextWinterStart = _world.winterEndsAtTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE
   965	                - ClanWorldConstants.WINTER_DURATION_TICKS;
   966	            uint64 nextWinterEnd = _world.winterEndsAtTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE;
   967	            if (nextWinterStart < _world.seasonEndTick) {
   968	                _world.winterStartsAtTick = nextWinterStart;
   969	                _world.winterEndsAtTick = nextWinterEnd;
   970	            } else {

exec
/bin/bash -lc "git ls-tree -r --name-only HEAD docs/planning | rg 'bandit|phase9|v4_6'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
docs/planning/clanworld_v4_6_phase5_economy_alignment.md

exec
/bin/bash -lc "git branch -r | rg '341|bandit|phase9|dev-phase-9|pr'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
  origin/dev-phase-4-heartbeat-progression
  origin/dev-phase-9-bandits
  origin/docs/spec-v4-6-bandit-redesign
  origin/feat/issue-206-phase9-eager-settle
  origin/feat/issue-207-phase9-attack-resolution
  origin/feat/issue-208-phase9-defender-split
  origin/feat/issue-209-phase9-blueprint-reward
  origin/feat/issue-210-phase9-cleanup
  origin/feat/issue-225-phase7-blueprint-transfer
  origin/fix/issue-264-phase9-cloud-review
  origin/fix/pr194-r2-super-swarm-fixes
  origin/fix/pr198-r3-wheelbarrow-and-sell-validation
  origin/fix/pr199-r2-phase8-super-swarm-fixes
  origin/fix/pr199-r4-super-swarm-fixes
  origin/fix/pr199-r7-sim-parity-and-abi-drift
  origin/fix/pr200-r2-otc-cloud-findings
  origin/fix/pr200-r3-stale-otc-and-expiry-type
  origin/fix/pr250-r2-phase10-super-swarm-fixes
  origin/fix/pr250-r3-cold-reset-regression-and-cloud-findings
  origin/fix/pr250-r4-getclanfullview-and-cold-rng-and-stale-storage

exec
/bin/bash -lc "git for-each-ref --format='%(refname:short)' refs/remotes refs/heads | rg 'bandit|phase9|341|v4_6'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
dev-phase-9-bandits
docs/spec-v4-6-bandit-redesign
feat/issue-186-bandit-state-machine
feat/issue-187-bandit-spawn
feat/issue-206-phase9-eager-settle
feat/issue-207-phase9-attack-resolution
feat/issue-208-phase9-defender-split
feat/issue-209-phase9-blueprint-reward
feat/issue-210-phase9-cleanup
fix/issue-264-phase9-cloud-review
style/bandit-archetype-sprites
style/canvas-responsive-scoreboard-bandit
origin/dev-phase-9-bandits
origin/docs/spec-v4-6-bandit-redesign
origin/feat/issue-206-phase9-eager-settle
origin/feat/issue-207-phase9-attack-resolution
origin/feat/issue-208-phase9-defender-split
origin/feat/issue-209-phase9-blueprint-reward
origin/feat/issue-210-phase9-cleanup
origin/fix/issue-264-phase9-cloud-review

exec
/bin/bash -lc 'rg -n "bandit_phase9|v4_6_bandit|WinterLocked|winter mechanics|quoteLootValue" docs packages | head -80' in /tmp/wt-superswarm-356
exec
/bin/bash -lc "git log --all --name-only --pretty=format: | rg 'clanworld_v4_6_bandit_phase9_redesign.md|bandit_phase9'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
docs/planning/clanworld_v4_6_bandit_phase9_redesign.md

 succeeded in 0ms:
docs/planning/clanworld_numbered_implementation_plan.md:84:- `quoteLootValueRaw`
docs/planning/clanworld_numbered_implementation_plan.md:85:- `quoteLootValueSettled`
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:417:- at winter start: plots enter `WinterLocked`
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:418:- at winter end: `WinterLocked -> Regrowing`
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:622:function quoteLootValue(uint32 clanId) external view returns (uint256 lootValue);
docs/planning/clanworld_v4_3_schema_patch.md:197:- `quoteLootValueRaw(clanId)`
docs/planning/clanworld_v4_3_schema_patch.md:198:- `quoteLootValueSettled(clanId)`
docs/planning/clanworld_v4_3_schema_patch.md:201:`quoteLootValueRaw(clanId)`:
docs/planning/clanworld_v4_3_schema_patch.md:207:`quoteLootValueSettled(clanId)`:
docs/planning/clanworld_v4_4_ui_indexer_getters.md:74:    uint256 lootValue;     // settled to current tick (uses quoteLootValueSettled)
docs/planning/clanworld_v4_4_ui_indexer_getters.md:82:- `lootValue` should call the v4.3 `quoteLootValueSettled` path
docs/planning/clanworld_v4_4_ui_indexer_getters.md:231:Per v4.3 §J ("Derived Getter Non-Mutation Rule"), none of these functions may mutate storage. They must simulate settlement using the same read-only path as `getDerivedClanState` and `quoteLootValueSettled`.
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:37:**Out of scope:** all non-economy mechanics. Bandit interactions with vault state (loot value getter — see `clanworld_v4_6_bandit_phase9_redesign.md`), winter mechanics (deferred — §9), market mechanics (Phase 6), deaths (Phase 10), gold/blueprint payouts. The rest of the v4 spec remains canonical unless overridden by a later addendum.
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:225:| `WinterLocked` | Winter active (see §9) | **Not wired in impl** — enum value declared, behavior deferred |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:262:The following winter mechanics are declared in constants but **not wired in the implementation**. They are explicitly out of scope for Phase 5B and will be implemented under Phase 5.6 (starvation upkeep) and Phase 7 (winter season):
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:266:| Winter wheat plot lockdown (§7.4) | plots enter `WinterLocked` at winter start; no harvest | NOT IMPLEMENTED — `_gatherWheat` does not check `winterActive`; `WinterLocked` enum value is dead | `WheatPlotState.WinterLocked` in `IClanWorld.sol:125` |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:269:| WinterLocked → Regrowing at winter end (v4_2 §7.4) | on winter end, locked plots → Regrowing | NOT IMPLEMENTED | — |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:291:| 11 | **Winter wheat plot lockdown** (§7.4) — plots enter `WinterLocked` at winter start; no harvest | `WinterLocked` enum state declared, not wired | Small–Medium — wire winter-start heartbeat to set plot state; add check in `_gatherWheat`; wire winter-end → Regrowing |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:339:- ✅ Wheat plots remain harvestable during winter (WinterLocked NOT wired)
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:350:- **Path A precedent (bandit mechanics):** [`docs/planning/clanworld_v4_6_bandit_phase9_redesign.md`](./clanworld_v4_6_bandit_phase9_redesign.md)
packages/contracts/abi/IClanWorld.json:1:{"abi":[{"type":"function","name":"finalizeSeason","inputs":[],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"getActionDuration","inputs":[{"name":"action","type":"uint8","internalType":"enum ActionType"}],"outputs":[{"name":"","type":"uint64","internalType":"uint64"}],"stateMutability":"pure"},{"type":"function","name":"getActiveBanditView","inputs":[],"outputs":[{"name":"","type":"tuple","internalType":"struct ActiveBanditView","components":[{"name":"exists","type":"bool","internalType":"bool"},{"name":"banditId","type":"uint32","internalType":"uint32"},{"name":"state","type":"uint8","internalType":"enum BanditState"},{"name":"currentRegion","type":"uint8","internalType":"uint8"},{"name":"attackAttemptsMade","type":"uint8","internalType":"uint8"},{"name":"maxAttemptsRemaining","type":"uint8","internalType":"uint8"},{"name":"stateEnteredTick","type":"uint64","internalType":"uint64"},{"name":"nextActionTick","type":"uint64","internalType":"uint64"},{"name":"tier","type":"uint8","internalType":"uint8"},{"name":"attackPower","type":"uint16","internalType":"uint16"},{"name":"carryWood","type":"uint256","internalType":"uint256"},{"name":"carryIron","type":"uint256","internalType":"uint256"},{"name":"carryWheat","type":"uint256","internalType":"uint256"},{"name":"carryFish","type":"uint256","internalType":"uint256"},{"name":"projectedTargetClanId","type":"uint32","internalType":"uint32"},{"name":"projectedTargetLootValue","type":"uint256","internalType":"uint256"}]}],"stateMutability":"view"},{"type":"function","name":"getActiveDefenders","inputs":[{"name":"targetClanId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"clansmanIds","type":"uint32[]","internalType":"uint32[]"}],"stateMutability":"view"},{"type":"function","name":"getActiveMission","inputs":[{"name":"clansmanId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"","type":"tuple","internalType":"struct Mission","components":[{"name":"active","type":"bool","internalType":"bool"},{"name":"nonce","type":"uint64","internalType":"uint64"},{"name":"submittedAtTick","type":"uint64","internalType":"uint64"},{"name":"executesAtTick","type":"uint64","internalType":"uint64"},{"name":"settlesAtTick","type":"uint64","internalType":"uint64"},{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"startRegion","type":"uint8","internalType":"uint8"},{"name":"targetRegion","type":"uint8","internalType":"uint8"},{"name":"action","type":"uint8","internalType":"enum ActionType"},{"name":"startTick","type":"uint64","internalType":"uint64"},{"name":"arrivalTick","type":"uint64","internalType":"uint64"},{"name":"actionStartTick","type":"uint64","internalType":"uint64"},{"name":"missionSeed","type":"bytes32","internalType":"bytes32"},{"name":"marketMode","type":"uint8","internalType":"enum MarketExecutionMode"},{"name":"targetClanId","type":"uint32","internalType":"uint32"},{"name":"marketToken","type":"address","internalType":"address"},{"name":"marketAmount","type":"uint256","internalType":"uint256"},{"name":"maxGoldIn","type":"uint256","internalType":"uint256"}]}],"stateMutability":"view"},{"type":"function","name":"getBanditTargetPreview","inputs":[{"name":"banditId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"previewClanId","type":"uint32","internalType":"uint32"}],"stateMutability":"view"},{"type":"function","name":"getBanditTroop","inputs":[{"name":"banditId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"","type":"tuple","internalType":"struct BanditTroop","components":[{"name":"banditId","type":"uint32","internalType":"uint32"},{"name":"state","type":"uint8","internalType":"enum BanditState"},{"name":"currentRegion","type":"uint8","internalType":"uint8"},{"name":"attackAttemptsMade","type":"uint8","internalType":"uint8"},{"name":"stateEnteredTick","type":"uint64","internalType":"uint64"},{"name":"nextActionTick","type":"uint64","internalType":"uint64"},{"name":"tier","type":"uint8","internalType":"uint8"},{"name":"attackPower","type":"uint16","internalType":"uint16"},{"name":"carryWood","type":"uint256","internalType":"uint256"},{"name":"carryIron","type":"uint256","internalType":"uint256"},{"name":"carryWheat","type":"uint256","internalType":"uint256"},{"name":"carryFish","type":"uint256","internalType":"uint256"}]}],"stateMutability":"view"},{"type":"function","name":"getClan","inputs":[{"name":"clanId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"","type":"tuple","internalType":"struct Clan","components":[{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"iftTokenId","type":"uint256","internalType":"uint256"},{"name":"owner","type":"address","internalType":"address"},{"name":"clanState","type":"uint8","internalType":"enum ClanState"},{"name":"baseRegion","type":"uint8","internalType":"uint8"},{"name":"baseLevel","type":"uint8","internalType":"uint8"},{"name":"wallLevel","type":"uint8","internalType":"uint8"},{"name":"monumentLevel","type":"uint8","internalType":"uint8"},{"name":"livingClansmen","type":"uint8","internalType":"uint8"},{"name":"lastSettledTick","type":"uint64","internalType":"uint64"},{"name":"starvationStartsAtTick","type":"uint64","internalType":"uint64"},{"name":"coldDamage","type":"uint16","internalType":"uint16"},{"name":"goldBalance","type":"uint256","internalType":"uint256"},{"name":"blueprintBalance","type":"uint256","internalType":"uint256"},{"name":"vaultWood","type":"uint256","internalType":"uint256"},{"name":"vaultIron","type":"uint256","internalType":"uint256"},{"name":"vaultWheat","type":"uint256","internalType":"uint256"},{"name":"vaultFish","type":"uint256","internalType":"uint256"}]}],"stateMutability":"view"},{"type":"function","name":"getClanFullView","inputs":[{"name":"clanId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"","type":"tuple","internalType":"struct ClanFullView","components":[{"name":"clan","type":"tuple","internalType":"struct DerivedClanState","components":[{"name":"clan","type":"tuple","internalType":"struct Clan","components":[{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"iftTokenId","type":"uint256","internalType":"uint256"},{"name":"owner","type":"address","internalType":"address"},{"name":"clanState","type":"uint8","internalType":"enum ClanState"},{"name":"baseRegion","type":"uint8","internalType":"uint8"},{"name":"baseLevel","type":"uint8","internalType":"uint8"},{"name":"wallLevel","type":"uint8","internalType":"uint8"},{"name":"monumentLevel","type":"uint8","internalType":"uint8"},{"name":"livingClansmen","type":"uint8","internalType":"uint8"},{"name":"lastSettledTick","type":"uint64","internalType":"uint64"},{"name":"starvationStartsAtTick","type":"uint64","internalType":"uint64"},{"name":"coldDamage","type":"uint16","internalType":"uint16"},{"name":"goldBalance","type":"uint256","internalType":"uint256"},{"name":"blueprintBalance","type":"uint256","internalType":"uint256"},{"name":"vaultWood","type":"uint256","internalType":"uint256"},{"name":"vaultIron","type":"uint256","internalType":"uint256"},{"name":"vaultWheat","type":"uint256","internalType":"uint256"},{"name":"vaultFish","type":"uint256","internalType":"uint256"}]},{"name":"isStarving","type":"bool","internalType":"bool"},{"name":"lootValue","type":"uint256","internalType":"uint256"},{"name":"derivedAtTick","type":"uint64","internalType":"uint64"}]},{"name":"clansmen","type":"tuple[]","internalType":"struct ClansmanFullView[]","components":[{"name":"clansman","type":"tuple","internalType":"struct DerivedClansmanState","components":[{"name":"clansman","type":"tuple","internalType":"struct Clansman","components":[{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"state","type":"uint8","internalType":"enum ClansmanState"},{"name":"currentRegion","type":"uint8","internalType":"uint8"},{"name":"cooldownEndsAtTs","type":"uint64","internalType":"uint64"},{"name":"lastMissionNonce","type":"uint64","internalType":"uint64"},{"name":"carryWood","type":"uint256","internalType":"uint256"},{"name":"carryIron","type":"uint256","internalType":"uint256"},{"name":"carryWheat","type":"uint256","internalType":"uint256"},{"name":"carryFish","type":"uint256","internalType":"uint256"}]},{"name":"activeMission","type":"tuple","internalType":"struct Mission","components":[{"name":"active","type":"bool","internalType":"bool"},{"name":"nonce","type":"uint64","internalType":"uint64"},{"name":"submittedAtTick","type":"uint64","internalType":"uint64"},{"name":"executesAtTick","type":"uint64","internalType":"uint64"},{"name":"settlesAtTick","type":"uint64","internalType":"uint64"},{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"startRegion","type":"uint8","internalType":"uint8"},{"name":"targetRegion","type":"uint8","internalType":"uint8"},{"name":"action","type":"uint8","internalType":"enum ActionType"},{"name":"startTick","type":"uint64","internalType":"uint64"},{"name":"arrivalTick","type":"uint64","internalType":"uint64"},{"name":"actionStartTick","type":"uint64","internalType":"uint64"},{"name":"missionSeed","type":"bytes32","internalType":"bytes32"},{"name":"marketMode","type":"uint8","internalType":"enum MarketExecutionMode"},{"name":"targetClanId","type":"uint32","internalType":"uint32"},{"name":"marketToken","type":"address","internalType":"address"},{"name":"marketAmount","type":"uint256","internalType":"uint256"},{"name":"maxGoldIn","type":"uint256","internalType":"uint256"}]},{"name":"effectiveRegion","type":"uint8","internalType":"uint8"},{"name":"derivedAtTick","type":"uint64","internalType":"uint64"}]},{"name":"activeMission","type":"tuple","internalType":"struct Mission","components":[{"name":"active","type":"bool","internalType":"bool"},{"name":"nonce","type":"uint64","internalType":"uint64"},{"name":"submittedAtTick","type":"uint64","internalType":"uint64"},{"name":"executesAtTick","type":"uint64","internalType":"uint64"},{"name":"settlesAtTick","type":"uint64","internalType":"uint64"},{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"startRegion","type":"uint8","internalType":"uint8"},{"name":"targetRegion","type":"uint8","internalType":"uint8"},{"name":"action","type":"uint8","internalType":"enum ActionType"},{"name":"startTick","type":"uint64","internalType":"uint64"},{"name":"arrivalTick","type":"uint64","internalType":"uint64"},{"name":"actionStartTick","type":"uint64","internalType":"uint64"},{"name":"missionSeed","type":"bytes32","internalType":"bytes32"},{"name":"marketMode","type":"uint8","internalType":"enum MarketExecutionMode"},{"name":"targetClanId","type":"uint32","internalType":"uint32"},{"name":"marketToken","type":"address","internalType":"address"},{"name":"marketAmount","type":"uint256","internalType":"uint256"},{"name":"maxGoldIn","type":"uint256","internalType":"uint256"}]}]},{"name":"westPlot","type":"tuple","internalType":"struct WheatPlot","components":[{"name":"state","type":"uint8","internalType":"enum WheatPlotState"},{"name":"region","type":"uint8","internalType":"uint8"},{"name":"remainingWheat","type":"uint256","internalType":"uint256"},{"name":"regrowUntilTick","type":"uint64","internalType":"uint64"}]},{"name":"eastPlot","type":"tuple","internalType":"struct WheatPlot","components":[{"name":"state","type":"uint8","internalType":"enum WheatPlotState"},{"name":"region","type":"uint8","internalType":"uint8"},{"name":"remainingWheat","type":"uint256","internalType":"uint256"},{"name":"regrowUntilTick","type":"uint64","internalType":"uint64"}]},{"name":"incomingDefenderIds","type":"uint32[]","internalType":"uint32[]"},{"name":"thisClanDefendingBaseId","type":"uint32","internalType":"uint32"}]}],"stateMutability":"view"},{"type":"function","name":"getClansman","inputs":[{"name":"clansmanId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"","type":"tuple","internalType":"struct Clansman","components":[{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"state","type":"uint8","internalType":"enum ClansmanState"},{"name":"currentRegion","type":"uint8","internalType":"uint8"},{"name":"cooldownEndsAtTs","type":"uint64","internalType":"uint64"},{"name":"lastMissionNonce","type":"uint64","internalType":"uint64"},{"name":"carryWood","type":"uint256","internalType":"uint256"},{"name":"carryIron","type":"uint256","internalType":"uint256"},{"name":"carryWheat","type":"uint256","internalType":"uint256"},{"name":"carryFish","type":"uint256","internalType":"uint256"}]}],"stateMutability":"view"},{"type":"function","name":"getDefendingClans","inputs":[{"name":"region","type":"uint8","internalType":"uint8"}],"outputs":[{"name":"clanIds","type":"uint32[]","internalType":"uint32[]"}],"stateMutability":"view"},{"type":"function","name":"getDerivedClanState","inputs":[{"name":"clanId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"","type":"tuple","internalType":"struct DerivedClanState","components":[{"name":"clan","type":"tuple","internalType":"struct Clan","components":[{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"iftTokenId","type":"uint256","internalType":"uint256"},{"name":"owner","type":"address","internalType":"address"},{"name":"clanState","type":"uint8","internalType":"enum ClanState"},{"name":"baseRegion","type":"uint8","internalType":"uint8"},{"name":"baseLevel","type":"uint8","internalType":"uint8"},{"name":"wallLevel","type":"uint8","internalType":"uint8"},{"name":"monumentLevel","type":"uint8","internalType":"uint8"},{"name":"livingClansmen","type":"uint8","internalType":"uint8"},{"name":"lastSettledTick","type":"uint64","internalType":"uint64"},{"name":"starvationStartsAtTick","type":"uint64","internalType":"uint64"},{"name":"coldDamage","type":"uint16","internalType":"uint16"},{"name":"goldBalance","type":"uint256","internalType":"uint256"},{"name":"blueprintBalance","type":"uint256","internalType":"uint256"},{"name":"vaultWood","type":"uint256","internalType":"uint256"},{"name":"vaultIron","type":"uint256","internalType":"uint256"},{"name":"vaultWheat","type":"uint256","internalType":"uint256"},{"name":"vaultFish","type":"uint256","internalType":"uint256"}]},{"name":"isStarving","type":"bool","internalType":"bool"},{"name":"lootValue","type":"uint256","internalType":"uint256"},{"name":"derivedAtTick","type":"uint64","internalType":"uint64"}]}],"stateMutability":"view"},{"type":"function","name":"getDerivedClansmanState","inputs":[{"name":"clansmanId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"","type":"tuple","internalType":"struct DerivedClansmanState","components":[{"name":"clansman","type":"tuple","internalType":"struct Clansman","components":[{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"state","type":"uint8","internalType":"enum ClansmanState"},{"name":"currentRegion","type":"uint8","internalType":"uint8"},{"name":"cooldownEndsAtTs","type":"uint64","internalType":"uint64"},{"name":"lastMissionNonce","type":"uint64","internalType":"uint64"},{"name":"carryWood","type":"uint256","internalType":"uint256"},{"name":"carryIron","type":"uint256","internalType":"uint256"},{"name":"carryWheat","type":"uint256","internalType":"uint256"},{"name":"carryFish","type":"uint256","internalType":"uint256"}]},{"name":"activeMission","type":"tuple","internalType":"struct Mission","components":[{"name":"active","type":"bool","internalType":"bool"},{"name":"nonce","type":"uint64","internalType":"uint64"},{"name":"submittedAtTick","type":"uint64","internalType":"uint64"},{"name":"executesAtTick","type":"uint64","internalType":"uint64"},{"name":"settlesAtTick","type":"uint64","internalType":"uint64"},{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"startRegion","type":"uint8","internalType":"uint8"},{"name":"targetRegion","type":"uint8","internalType":"uint8"},{"name":"action","type":"uint8","internalType":"enum ActionType"},{"name":"startTick","type":"uint64","internalType":"uint64"},{"name":"arrivalTick","type":"uint64","internalType":"uint64"},{"name":"actionStartTick","type":"uint64","internalType":"uint64"},{"name":"missionSeed","type":"bytes32","internalType":"bytes32"},{"name":"marketMode","type":"uint8","internalType":"enum MarketExecutionMode"},{"name":"targetClanId","type":"uint32","internalType":"uint32"},{"name":"marketToken","type":"address","internalType":"address"},{"name":"marketAmount","type":"uint256","internalType":"uint256"},{"name":"maxGoldIn","type":"uint256","internalType":"uint256"}]},{"name":"effectiveRegion","type":"uint8","internalType":"uint8"},{"name":"derivedAtTick","type":"uint64","internalType":"uint64"}]}],"stateMutability":"view"},{"type":"function","name":"getMarketState","inputs":[],"outputs":[{"name":"","type":"tuple","internalType":"struct MarketState","components":[{"name":"wood","type":"tuple","internalType":"struct PoolReserves","components":[{"name":"resourceToken","type":"address","internalType":"address"},{"name":"resourceReserve","type":"uint256","internalType":"uint256"},{"name":"goldReserve","type":"uint256","internalType":"uint256"},{"name":"spotPriceGoldPerResource","type":"uint256","internalType":"uint256"}]},{"name":"wheat","type":"tuple","internalType":"struct PoolReserves","components":[{"name":"resourceToken","type":"address","internalType":"address"},{"name":"resourceReserve","type":"uint256","internalType":"uint256"},{"name":"goldReserve","type":"uint256","internalType":"uint256"},{"name":"spotPriceGoldPerResource","type":"uint256","internalType":"uint256"}]},{"name":"fish","type":"tuple","internalType":"struct PoolReserves","components":[{"name":"resourceToken","type":"address","internalType":"address"},{"name":"resourceReserve","type":"uint256","internalType":"uint256"},{"name":"goldReserve","type":"uint256","internalType":"uint256"},{"name":"spotPriceGoldPerResource","type":"uint256","internalType":"uint256"}]},{"name":"iron","type":"tuple","internalType":"struct PoolReserves","components":[{"name":"resourceToken","type":"address","internalType":"address"},{"name":"resourceReserve","type":"uint256","internalType":"uint256"},{"name":"goldReserve","type":"uint256","internalType":"uint256"},{"name":"spotPriceGoldPerResource","type":"uint256","internalType":"uint256"}]},{"name":"currentTick","type":"uint64","internalType":"uint64"},{"name":"currentTickQueue","type":"tuple[]","internalType":"struct ScheduledMarketAction[]","components":[{"name":"executeAtTick","type":"uint64","internalType":"uint64"},{"name":"commitSequence","type":"uint64","internalType":"uint64"},{"name":"missionNonce","type":"uint64","internalType":"uint64"},{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"action","type":"uint8","internalType":"enum ActionType"},{"name":"marketToken","type":"address","internalType":"address"},{"name":"marketAmount","type":"uint256","internalType":"uint256"},{"name":"maxGoldIn","type":"uint256","internalType":"uint256"}]},{"name":"nextTickQueue","type":"tuple[]","internalType":"struct ScheduledMarketAction[]","components":[{"name":"executeAtTick","type":"uint64","internalType":"uint64"},{"name":"commitSequence","type":"uint64","internalType":"uint64"},{"name":"missionNonce","type":"uint64","internalType":"uint64"},{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"action","type":"uint8","internalType":"enum ActionType"},{"name":"marketToken","type":"address","internalType":"address"},{"name":"marketAmount","type":"uint256","internalType":"uint256"},{"name":"maxGoldIn","type":"uint256","internalType":"uint256"}]}]}],"stateMutability":"view"},{"type":"function","name":"getMissionTiming","inputs":[{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"clansmanId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"submitted","type":"uint64","internalType":"uint64"},{"name":"executes","type":"uint64","internalType":"uint64"},{"name":"settles","type":"uint64","internalType":"uint64"}],"stateMutability":"view"},{"type":"function","name":"getRegionPopulation","inputs":[{"name":"region","type":"uint8","internalType":"uint8"}],"outputs":[{"name":"","type":"tuple[]","internalType":"struct RegionOccupant[]","components":[{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"state","type":"uint8","internalType":"enum ClansmanState"},{"name":"currentAction","type":"uint8","internalType":"enum ActionType"},{"name":"missionNonce","type":"uint64","internalType":"uint64"}]}],"stateMutability":"view"},{"type":"function","name":"getScheduledMarketActionsForTick","inputs":[{"name":"tick","type":"uint64","internalType":"uint64"}],"outputs":[{"name":"","type":"tuple[]","internalType":"struct ScheduledMarketAction[]","components":[{"name":"executeAtTick","type":"uint64","internalType":"uint64"},{"name":"commitSequence","type":"uint64","internalType":"uint64"},{"name":"missionNonce","type":"uint64","internalType":"uint64"},{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"action","type":"uint8","internalType":"enum ActionType"},{"name":"marketToken","type":"address","internalType":"address"},{"name":"marketAmount","type":"uint256","internalType":"uint256"},{"name":"maxGoldIn","type":"uint256","internalType":"uint256"}]}],"stateMutability":"view"},{"type":"function","name":"getTravelTicks","inputs":[{"name":"fromRegion","type":"uint8","internalType":"uint8"},{"name":"toRegion","type":"uint8","internalType":"uint8"}],"outputs":[{"name":"","type":"uint64","internalType":"uint64"}],"stateMutability":"pure"},{"type":"function","name":"getTreasuryState","inputs":[],"outputs":[{"name":"","type":"tuple","internalType":"struct TreasuryState","components":[{"name":"treasuryOwner","type":"address","internalType":"address"},{"name":"prizePotGold","type":"uint256","internalType":"uint256"},{"name":"poolsSeeded","type":"bool","internalType":"bool"},{"name":"woodToken","type":"address","internalType":"address"},{"name":"wheatToken","type":"address","internalType":"address"},{"name":"fishToken","type":"address","internalType":"address"},{"name":"ironToken","type":"address","internalType":"address"},{"name":"goldToken","type":"address","internalType":"address"},{"name":"blueprintToken","type":"address","internalType":"address"},{"name":"woodGoldPool","type":"address","internalType":"address"},{"name":"wheatGoldPool","type":"address","internalType":"address"},{"name":"fishGoldPool","type":"address","internalType":"address"},{"name":"ironGoldPool","type":"address","internalType":"address"}]}],"stateMutability":"view"},{"type":"function","name":"getWheatPlots","inputs":[{"name":"clanId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"west","type":"tuple","internalType":"struct WheatPlot","components":[{"name":"state","type":"uint8","internalType":"enum WheatPlotState"},{"name":"region","type":"uint8","internalType":"uint8"},{"name":"remainingWheat","type":"uint256","internalType":"uint256"},{"name":"regrowUntilTick","type":"uint64","internalType":"uint64"}]},{"name":"east","type":"tuple","internalType":"struct WheatPlot","components":[{"name":"state","type":"uint8","internalType":"enum WheatPlotState"},{"name":"region","type":"uint8","internalType":"uint8"},{"name":"remainingWheat","type":"uint256","internalType":"uint256"},{"name":"regrowUntilTick","type":"uint64","internalType":"uint64"}]}],"stateMutability":"view"},{"type":"function","name":"getWorldSnapshot","inputs":[],"outputs":[{"name":"","type":"tuple","internalType":"struct WorldSnapshot","components":[{"name":"currentTick","type":"uint64","internalType":"uint64"},{"name":"seasonStartTick","type":"uint64","internalType":"uint64"},{"name":"seasonEndTick","type":"uint64","internalType":"uint64"},{"name":"seasonFinalized","type":"bool","internalType":"bool"},{"name":"currentSeasonNumber","type":"uint64","internalType":"uint64"},{"name":"nextHeartbeatAtTick","type":"uint64","internalType":"uint64"},{"name":"winterActive","type":"bool","internalType":"bool"},{"name":"winterStartsAtTick","type":"uint64","internalType":"uint64"},{"name":"winterEndsAtTick","type":"uint64","internalType":"uint64"},{"name":"activeBanditId","type":"uint32","internalType":"uint32"},{"name":"currentTickSeed","type":"bytes32","internalType":"bytes32"},{"name":"leaderboard","type":"tuple[]","internalType":"struct LeaderboardEntry[]","components":[{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"owner","type":"address","internalType":"address"},{"name":"monumentLevel","type":"uint8","internalType":"uint8"},{"name":"baseLevel","type":"uint8","internalType":"uint8"},{"name":"wallLevel","type":"uint8","internalType":"uint8"},{"name":"livingClansmen","type":"uint8","internalType":"uint8"},{"name":"state","type":"uint8","internalType":"enum ClanState"},{"name":"lootValue","type":"uint256","internalType":"uint256"}]}]}],"stateMutability":"view"},{"type":"function","name":"getWorldState","inputs":[],"outputs":[{"name":"","type":"tuple","internalType":"struct WorldState","components":[{"name":"currentTick","type":"uint64","internalType":"uint64"},{"name":"seasonStartTick","type":"uint64","internalType":"uint64"},{"name":"seasonEndTick","type":"uint64","internalType":"uint64"},{"name":"seasonFinalized","type":"bool","internalType":"bool"},{"name":"currentSeasonNumber","type":"uint64","internalType":"uint64"},{"name":"nextHeartbeatAtTick","type":"uint64","internalType":"uint64"},{"name":"nextHeartbeatAtTs","type":"uint64","internalType":"uint64"},{"name":"nextBanditSpawnEligibleTick","type":"uint64","internalType":"uint64"},{"name":"currentBanditSpawnChanceBps","type":"uint16","internalType":"uint16"},{"name":"currentTickSeed","type":"bytes32","internalType":"bytes32"},{"name":"activeBanditId","type":"uint32","internalType":"uint32"},{"name":"winterActive","type":"bool","internalType":"bool"},{"name":"winterStartsAtTick","type":"uint64","internalType":"uint64"},{"name":"winterEndsAtTick","type":"uint64","internalType":"uint64"},{"name":"nextCommitSequence","type":"uint64","internalType":"uint64"}]}],"stateMutability":"view"},{"type":"function","name":"heartbeat","inputs":[],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"initTreasury","inputs":[{"name":"tokens","type":"address[6]","internalType":"address[6]"},{"name":"pools","type":"address[4]","internalType":"address[4]"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"mintClan","inputs":[{"name":"to","type":"address","internalType":"address"}],"outputs":[{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"iftTokenId","type":"uint256","internalType":"uint256"}],"stateMutability":"nonpayable"},{"type":"function","name":"quoteLootValueRaw","inputs":[{"name":"clanId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"lootValue","type":"uint256","internalType":"uint256"}],"stateMutability":"view"},{"type":"function","name":"quoteLootValueSettled","inputs":[{"name":"clanId","type":"uint32","internalType":"uint32"}],"outputs":[{"name":"lootValue","type":"uint256","internalType":"uint256"}],"stateMutability":"view"},{"type":"function","name":"quoteTravel","inputs":[{"name":"srcRegion","type":"uint8","internalType":"uint8"},{"name":"dstRegion","type":"uint8","internalType":"uint8"}],"outputs":[{"name":"travelTicks","type":"uint8","internalType":"uint8"},{"name":"path","type":"bytes8","internalType":"bytes8"}],"stateMutability":"view"},{"type":"function","name":"seedPools","inputs":[{"name":"cfg","type":"tuple","internalType":"struct PoolSeedConfig","components":[{"name":"woodSeed","type":"uint256","internalType":"uint256"},{"name":"wheatSeed","type":"uint256","internalType":"uint256"},{"name":"fishSeed","type":"uint256","internalType":"uint256"},{"name":"ironSeed","type":"uint256","internalType":"uint256"},{"name":"goldSeedForWood","type":"uint256","internalType":"uint256"},{"name":"goldSeedForWheat","type":"uint256","internalType":"uint256"},{"name":"goldSeedForFish","type":"uint256","internalType":"uint256"},{"name":"goldSeedForIron","type":"uint256","internalType":"uint256"}]}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"settleClan","inputs":[{"name":"clanId","type":"uint32","internalType":"uint32"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"settleClansman","inputs":[{"name":"csId","type":"uint32","internalType":"uint32"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"submitClanOrders","inputs":[{"name":"clanId","type":"uint32","internalType":"uint32"},{"name":"orders","type":"tuple[]","internalType":"struct ClanOrder[]","components":[{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"gotoRegion","type":"uint8","internalType":"uint8"},{"name":"action","type":"uint8","internalType":"enum ActionType"},{"name":"targetClanId","type":"uint32","internalType":"uint32"},{"name":"marketToken","type":"address","internalType":"address"},{"name":"marketAmount","type":"uint256","internalType":"uint256"},{"name":"maxGoldIn","type":"uint256","internalType":"uint256"}]}],"outputs":[{"name":"","type":"tuple[]","internalType":"struct OrderResult[]","components":[{"name":"clansmanId","type":"uint32","internalType":"uint32"},{"name":"status","type":"uint8","internalType":"enum StatusCode"},{"name":"cooldownEndsAtTs","type":"uint64","internalType":"uint64"},{"name":"missionNonce","type":"uint64","internalType":"uint64"}]}],"stateMutability":"nonpayable"},{"type":"function","name":"transferBlueprint","inputs":[{"name":"fromClanId","type":"uint32","internalType":"uint32"},{"name":"toClanId","type":"uint32","internalType":"uint32"},{"name":"amount","type":"uint256","internalType":"uint256"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"transferBundle","inputs":[{"name":"fromClanId","type":"uint32","internalType":"uint32"},{"name":"toClanId","type":"uint32","internalType":"uint32"},{"name":"gold","type":"uint256","internalType":"uint256"},{"name":"blueprint","type":"uint256","internalType":"uint256"},{"name":"wood","type":"uint256","internalType":"uint256"},{"name":"iron","type":"uint256","internalType":"uint256"},{"name":"wheat","type":"uint256","internalType":"uint256"},{"name":"fish","type":"uint256","internalType":"uint256"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"transferGold","inputs":[{"name":"fromClanId","type":"uint32","internalType":"uint32"},{"name":"toClanId","type":"uint32","internalType":"uint32"},{"name":"amount","type":"uint256","internalType":"uint256"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"transferVaultResource","inputs":[{"name":"fromClanId","type":"uint32","internalType":"uint32"},{"name":"toClanId","type":"uint32","internalType":"uint32"},{"name":"resource","type":"uint8","internalType":"enum ResourceType"},{"name":"amount","type":"uint256","internalType":"uint256"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"event","name":"BanditAttackResolved","inputs":[{"name":"banditId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"targetClanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"defended","type":"bool","indexed":false,"internalType":"bool"},{"name":"attackPower","type":"uint16","indexed":false,"internalType":"uint16"},{"name":"totalDefense","type":"uint16","indexed":false,"internalType":"uint16"},{"name":"wallLevelAfter","type":"uint16","indexed":false,"internalType":"uint16"},{"name":"stolenWood","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"stolenIron","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"stolenWheat","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"stolenFish","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"BanditDefeated","inputs":[{"name":"banditId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"targetClanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"BanditEscaped","inputs":[{"name":"banditId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"BanditMoved","inputs":[{"name":"banditId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"fromRegion","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"toRegion","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"BanditSpawned","inputs":[{"name":"banditId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"region","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"tier","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"attackPower","type":"uint16","indexed":false,"internalType":"uint16"}],"anonymous":false},{"type":"event","name":"BanditStateChanged","inputs":[{"name":"banditId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"oldState","type":"uint8","indexed":false,"internalType":"enum BanditState"},{"name":"newState","type":"uint8","indexed":false,"internalType":"enum BanditState"},{"name":"region","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"BaseLevelChanged","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"oldLevel","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"newLevel","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"BlueprintAwarded","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"banditId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"amount","type":"uint256","indexed":false,"internalType":"uint256"}],"anonymous":false},{"type":"event","name":"BlueprintTransferred","inputs":[{"name":"fromClanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"toClanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"amount","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"ClanEliminated","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"tick","type":"uint64","indexed":true,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"ClanSettled","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"settledToTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"ClanSpawned","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"owner","type":"address","indexed":true,"internalType":"address"},{"name":"iftTokenId","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"baseRegion","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"ClanStarvationChanged","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"isStarving","type":"bool","indexed":false,"internalType":"bool"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"ClansmanDiedFromCold","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"ColdDamageApplied","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"oldDamage","type":"uint16","indexed":false,"internalType":"uint16"},{"name":"newDamage","type":"uint16","indexed":false,"internalType":"uint16"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"GoldTransferred","inputs":[{"name":"fromClanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"toClanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"amount","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"ImmediateMarketActionExecuted","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clansmanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"tokenIn","type":"address","indexed":false,"internalType":"address"},{"name":"tokenOut","type":"address","indexed":false,"internalType":"address"},{"name":"amountIn","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"amountOut","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"LootDistributedToDefender","inputs":[{"name":"banditId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clansmanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"wood","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"iron","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"wheat","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"fish","type":"uint256","indexed":false,"internalType":"uint256"}],"anonymous":false},{"type":"event","name":"MarketActionFailed","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clansmanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"action","type":"uint8","indexed":false,"internalType":"enum ActionType"},{"name":"reason","type":"uint8","indexed":false,"internalType":"enum StatusCode"}],"anonymous":false},{"type":"event","name":"MissionAssigned","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clansmanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"missionNonce","type":"uint64","indexed":false,"internalType":"uint64"},{"name":"action","type":"uint8","indexed":false,"internalType":"enum ActionType"},{"name":"startRegion","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"targetRegion","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"startTick","type":"uint64","indexed":false,"internalType":"uint64"},{"name":"arrivalTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"MissionCompleted","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clansmanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"missionNonce","type":"uint64","indexed":false,"internalType":"uint64"},{"name":"action","type":"uint8","indexed":false,"internalType":"enum ActionType"}],"anonymous":false},{"type":"event","name":"MissionInterrupted","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clansmanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"oldMissionNonce","type":"uint64","indexed":false,"internalType":"uint64"},{"name":"newMissionNonce","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"MonumentLevelChanged","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"oldLevel","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"newLevel","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"PoolsSeeded","inputs":[{"name":"woodGoldPool","type":"address","indexed":false,"internalType":"address"},{"name":"wheatGoldPool","type":"address","indexed":false,"internalType":"address"},{"name":"fishGoldPool","type":"address","indexed":false,"internalType":"address"},{"name":"ironGoldPool","type":"address","indexed":false,"internalType":"address"}],"anonymous":false},{"type":"event","name":"ResourcesDeposited","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clansmanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"woodDelta","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"ironDelta","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"wheatDelta","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"fishDelta","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"ResourcesGathered","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clansmanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"action","type":"uint8","indexed":false,"internalType":"enum ActionType"},{"name":"woodGained","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"ironGained","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"wheatGained","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"fishGained","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"goldBonus","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"ScheduledMarketActionCommitted","inputs":[{"name":"executeAtTick","type":"uint64","indexed":true,"internalType":"uint64"},{"name":"commitSequence","type":"uint64","indexed":true,"internalType":"uint64"},{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clansmanId","type":"uint32","indexed":false,"internalType":"uint32"},{"name":"action","type":"uint8","indexed":false,"internalType":"enum ActionType"},{"name":"marketToken","type":"address","indexed":false,"internalType":"address"},{"name":"marketAmount","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"maxGoldIn","type":"uint256","indexed":false,"internalType":"uint256"}],"anonymous":false},{"type":"event","name":"ScheduledMarketActionExecuted","inputs":[{"name":"executeAtTick","type":"uint64","indexed":true,"internalType":"uint64"},{"name":"commitSequence","type":"uint64","indexed":true,"internalType":"uint64"},{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clansmanId","type":"uint32","indexed":false,"internalType":"uint32"},{"name":"tokenIn","type":"address","indexed":false,"internalType":"address"},{"name":"tokenOut","type":"address","indexed":false,"internalType":"address"},{"name":"amountIn","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"amountOut","type":"uint256","indexed":false,"internalType":"uint256"}],"anonymous":false},{"type":"event","name":"SeasonFinalized","inputs":[{"name":"tick","type":"uint64","indexed":true,"internalType":"uint64"},{"name":"rankedClanIds","type":"uint32[]","indexed":false,"internalType":"uint32[]"}],"anonymous":false},{"type":"event","name":"TickAdvanced","inputs":[{"name":"closedTick","type":"uint64","indexed":false,"internalType":"uint64"},{"name":"openedTick","type":"uint64","indexed":false,"internalType":"uint64"},{"name":"tickSeed","type":"bytes32","indexed":false,"internalType":"bytes32"}],"anonymous":false},{"type":"event","name":"VaultResourceTransferred","inputs":[{"name":"fromClanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"toClanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"resource","type":"uint8","indexed":false,"internalType":"enum ResourceType"},{"name":"amount","type":"uint256","indexed":false,"internalType":"uint256"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"WallLevelChanged","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"oldLevel","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"newLevel","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"atTick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"WinterEnded","inputs":[{"name":"tick","type":"uint64","indexed":true,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"WinterStarted","inputs":[{"name":"tick","type":"uint64","indexed":true,"internalType":"uint64"}],"anonymous":false},{"type":"event","name":"WorkerArrived","inputs":[{"name":"clanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"clansmanId","type":"uint32","indexed":true,"internalType":"uint32"},{"name":"region","type":"uint8","indexed":false,"internalType":"uint8"},{"name":"tick","type":"uint64","indexed":false,"internalType":"uint64"}],"anonymous":false}],"bytecode":{"object":"0x","sourceMap":"","linkReferences":{}},"deployedBytecode":{"object":"0x","sourceMap":"","linkReferences":{}},"methodIdentifiers":{"finalizeSeason()":"30fb8f8a","getActionDuration(uint8)":"e24864d8","getActiveBanditView()":"19abee0f","getActiveDefenders(uint32)":"d7f55bbc","getActiveMission(uint32)":"c7898535","getBanditTargetPreview(uint32)":"8233c665","getBanditTroop(uint32)":"a237d380","getClan(uint32)":"73c3d0da","getClanFullView(uint32)":"b6b1902d","getClansman(uint32)":"481a43a2","getDefendingClans(uint8)":"922b82d9","getDerivedClanState(uint32)":"1b43cdd8","getDerivedClansmanState(uint32)":"a22e3257","getMarketState()":"d8165743","getMissionTiming(uint32,uint32)":"bb6982c7","getRegionPopulation(uint8)":"b3d2cbdb","getScheduledMarketActionsForTick(uint64)":"1d0bf24c","getTravelTicks(uint8,uint8)":"c7e29ce6","getTreasuryState()":"23a8bdca","getWheatPlots(uint32)":"101583da","getWorldSnapshot()":"96fe8161","getWorldState()":"671eb0d2","heartbeat()":"3defb962","initTreasury(address[6],address[4])":"38c7f5c4","mintClan(address)":"b3705e4e","quoteLootValueRaw(uint32)":"1ade4dda","quoteLootValueSettled(uint32)":"7f9e027b","quoteTravel(uint8,uint8)":"135503af","seedPools((uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256))":"c46a6fb2","settleClan(uint32)":"3073b90b","settleClansman(uint32)":"f1d68ae2","submitClanOrders(uint32,(uint32,uint8,uint8,uint32,address,uint256,uint256)[])":"7971fc2c","transferBlueprint(uint32,uint32,uint256)":"33f8d51d","transferBundle(uint32,uint32,uint256,uint256,uint256,uint256,uint256,uint256)":"c28492ab","transferGold(uint32,uint32,uint256)":"c3fd8ac9","transferVaultResource(uint32,uint32,uint8,uint256)":"a54e020c"},"rawMetadata":"{\"compiler\":{\"version\":\"0.8.34+commit.80d5c536\"},\"language\":\"Solidity\",\"output\":{\"abi\":[{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"targetClanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"bool\",\"name\":\"defended\",\"type\":\"bool\"},{\"indexed\":false,\"internalType\":\"uint16\",\"name\":\"attackPower\",\"type\":\"uint16\"},{\"indexed\":false,\"internalType\":\"uint16\",\"name\":\"totalDefense\",\"type\":\"uint16\"},{\"indexed\":false,\"internalType\":\"uint16\",\"name\":\"wallLevelAfter\",\"type\":\"uint16\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"stolenWood\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"stolenIron\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"stolenWheat\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"stolenFish\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"BanditAttackResolved\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"targetClanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"BanditDefeated\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"BanditEscaped\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"fromRegion\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"toRegion\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"BanditMoved\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"region\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"tier\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint16\",\"name\":\"attackPower\",\"type\":\"uint16\"}],\"name\":\"BanditSpawned\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"enum BanditState\",\"name\":\"oldState\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"enum BanditState\",\"name\":\"newState\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"region\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"BanditStateChanged\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"oldLevel\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"newLevel\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"BaseLevelChanged\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"amount\",\"type\":\"uint256\"}],\"name\":\"BlueprintAwarded\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"fromClanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"toClanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"amount\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"BlueprintTransferred\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint64\",\"name\":\"tick\",\"type\":\"uint64\"}],\"name\":\"ClanEliminated\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"settledToTick\",\"type\":\"uint64\"}],\"name\":\"ClanSettled\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"address\",\"name\":\"owner\",\"type\":\"address\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"iftTokenId\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"baseRegion\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"ClanSpawned\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"bool\",\"name\":\"isStarving\",\"type\":\"bool\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"ClanStarvationChanged\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"ClansmanDiedFromCold\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint16\",\"name\":\"oldDamage\",\"type\":\"uint16\"},{\"indexed\":false,\"internalType\":\"uint16\",\"name\":\"newDamage\",\"type\":\"uint16\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"ColdDamageApplied\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"fromClanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"toClanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"amount\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"GoldTransferred\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"address\",\"name\":\"tokenIn\",\"type\":\"address\"},{\"indexed\":false,\"internalType\":\"address\",\"name\":\"tokenOut\",\"type\":\"address\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"amountIn\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"amountOut\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"ImmediateMarketActionExecuted\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"wood\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"iron\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"wheat\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"fish\",\"type\":\"uint256\"}],\"name\":\"LootDistributedToDefender\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"enum StatusCode\",\"name\":\"reason\",\"type\":\"uint8\"}],\"name\":\"MarketActionFailed\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"missionNonce\",\"type\":\"uint64\"},{\"indexed\":false,\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"startRegion\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"targetRegion\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"startTick\",\"type\":\"uint64\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"arrivalTick\",\"type\":\"uint64\"}],\"name\":\"MissionAssigned\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"missionNonce\",\"type\":\"uint64\"},{\"indexed\":false,\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"}],\"name\":\"MissionCompleted\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"oldMissionNonce\",\"type\":\"uint64\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"newMissionNonce\",\"type\":\"uint64\"}],\"name\":\"MissionInterrupted\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"oldLevel\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"newLevel\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"MonumentLevelChanged\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":false,\"internalType\":\"address\",\"name\":\"woodGoldPool\",\"type\":\"address\"},{\"indexed\":false,\"internalType\":\"address\",\"name\":\"wheatGoldPool\",\"type\":\"address\"},{\"indexed\":false,\"internalType\":\"address\",\"name\":\"fishGoldPool\",\"type\":\"address\"},{\"indexed\":false,\"internalType\":\"address\",\"name\":\"ironGoldPool\",\"type\":\"address\"}],\"name\":\"PoolsSeeded\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"woodDelta\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"ironDelta\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"wheatDelta\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"fishDelta\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"ResourcesDeposited\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"woodGained\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"ironGained\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"wheatGained\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"fishGained\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"goldBonus\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"ResourcesGathered\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint64\",\"name\":\"executeAtTick\",\"type\":\"uint64\"},{\"indexed\":true,\"internalType\":\"uint64\",\"name\":\"commitSequence\",\"type\":\"uint64\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"address\",\"name\":\"marketToken\",\"type\":\"address\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"marketAmount\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"maxGoldIn\",\"type\":\"uint256\"}],\"name\":\"ScheduledMarketActionCommitted\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint64\",\"name\":\"executeAtTick\",\"type\":\"uint64\"},{\"indexed\":true,\"internalType\":\"uint64\",\"name\":\"commitSequence\",\"type\":\"uint64\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"address\",\"name\":\"tokenIn\",\"type\":\"address\"},{\"indexed\":false,\"internalType\":\"address\",\"name\":\"tokenOut\",\"type\":\"address\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"amountIn\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"amountOut\",\"type\":\"uint256\"}],\"name\":\"ScheduledMarketActionExecuted\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint64\",\"name\":\"tick\",\"type\":\"uint64\"},{\"indexed\":false,\"internalType\":\"uint32[]\",\"name\":\"rankedClanIds\",\"type\":\"uint32[]\"}],\"name\":\"SeasonFinalized\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"closedTick\",\"type\":\"uint64\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"openedTick\",\"type\":\"uint64\"},{\"indexed\":false,\"internalType\":\"bytes32\",\"name\":\"tickSeed\",\"type\":\"bytes32\"}],\"name\":\"TickAdvanced\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"fromClanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"toClanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"enum ResourceType\",\"name\":\"resource\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"amount\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"VaultResourceTransferred\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"oldLevel\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"newLevel\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"atTick\",\"type\":\"uint64\"}],\"name\":\"WallLevelChanged\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint64\",\"name\":\"tick\",\"type\":\"uint64\"}],\"name\":\"WinterEnded\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint64\",\"name\":\"tick\",\"type\":\"uint64\"}],\"name\":\"WinterStarted\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"indexed\":false,\"internalType\":\"uint8\",\"name\":\"region\",\"type\":\"uint8\"},{\"indexed\":false,\"internalType\":\"uint64\",\"name\":\"tick\",\"type\":\"uint64\"}],\"name\":\"WorkerArrived\",\"type\":\"event\"},{\"inputs\":[],\"name\":\"finalizeSeason\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"}],\"name\":\"getActionDuration\",\"outputs\":[{\"internalType\":\"uint64\",\"name\":\"\",\"type\":\"uint64\"}],\"stateMutability\":\"pure\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"getActiveBanditView\",\"outputs\":[{\"components\":[{\"internalType\":\"bool\",\"name\":\"exists\",\"type\":\"bool\"},{\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"},{\"internalType\":\"enum BanditState\",\"name\":\"state\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"currentRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"attackAttemptsMade\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"maxAttemptsRemaining\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"stateEnteredTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"nextActionTick\",\"type\":\"uint64\"},{\"internalType\":\"uint8\",\"name\":\"tier\",\"type\":\"uint8\"},{\"internalType\":\"uint16\",\"name\":\"attackPower\",\"type\":\"uint16\"},{\"internalType\":\"uint256\",\"name\":\"carryWood\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryIron\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryFish\",\"type\":\"uint256\"},{\"internalType\":\"uint32\",\"name\":\"projectedTargetClanId\",\"type\":\"uint32\"},{\"internalType\":\"uint256\",\"name\":\"projectedTargetLootValue\",\"type\":\"uint256\"}],\"internalType\":\"struct ActiveBanditView\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"targetClanId\",\"type\":\"uint32\"}],\"name\":\"getActiveDefenders\",\"outputs\":[{\"internalType\":\"uint32[]\",\"name\":\"clansmanIds\",\"type\":\"uint32[]\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"}],\"name\":\"getActiveMission\",\"outputs\":[{\"components\":[{\"internalType\":\"bool\",\"name\":\"active\",\"type\":\"bool\"},{\"internalType\":\"uint64\",\"name\":\"nonce\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"submittedAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"executesAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"settlesAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"uint8\",\"name\":\"startRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"targetRegion\",\"type\":\"uint8\"},{\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"startTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"arrivalTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"actionStartTick\",\"type\":\"uint64\"},{\"internalType\":\"bytes32\",\"name\":\"missionSeed\",\"type\":\"bytes32\"},{\"internalType\":\"enum MarketExecutionMode\",\"name\":\"marketMode\",\"type\":\"uint8\"},{\"internalType\":\"uint32\",\"name\":\"targetClanId\",\"type\":\"uint32\"},{\"internalType\":\"address\",\"name\":\"marketToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"marketAmount\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"maxGoldIn\",\"type\":\"uint256\"}],\"internalType\":\"struct Mission\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"}],\"name\":\"getBanditTargetPreview\",\"outputs\":[{\"internalType\":\"uint32\",\"name\":\"previewClanId\",\"type\":\"uint32\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"}],\"name\":\"getBanditTroop\",\"outputs\":[{\"components\":[{\"internalType\":\"uint32\",\"name\":\"banditId\",\"type\":\"uint32\"},{\"internalType\":\"enum BanditState\",\"name\":\"state\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"currentRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"attackAttemptsMade\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"stateEnteredTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"nextActionTick\",\"type\":\"uint64\"},{\"internalType\":\"uint8\",\"name\":\"tier\",\"type\":\"uint8\"},{\"internalType\":\"uint16\",\"name\":\"attackPower\",\"type\":\"uint16\"},{\"internalType\":\"uint256\",\"name\":\"carryWood\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryIron\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryFish\",\"type\":\"uint256\"}],\"internalType\":\"struct BanditTroop\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"}],\"name\":\"getClan\",\"outputs\":[{\"components\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"uint256\",\"name\":\"iftTokenId\",\"type\":\"uint256\"},{\"internalType\":\"address\",\"name\":\"owner\",\"type\":\"address\"},{\"internalType\":\"enum ClanState\",\"name\":\"clanState\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"baseRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"baseLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"wallLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"monumentLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"livingClansmen\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"lastSettledTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"starvationStartsAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint16\",\"name\":\"coldDamage\",\"type\":\"uint16\"},{\"internalType\":\"uint256\",\"name\":\"goldBalance\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"blueprintBalance\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultWood\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultIron\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultFish\",\"type\":\"uint256\"}],\"internalType\":\"struct Clan\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"}],\"name\":\"getClanFullView\",\"outputs\":[{\"components\":[{\"components\":[{\"components\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"uint256\",\"name\":\"iftTokenId\",\"type\":\"uint256\"},{\"internalType\":\"address\",\"name\":\"owner\",\"type\":\"address\"},{\"internalType\":\"enum ClanState\",\"name\":\"clanState\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"baseRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"baseLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"wallLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"monumentLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"livingClansmen\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"lastSettledTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"starvationStartsAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint16\",\"name\":\"coldDamage\",\"type\":\"uint16\"},{\"internalType\":\"uint256\",\"name\":\"goldBalance\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"blueprintBalance\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultWood\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultIron\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultFish\",\"type\":\"uint256\"}],\"internalType\":\"struct Clan\",\"name\":\"clan\",\"type\":\"tuple\"},{\"internalType\":\"bool\",\"name\":\"isStarving\",\"type\":\"bool\"},{\"internalType\":\"uint256\",\"name\":\"lootValue\",\"type\":\"uint256\"},{\"internalType\":\"uint64\",\"name\":\"derivedAtTick\",\"type\":\"uint64\"}],\"internalType\":\"struct DerivedClanState\",\"name\":\"clan\",\"type\":\"tuple\"},{\"components\":[{\"components\":[{\"components\":[{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"enum ClansmanState\",\"name\":\"state\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"currentRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"cooldownEndsAtTs\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"lastMissionNonce\",\"type\":\"uint64\"},{\"internalType\":\"uint256\",\"name\":\"carryWood\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryIron\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryFish\",\"type\":\"uint256\"}],\"internalType\":\"struct Clansman\",\"name\":\"clansman\",\"type\":\"tuple\"},{\"components\":[{\"internalType\":\"bool\",\"name\":\"active\",\"type\":\"bool\"},{\"internalType\":\"uint64\",\"name\":\"nonce\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"submittedAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"executesAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"settlesAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"uint8\",\"name\":\"startRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"targetRegion\",\"type\":\"uint8\"},{\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"startTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"arrivalTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"actionStartTick\",\"type\":\"uint64\"},{\"internalType\":\"bytes32\",\"name\":\"missionSeed\",\"type\":\"bytes32\"},{\"internalType\":\"enum MarketExecutionMode\",\"name\":\"marketMode\",\"type\":\"uint8\"},{\"internalType\":\"uint32\",\"name\":\"targetClanId\",\"type\":\"uint32\"},{\"internalType\":\"address\",\"name\":\"marketToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"marketAmount\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"maxGoldIn\",\"type\":\"uint256\"}],\"internalType\":\"struct Mission\",\"name\":\"activeMission\",\"type\":\"tuple\"},{\"internalType\":\"uint8\",\"name\":\"effectiveRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"derivedAtTick\",\"type\":\"uint64\"}],\"internalType\":\"struct DerivedClansmanState\",\"name\":\"clansman\",\"type\":\"tuple\"},{\"components\":[{\"internalType\":\"bool\",\"name\":\"active\",\"type\":\"bool\"},{\"internalType\":\"uint64\",\"name\":\"nonce\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"submittedAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"executesAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"settlesAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"uint8\",\"name\":\"startRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"targetRegion\",\"type\":\"uint8\"},{\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"startTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"arrivalTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"actionStartTick\",\"type\":\"uint64\"},{\"internalType\":\"bytes32\",\"name\":\"missionSeed\",\"type\":\"bytes32\"},{\"internalType\":\"enum MarketExecutionMode\",\"name\":\"marketMode\",\"type\":\"uint8\"},{\"internalType\":\"uint32\",\"name\":\"targetClanId\",\"type\":\"uint32\"},{\"internalType\":\"address\",\"name\":\"marketToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"marketAmount\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"maxGoldIn\",\"type\":\"uint256\"}],\"internalType\":\"struct Mission\",\"name\":\"activeMission\",\"type\":\"tuple\"}],\"internalType\":\"struct ClansmanFullView[]\",\"name\":\"clansmen\",\"type\":\"tuple[]\"},{\"components\":[{\"internalType\":\"enum WheatPlotState\",\"name\":\"state\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"region\",\"type\":\"uint8\"},{\"internalType\":\"uint256\",\"name\":\"remainingWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint64\",\"name\":\"regrowUntilTick\",\"type\":\"uint64\"}],\"internalType\":\"struct WheatPlot\",\"name\":\"westPlot\",\"type\":\"tuple\"},{\"components\":[{\"internalType\":\"enum WheatPlotState\",\"name\":\"state\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"region\",\"type\":\"uint8\"},{\"internalType\":\"uint256\",\"name\":\"remainingWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint64\",\"name\":\"regrowUntilTick\",\"type\":\"uint64\"}],\"internalType\":\"struct WheatPlot\",\"name\":\"eastPlot\",\"type\":\"tuple\"},{\"internalType\":\"uint32[]\",\"name\":\"incomingDefenderIds\",\"type\":\"uint32[]\"},{\"internalType\":\"uint32\",\"name\":\"thisClanDefendingBaseId\",\"type\":\"uint32\"}],\"internalType\":\"struct ClanFullView\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"}],\"name\":\"getClansman\",\"outputs\":[{\"components\":[{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"enum ClansmanState\",\"name\":\"state\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"currentRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"cooldownEndsAtTs\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"lastMissionNonce\",\"type\":\"uint64\"},{\"internalType\":\"uint256\",\"name\":\"carryWood\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryIron\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryFish\",\"type\":\"uint256\"}],\"internalType\":\"struct Clansman\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint8\",\"name\":\"region\",\"type\":\"uint8\"}],\"name\":\"getDefendingClans\",\"outputs\":[{\"internalType\":\"uint32[]\",\"name\":\"clanIds\",\"type\":\"uint32[]\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"}],\"name\":\"getDerivedClanState\",\"outputs\":[{\"components\":[{\"components\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"uint256\",\"name\":\"iftTokenId\",\"type\":\"uint256\"},{\"internalType\":\"address\",\"name\":\"owner\",\"type\":\"address\"},{\"internalType\":\"enum ClanState\",\"name\":\"clanState\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"baseRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"baseLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"wallLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"monumentLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"livingClansmen\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"lastSettledTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"starvationStartsAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint16\",\"name\":\"coldDamage\",\"type\":\"uint16\"},{\"internalType\":\"uint256\",\"name\":\"goldBalance\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"blueprintBalance\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultWood\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultIron\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"vaultFish\",\"type\":\"uint256\"}],\"internalType\":\"struct Clan\",\"name\":\"clan\",\"type\":\"tuple\"},{\"internalType\":\"bool\",\"name\":\"isStarving\",\"type\":\"bool\"},{\"internalType\":\"uint256\",\"name\":\"lootValue\",\"type\":\"uint256\"},{\"internalType\":\"uint64\",\"name\":\"derivedAtTick\",\"type\":\"uint64\"}],\"internalType\":\"struct DerivedClanState\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"}],\"name\":\"getDerivedClansmanState\",\"outputs\":[{\"components\":[{\"components\":[{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"enum ClansmanState\",\"name\":\"state\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"currentRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"cooldownEndsAtTs\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"lastMissionNonce\",\"type\":\"uint64\"},{\"internalType\":\"uint256\",\"name\":\"carryWood\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryIron\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"carryFish\",\"type\":\"uint256\"}],\"internalType\":\"struct Clansman\",\"name\":\"clansman\",\"type\":\"tuple\"},{\"components\":[{\"internalType\":\"bool\",\"name\":\"active\",\"type\":\"bool\"},{\"internalType\":\"uint64\",\"name\":\"nonce\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"submittedAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"executesAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"settlesAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"uint8\",\"name\":\"startRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"targetRegion\",\"type\":\"uint8\"},{\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"startTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"arrivalTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"actionStartTick\",\"type\":\"uint64\"},{\"internalType\":\"bytes32\",\"name\":\"missionSeed\",\"type\":\"bytes32\"},{\"internalType\":\"enum MarketExecutionMode\",\"name\":\"marketMode\",\"type\":\"uint8\"},{\"internalType\":\"uint32\",\"name\":\"targetClanId\",\"type\":\"uint32\"},{\"internalType\":\"address\",\"name\":\"marketToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"marketAmount\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"maxGoldIn\",\"type\":\"uint256\"}],\"internalType\":\"struct Mission\",\"name\":\"activeMission\",\"type\":\"tuple\"},{\"internalType\":\"uint8\",\"name\":\"effectiveRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"derivedAtTick\",\"type\":\"uint64\"}],\"internalType\":\"struct DerivedClansmanState\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"getMarketState\",\"outputs\":[{\"components\":[{\"components\":[{\"internalType\":\"address\",\"name\":\"resourceToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"resourceReserve\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"goldReserve\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"spotPriceGoldPerResource\",\"type\":\"uint256\"}],\"internalType\":\"struct PoolReserves\",\"name\":\"wood\",\"type\":\"tuple\"},{\"components\":[{\"internalType\":\"address\",\"name\":\"resourceToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"resourceReserve\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"goldReserve\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"spotPriceGoldPerResource\",\"type\":\"uint256\"}],\"internalType\":\"struct PoolReserves\",\"name\":\"wheat\",\"type\":\"tuple\"},{\"components\":[{\"internalType\":\"address\",\"name\":\"resourceToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"resourceReserve\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"goldReserve\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"spotPriceGoldPerResource\",\"type\":\"uint256\"}],\"internalType\":\"struct PoolReserves\",\"name\":\"fish\",\"type\":\"tuple\"},{\"components\":[{\"internalType\":\"address\",\"name\":\"resourceToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"resourceReserve\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"goldReserve\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"spotPriceGoldPerResource\",\"type\":\"uint256\"}],\"internalType\":\"struct PoolReserves\",\"name\":\"iron\",\"type\":\"tuple\"},{\"internalType\":\"uint64\",\"name\":\"currentTick\",\"type\":\"uint64\"},{\"components\":[{\"internalType\":\"uint64\",\"name\":\"executeAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"commitSequence\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"missionNonce\",\"type\":\"uint64\"},{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"internalType\":\"address\",\"name\":\"marketToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"marketAmount\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"maxGoldIn\",\"type\":\"uint256\"}],\"internalType\":\"struct ScheduledMarketAction[]\",\"name\":\"currentTickQueue\",\"type\":\"tuple[]\"},{\"components\":[{\"internalType\":\"uint64\",\"name\":\"executeAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"commitSequence\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"missionNonce\",\"type\":\"uint64\"},{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"internalType\":\"address\",\"name\":\"marketToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"marketAmount\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"maxGoldIn\",\"type\":\"uint256\"}],\"internalType\":\"struct ScheduledMarketAction[]\",\"name\":\"nextTickQueue\",\"type\":\"tuple[]\"}],\"internalType\":\"struct MarketState\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"}],\"name\":\"getMissionTiming\",\"outputs\":[{\"internalType\":\"uint64\",\"name\":\"submitted\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"executes\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"settles\",\"type\":\"uint64\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint8\",\"name\":\"region\",\"type\":\"uint8\"}],\"name\":\"getRegionPopulation\",\"outputs\":[{\"components\":[{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"enum ClansmanState\",\"name\":\"state\",\"type\":\"uint8\"},{\"internalType\":\"enum ActionType\",\"name\":\"currentAction\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"missionNonce\",\"type\":\"uint64\"}],\"internalType\":\"struct RegionOccupant[]\",\"name\":\"\",\"type\":\"tuple[]\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint64\",\"name\":\"tick\",\"type\":\"uint64\"}],\"name\":\"getScheduledMarketActionsForTick\",\"outputs\":[{\"components\":[{\"internalType\":\"uint64\",\"name\":\"executeAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"commitSequence\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"missionNonce\",\"type\":\"uint64\"},{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"internalType\":\"address\",\"name\":\"marketToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"marketAmount\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"maxGoldIn\",\"type\":\"uint256\"}],\"internalType\":\"struct ScheduledMarketAction[]\",\"name\":\"\",\"type\":\"tuple[]\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint8\",\"name\":\"fromRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"toRegion\",\"type\":\"uint8\"}],\"name\":\"getTravelTicks\",\"outputs\":[{\"internalType\":\"uint64\",\"name\":\"\",\"type\":\"uint64\"}],\"stateMutability\":\"pure\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"getTreasuryState\",\"outputs\":[{\"components\":[{\"internalType\":\"address\",\"name\":\"treasuryOwner\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"prizePotGold\",\"type\":\"uint256\"},{\"internalType\":\"bool\",\"name\":\"poolsSeeded\",\"type\":\"bool\"},{\"internalType\":\"address\",\"name\":\"woodToken\",\"type\":\"address\"},{\"internalType\":\"address\",\"name\":\"wheatToken\",\"type\":\"address\"},{\"internalType\":\"address\",\"name\":\"fishToken\",\"type\":\"address\"},{\"internalType\":\"address\",\"name\":\"ironToken\",\"type\":\"address\"},{\"internalType\":\"address\",\"name\":\"goldToken\",\"type\":\"address\"},{\"internalType\":\"address\",\"name\":\"blueprintToken\",\"type\":\"address\"},{\"internalType\":\"address\",\"name\":\"woodGoldPool\",\"type\":\"address\"},{\"internalType\":\"address\",\"name\":\"wheatGoldPool\",\"type\":\"address\"},{\"internalType\":\"address\",\"name\":\"fishGoldPool\",\"type\":\"address\"},{\"internalType\":\"address\",\"name\":\"ironGoldPool\",\"type\":\"address\"}],\"internalType\":\"struct TreasuryState\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"}],\"name\":\"getWheatPlots\",\"outputs\":[{\"components\":[{\"internalType\":\"enum WheatPlotState\",\"name\":\"state\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"region\",\"type\":\"uint8\"},{\"internalType\":\"uint256\",\"name\":\"remainingWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint64\",\"name\":\"regrowUntilTick\",\"type\":\"uint64\"}],\"internalType\":\"struct WheatPlot\",\"name\":\"west\",\"type\":\"tuple\"},{\"components\":[{\"internalType\":\"enum WheatPlotState\",\"name\":\"state\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"region\",\"type\":\"uint8\"},{\"internalType\":\"uint256\",\"name\":\"remainingWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint64\",\"name\":\"regrowUntilTick\",\"type\":\"uint64\"}],\"internalType\":\"struct WheatPlot\",\"name\":\"east\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"getWorldSnapshot\",\"outputs\":[{\"components\":[{\"internalType\":\"uint64\",\"name\":\"currentTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"seasonStartTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"seasonEndTick\",\"type\":\"uint64\"},{\"internalType\":\"bool\",\"name\":\"seasonFinalized\",\"type\":\"bool\"},{\"internalType\":\"uint64\",\"name\":\"currentSeasonNumber\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"nextHeartbeatAtTick\",\"type\":\"uint64\"},{\"internalType\":\"bool\",\"name\":\"winterActive\",\"type\":\"bool\"},{\"internalType\":\"uint64\",\"name\":\"winterStartsAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"winterEndsAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint32\",\"name\":\"activeBanditId\",\"type\":\"uint32\"},{\"internalType\":\"bytes32\",\"name\":\"currentTickSeed\",\"type\":\"bytes32\"},{\"components\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"address\",\"name\":\"owner\",\"type\":\"address\"},{\"internalType\":\"uint8\",\"name\":\"monumentLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"baseLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"wallLevel\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"livingClansmen\",\"type\":\"uint8\"},{\"internalType\":\"enum ClanState\",\"name\":\"state\",\"type\":\"uint8\"},{\"internalType\":\"uint256\",\"name\":\"lootValue\",\"type\":\"uint256\"}],\"internalType\":\"struct LeaderboardEntry[]\",\"name\":\"leaderboard\",\"type\":\"tuple[]\"}],\"internalType\":\"struct WorldSnapshot\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"getWorldState\",\"outputs\":[{\"components\":[{\"internalType\":\"uint64\",\"name\":\"currentTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"seasonStartTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"seasonEndTick\",\"type\":\"uint64\"},{\"internalType\":\"bool\",\"name\":\"seasonFinalized\",\"type\":\"bool\"},{\"internalType\":\"uint64\",\"name\":\"currentSeasonNumber\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"nextHeartbeatAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"nextHeartbeatAtTs\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"nextBanditSpawnEligibleTick\",\"type\":\"uint64\"},{\"internalType\":\"uint16\",\"name\":\"currentBanditSpawnChanceBps\",\"type\":\"uint16\"},{\"internalType\":\"bytes32\",\"name\":\"currentTickSeed\",\"type\":\"bytes32\"},{\"internalType\":\"uint32\",\"name\":\"activeBanditId\",\"type\":\"uint32\"},{\"internalType\":\"bool\",\"name\":\"winterActive\",\"type\":\"bool\"},{\"internalType\":\"uint64\",\"name\":\"winterStartsAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"winterEndsAtTick\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"nextCommitSequence\",\"type\":\"uint64\"}],\"internalType\":\"struct WorldState\",\"name\":\"\",\"type\":\"tuple\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"heartbeat\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"address[6]\",\"name\":\"tokens\",\"type\":\"address[6]\"},{\"internalType\":\"address[4]\",\"name\":\"pools\",\"type\":\"address[4]\"}],\"name\":\"initTreasury\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"address\",\"name\":\"to\",\"type\":\"address\"}],\"name\":\"mintClan\",\"outputs\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"internalType\":\"uint256\",\"name\":\"iftTokenId\",\"type\":\"uint256\"}],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"}],\"name\":\"quoteLootValueRaw\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"lootValue\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"}],\"name\":\"quoteLootValueSettled\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"lootValue\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint8\",\"name\":\"srcRegion\",\"type\":\"uint8\"},{\"internalType\":\"uint8\",\"name\":\"dstRegion\",\"type\":\"uint8\"}],\"name\":\"quoteTravel\",\"outputs\":[{\"internalType\":\"uint8\",\"name\":\"travelTicks\",\"type\":\"uint8\"},{\"internalType\":\"bytes8\",\"name\":\"path\",\"type\":\"bytes8\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"components\":[{\"internalType\":\"uint256\",\"name\":\"woodSeed\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"wheatSeed\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"fishSeed\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"ironSeed\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"goldSeedForWood\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"goldSeedForWheat\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"goldSeedForFish\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"goldSeedForIron\",\"type\":\"uint256\"}],\"internalType\":\"struct PoolSeedConfig\",\"name\":\"cfg\",\"type\":\"tuple\"}],\"name\":\"seedPools\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"}],\"name\":\"settleClan\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"csId\",\"type\":\"uint32\"}],\"name\":\"settleClansman\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"clanId\",\"type\":\"uint32\"},{\"components\":[{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"uint8\",\"name\":\"gotoRegion\",\"type\":\"uint8\"},{\"internalType\":\"enum ActionType\",\"name\":\"action\",\"type\":\"uint8\"},{\"internalType\":\"uint32\",\"name\":\"targetClanId\",\"type\":\"uint32\"},{\"internalType\":\"address\",\"name\":\"marketToken\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"marketAmount\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"maxGoldIn\",\"type\":\"uint256\"}],\"internalType\":\"struct ClanOrder[]\",\"name\":\"orders\",\"type\":\"tuple[]\"}],\"name\":\"submitClanOrders\",\"outputs\":[{\"components\":[{\"internalType\":\"uint32\",\"name\":\"clansmanId\",\"type\":\"uint32\"},{\"internalType\":\"enum StatusCode\",\"name\":\"status\",\"type\":\"uint8\"},{\"internalType\":\"uint64\",\"name\":\"cooldownEndsAtTs\",\"type\":\"uint64\"},{\"internalType\":\"uint64\",\"name\":\"missionNonce\",\"type\":\"uint64\"}],\"internalType\":\"struct OrderResult[]\",\"name\":\"\",\"type\":\"tuple[]\"}],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"fromClanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"toClanId\",\"type\":\"uint32\"},{\"internalType\":\"uint256\",\"name\":\"amount\",\"type\":\"uint256\"}],\"name\":\"transferBlueprint\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"fromClanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"toClanId\",\"type\":\"uint32\"},{\"internalType\":\"uint256\",\"name\":\"gold\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"blueprint\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"wood\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"iron\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"wheat\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"fish\",\"type\":\"uint256\"}],\"name\":\"transferBundle\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"fromClanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"toClanId\",\"type\":\"uint32\"},{\"internalType\":\"uint256\",\"name\":\"amount\",\"type\":\"uint256\"}],\"name\":\"transferGold\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint32\",\"name\":\"fromClanId\",\"type\":\"uint32\"},{\"internalType\":\"uint32\",\"name\":\"toClanId\",\"type\":\"uint32\"},{\"internalType\":\"enum ResourceType\",\"name\":\"resource\",\"type\":\"uint8\"},{\"internalType\":\"uint256\",\"name\":\"amount\",\"type\":\"uint256\"}],\"name\":\"transferVaultResource\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"}],\"devdoc\":{\"kind\":\"dev\",\"methods\":{},\"version\":1},\"userdoc\":{\"kind\":\"user\",\"methods\":{\"finalizeSeason()\":{\"notice\":\"Finalize the current season. Permissionless after seasonEndTick.\"},\"getActiveBanditView()\":{\"notice\":\"Single-call bandit drama state, including projected target if         attack resolved this tick. Drives the bandit warning UI.\"},\"getBanditTargetPreview(uint32)\":{\"notice\":\"Non-binding preview. Bandit targeting is recomputed at attack         resolution time using then-current eagerly settled state.\"},\"getClanFullView(uint32)\":{\"notice\":\"Single-call complete clan rendering data: derived clan + all         clansmen with derived state and active missions + plot states +         defender bookkeeping. Drives the entire sprite layer.\"},\"getMarketState()\":{\"notice\":\"Single-call market panel data: 4 pool reserves + spot prices +         scheduled queues for current and next tick. Drives market UI         and indexer's per-tick price-history sampling.\"},\"getRegionPopulation(uint8)\":{\"notice\":\"Optional. List clansmen currently in a region for tap-to-inspect         tooltips. Can be derived clientside; included for completeness.\"},\"getWorldSnapshot()\":{\"notice\":\"Single-call top-level world state plus per-clan leaderboard data.         Drives top HUD bar, season clock, winter indicator, leaderboard.\"},\"heartbeat()\":{\"notice\":\"Permissionless heartbeat. Closes the current tick, resolves         scheduled market actions and world events, advances the tick.         Rate-limited by WorldState.nextHeartbeatAtTs.\"},\"initTreasury(address[6],address[4])\":{\"notice\":\"Owner-only. Registers token and pool addresses once before seeding.         tokens order: wood, iron, wheat, fish, gold, blueprint.         pools order: wood, wheat, fish, iron.\"},\"mintClan(address)\":{\"notice\":\"Mint a new clan iNFT and spawn its homebase in a valid region.\"},\"seedPools((uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256))\":{\"notice\":\"Owner-only. Seeds the four Unicorn Town pools at deploy time.\"},\"settleClan(uint32)\":{\"notice\":\"Lazily settle a clan forward to current tick. Idempotent.\"},\"settleClansman(uint32)\":{\"notice\":\"Lazily settle a single clansman's mission to current tick. Idempotent.\"},\"submitClanOrders(uint32,(uint32,uint8,uint8,uint32,address,uint256,uint256)[])\":{\"notice\":\"Submit one or more orders for a single clan's clansmen.         Per-order failures do not revert the tx.\"}},\"version\":1}},\"settings\":{\"compilationTarget\":{\"src/IClanWorld.sol\":\"IClanWorld\"},\"evmVersion\":\"prague\",\"libraries\":{},\"metadata\":{\"bytecodeHash\":\"ipfs\"},\"optimizer\":{\"enabled\":true,\"runs\":200},\"remappings\":[\":forge-std/=lib/forge-std/src/\"],\"viaIR\":true},\"sources\":{\"src/IClanWorld.sol\":{\"keccak256\":\"0xaef95040130eb2fb1f96d948f2af3b1946943b8e63dbb43c46a9db2cd8df6835\",\"license\":\"MIT\",\"urls\":[\"bzz-raw://64cae733ba6ac28007dff7df0c27b4dde9edfb5903e8063791332321b7a33c63\",\"dweb:/ipfs/QmbbnVbgcGkA4kYayrA9zbiz72cMjJtQhPeXAbd6Yn6xfY\"]}},\"version\":1}","metadata":{"compiler":{"version":"0.8.34+commit.80d5c536"},"language":"Solidity","output":{"abi":[{"inputs":[{"internalType":"uint32","name":"banditId","type":"uint32","indexed":true},{"internalType":"uint32","name":"targetClanId","type":"uint32","indexed":true},{"internalType":"bool","name":"defended","type":"bool","indexed":false},{"internalType":"uint16","name":"attackPower","type":"uint16","indexed":false},{"internalType":"uint16","name":"totalDefense","type":"uint16","indexed":false},{"internalType":"uint16","name":"wallLevelAfter","type":"uint16","indexed":false},{"internalType":"uint256","name":"stolenWood","type":"uint256","indexed":false},{"internalType":"uint256","name":"stolenIron","type":"uint256","indexed":false},{"internalType":"uint256","name":"stolenWheat","type":"uint256","indexed":false},{"internalType":"uint256","name":"stolenFish","type":"uint256","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"BanditAttackResolved","anonymous":false},{"inputs":[{"internalType":"uint32","name":"banditId","type":"uint32","indexed":true},{"internalType":"uint32","name":"targetClanId","type":"uint32","indexed":true},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"BanditDefeated","anonymous":false},{"inputs":[{"internalType":"uint32","name":"banditId","type":"uint32","indexed":true},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"BanditEscaped","anonymous":false},{"inputs":[{"internalType":"uint32","name":"banditId","type":"uint32","indexed":true},{"internalType":"uint8","name":"fromRegion","type":"uint8","indexed":false},{"internalType":"uint8","name":"toRegion","type":"uint8","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"BanditMoved","anonymous":false},{"inputs":[{"internalType":"uint32","name":"banditId","type":"uint32","indexed":true},{"internalType":"uint8","name":"region","type":"uint8","indexed":false},{"internalType":"uint8","name":"tier","type":"uint8","indexed":false},{"internalType":"uint16","name":"attackPower","type":"uint16","indexed":false}],"type":"event","name":"BanditSpawned","anonymous":false},{"inputs":[{"internalType":"uint32","name":"banditId","type":"uint32","indexed":true},{"internalType":"enum BanditState","name":"oldState","type":"uint8","indexed":false},{"internalType":"enum BanditState","name":"newState","type":"uint8","indexed":false},{"internalType":"uint8","name":"region","type":"uint8","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"BanditStateChanged","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint8","name":"oldLevel","type":"uint8","indexed":false},{"internalType":"uint8","name":"newLevel","type":"uint8","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"BaseLevelChanged","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"banditId","type":"uint32","indexed":true},{"internalType":"uint256","name":"amount","type":"uint256","indexed":false}],"type":"event","name":"BlueprintAwarded","anonymous":false},{"inputs":[{"internalType":"uint32","name":"fromClanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"toClanId","type":"uint32","indexed":true},{"internalType":"uint256","name":"amount","type":"uint256","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"BlueprintTransferred","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint64","name":"tick","type":"uint64","indexed":true}],"type":"event","name":"ClanEliminated","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint64","name":"settledToTick","type":"uint64","indexed":false}],"type":"event","name":"ClanSettled","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"address","name":"owner","type":"address","indexed":true},{"internalType":"uint256","name":"iftTokenId","type":"uint256","indexed":false},{"internalType":"uint8","name":"baseRegion","type":"uint8","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"ClanSpawned","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"bool","name":"isStarving","type":"bool","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"ClanStarvationChanged","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"ClansmanDiedFromCold","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint16","name":"oldDamage","type":"uint16","indexed":false},{"internalType":"uint16","name":"newDamage","type":"uint16","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"ColdDamageApplied","anonymous":false},{"inputs":[{"internalType":"uint32","name":"fromClanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"toClanId","type":"uint32","indexed":true},{"internalType":"uint256","name":"amount","type":"uint256","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"GoldTransferred","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clansmanId","type":"uint32","indexed":true},{"internalType":"address","name":"tokenIn","type":"address","indexed":false},{"internalType":"address","name":"tokenOut","type":"address","indexed":false},{"internalType":"uint256","name":"amountIn","type":"uint256","indexed":false},{"internalType":"uint256","name":"amountOut","type":"uint256","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"ImmediateMarketActionExecuted","anonymous":false},{"inputs":[{"internalType":"uint32","name":"banditId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clansmanId","type":"uint32","indexed":true},{"internalType":"uint256","name":"wood","type":"uint256","indexed":false},{"internalType":"uint256","name":"iron","type":"uint256","indexed":false},{"internalType":"uint256","name":"wheat","type":"uint256","indexed":false},{"internalType":"uint256","name":"fish","type":"uint256","indexed":false}],"type":"event","name":"LootDistributedToDefender","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clansmanId","type":"uint32","indexed":true},{"internalType":"enum ActionType","name":"action","type":"uint8","indexed":false},{"internalType":"enum StatusCode","name":"reason","type":"uint8","indexed":false}],"type":"event","name":"MarketActionFailed","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clansmanId","type":"uint32","indexed":true},{"internalType":"uint64","name":"missionNonce","type":"uint64","indexed":false},{"internalType":"enum ActionType","name":"action","type":"uint8","indexed":false},{"internalType":"uint8","name":"startRegion","type":"uint8","indexed":false},{"internalType":"uint8","name":"targetRegion","type":"uint8","indexed":false},{"internalType":"uint64","name":"startTick","type":"uint64","indexed":false},{"internalType":"uint64","name":"arrivalTick","type":"uint64","indexed":false}],"type":"event","name":"MissionAssigned","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clansmanId","type":"uint32","indexed":true},{"internalType":"uint64","name":"missionNonce","type":"uint64","indexed":false},{"internalType":"enum ActionType","name":"action","type":"uint8","indexed":false}],"type":"event","name":"MissionCompleted","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clansmanId","type":"uint32","indexed":true},{"internalType":"uint64","name":"oldMissionNonce","type":"uint64","indexed":false},{"internalType":"uint64","name":"newMissionNonce","type":"uint64","indexed":false}],"type":"event","name":"MissionInterrupted","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint8","name":"oldLevel","type":"uint8","indexed":false},{"internalType":"uint8","name":"newLevel","type":"uint8","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"MonumentLevelChanged","anonymous":false},{"inputs":[{"internalType":"address","name":"woodGoldPool","type":"address","indexed":false},{"internalType":"address","name":"wheatGoldPool","type":"address","indexed":false},{"internalType":"address","name":"fishGoldPool","type":"address","indexed":false},{"internalType":"address","name":"ironGoldPool","type":"address","indexed":false}],"type":"event","name":"PoolsSeeded","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clansmanId","type":"uint32","indexed":true},{"internalType":"uint256","name":"woodDelta","type":"uint256","indexed":false},{"internalType":"uint256","name":"ironDelta","type":"uint256","indexed":false},{"internalType":"uint256","name":"wheatDelta","type":"uint256","indexed":false},{"internalType":"uint256","name":"fishDelta","type":"uint256","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"ResourcesDeposited","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clansmanId","type":"uint32","indexed":true},{"internalType":"enum ActionType","name":"action","type":"uint8","indexed":false},{"internalType":"uint256","name":"woodGained","type":"uint256","indexed":false},{"internalType":"uint256","name":"ironGained","type":"uint256","indexed":false},{"internalType":"uint256","name":"wheatGained","type":"uint256","indexed":false},{"internalType":"uint256","name":"fishGained","type":"uint256","indexed":false},{"internalType":"uint256","name":"goldBonus","type":"uint256","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"ResourcesGathered","anonymous":false},{"inputs":[{"internalType":"uint64","name":"executeAtTick","type":"uint64","indexed":true},{"internalType":"uint64","name":"commitSequence","type":"uint64","indexed":true},{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clansmanId","type":"uint32","indexed":false},{"internalType":"enum ActionType","name":"action","type":"uint8","indexed":false},{"internalType":"address","name":"marketToken","type":"address","indexed":false},{"internalType":"uint256","name":"marketAmount","type":"uint256","indexed":false},{"internalType":"uint256","name":"maxGoldIn","type":"uint256","indexed":false}],"type":"event","name":"ScheduledMarketActionCommitted","anonymous":false},{"inputs":[{"internalType":"uint64","name":"executeAtTick","type":"uint64","indexed":true},{"internalType":"uint64","name":"commitSequence","type":"uint64","indexed":true},{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clansmanId","type":"uint32","indexed":false},{"internalType":"address","name":"tokenIn","type":"address","indexed":false},{"internalType":"address","name":"tokenOut","type":"address","indexed":false},{"internalType":"uint256","name":"amountIn","type":"uint256","indexed":false},{"internalType":"uint256","name":"amountOut","type":"uint256","indexed":false}],"type":"event","name":"ScheduledMarketActionExecuted","anonymous":false},{"inputs":[{"internalType":"uint64","name":"tick","type":"uint64","indexed":true},{"internalType":"uint32[]","name":"rankedClanIds","type":"uint32[]","indexed":false}],"type":"event","name":"SeasonFinalized","anonymous":false},{"inputs":[{"internalType":"uint64","name":"closedTick","type":"uint64","indexed":false},{"internalType":"uint64","name":"openedTick","type":"uint64","indexed":false},{"internalType":"bytes32","name":"tickSeed","type":"bytes32","indexed":false}],"type":"event","name":"TickAdvanced","anonymous":false},{"inputs":[{"internalType":"uint32","name":"fromClanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"toClanId","type":"uint32","indexed":true},{"internalType":"enum ResourceType","name":"resource","type":"uint8","indexed":false},{"internalType":"uint256","name":"amount","type":"uint256","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"VaultResourceTransferred","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint8","name":"oldLevel","type":"uint8","indexed":false},{"internalType":"uint8","name":"newLevel","type":"uint8","indexed":false},{"internalType":"uint64","name":"atTick","type":"uint64","indexed":false}],"type":"event","name":"WallLevelChanged","anonymous":false},{"inputs":[{"internalType":"uint64","name":"tick","type":"uint64","indexed":true}],"type":"event","name":"WinterEnded","anonymous":false},{"inputs":[{"internalType":"uint64","name":"tick","type":"uint64","indexed":true}],"type":"event","name":"WinterStarted","anonymous":false},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32","indexed":true},{"internalType":"uint32","name":"clansmanId","type":"uint32","indexed":true},{"internalType":"uint8","name":"region","type":"uint8","indexed":false},{"internalType":"uint64","name":"tick","type":"uint64","indexed":false}],"type":"event","name":"WorkerArrived","anonymous":false},{"inputs":[],"stateMutability":"nonpayable","type":"function","name":"finalizeSeason"},{"inputs":[{"internalType":"enum ActionType","name":"action","type":"uint8"}],"stateMutability":"pure","type":"function","name":"getActionDuration","outputs":[{"internalType":"uint64","name":"","type":"uint64"}]},{"inputs":[],"stateMutability":"view","type":"function","name":"getActiveBanditView","outputs":[{"internalType":"struct ActiveBanditView","name":"","type":"tuple","components":[{"internalType":"bool","name":"exists","type":"bool"},{"internalType":"uint32","name":"banditId","type":"uint32"},{"internalType":"enum BanditState","name":"state","type":"uint8"},{"internalType":"uint8","name":"currentRegion","type":"uint8"},{"internalType":"uint8","name":"attackAttemptsMade","type":"uint8"},{"internalType":"uint8","name":"maxAttemptsRemaining","type":"uint8"},{"internalType":"uint64","name":"stateEnteredTick","type":"uint64"},{"internalType":"uint64","name":"nextActionTick","type":"uint64"},{"internalType":"uint8","name":"tier","type":"uint8"},{"internalType":"uint16","name":"attackPower","type":"uint16"},{"internalType":"uint256","name":"carryWood","type":"uint256"},{"internalType":"uint256","name":"carryIron","type":"uint256"},{"internalType":"uint256","name":"carryWheat","type":"uint256"},{"internalType":"uint256","name":"carryFish","type":"uint256"},{"internalType":"uint32","name":"projectedTargetClanId","type":"uint32"},{"internalType":"uint256","name":"projectedTargetLootValue","type":"uint256"}]}]},{"inputs":[{"internalType":"uint32","name":"targetClanId","type":"uint32"}],"stateMutability":"view","type":"function","name":"getActiveDefenders","outputs":[{"internalType":"uint32[]","name":"clansmanIds","type":"uint32[]"}]},{"inputs":[{"internalType":"uint32","name":"clansmanId","type":"uint32"}],"stateMutability":"view","type":"function","name":"getActiveMission","outputs":[{"internalType":"struct Mission","name":"","type":"tuple","components":[{"internalType":"bool","name":"active","type":"bool"},{"internalType":"uint64","name":"nonce","type":"uint64"},{"internalType":"uint64","name":"submittedAtTick","type":"uint64"},{"internalType":"uint64","name":"executesAtTick","type":"uint64"},{"internalType":"uint64","name":"settlesAtTick","type":"uint64"},{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"uint8","name":"startRegion","type":"uint8"},{"internalType":"uint8","name":"targetRegion","type":"uint8"},{"internalType":"enum ActionType","name":"action","type":"uint8"},{"internalType":"uint64","name":"startTick","type":"uint64"},{"internalType":"uint64","name":"arrivalTick","type":"uint64"},{"internalType":"uint64","name":"actionStartTick","type":"uint64"},{"internalType":"bytes32","name":"missionSeed","type":"bytes32"},{"internalType":"enum MarketExecutionMode","name":"marketMode","type":"uint8"},{"internalType":"uint32","name":"targetClanId","type":"uint32"},{"internalType":"address","name":"marketToken","type":"address"},{"internalType":"uint256","name":"marketAmount","type":"uint256"},{"internalType":"uint256","name":"maxGoldIn","type":"uint256"}]}]},{"inputs":[{"internalType":"uint32","name":"banditId","type":"uint32"}],"stateMutability":"view","type":"function","name":"getBanditTargetPreview","outputs":[{"internalType":"uint32","name":"previewClanId","type":"uint32"}]},{"inputs":[{"internalType":"uint32","name":"banditId","type":"uint32"}],"stateMutability":"view","type":"function","name":"getBanditTroop","outputs":[{"internalType":"struct BanditTroop","name":"","type":"tuple","components":[{"internalType":"uint32","name":"banditId","type":"uint32"},{"internalType":"enum BanditState","name":"state","type":"uint8"},{"internalType":"uint8","name":"currentRegion","type":"uint8"},{"internalType":"uint8","name":"attackAttemptsMade","type":"uint8"},{"internalType":"uint64","name":"stateEnteredTick","type":"uint64"},{"internalType":"uint64","name":"nextActionTick","type":"uint64"},{"internalType":"uint8","name":"tier","type":"uint8"},{"internalType":"uint16","name":"attackPower","type":"uint16"},{"internalType":"uint256","name":"carryWood","type":"uint256"},{"internalType":"uint256","name":"carryIron","type":"uint256"},{"internalType":"uint256","name":"carryWheat","type":"uint256"},{"internalType":"uint256","name":"carryFish","type":"uint256"}]}]},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32"}],"stateMutability":"view","type":"function","name":"getClan","outputs":[{"internalType":"struct Clan","name":"","type":"tuple","components":[{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"uint256","name":"iftTokenId","type":"uint256"},{"internalType":"address","name":"owner","type":"address"},{"internalType":"enum ClanState","name":"clanState","type":"uint8"},{"internalType":"uint8","name":"baseRegion","type":"uint8"},{"internalType":"uint8","name":"baseLevel","type":"uint8"},{"internalType":"uint8","name":"wallLevel","type":"uint8"},{"internalType":"uint8","name":"monumentLevel","type":"uint8"},{"internalType":"uint8","name":"livingClansmen","type":"uint8"},{"internalType":"uint64","name":"lastSettledTick","type":"uint64"},{"internalType":"uint64","name":"starvationStartsAtTick","type":"uint64"},{"internalType":"uint16","name":"coldDamage","type":"uint16"},{"internalType":"uint256","name":"goldBalance","type":"uint256"},{"internalType":"uint256","name":"blueprintBalance","type":"uint256"},{"internalType":"uint256","name":"vaultWood","type":"uint256"},{"internalType":"uint256","name":"vaultIron","type":"uint256"},{"internalType":"uint256","name":"vaultWheat","type":"uint256"},{"internalType":"uint256","name":"vaultFish","type":"uint256"}]}]},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32"}],"stateMutability":"view","type":"function","name":"getClanFullView","outputs":[{"internalType":"struct ClanFullView","name":"","type":"tuple","components":[{"internalType":"struct DerivedClanState","name":"clan","type":"tuple","components":[{"internalType":"struct Clan","name":"clan","type":"tuple","components":[{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"uint256","name":"iftTokenId","type":"uint256"},{"internalType":"address","name":"owner","type":"address"},{"internalType":"enum ClanState","name":"clanState","type":"uint8"},{"internalType":"uint8","name":"baseRegion","type":"uint8"},{"internalType":"uint8","name":"baseLevel","type":"uint8"},{"internalType":"uint8","name":"wallLevel","type":"uint8"},{"internalType":"uint8","name":"monumentLevel","type":"uint8"},{"internalType":"uint8","name":"livingClansmen","type":"uint8"},{"internalType":"uint64","name":"lastSettledTick","type":"uint64"},{"internalType":"uint64","name":"starvationStartsAtTick","type":"uint64"},{"internalType":"uint16","name":"coldDamage","type":"uint16"},{"internalType":"uint256","name":"goldBalance","type":"uint256"},{"internalType":"uint256","name":"blueprintBalance","type":"uint256"},{"internalType":"uint256","name":"vaultWood","type":"uint256"},{"internalType":"uint256","name":"vaultIron","type":"uint256"},{"internalType":"uint256","name":"vaultWheat","type":"uint256"},{"internalType":"uint256","name":"vaultFish","type":"uint256"}]},{"internalType":"bool","name":"isStarving","type":"bool"},{"internalType":"uint256","name":"lootValue","type":"uint256"},{"internalType":"uint64","name":"derivedAtTick","type":"uint64"}]},{"internalType":"struct ClansmanFullView[]","name":"clansmen","type":"tuple[]","components":[{"internalType":"struct DerivedClansmanState","name":"clansman","type":"tuple","components":[{"internalType":"struct Clansman","name":"clansman","type":"tuple","components":[{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"enum ClansmanState","name":"state","type":"uint8"},{"internalType":"uint8","name":"currentRegion","type":"uint8"},{"internalType":"uint64","name":"cooldownEndsAtTs","type":"uint64"},{"internalType":"uint64","name":"lastMissionNonce","type":"uint64"},{"internalType":"uint256","name":"carryWood","type":"uint256"},{"internalType":"uint256","name":"carryIron","type":"uint256"},{"internalType":"uint256","name":"carryWheat","type":"uint256"},{"internalType":"uint256","name":"carryFish","type":"uint256"}]},{"internalType":"struct Mission","name":"activeMission","type":"tuple","components":[{"internalType":"bool","name":"active","type":"bool"},{"internalType":"uint64","name":"nonce","type":"uint64"},{"internalType":"uint64","name":"submittedAtTick","type":"uint64"},{"internalType":"uint64","name":"executesAtTick","type":"uint64"},{"internalType":"uint64","name":"settlesAtTick","type":"uint64"},{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"uint8","name":"startRegion","type":"uint8"},{"internalType":"uint8","name":"targetRegion","type":"uint8"},{"internalType":"enum ActionType","name":"action","type":"uint8"},{"internalType":"uint64","name":"startTick","type":"uint64"},{"internalType":"uint64","name":"arrivalTick","type":"uint64"},{"internalType":"uint64","name":"actionStartTick","type":"uint64"},{"internalType":"bytes32","name":"missionSeed","type":"bytes32"},{"internalType":"enum MarketExecutionMode","name":"marketMode","type":"uint8"},{"internalType":"uint32","name":"targetClanId","type":"uint32"},{"internalType":"address","name":"marketToken","type":"address"},{"internalType":"uint256","name":"marketAmount","type":"uint256"},{"internalType":"uint256","name":"maxGoldIn","type":"uint256"}]},{"internalType":"uint8","name":"effectiveRegion","type":"uint8"},{"internalType":"uint64","name":"derivedAtTick","type":"uint64"}]},{"internalType":"struct Mission","name":"activeMission","type":"tuple","components":[{"internalType":"bool","name":"active","type":"bool"},{"internalType":"uint64","name":"nonce","type":"uint64"},{"internalType":"uint64","name":"submittedAtTick","type":"uint64"},{"internalType":"uint64","name":"executesAtTick","type":"uint64"},{"internalType":"uint64","name":"settlesAtTick","type":"uint64"},{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"uint8","name":"startRegion","type":"uint8"},{"internalType":"uint8","name":"targetRegion","type":"uint8"},{"internalType":"enum ActionType","name":"action","type":"uint8"},{"internalType":"uint64","name":"startTick","type":"uint64"},{"internalType":"uint64","name":"arrivalTick","type":"uint64"},{"internalType":"uint64","name":"actionStartTick","type":"uint64"},{"internalType":"bytes32","name":"missionSeed","type":"bytes32"},{"internalType":"enum MarketExecutionMode","name":"marketMode","type":"uint8"},{"internalType":"uint32","name":"targetClanId","type":"uint32"},{"internalType":"address","name":"marketToken","type":"address"},{"internalType":"uint256","name":"marketAmount","type":"uint256"},{"internalType":"uint256","name":"maxGoldIn","type":"uint256"}]}]},{"internalType":"struct WheatPlot","name":"westPlot","type":"tuple","components":[{"internalType":"enum WheatPlotState","name":"state","type":"uint8"},{"internalType":"uint8","name":"region","type":"uint8"},{"internalType":"uint256","name":"remainingWheat","type":"uint256"},{"internalType":"uint64","name":"regrowUntilTick","type":"uint64"}]},{"internalType":"struct WheatPlot","name":"eastPlot","type":"tuple","components":[{"internalType":"enum WheatPlotState","name":"state","type":"uint8"},{"internalType":"uint8","name":"region","type":"uint8"},{"internalType":"uint256","name":"remainingWheat","type":"uint256"},{"internalType":"uint64","name":"regrowUntilTick","type":"uint64"}]},{"internalType":"uint32[]","name":"incomingDefenderIds","type":"uint32[]"},{"internalType":"uint32","name":"thisClanDefendingBaseId","type":"uint32"}]}]},{"inputs":[{"internalType":"uint32","name":"clansmanId","type":"uint32"}],"stateMutability":"view","type":"function","name":"getClansman","outputs":[{"internalType":"struct Clansman","name":"","type":"tuple","components":[{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"enum ClansmanState","name":"state","type":"uint8"},{"internalType":"uint8","name":"currentRegion","type":"uint8"},{"internalType":"uint64","name":"cooldownEndsAtTs","type":"uint64"},{"internalType":"uint64","name":"lastMissionNonce","type":"uint64"},{"internalType":"uint256","name":"carryWood","type":"uint256"},{"internalType":"uint256","name":"carryIron","type":"uint256"},{"internalType":"uint256","name":"carryWheat","type":"uint256"},{"internalType":"uint256","name":"carryFish","type":"uint256"}]}]},{"inputs":[{"internalType":"uint8","name":"region","type":"uint8"}],"stateMutability":"view","type":"function","name":"getDefendingClans","outputs":[{"internalType":"uint32[]","name":"clanIds","type":"uint32[]"}]},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32"}],"stateMutability":"view","type":"function","name":"getDerivedClanState","outputs":[{"internalType":"struct DerivedClanState","name":"","type":"tuple","components":[{"internalType":"struct Clan","name":"clan","type":"tuple","components":[{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"uint256","name":"iftTokenId","type":"uint256"},{"internalType":"address","name":"owner","type":"address"},{"internalType":"enum ClanState","name":"clanState","type":"uint8"},{"internalType":"uint8","name":"baseRegion","type":"uint8"},{"internalType":"uint8","name":"baseLevel","type":"uint8"},{"internalType":"uint8","name":"wallLevel","type":"uint8"},{"internalType":"uint8","name":"monumentLevel","type":"uint8"},{"internalType":"uint8","name":"livingClansmen","type":"uint8"},{"internalType":"uint64","name":"lastSettledTick","type":"uint64"},{"internalType":"uint64","name":"starvationStartsAtTick","type":"uint64"},{"internalType":"uint16","name":"coldDamage","type":"uint16"},{"internalType":"uint256","name":"goldBalance","type":"uint256"},{"internalType":"uint256","name":"blueprintBalance","type":"uint256"},{"internalType":"uint256","name":"vaultWood","type":"uint256"},{"internalType":"uint256","name":"vaultIron","type":"uint256"},{"internalType":"uint256","name":"vaultWheat","type":"uint256"},{"internalType":"uint256","name":"vaultFish","type":"uint256"}]},{"internalType":"bool","name":"isStarving","type":"bool"},{"internalType":"uint256","name":"lootValue","type":"uint256"},{"internalType":"uint64","name":"derivedAtTick","type":"uint64"}]}]},{"inputs":[{"internalType":"uint32","name":"clansmanId","type":"uint32"}],"stateMutability":"view","type":"function","name":"getDerivedClansmanState","outputs":[{"internalType":"struct DerivedClansmanState","name":"","type":"tuple","components":[{"internalType":"struct Clansman","name":"clansman","type":"tuple","components":[{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"enum ClansmanState","name":"state","type":"uint8"},{"internalType":"uint8","name":"currentRegion","type":"uint8"},{"internalType":"uint64","name":"cooldownEndsAtTs","type":"uint64"},{"internalType":"uint64","name":"lastMissionNonce","type":"uint64"},{"internalType":"uint256","name":"carryWood","type":"uint256"},{"internalType":"uint256","name":"carryIron","type":"uint256"},{"internalType":"uint256","name":"carryWheat","type":"uint256"},{"internalType":"uint256","name":"carryFish","type":"uint256"}]},{"internalType":"struct Mission","name":"activeMission","type":"tuple","components":[{"internalType":"bool","name":"active","type":"bool"},{"internalType":"uint64","name":"nonce","type":"uint64"},{"internalType":"uint64","name":"submittedAtTick","type":"uint64"},{"internalType":"uint64","name":"executesAtTick","type":"uint64"},{"internalType":"uint64","name":"settlesAtTick","type":"uint64"},{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"uint8","name":"startRegion","type":"uint8"},{"internalType":"uint8","name":"targetRegion","type":"uint8"},{"internalType":"enum ActionType","name":"action","type":"uint8"},{"internalType":"uint64","name":"startTick","type":"uint64"},{"internalType":"uint64","name":"arrivalTick","type":"uint64"},{"internalType":"uint64","name":"actionStartTick","type":"uint64"},{"internalType":"bytes32","name":"missionSeed","type":"bytes32"},{"internalType":"enum MarketExecutionMode","name":"marketMode","type":"uint8"},{"internalType":"uint32","name":"targetClanId","type":"uint32"},{"internalType":"address","name":"marketToken","type":"address"},{"internalType":"uint256","name":"marketAmount","type":"uint256"},{"internalType":"uint256","name":"maxGoldIn","type":"uint256"}]},{"internalType":"uint8","name":"effectiveRegion","type":"uint8"},{"internalType":"uint64","name":"derivedAtTick","type":"uint64"}]}]},{"inputs":[],"stateMutability":"view","type":"function","name":"getMarketState","outputs":[{"internalType":"struct MarketState","name":"","type":"tuple","components":[{"internalType":"struct PoolReserves","name":"wood","type":"tuple","components":[{"internalType":"address","name":"resourceToken","type":"address"},{"internalType":"uint256","name":"resourceReserve","type":"uint256"},{"internalType":"uint256","name":"goldReserve","type":"uint256"},{"internalType":"uint256","name":"spotPriceGoldPerResource","type":"uint256"}]},{"internalType":"struct PoolReserves","name":"wheat","type":"tuple","components":[{"internalType":"address","name":"resourceToken","type":"address"},{"internalType":"uint256","name":"resourceReserve","type":"uint256"},{"internalType":"uint256","name":"goldReserve","type":"uint256"},{"internalType":"uint256","name":"spotPriceGoldPerResource","type":"uint256"}]},{"internalType":"struct PoolReserves","name":"fish","type":"tuple","components":[{"internalType":"address","name":"resourceToken","type":"address"},{"internalType":"uint256","name":"resourceReserve","type":"uint256"},{"internalType":"uint256","name":"goldReserve","type":"uint256"},{"internalType":"uint256","name":"spotPriceGoldPerResource","type":"uint256"}]},{"internalType":"struct PoolReserves","name":"iron","type":"tuple","components":[{"internalType":"address","name":"resourceToken","type":"address"},{"internalType":"uint256","name":"resourceReserve","type":"uint256"},{"internalType":"uint256","name":"goldReserve","type":"uint256"},{"internalType":"uint256","name":"spotPriceGoldPerResource","type":"uint256"}]},{"internalType":"uint64","name":"currentTick","type":"uint64"},{"internalType":"struct ScheduledMarketAction[]","name":"currentTickQueue","type":"tuple[]","components":[{"internalType":"uint64","name":"executeAtTick","type":"uint64"},{"internalType":"uint64","name":"commitSequence","type":"uint64"},{"internalType":"uint64","name":"missionNonce","type":"uint64"},{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"enum ActionType","name":"action","type":"uint8"},{"internalType":"address","name":"marketToken","type":"address"},{"internalType":"uint256","name":"marketAmount","type":"uint256"},{"internalType":"uint256","name":"maxGoldIn","type":"uint256"}]},{"internalType":"struct ScheduledMarketAction[]","name":"nextTickQueue","type":"tuple[]","components":[{"internalType":"uint64","name":"executeAtTick","type":"uint64"},{"internalType":"uint64","name":"commitSequence","type":"uint64"},{"internalType":"uint64","name":"missionNonce","type":"uint64"},{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"enum ActionType","name":"action","type":"uint8"},{"internalType":"address","name":"marketToken","type":"address"},{"internalType":"uint256","name":"marketAmount","type":"uint256"},{"internalType":"uint256","name":"maxGoldIn","type":"uint256"}]}]}]},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"uint32","name":"clansmanId","type":"uint32"}],"stateMutability":"view","type":"function","name":"getMissionTiming","outputs":[{"internalType":"uint64","name":"submitted","type":"uint64"},{"internalType":"uint64","name":"executes","type":"uint64"},{"internalType":"uint64","name":"settles","type":"uint64"}]},{"inputs":[{"internalType":"uint8","name":"region","type":"uint8"}],"stateMutability":"view","type":"function","name":"getRegionPopulation","outputs":[{"internalType":"struct RegionOccupant[]","name":"","type":"tuple[]","components":[{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"enum ClansmanState","name":"state","type":"uint8"},{"internalType":"enum ActionType","name":"currentAction","type":"uint8"},{"internalType":"uint64","name":"missionNonce","type":"uint64"}]}]},{"inputs":[{"internalType":"uint64","name":"tick","type":"uint64"}],"stateMutability":"view","type":"function","name":"getScheduledMarketActionsForTick","outputs":[{"internalType":"struct ScheduledMarketAction[]","name":"","type":"tuple[]","components":[{"internalType":"uint64","name":"executeAtTick","type":"uint64"},{"internalType":"uint64","name":"commitSequence","type":"uint64"},{"internalType":"uint64","name":"missionNonce","type":"uint64"},{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"enum ActionType","name":"action","type":"uint8"},{"internalType":"address","name":"marketToken","type":"address"},{"internalType":"uint256","name":"marketAmount","type":"uint256"},{"internalType":"uint256","name":"maxGoldIn","type":"uint256"}]}]},{"inputs":[{"internalType":"uint8","name":"fromRegion","type":"uint8"},{"internalType":"uint8","name":"toRegion","type":"uint8"}],"stateMutability":"pure","type":"function","name":"getTravelTicks","outputs":[{"internalType":"uint64","name":"","type":"uint64"}]},{"inputs":[],"stateMutability":"view","type":"function","name":"getTreasuryState","outputs":[{"internalType":"struct TreasuryState","name":"","type":"tuple","components":[{"internalType":"address","name":"treasuryOwner","type":"address"},{"internalType":"uint256","name":"prizePotGold","type":"uint256"},{"internalType":"bool","name":"poolsSeeded","type":"bool"},{"internalType":"address","name":"woodToken","type":"address"},{"internalType":"address","name":"wheatToken","type":"address"},{"internalType":"address","name":"fishToken","type":"address"},{"internalType":"address","name":"ironToken","type":"address"},{"internalType":"address","name":"goldToken","type":"address"},{"internalType":"address","name":"blueprintToken","type":"address"},{"internalType":"address","name":"woodGoldPool","type":"address"},{"internalType":"address","name":"wheatGoldPool","type":"address"},{"internalType":"address","name":"fishGoldPool","type":"address"},{"internalType":"address","name":"ironGoldPool","type":"address"}]}]},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32"}],"stateMutability":"view","type":"function","name":"getWheatPlots","outputs":[{"internalType":"struct WheatPlot","name":"west","type":"tuple","components":[{"internalType":"enum WheatPlotState","name":"state","type":"uint8"},{"internalType":"uint8","name":"region","type":"uint8"},{"internalType":"uint256","name":"remainingWheat","type":"uint256"},{"internalType":"uint64","name":"regrowUntilTick","type":"uint64"}]},{"internalType":"struct WheatPlot","name":"east","type":"tuple","components":[{"internalType":"enum WheatPlotState","name":"state","type":"uint8"},{"internalType":"uint8","name":"region","type":"uint8"},{"internalType":"uint256","name":"remainingWheat","type":"uint256"},{"internalType":"uint64","name":"regrowUntilTick","type":"uint64"}]}]},{"inputs":[],"stateMutability":"view","type":"function","name":"getWorldSnapshot","outputs":[{"internalType":"struct WorldSnapshot","name":"","type":"tuple","components":[{"internalType":"uint64","name":"currentTick","type":"uint64"},{"internalType":"uint64","name":"seasonStartTick","type":"uint64"},{"internalType":"uint64","name":"seasonEndTick","type":"uint64"},{"internalType":"bool","name":"seasonFinalized","type":"bool"},{"internalType":"uint64","name":"currentSeasonNumber","type":"uint64"},{"internalType":"uint64","name":"nextHeartbeatAtTick","type":"uint64"},{"internalType":"bool","name":"winterActive","type":"bool"},{"internalType":"uint64","name":"winterStartsAtTick","type":"uint64"},{"internalType":"uint64","name":"winterEndsAtTick","type":"uint64"},{"internalType":"uint32","name":"activeBanditId","type":"uint32"},{"internalType":"bytes32","name":"currentTickSeed","type":"bytes32"},{"internalType":"struct LeaderboardEntry[]","name":"leaderboard","type":"tuple[]","components":[{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint8","name":"monumentLevel","type":"uint8"},{"internalType":"uint8","name":"baseLevel","type":"uint8"},{"internalType":"uint8","name":"wallLevel","type":"uint8"},{"internalType":"uint8","name":"livingClansmen","type":"uint8"},{"internalType":"enum ClanState","name":"state","type":"uint8"},{"internalType":"uint256","name":"lootValue","type":"uint256"}]}]}]},{"inputs":[],"stateMutability":"view","type":"function","name":"getWorldState","outputs":[{"internalType":"struct WorldState","name":"","type":"tuple","components":[{"internalType":"uint64","name":"currentTick","type":"uint64"},{"internalType":"uint64","name":"seasonStartTick","type":"uint64"},{"internalType":"uint64","name":"seasonEndTick","type":"uint64"},{"internalType":"bool","name":"seasonFinalized","type":"bool"},{"internalType":"uint64","name":"currentSeasonNumber","type":"uint64"},{"internalType":"uint64","name":"nextHeartbeatAtTick","type":"uint64"},{"internalType":"uint64","name":"nextHeartbeatAtTs","type":"uint64"},{"internalType":"uint64","name":"nextBanditSpawnEligibleTick","type":"uint64"},{"internalType":"uint16","name":"currentBanditSpawnChanceBps","type":"uint16"},{"internalType":"bytes32","name":"currentTickSeed","type":"bytes32"},{"internalType":"uint32","name":"activeBanditId","type":"uint32"},{"internalType":"bool","name":"winterActive","type":"bool"},{"internalType":"uint64","name":"winterStartsAtTick","type":"uint64"},{"internalType":"uint64","name":"winterEndsAtTick","type":"uint64"},{"internalType":"uint64","name":"nextCommitSequence","type":"uint64"}]}]},{"inputs":[],"stateMutability":"nonpayable","type":"function","name":"heartbeat"},{"inputs":[{"internalType":"address[6]","name":"tokens","type":"address[6]"},{"internalType":"address[4]","name":"pools","type":"address[4]"}],"stateMutability":"nonpayable","type":"function","name":"initTreasury"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"stateMutability":"nonpayable","type":"function","name":"mintClan","outputs":[{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"uint256","name":"iftTokenId","type":"uint256"}]},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32"}],"stateMutability":"view","type":"function","name":"quoteLootValueRaw","outputs":[{"internalType":"uint256","name":"lootValue","type":"uint256"}]},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32"}],"stateMutability":"view","type":"function","name":"quoteLootValueSettled","outputs":[{"internalType":"uint256","name":"lootValue","type":"uint256"}]},{"inputs":[{"internalType":"uint8","name":"srcRegion","type":"uint8"},{"internalType":"uint8","name":"dstRegion","type":"uint8"}],"stateMutability":"view","type":"function","name":"quoteTravel","outputs":[{"internalType":"uint8","name":"travelTicks","type":"uint8"},{"internalType":"bytes8","name":"path","type":"bytes8"}]},{"inputs":[{"internalType":"struct PoolSeedConfig","name":"cfg","type":"tuple","components":[{"internalType":"uint256","name":"woodSeed","type":"uint256"},{"internalType":"uint256","name":"wheatSeed","type":"uint256"},{"internalType":"uint256","name":"fishSeed","type":"uint256"},{"internalType":"uint256","name":"ironSeed","type":"uint256"},{"internalType":"uint256","name":"goldSeedForWood","type":"uint256"},{"internalType":"uint256","name":"goldSeedForWheat","type":"uint256"},{"internalType":"uint256","name":"goldSeedForFish","type":"uint256"},{"internalType":"uint256","name":"goldSeedForIron","type":"uint256"}]}],"stateMutability":"nonpayable","type":"function","name":"seedPools"},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32"}],"stateMutability":"nonpayable","type":"function","name":"settleClan"},{"inputs":[{"internalType":"uint32","name":"csId","type":"uint32"}],"stateMutability":"nonpayable","type":"function","name":"settleClansman"},{"inputs":[{"internalType":"uint32","name":"clanId","type":"uint32"},{"internalType":"struct ClanOrder[]","name":"orders","type":"tuple[]","components":[{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"uint8","name":"gotoRegion","type":"uint8"},{"internalType":"enum ActionType","name":"action","type":"uint8"},{"internalType":"uint32","name":"targetClanId","type":"uint32"},{"internalType":"address","name":"marketToken","type":"address"},{"internalType":"uint256","name":"marketAmount","type":"uint256"},{"internalType":"uint256","name":"maxGoldIn","type":"uint256"}]}],"stateMutability":"nonpayable","type":"function","name":"submitClanOrders","outputs":[{"internalType":"struct OrderResult[]","name":"","type":"tuple[]","components":[{"internalType":"uint32","name":"clansmanId","type":"uint32"},{"internalType":"enum StatusCode","name":"status","type":"uint8"},{"internalType":"uint64","name":"cooldownEndsAtTs","type":"uint64"},{"internalType":"uint64","name":"missionNonce","type":"uint64"}]}]},{"inputs":[{"internalType":"uint32","name":"fromClanId","type":"uint32"},{"internalType":"uint32","name":"toClanId","type":"uint32"},{"internalType":"uint256","name":"amount","type":"uint256"}],"stateMutability":"nonpayable","type":"function","name":"transferBlueprint"},{"inputs":[{"internalType":"uint32","name":"fromClanId","type":"uint32"},{"internalType":"uint32","name":"toClanId","type":"uint32"},{"internalType":"uint256","name":"gold","type":"uint256"},{"internalType":"uint256","name":"blueprint","type":"uint256"},{"internalType":"uint256","name":"wood","type":"uint256"},{"internalType":"uint256","name":"iron","type":"uint256"},{"internalType":"uint256","name":"wheat","type":"uint256"},{"internalType":"uint256","name":"fish","type":"uint256"}],"stateMutability":"nonpayable","type":"function","name":"transferBundle"},{"inputs":[{"internalType":"uint32","name":"fromClanId","type":"uint32"},{"internalType":"uint32","name":"toClanId","type":"uint32"},{"internalType":"uint256","name":"amount","type":"uint256"}],"stateMutability":"nonpayable","type":"function","name":"transferGold"},{"inputs":[{"internalType":"uint32","name":"fromClanId","type":"uint32"},{"internalType":"uint32","name":"toClanId","type":"uint32"},{"internalType":"enum ResourceType","name":"resource","type":"uint8"},{"internalType":"uint256","name":"amount","type":"uint256"}],"stateMutability":"nonpayable","type":"function","name":"transferVaultResource"}],"devdoc":{"kind":"dev","methods":{},"version":1},"userdoc":{"kind":"user","methods":{"finalizeSeason()":{"notice":"Finalize the current season. Permissionless after seasonEndTick."},"getActiveBanditView()":{"notice":"Single-call bandit drama state, including projected target if         attack resolved this tick. Drives the bandit warning UI."},"getBanditTargetPreview(uint32)":{"notice":"Non-binding preview. Bandit targeting is recomputed at attack         resolution time using then-current eagerly settled state."},"getClanFullView(uint32)":{"notice":"Single-call complete clan rendering data: derived clan + all         clansmen with derived state and active missions + plot states +         defender bookkeeping. Drives the entire sprite layer."},"getMarketState()":{"notice":"Single-call market panel data: 4 pool reserves + spot prices +         scheduled queues for current and next tick. Drives market UI         and indexer's per-tick price-history sampling."},"getRegionPopulation(uint8)":{"notice":"Optional. List clansmen currently in a region for tap-to-inspect         tooltips. Can be derived clientside; included for completeness."},"getWorldSnapshot()":{"notice":"Single-call top-level world state plus per-clan leaderboard data.         Drives top HUD bar, season clock, winter indicator, leaderboard."},"heartbeat()":{"notice":"Permissionless heartbeat. Closes the current tick, resolves         scheduled market actions and world events, advances the tick.         Rate-limited by WorldState.nextHeartbeatAtTs."},"initTreasury(address[6],address[4])":{"notice":"Owner-only. Registers token and pool addresses once before seeding.         tokens order: wood, iron, wheat, fish, gold, blueprint.         pools order: wood, wheat, fish, iron."},"mintClan(address)":{"notice":"Mint a new clan iNFT and spawn its homebase in a valid region."},"seedPools((uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256))":{"notice":"Owner-only. Seeds the four Unicorn Town pools at deploy time."},"settleClan(uint32)":{"notice":"Lazily settle a clan forward to current tick. Idempotent."},"settleClansman(uint32)":{"notice":"Lazily settle a single clansman's mission to current tick. Idempotent."},"submitClanOrders(uint32,(uint32,uint8,uint8,uint32,address,uint256,uint256)[])":{"notice":"Submit one or more orders for a single clan's clansmen.         Per-order failures do not revert the tx."}},"version":1}},"settings":{"remappings":["forge-std/=lib/forge-std/src/"],"optimizer":{"enabled":true,"runs":200},"metadata":{"bytecodeHash":"ipfs"},"compilationTarget":{"src/IClanWorld.sol":"IClanWorld"},"evmVersion":"prague","libraries":{},"viaIR":true},"sources":{"src/IClanWorld.sol":{"keccak256":"0xaef95040130eb2fb1f96d948f2af3b1946943b8e63dbb43c46a9db2cd8df6835","urls":["bzz-raw://64cae733ba6ac28007dff7df0c27b4dde9edfb5903e8063791332321b7a33c63","dweb:/ipfs/QmbbnVbgcGkA4kYayrA9zbiz72cMjJtQhPeXAbd6Yn6xfY"],"license":"MIT"}},"version":1},"id":24}
docs/reviews/pr356-codereview-codex-5-5.md:38:   - P9 bandit: loot-value getter (`quoteLootValueRaw/Settled`) consumes Phase-5 vault state. Does the addendum keep the vault interface stable?
docs/reviews/pr356-codereview-codex-5-5.md:39:   - P10 winter: §9 declares wood burn / upkeep multiplier / wheat WinterLocked as DEFERRED. Is that consistent with PR #341 v4.6 bandit redesign which also deferred winter mechanics?
docs/reviews/pr356-codereview-codex-5-5.md:109:**Out of scope:** all non-economy mechanics. Bandit interactions with vault state (loot value getter — see `clanworld_v4_6_bandit_phase9_redesign.md`), winter mechanics (deferred — §9), market mechanics (Phase 6), deaths (Phase 10), gold/blueprint payouts. The rest of the v4 spec remains canonical unless overridden by a later addendum.
docs/reviews/pr356-codereview-codex-5-5.md:297:| `WinterLocked` | Winter active (see §9) | **Not wired in impl** — enum value declared, behavior deferred |
docs/reviews/pr356-codereview-codex-5-5.md:334:The following winter mechanics are declared in constants but **not wired in the implementation**. They are explicitly out of scope for Phase 5B and will be implemented under Phase 5.6 (starvation upkeep) and Phase 7 (winter season):
docs/reviews/pr356-codereview-codex-5-5.md:338:| Winter wheat plot lockdown (§7.4) | plots enter `WinterLocked` at winter start; no harvest | NOT IMPLEMENTED — `_gatherWheat` does not check `winterActive`; `WinterLocked` enum value is dead | `WheatPlotState.WinterLocked` in `IClanWorld.sol:125` |
docs/reviews/pr356-codereview-codex-5-5.md:341:| WinterLocked → Regrowing at winter end (v4_2 §7.4) | on winter end, locked plots → Regrowing | NOT IMPLEMENTED | — |
docs/reviews/pr356-codereview-codex-5-5.md:363:| 11 | **Winter wheat plot lockdown** (§7.4) — plots enter `WinterLocked` at winter start; no harvest | `WinterLocked` enum state declared, not wired | Small–Medium — wire winter-start heartbeat to set plot state; add check in `_gatherWheat`; wire winter-end → Regrowing |
docs/reviews/pr356-codereview-codex-5-5.md:411:- ✅ Wheat plots remain harvestable during winter (WinterLocked NOT wired)
docs/reviews/pr356-codereview-codex-5-5.md:422:- **Path A precedent (bandit mechanics):** [`docs/planning/clanworld_v4_6_bandit_phase9_redesign.md`](./clanworld_v4_6_bandit_phase9_redesign.md)
docs/reviews/pr356-codereview-codex-5-5.md:451:| `docs/planning/clanworld_v4_2_state_schema_interface_spec.md` | §5 constants (`WOOD_CAP/IRON_CAP/WHEAT_CAP/FISH_CAP`, `WOOD_BASE_YIELD=2e18`, `WOOD_CRIT_BONUS=1e18`, `WOOD_CRIT_BPS=2000`, `IRON_BASE_YIELD=5e17`, `GOLD_FROM_IRON_BPS=200`, `FISH_DOCKS_BPS=2500`, `FISH_DEEP_BPS=7500`, `WHEAT_UPKEEP_PER_CLANSMAN=1e18`, `FISH_UPKEEP_PER_CLANSMAN=1e17`, `WINTER_WOOD_BURN_PER_BASE=1e18`); §7.3 Clan struct (vault fields, `starvationStartsAtTick`, `starvingCached`); §7.4 WheatPlot; §7.5 Clansman carry fields; §8.1–8.2 mission shape + DefendBase persistence (touches only deposit/gather lifecycle indirectly); §9.1–9.2 raw + derived getters (notably `quoteLootValueRaw/Settled` consume Phase 5 vault state) |
docs/reviews/pr356-codereview-codex-5-5.md:509:| **Winter wheat plot lockdown (§7.4)** | "during winter: wheat plots are unavailable; harvesting wheat is not allowed" | NOT IMPLEMENTED. `_gatherWheat` does not check `_world.winterActive`. `_settleClan` per-tick wheat-plot regrow loop has no `WinterLocked` transition. | `ClanWorld.sol:376-383, 612-665` | ❌ MISSING — wheat plots remain harvestable during winter |
docs/reviews/pr356-codereview-codex-5-5.md:510:| **WheatPlotState enum has WinterLocked** | yes (v4_2 §7.4) | enum has 3 states: `Harvestable, Regrowing, WinterLocked` | `IClanWorld.sol:123-127` | ⚠️ PARTIAL — schema present, behavior absent (dead enum value) |
docs/reviews/pr356-codereview-codex-5-5.md:526:| **Wheat-plot WinterLocked transition at winter start (v4_2 §7.4)** | "at winter start: plots enter `WinterLocked`" | NOT IMPLEMENTED — heartbeat does not set plot state to `WinterLocked`; the enum value is dead. | `ClanWorld.sol:376-383, 1043-1054` | ❌ MISSING |
docs/reviews/pr356-codereview-codex-5-5.md:527:| **Wheat-plot WinterLocked → Regrowing at winter end (v4_2 §7.4)** | "at winter end: `WinterLocked → Regrowing`" | NOT IMPLEMENTED | (no code) | ❌ MISSING |
docs/reviews/pr356-codereview-codex-5-5.md:536:| **Loot value getter raw (v4.3 H)** | reads committed vault only | `quoteLootValueRaw` (impl elsewhere — Phase-9 already verified ✅ in pr194 audit) | (out of Phase-5 diff) | ✅ MATCHES (cross-phase consumer) |
docs/reviews/pr356-codereview-codex-5-5.md:537:| **Loot value getter settled (v4.3 H)** | settles to current tick | `quoteLootValueSettled` (impl elsewhere) | (out of Phase-5 diff) | ✅ MATCHES |
docs/reviews/pr356-codereview-codex-5-5.md:599:| **Winter wheat plot lockdown (§7.4)** | Plot must enter `WinterLocked` at winter start. Zero tests. | Phase 5.4 / Phase 7 winter |
docs/reviews/pr356-codereview-codex-5-5.md:663:**Expected per spec:** mission rejected OR completes with 0 yield; plot state = `WinterLocked`.
docs/reviews/pr356-codereview-codex-5-5.md:665:**He should verify:** call `getWheatPlots(clanId)` during winter — both plots will report `state = Harvestable` (impl) instead of `WinterLocked` (spec).
docs/reviews/pr356-codereview-codex-5-5.md:699:**Path A — Ratify impl as canonical, update spec:** Phase 5 has clearly evolved into a batched-action economy where yield calibration is geared to action-size × duty-cycle, not per-tick continuous flow. Drafting `clanworld_v4_6_phase5_economy_alignment.md` documenting (a) batched-action semantics, (b) recalibrated per-action yields equivalent to spec per-action-tick numbers, (c) the 10e18 wood cap, (d) starvation-tick semantics — formalizes the as-built. Phase 5.6 / Phase 7 winter mechanics still need impl per the same addendum or separate Phase-7 ticket.
docs/reviews/pr356-codereview-codex-5-5.md:721:  - **Substantial drift (13):** continuous-vs-batched action lifecycle, wood crit shape, all four per-tick yield rates, starvation onset tick, winter wheat lockdown, winter upkeep multiplier, winter wood burn, wheat WinterLocked transitions (start + end), cold damage path. All require either an impl rewrite (Path B) or spec acceptance (Path A).
docs/reviews/pr356-codereview-codex-5-5.md:723:If Path A is approved: file a single `clanworld_v4_6_phase5_economy_alignment.md` ADR draft and proceed to UAT against the new spec. Phase 5.6 (starvation upkeep) and Phase 7 (winter) remain open issues that will need to address the missing winter mechanics regardless of A or B.
docs/reviews/pr356-codereview-codex-5-5.md:793:+**Out of scope:** all non-economy mechanics. Bandit interactions with vault state (loot value getter — see `clanworld_v4_6_bandit_phase9_redesign.md`), winter mechanics (deferred — §9), market mechanics (Phase 6), deaths (Phase 10), gold/blueprint payouts. The rest of the v4 spec remains canonical unless overridden by a later addendum.
docs/reviews/pr356-codereview-codex-5-5.md:981:+| `WinterLocked` | Winter active (see §9) | **Not wired in impl** — enum value declared, behavior deferred |
docs/reviews/pr356-codereview-codex-5-5.md:1018:+The following winter mechanics are declared in constants but **not wired in the implementation**. They are explicitly out of scope for Phase 5B and will be implemented under Phase 5.6 (starvation upkeep) and Phase 7 (winter season):
docs/reviews/pr356-codereview-codex-5-5.md:1022:+| Winter wheat plot lockdown (§7.4) | plots enter `WinterLocked` at winter start; no harvest | NOT IMPLEMENTED — `_gatherWheat` does not check `winterActive`; `WinterLocked` enum value is dead | `WheatPlotState.WinterLocked` in `IClanWorld.sol:125` |
docs/reviews/pr356-codereview-codex-5-5.md:1025:+| WinterLocked → Regrowing at winter end (v4_2 §7.4) | on winter end, locked plots → Regrowing | NOT IMPLEMENTED | — |
docs/reviews/pr356-codereview-codex-5-5.md:1047:+| 11 | **Winter wheat plot lockdown** (§7.4) — plots enter `WinterLocked` at winter start; no harvest | `WinterLocked` enum state declared, not wired | Small–Medium — wire winter-start heartbeat to set plot state; add check in `_gatherWheat`; wire winter-end → Regrowing |
docs/reviews/pr356-codereview-codex-5-5.md:1095:+- ✅ Wheat plots remain harvestable during winter (WinterLocked NOT wired)
docs/reviews/pr356-codereview-codex-5-5.md:1106:+- **Path A precedent (bandit mechanics):** [`docs/planning/clanworld_v4_6_bandit_phase9_redesign.md`](./clanworld_v4_6_bandit_phase9_redesign.md)
docs/reviews/pr356-codereview-codex-5-5.md:1234:   126	    WinterLocked
docs/reviews/pr356-codereview-codex-5-5.md:1816:    37	**Out of scope:** all non-economy mechanics. Bandit interactions with vault state (loot value getter — see `clanworld_v4_6_bandit_phase9_redesign.md`), winter mechanics (deferred — §9), market mechanics (Phase 6), deaths (Phase 10), gold/blueprint payouts. The rest of the v4 spec remains canonical unless overridden by a later addendum.
docs/reviews/pr356-codereview-codex-5-5.md:2008:   225	| `WinterLocked` | Winter active (see §9) | **Not wired in impl** — enum value declared, behavior deferred |
docs/reviews/pr356-codereview-codex-5-5.md:2045:   262	The following winter mechanics are declared in constants but **not wired in the implementation**. They are explicitly out of scope for Phase 5B and will be implemented under Phase 5.6 (starvation upkeep) and Phase 7 (winter season):
docs/reviews/pr356-codereview-codex-5-5.md:2049:   266	| Winter wheat plot lockdown (§7.4) | plots enter `WinterLocked` at winter start; no harvest | NOT IMPLEMENTED — `_gatherWheat` does not check `winterActive`; `WinterLocked` enum value is dead | `WheatPlotState.WinterLocked` in `IClanWorld.sol:125` |
docs/reviews/pr356-codereview-codex-5-5.md:2052:   269	| WinterLocked → Regrowing at winter end (v4_2 §7.4) | on winter end, locked plots → Regrowing | NOT IMPLEMENTED | — |
docs/reviews/pr356-codereview-codex-5-5.md:2074:   291	| 11 | **Winter wheat plot lockdown** (§7.4) — plots enter `WinterLocked` at winter start; no harvest | `WinterLocked` enum state declared, not wired | Small–Medium — wire winter-start heartbeat to set plot state; add check in `_gatherWheat`; wire winter-end → Regrowing |
docs/reviews/pr356-codereview-codex-5-5.md:2122:   339	- ✅ Wheat plots remain harvestable during winter (WinterLocked NOT wired)
docs/reviews/pr356-codereview-codex-5-5.md:2133:   350	- **Path A precedent (bandit mechanics):** [`docs/planning/clanworld_v4_6_bandit_phase9_redesign.md`](./clanworld_v4_6_bandit_phase9_redesign.md)
docs/reviews/pr356-codereview-codex-5-5.md:2191:/bin/bash -lc "git show HEAD:docs/planning/clanworld_v4_6_bandit_phase9_redesign.md | nl -ba | sed -n '1,220p'" in /tmp/wt-superswarm-356
docs/reviews/pr356-codereview-codex-5-5.md:2193:fatal: path 'docs/planning/clanworld_v4_6_bandit_phase9_redesign.md' does not exist in 'HEAD'
docs/reviews/pr356-codereview-codex-5-5.md:2196:/bin/bash -lc 'git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | rg -n "quoteLootValue|vaultWood|vaultIron|vaultWheat|vaultFish|winterActive|WINTER|Market|price|yield"' in /tmp/wt-superswarm-356
docs/reviews/pr356-codereview-codex-5-5.md:2338:1943:    function quoteLootValueRaw(uint32 clanId) external view override returns (uint256) {
docs/reviews/pr356-codereview-codex-5-5.md:2339:1947:    function quoteLootValueSettled(uint32 clanId) external view override returns (uint256) {
docs/reviews/pr356-codereview-codex-5-5.md:2348:/bin/bash -lc 'git show HEAD:docs/planning/clanworld_v4_6_bandit_phase9_redesign.md | rg -n "winter|Winter|defer|deferred|quoteLoot|loot|Phase 5|vault"' in /tmp/wt-superswarm-356
docs/reviews/pr356-codereview-codex-5-5.md:2350:fatal: path 'docs/planning/clanworld_v4_6_bandit_phase9_redesign.md' does not exist in 'HEAD'
docs/reviews/pr356-codereview-codex-5-5.md:2793:  1943	    function quoteLootValueRaw(uint32 clanId) external view override returns (uint256) {
docs/reviews/pr356-codereview-codex-5-5.md:2797:  1947	    function quoteLootValueSettled(uint32 clanId) external view override returns (uint256) {
packages/contracts/src/ClanWorld.sol:1943:    function quoteLootValueRaw(uint32 clanId) external view override returns (uint256) {
packages/contracts/src/ClanWorld.sol:1947:    function quoteLootValueSettled(uint32 clanId) external view override returns (uint256) {
packages/contracts/src/ClanWorldStub.sol:278:    function quoteLootValueRaw(uint32) external pure override returns (uint256) {
packages/contracts/src/ClanWorldStub.sol:282:    function quoteLootValueSettled(uint32) external pure override returns (uint256) {
packages/contracts/src/IClanWorld.sol:126:    WinterLocked
packages/contracts/src/IClanWorld.sol:752:    function quoteLootValueRaw(uint32 clanId) external view returns (uint256 lootValue);
packages/contracts/src/IClanWorld.sol:754:    function quoteLootValueSettled(uint32 clanId) external view returns (uint256 lootValue);

exec
/bin/bash -lc "git show origin/docs/spec-v4-6-bandit-redesign:docs/planning/clanworld_v4_6_bandit_phase9_redesign.md | nl -ba | sed -n '1,260p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
     1	# ClanWorld v4.6 Addendum — Bandit Phase 9 Redesign (Path A: as-built canonization)
     2	
     3	**Status:** Authoritative addendum, scoped to bandit mechanics only
     4	**Read order:** This doc supersedes the bandit-mechanic language in `clanworld_v4_spec.md` §6, `clanworld_v4_1_addendum.md` (A3, A4, A11), and the bandit-relevant constants in `clanworld_v4_2_state_schema_interface_spec.md` §5 / §7.7 / §7.10 / §7.11. When implementers find disagreement on bandit behavior, this doc wins.
     5	**Purpose:** Canonize the as-built Phase 9 bandit implementation in `packages/contracts/src/ClanWorld.sol` as the new authoritative ruleset for the hackathon submissions, and explicitly enumerate the v4 mechanics that did not ship as DEFERRED-TO-RESTORATION.
     6	**Audience:** Reviewers, UAT runs against the contract on World Chain Sepolia / Base Sepolia, future restoration work.
     7	
     8	---
     9	
    10	## 0. Why this doc exists — Path A decision (Liam, 2026-04-30)
    11	
    12	A spec-vs-impl audit by Claude Opus 4.7 (1M ctx) — the "PR #194 spec-compliance UAT" report at [`docs/reviews/pr194-spec-compliance-uat.md`](../reviews/pr194-spec-compliance-uat.md) — confirmed that the Phase 9 bandit implementation diverges from the v4 spec on numerous core mechanics. Eleven of those drifts are significant (rampage path, vault loot theft, attack-attempt cap, threshold combat, per-clansman split, etc.).
    13	
    14	Two interpretive paths were available:
    15	
    16	- **Path A (chosen)** — declare the implementation canonical, write this addendum as the new authoritative ruleset, defer the v4-specific mechanics to a post-hackathon restoration milestone.
    17	- **Path B (rejected for hackathon timeline)** — declare the v4 spec canonical, treat the implementation as drift, dispatch a Phase 9.5 rework to align.
    18	
    19	Path A was selected because (1) the as-built code is internally consistent and well-tested (the multi-round super-swarm + per-issue PR pipeline already validated it against itself); (2) Phase 9 work has fully landed and downstream phases (10 winter, market) have been built on top of the as-built bandit mechanics; (3) restoring the v4 ruleset is a multi-day Phase 9.5 lift that isn't on the hackathon critical path; (4) the v4 spec was written before Phase 9 implementation experimentation, and several of its mechanics (rampage path, vault theft, terminal escape) trade off complexity for tension that the as-built simpler model has been shown to deliver well enough.
    20	
    21	This doc canonizes the as-built mechanics. The eight largest drifted mechanics are tracked as a deferred-to-restoration list in §6 and on GH issue [#340](https://github.com/OmniPass-world/clan-world/issues/340) under the `spec-v4-restoration-post-hackathon` milestone for later evaluation.
    22	
    23	---
    24	
    25	## 1. Scope of this addendum
    26	
    27	**In scope:** every bandit mechanic visible to a player or a UAT runner, as implemented in:
    28	
    29	- `packages/contracts/src/ClanWorld.sol` — bandit lifecycle, attack resolution, defender contribution, defeat reward distribution
    30	- `packages/contracts/src/IClanWorld.sol` — bandit struct fields, state enum, ABI surface, constants
    31	- `packages/contracts/test/Bandit.t.sol`, `BanditAttackResolution.t.sol`, `BanditSpawn.t.sol` — codified behavior
    32	
    33	**Out of scope:** all non-bandit mechanics. The rest of the v4 spec (clan minting, missions, market, winter, deaths, gold/blueprint payouts unrelated to bandits) remains canonical.
    34	
    35	**Authoritative as of HEAD:** `218f9020ecb0f4b8277ef59dd55de8e004404d80` (the HEAD against which the spec-compliance UAT was run; identical to PR #194's merged commit on `dev-phase-9-bandits`).
    36	
    37	---
    38	
    39	## 2. As-built bandit lifecycle
    40	
    41	### 2.1 State machine
    42	
    43	The implementation defines **7 states** (vs. 5 in v4 §6.5):
    44	
    45	```
    46	None → Spawned → Camped → Attacking → (Defeated | Escaped) → Resting → Camped → Attacking → ...
    47	```
    48	
    49	| State | Duration | Transition trigger | Notes |
    50	|---|---|---|---|
    51	| `None` | (sentinel) | Default zero value, indicates no troop | Defensive — prevents zero-init from looking like a real state |
    52	| `Spawned` | 1 tick | Heartbeat `_advanceBanditStates` | Settles candidate region, then transitions to `Camped` |
    53	| `Camped` | 3 ticks (`BANDIT_CAMP_TICKS`) | Tick counter expires | Picks attack target on exit (NOT at attack resolution time) |
    54	| `Attacking` | 1 tick | Heartbeat resolves attack via `_resolveBanditAttack` | Either Defeated (if defenders win threshold) or Escaped (if attack lands as damage event) |
    55	| `Defeated` | terminal | n/a | Bandit removed; carry distributed; blueprint awarded to target clan |
    56	| `Escaped` | 2 ticks | Tick counter expires → `Resting` | NON-TERMINAL — distinguishes from spec's terminal escape |
    57	| `Resting` | 2 ticks | Tick counter expires → `Camped` | Bandit stays in the same region; no rampage |
    58	
    59	**Effective spawn-to-attack interval = 4 ticks** (1 Spawned + 3 Camped). After the first attack, the steady-state cycle is `Attacking → Escaped(2) → Resting(2) → Camped(3) → Attacking` = 7 ticks per attempt.
    60	
    61	**Bandit `region` is set on spawn and never changes.** A bandit lives in its spawn region for its entire lifecycle. There is no rampage path, no inter-region movement.
    62	
    63	### 2.2 Spawn cadence
    64	
    65	| Constant | Value | Source |
    66	|---|---|---|
    67	| `BANDIT_SPAWN_PROBABILITY_INCREMENT_BPS` | 1000 (10%) | `ClanWorld.sol:91` |
    68	| `BANDIT_SPAWN_MAX_PROBABILITY_BPS` | 8000 (80%) | `ClanWorld.sol:92` |
    69	| `MIN_SPAWN_COOLDOWN_TICKS` (= `BANDIT_COOLDOWN_TICKS`) | 10 | `ClanWorld.sol:90` |
    70	| `MAX_TOTAL_BANDITS` | 8 | `ClanWorld.sol:93` |
    71	| `MAX_BANDITS_PER_REGION` | 3 | `ClanWorld.sol:94` |
    72	
    73	**Per-tick spawn check** (per region, with per-region cooldown timer):
    74	
    75	1. If region cooldown active → skip
    76	2. If active bandit count for region ≥ `MAX_BANDITS_PER_REGION` → skip
    77	3. If global active bandit count ≥ `MAX_TOTAL_BANDITS` → skip
    78	4. Probability accumulator for region += 1000 bps (capped at 8000)
    79	5. Roll RNG vs accumulator → if hit, spawn this region; otherwise carry accumulator forward to next tick
    80	6. On spawn: reset that region's accumulator + start that region's cooldown timer (10 ticks)
    81	
    82	**Up to 8 bandits can be active simultaneously globally** (vs spec's "at most 1"), with up to 3 per region.
    83	
    84	**Cooldown is per-region, not global, and starts at spawn time, not at resolution time.** A defeat in Forest does not pause Mountains spawns; Mountains can still roll its own spawn next tick.
    85	
    86	### 2.3 Spawn region selection
    87	
    88	Eligible regions are determined by **clansman presence**, not by hard-coded ID. The implementation does NOT exclude region 3 (UnicornTown) or region 8 (DeepSea); a clansman traveling through those regions on a market trip can make them spawn-eligible.
    89	
    90	**Region selection is loot-and-clansman weighted** (NOT uniform random — see `ClanWorld.sol:2230-2269`):
    91	
    92	- `weights[r] += 100 + lootValue / 1e18`  (base + loot bonus)
    93	- `weights[r] += 25 * clansmenInRegion(r)`  (per-clansman bonus)
    94	
    95	Then RNG-weighted pick across `weights[]`. This biases bandits toward loot-rich, populated regions — intentional per inline code comment ("heuristic to make bandits feel pressuring").
    96	
    97	### 2.4 Bandit strength
    98	
    99	**No tier system.** Each spawned bandit has a uniform-random `strength` value in `[100, 250]`:
   100	
   101	- `MIN_BANDIT_SPAWN_STRENGTH = 100` (`ClanWorld.sol:108`)
   102	- `BANDIT_SPAWN_STRENGTH_SPREAD = 151` (`ClanWorld.sol:109`)
   103	- `attackPower = MIN_BANDIT_SPAWN_STRENGTH + rng % BANDIT_SPAWN_STRENGTH_SPREAD`
   104	
   105	The struct field `tier` from v4_3 G is absent. The ABI emits `tier: 0` for backward compatibility but it is not load-bearing.
   106	
   107	### 2.5 Targeting
   108	
   109	At `Camped → Attacking` transition (one tick before resolution), the implementation picks a target:
   110	
   111	- Filters to clans with `baseRegion == bandit.region` (matches spec §6.8)
   112	- Eager-settles the eventually-picked target (per-target settlement; does NOT eager-settle ALL bases in region as v4_1 A4 demands)
   113	- Ranks remaining bases by loot value: `wood + wheat + 2*fish + 4*iron` (matches spec §6.9 — gold is NOT counted)
   114	- Tiebreak among equal-loot bases: **uniform random across ties** (NOT lowest-clanId as spec §6.8 requires)
   115	- If no eligible base in region → bandit transitions to `Escaped` (spec wanted noop "stay in region, try next tick"; impl marks Escaped which is non-terminal here, so functionally similar but surfaces as Escaped state in ABI)
   116	
   117	---
   118	
   119	## 3. As-built combat model
   120	
   121	The implementation uses a **damage-based HP model** (vs spec's threshold-comparison model). On `Attacking → resolution` tick:
   122	
   123	### 3.1 Defender contribution roll
   124	
   125	For each clan with at least one clansman currently on a `DefendBase` mission **at home base**:
   126	
   127	- For each such defending clansman → RNG roll uniform in `[0, 100]` → contributes that as defense damage
   128	- Starving clans contribute 0 (matches spec A9 — see `_isStarving` filter at `ClanWorld.sol:1920, 1950`)
   129	- WAITING-at-home clansmen (not on `DefendBase` mission) contribute 0 — they do NOT count for defense (spec §6.13 wanted them to contribute 5 each; impl ignores them)
   130	
   131	Total defender damage = sum across all defending clansmen.
   132	
   133	### 3.2 Attack outcome — damage absorption order
   134	
   135	Compare `totalClansmanDefense` vs `2 * attackPower`:
   136	
   137	**Outcome A — clean defeat:**
   138	- If `totalClansmanDefense >= 2 * attackPower` → bandit defeated, no other damage applied
   139	- Note: spec's threshold was `1x`, impl uses `2x` — defenders need twice as much firepower
   140	- Bandit transitions to `Defeated` → blueprint reward awarded → carry distributed (carry is always 0 in production; see §3.3)
   141	
   142	**Outcome B — damage event (loss path):**
   143	- If `totalClansmanDefense < 2 * attackPower` → damage = `2 * attackPower - totalClansmanDefense`
   144	- Damage absorbed in tiers:
   145	  1. Wall HP first: `WALL_HP_PER_LEVEL = 100`. Wall absorbs up to `wallLevel * 100` damage. Wall level decrements by 1 per attack that hits the wall.
   146	  2. Base HP next: `BASE_HP_PER_LEVEL = 25`. Base absorbs up to `baseLevel * 25` damage.
   147	  3. Clansman casualties: if damage exceeds combined wall+base HP, **clansmen die** to absorb the residual. This contradicts spec §6.15 which says no clansman casualties from bandits in v1.
   148	  4. If all clansmen die → clan is marked dead.
   149	- Bandit transitions to `Escaped` (which is non-terminal in this impl).
   150	
   151	### 3.3 No vault loot theft
   152	
   153	**The implementation does not implement vault loot theft.** Spec §6.15C and §6.16 mandate that a successful attack steals 20% of each vault resource (wood, wheat, fish, iron) into the bandit's `carryX` fields. The impl:
   154	
   155	- Has `BanditTroop.carryWood/Iron/Wheat/Fish/Gold` struct fields (`IClanWorld.sol:310-314`) but no production code path ever writes to them. Only the test harness `setBanditCarry` populates these.
   156	- The constants `BANDIT_BASE_STEAL_BPS = 2000` (`IClanWorld.sol:71`) and `BANDIT_DROP_TO_DEFENDERS_BPS = 5000` (`IClanWorld.sol:72`) are declared but never referenced by production code.
   157	- The `BanditAttackResolved` event hardcodes `stolenWood/Iron/Wheat/Fish` to 0 (`ClanWorld.sol:1824-1827`).
   158	
   159	**Net effect:** target clan vaults are unchanged by bandit attacks. Bandits do damage to wall/base/clansmen but never extract physical loot.
   160	
   161	### 3.4 No attack-attempt cap
   162	
   163	Spec §6.12 requires bandits to be removed from the world after 6 attempts (7th = ESCAPED + carried loot burned + troop deleted). The impl has no `attackAttemptsMade` counter; the field is absent from the struct (`IClanWorld.sol:303-315`) and the ABI returns `attackAttemptsMade: 0` always. Bandits cycle indefinitely until either the target clan dies or defenders defeat them.
   164	
   165	---
   166	
   167	## 4. As-built defender contributions and rewards
   168	
   169	### 4.1 Eligibility rule
   170	
   171	A clansman counts as a defender **if and only if** all of the following hold:
   172	
   173	- Their clan is the bandit's target clan (only target-clan clansmen can defend in the impl)
   174	- They are alive (`!_isClansmanDead`)
   175	- They are at home base (mission location is the home region)
   176	- Their active mission action is `DefendBase`
   177	- Their clan is not starving (`!_isStarving(defenderClan)`)
   178	
   179	WAITING-at-home (no active mission, or mission action ≠ `DefendBase`) clansmen do NOT contribute. This is a behavioral departure from spec §6.13 which wanted them to contribute 5 each.
   180	
   181	### 4.2 Defense damage roll
   182	
   183	Per-clansman: uniform RNG roll in `[0, 100]`. Sum across all eligible defenders = `totalClansmanDefense`.
   184	
   185	The roll can return 0; impl does NOT filter zero-roll defenders from reward eligibility (every active defender is reward-eligible regardless of actual roll).
   186	
   187	### 4.3 Defeat reward distribution
   188	
   189	On `Defeated` outcome:
   190	
   191	- **Blueprint reward:** 1e18 Blueprint deposited into target clan's vault. (Spec §6.17 also called for 1e18 Gold to the same vault; impl omits the gold portion.)
   192	- **Carry distribution:** 100% of bandit's carry is split equally among defending clans. Distribution is **per-clan**, not per-clansman: each unique clan with ≥1 active defender gets exactly 1 share, regardless of how many of its clansmen are defending. (Spec A11 wanted per-clansman granularity.)
   193	- **Whole-token rounding:** integer division per-resource, residue burned.
   194	- **Carry is zero in practice** (see §3.3) — so this distribution code only fires non-zero in test harness scenarios with `setBanditCarry`.
   195	
   196	### 4.4 Defender registry semantics
   197	
   198	- `DefendBase` is a persistent mission — a clansman set to defend stays defending across multiple bandit attacks until reassigned, killed, or until the defended clan dies (matches v4.2 §8.2).
   199	- Defender registries are cleaned on clansman death (`_clearDefender` at `ClanWorld.sol:565-588`) and on defended-clan death (`_releaseDefendersForDeadTarget` at `ClanWorld.sol:2771-2792`).
   200	- Dead-target cleanup transitions any active bandit attack against a dead clan to `Escaped` (`_abortBanditAttacksForDeadTarget` at `ClanWorld.sol:590-608`).
   201	
   202	---
   203	
   204	## 5. Constants — as-built canonical values
   205	
   206	These supersede the bandit-related constants in `clanworld_v4_2_state_schema_interface_spec.md` §5.
   207	
   208	| Constant | Spec value (deprecated) | As-built canonical | Source |
   209	|---|---|---|---|
   210	| `BANDIT_COOLDOWN_TICKS` | 10 | 10 | `ClanWorld.sol:90` ✅ unchanged |
   211	| `BANDIT_CAMP_TICKS` | 3 | 3 | `ClanWorld.sol:1605, 1612` ✅ unchanged |
   212	| `BANDIT_REST_TICKS` | 2 (post-attack) | 2 (in `Resting`); 2 additional in `Escaped` | `ClanWorld.sol:1689-1697` |
   213	| `BANDIT_MAX_ATTEMPTS` | 6 | not implemented | — |
   214	| `BANDIT_BASE_STEAL_BPS` | 2000 (20%) | declared, not referenced | `IClanWorld.sol:71` |
   215	| `BANDIT_DROP_TO_DEFENDERS_BPS` | 5000 (50%) | declared, not referenced; impl uses 100% | `IClanWorld.sol:72` |
   216	| Spawn base chance | 5% | 10% | `ClanWorld.sol:91` |
   217	| Spawn increment per missed tick | +1% | +10% | `ClanWorld.sol:91` |
   218	| Spawn cap | 20% | 80% | `ClanWorld.sol:92` |
   219	| `MAX_TOTAL_BANDITS` | (implicitly 1) | 8 | `ClanWorld.sol:93` |
   220	| `MAX_BANDITS_PER_REGION` | (n/a) | 3 | `ClanWorld.sol:94` |
   221	| `MIN_BANDIT_SPAWN_STRENGTH` | (n/a; tier 1 = 30) | 100 | `ClanWorld.sol:108` |
   222	| `BANDIT_SPAWN_STRENGTH_SPREAD` | (n/a; tier-fixed) | 151 → strength uniform `[100,250]` | `ClanWorld.sol:109` |
   223	| `WALL_HP_PER_LEVEL` | (n/a; threshold = 10×wall) | 100 | `ClanWorld.sol:111` |
   224	| `BASE_HP_PER_LEVEL` | (n/a; threshold = 5×base) | 25 | `ClanWorld.sol:112` |
   225	
   226	The state enum is also expanded:
   227	
   228	| State | v4 spec (§6.5) | As-built (`IClanWorld.sol:107-115`) |
   229	|---|---|---|
   230	| `None` | — | 0 (sentinel) |
   231	| `Spawned` | — | 1 (1-tick pre-camp) |
   232	| `CAMPING` / `Camped` | yes | 2 |
   233	| `RESTING` / `Resting` | yes | 3 |
   234	| `ATTACKING` / `Attacking` | yes | 4 |
   235	| `DEFEATED` / `Defeated` | yes (terminal) | 5 (terminal) |
   236	| `ESCAPED` / `Escaped` | yes (terminal in spec) | 6 (NON-terminal in impl; cycles back to Resting) |
   237	
   238	---
   239	
   240	## 6. Deferred to restoration milestone (`spec-v4-restoration-post-hackathon`)
   241	
   242	The following v4 mechanics are **explicitly NOT being implemented for the hackathon submissions**. They are tracked for evaluation under the `spec-v4-restoration-post-hackathon` GH milestone. Restoration is conditional on hackathon timeline and the post-hackathon evaluation that the original v4 mechanics deliver more gameplay value than the as-built simpler model.
   243	
   244	| # | v4 spec mechanic | As-built behavior | Restoration cost (rough) |
   245	|---|---|---|---|
   246	| 1 | **Vault loot theft** (§6.15C, §6.16) — bandits steal 20% of wood/wheat/fish/iron on failed defense, accumulate carry until defeat/escape | Bandits never extract loot; carry remains 0 in production | Medium — re-wire `_resolveBanditAttack`, write carry update path, plumb through `BanditAttackResolved` event |
   247	| 2 | **Rampage path** (§6.10, §6.11) — bandit moves 1→2→5→7→6→4→1 clockwise on completion of each attack-rest cycle | Bandit stays in spawn region forever | Medium — add region-transition logic on rest-end, ensure single-troop-per-rampage invariant if combined with #5 |
   248	| 3 | **Attack-attempt cap** (§6.12) — 6 attempts max, 7th = ESCAPED + carry burned + troop removed | No counter; bandits cycle indefinitely | Small — add `attackAttemptsMade` field to `BanditTroop`, increment on each Attacking-tick, terminal-Escape branch when ≥ 6 |
   249	| 4 | **Tier-based attack power** (§6.14, v4.3 G) — `tier` 1..5 with `attackPower` ∈ {30, 45, 60, 80, 95}, derivation via `getBanditAttackPower(tier)` | Random uniform `[100, 250]` strength; no tier field | Small — add `tier` field, derivation helper, replace strength roll |
   250	| 5 | **Lowest-clanId tiebreak** (§6.8) — when multiple bases tied for highest loot value, lowest clanId targeted (deterministic) | RNG-bounded uniform pick (non-deterministic across replay) | Tiny — replace RNG pick with min-clanId scan |
   251	| 6 | **WAITING-at-home defense contribution** (§6.13) — clansmen passively at home contribute 5 defense each (vs 10 for explicit `DefendBase`) | Only `DefendBase` mission counts; passive home clansmen contribute 0 | Small — extend `_collectDefenderContribution` to include WAITING-at-home, add 5-or-10 dispatch on mission state |
   252	| 7 | **Terminal Escaped state** (§6.12) — Escaped is a removal event; troop deleted from world; carry burned | Escaped is a 2-tick transient that cycles back into Resting | Small — when terminal-escape branch fires (e.g. from #3), remove troop instead of cycling |
   253	| 8 | **Single-troop global limit** (§6.1) — at most ONE active bandit globally | Up to 8 globally; up to 3 per region | Small — set `MAX_TOTAL_BANDITS = 1`; remove per-region cap (or set both to 1); collapse multi-troop spawn loop |
   254	
   255	**Additional smaller drifts** noted in the UAT report but bundled with the above on restoration (no separate tracking):
   256	
   257	- Threshold-comparison combat (Cases A/B/C in §6.15) instead of damage-HP combat — entangled with #1, #6, and the wall/base HP retuning
   258	- Per-clansman defeat-reward granularity (A11) instead of per-clan — entangled with #1 (no carry to distribute means impl difference doesn't yet matter)
   259	- Global cooldown semantics (§6.3) instead of per-region — entangled with #8 (with single-troop, the distinction collapses)
   260	- Spawn rate curve (5% / +1% / 20% cap) instead of (10% / +10% / 80% cap) — small constant retune, bundled with #8 because rate tuning is most relevant at single-troop saturation

exec
/bin/bash -lc 'git show origin/docs/spec-v4-6-bandit-redesign:docs/planning/clanworld_v4_6_bandit_phase9_redesign.md | rg -n "winter|Winter|defer|deferred|quoteLoot|loot|vault|Phase 5|P10|Phase 10"' in /tmp/wt-superswarm-356
 succeeded in 0ms:
12:A spec-vs-impl audit by Claude Opus 4.7 (1M ctx) — the "PR #194 spec-compliance UAT" report at [`docs/reviews/pr194-spec-compliance-uat.md`](../reviews/pr194-spec-compliance-uat.md) — confirmed that the Phase 9 bandit implementation diverges from the v4 spec on numerous core mechanics. Eleven of those drifts are significant (rampage path, vault loot theft, attack-attempt cap, threshold combat, per-clansman split, etc.).
16:- **Path A (chosen)** — declare the implementation canonical, write this addendum as the new authoritative ruleset, defer the v4-specific mechanics to a post-hackathon restoration milestone.
19:Path A was selected because (1) the as-built code is internally consistent and well-tested (the multi-round super-swarm + per-issue PR pipeline already validated it against itself); (2) Phase 9 work has fully landed and downstream phases (10 winter, market) have been built on top of the as-built bandit mechanics; (3) restoring the v4 ruleset is a multi-day Phase 9.5 lift that isn't on the hackathon critical path; (4) the v4 spec was written before Phase 9 implementation experimentation, and several of its mechanics (rampage path, vault theft, terminal escape) trade off complexity for tension that the as-built simpler model has been shown to deliver well enough.
21:This doc canonizes the as-built mechanics. The eight largest drifted mechanics are tracked as a deferred-to-restoration list in §6 and on GH issue [#340](https://github.com/OmniPass-world/clan-world/issues/340) under the `spec-v4-restoration-post-hackathon` milestone for later evaluation.
33:**Out of scope:** all non-bandit mechanics. The rest of the v4 spec (clan minting, missions, market, winter, deaths, gold/blueprint payouts unrelated to bandits) remains canonical.
90:**Region selection is loot-and-clansman weighted** (NOT uniform random — see `ClanWorld.sol:2230-2269`):
92:- `weights[r] += 100 + lootValue / 1e18`  (base + loot bonus)
95:Then RNG-weighted pick across `weights[]`. This biases bandits toward loot-rich, populated regions — intentional per inline code comment ("heuristic to make bandits feel pressuring").
113:- Ranks remaining bases by loot value: `wood + wheat + 2*fish + 4*iron` (matches spec §6.9 — gold is NOT counted)
114:- Tiebreak among equal-loot bases: **uniform random across ties** (NOT lowest-clanId as spec §6.8 requires)
151:### 3.3 No vault loot theft
153:**The implementation does not implement vault loot theft.** Spec §6.15C and §6.16 mandate that a successful attack steals 20% of each vault resource (wood, wheat, fish, iron) into the bandit's `carryX` fields. The impl:
159:**Net effect:** target clan vaults are unchanged by bandit attacks. Bandits do damage to wall/base/clansmen but never extract physical loot.
163:Spec §6.12 requires bandits to be removed from the world after 6 attempts (7th = ESCAPED + carried loot burned + troop deleted). The impl has no `attackAttemptsMade` counter; the field is absent from the struct (`IClanWorld.sol:303-315`) and the ABI returns `attackAttemptsMade: 0` always. Bandits cycle indefinitely until either the target clan dies or defenders defeat them.
191:- **Blueprint reward:** 1e18 Blueprint deposited into target clan's vault. (Spec §6.17 also called for 1e18 Gold to the same vault; impl omits the gold portion.)
246:| 1 | **Vault loot theft** (§6.15C, §6.16) — bandits steal 20% of wood/wheat/fish/iron on failed defense, accumulate carry until defeat/escape | Bandits never extract loot; carry remains 0 in production | Medium — re-wire `_resolveBanditAttack`, write carry update path, plumb through `BanditAttackResolved` event |
250:| 5 | **Lowest-clanId tiebreak** (§6.8) — when multiple bases tied for highest loot value, lowest clanId targeted (deterministic) | RNG-bounded uniform pick (non-deterministic across replay) | Tiny — replace RNG pick with min-clanId scan |
277:- ✅ Bandits do NOT steal vault resources; vault wood/wheat/fish/iron are unchanged after bandit attacks
278:- ✅ Defeated bandits drop only the blueprint (no carry, no gold) to the target clan vault
280:- ✅ Tied loot values across multiple region bases break to a random base, not lowest-clanId
283:If a UAT scenario expects v4-spec behavior (vault theft, rampage transitions, attack-cap removal, etc.), it will fail. **Use this addendum as the oracle**, not v4 §6.
294:  - `clanworld_v4_3_schema_patch.md` E (domain RNG), F (defender cleanup), G (tier canonical), H (loot getter split — v4.3 H still applies; impl matches)
296:- **Restoration tracking:** GH milestone `spec-v4-restoration-post-hackathon` (#25) and tracking issue [#340](https://github.com/OmniPass-world/clan-world/issues/340) — bandit mechanics gap list with the 8 deferred items as a checkbox list

exec
/bin/bash -lc 'git show origin/docs/spec-v4-6-bandit-redesign:docs/planning/clanworld_v4_6_bandit_phase9_redesign.md | wc -l' in /tmp/wt-superswarm-356
 succeeded in 0ms:
296

exec
/bin/bash -lc "git show origin/docs/spec-v4-6-bandit-redesign:docs/planning/clanworld_v4_6_bandit_phase9_redesign.md | nl -ba | sed -n '260,310p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   260	- Spawn rate curve (5% / +1% / 20% cap) instead of (10% / +10% / 80% cap) — small constant retune, bundled with #8 because rate tuning is most relevant at single-troop saturation
   261	- UnicornTown / DeepSea spawn ban (§6.2) — small allowlist check; bundled with #8 because the active-troop-1 model makes spawn region pickier
   262	- v4.3 E domain-key separation (`bandit_spawn` vs `bandit_spawn_region`) — small, can ship independently
   263	- v4.1 A4 eager-settle ALL bases in region — small; can ship independently or with #2 (rampage needs eager-settle anyway)
   264	- 1e18 Gold reward in defeat (§6.17) — tiny, line-level fix; can ship anytime
   265	- Schema cleanup: drop unused `carryGold`, populate `tier` field (v4.3 G), drop unused constants — bundled with #1, #4
   266	
   267	---
   268	
   269	## 7. UAT runners — what to expect
   270	
   271	When Liam (or anyone running interactive UAT against this contract) observes bandit behavior, **expect the as-built mechanics, not the v4 spec mechanics.** Specifically:
   272	
   273	- ✅ Bandits spawn frequently (10% per region per tick, ramping to 80%) and can stack up to 8 globally / 3 per region
   274	- ✅ Bandits stay in their spawn region for their entire lifecycle
   275	- ✅ Bandits attack the same region repeatedly until their target clan dies, defenders defeat them, or you stop watching
   276	- ✅ Bandits do damage to wall, base, and clansmen (clansmen DO die from bandit attacks in this impl)
   277	- ✅ Bandits do NOT steal vault resources; vault wood/wheat/fish/iron are unchanged after bandit attacks
   278	- ✅ Defeated bandits drop only the blueprint (no carry, no gold) to the target clan vault
   279	- ✅ Defenders must be on `DefendBase` mission AT HOME — passive WAITING clansmen contribute 0 defense
   280	- ✅ Tied loot values across multiple region bases break to a random base, not lowest-clanId
   281	- ✅ Bandits can spawn in UnicornTown or DeepSea if a clansman is passing through (no spec ban enforced)
   282	
   283	If a UAT scenario expects v4-spec behavior (vault theft, rampage transitions, attack-cap removal, etc.), it will fail. **Use this addendum as the oracle**, not v4 §6.
   284	
   285	---
   286	
   287	## 8. References
   288	
   289	- **Spec-compliance UAT report:** [`docs/reviews/pr194-spec-compliance-uat.md`](../reviews/pr194-spec-compliance-uat.md) — full mechanic-by-mechanic table, test-coverage gap analysis, scenario predictions
   290	- **Source v4 docs being superseded for bandit mechanics:**
   291	  - `clanworld_v4_spec.md` §6.1–6.18, §4.14 (bandit drop overflow)
   292	  - `clanworld_v4_1_addendum.md` A3, A4, A9, A11
   293	  - `clanworld_v4_2_state_schema_interface_spec.md` §5 (bandit constants), §7.7 (BanditTroop layout), §7.10–7.11 (defender registries), §8.2 (DefendBase semantics)
   294	  - `clanworld_v4_3_schema_patch.md` E (domain RNG), F (defender cleanup), G (tier canonical), H (loot getter split — v4.3 H still applies; impl matches)
   295	- **Implementation HEAD canonized by this addendum:** `218f9020ecb0f4b8277ef59dd55de8e004404d80`
   296	- **Restoration tracking:** GH milestone `spec-v4-restoration-post-hackathon` (#25) and tracking issue [#340](https://github.com/OmniPass-world/clan-world/issues/340) — bandit mechanics gap list with the 8 deferred items as a checkbox list

exec
/bin/bash -lc "git show HEAD:docs/planning/clanworld_v4_2_state_schema_interface_spec.md | nl -ba | sed -n '405,425p'" in /tmp/wt-superswarm-356
exec
/bin/bash -lc "git show HEAD:docs/planning/clanworld_v4_2_state_schema_interface_spec.md | nl -ba | sed -n '615,630p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   615	These may settle lazily in view / simulation form.
   616	
   617	```solidity
   618	function getDerivedClanState(uint32 clanId) external view returns (DerivedClanState memory);
   619	function getDerivedClansmanState(uint32 clansmanId) external view returns (DerivedClansmanState memory);
   620	function getBanditTargetPreview(uint32 banditId) external view returns (uint32 previewClanId);
   621	function quoteTravel(uint8 src, uint8 dst) external view returns (uint8 travelTicks, bytes8 path);
   622	function quoteLootValue(uint32 clanId) external view returns (uint256 lootValue);
   623	```
   624	
   625	### 9.3 Bandit target preview disclaimer
   626	`getBanditTargetPreview()` is **non-binding**.
   627	
   628	Bandit targeting is recomputed at attack resolution time using then-current eagerly settled state.
   629	
   630	---

 succeeded in 0ms:
   405	Each clan owns exactly two plots.
   406	
   407	```solidity
   408	struct WheatPlot {
   409	    WheatPlotState state;
   410	    uint8 region;              // WestFarmland or EastFarmland
   411	    uint256 remainingWheat;
   412	    uint64 regrowUntilTick;
   413	}
   414	```
   415	
   416	Winter transition semantics:
   417	- at winter start: plots enter `WinterLocked`
   418	- at winter end: `WinterLocked -> Regrowing`
   419	- after 4 ticks: `Regrowing -> Harvestable` with reset `remainingWheat`
   420	
   421	### 7.5 Clansman
   422	
   423	```solidity
   424	struct Clansman {
   425	    uint32 clansmanId;

exec
/bin/bash -lc 'git show HEAD:docs/planning/clanworld_v4_spec.md | rg -n "continuous|tick-by-tick|starvation status begins|wood|carry caps|Winter|winter|upkeep|deposit"' in /tmp/wt-superswarm-356
 succeeded in 0ms:
5:**Scope:** World layout, tick semantics, settlement rules, missions, resources, market execution, bandits, winter, building, victory, human steering, trust model, spawn rules, elimination rules, pool seeding, and season lifecycle.
11:ClanWorld is an autonomous strategy game in which each player owns a homebase iNFT and an Elder agent that directs a small clan of workers across a shared world. Workers travel between regions, gather and deposit materials, defend bases, survive winter, trade assets, and compete to build the tallest monument.
154:- local upkeep
211:- goto Forest, chop wood
212:- goto Unicorn Town, sell wood
213:- goto Homebase, deposit resources
215:- goto noop, sell wood immediately in Unicorn Town
263:- `deposit_resources` requested at a non-homebase destination
272:- arrives to deposit with empty cargo
283:- chop wood until cap, then wait in Forest
284:- deposit resources, then wait at Homebase
298:These resolve tick-by-tick until stopped or blocked.
301:- chop wood
313:- deposit resources
326:`defend_base` is a **persistent continuous mission**.
352:1. apply clan upkeep for the tick
355:4. resolve one tick of continuous action for acting clansmen
403:- winter wood burn
409:Carried resources do **not** count until deposited.
412:A clansman must be at their own homebase and perform `deposit_resources` for carried resources to enter the clan vault.
417:- base yield = `2e18` wood per action tick
419:- critical bonus = `+1e18` wood
437:- worker has `14e18` wood carried
438:- worker wood capacity is `15e18`
474:If a clan vault cannot satisfy required wheat or fish upkeep during a tick:
475:- starvation status begins on the **next tick**
484:Outside Winter, starvation does **not** directly kill clansmen in v1.
530:- `goto Unicorn Town, action = sell wood`
603:- Wood / Gold: `1000 wood : 500 gold`
698:- wood = `1` point per token
781:  - wood
823:# 7. Winter Rules
825:## 7.1 Winter cadence
826:Winter occurs every `110` ticks.
828:## 7.2 Winter duration
829:Winter lasts `10` ticks.
831:## 7.3 Winter upkeep
832:During winter, each clan consumes:
835:- wood burn = `1e18` wood per base per tick
837:## 7.4 Winter farming rule
838:During winter:
841:- regrowth does not complete during winter
843:At winter start:
845:- both plots restart regrowing after winter ends
846:- both plots become harvestable again `4` ticks after winter ends
848:## 7.5 Winter gathering outside farming
849:During winter:
854:## 7.6 Winter failure: cold damage
855:If a base cannot pay the required winter wood burn for a tick:
866:`coldDamage` resets to `0` at the end of each Winter.
868:Cold damage does **not** persist across winters.
870:Wall damage and clansman deaths caused by earlier winter cold still persist, but the temporary cold-damage accumulator does not carry into the next winter cycle.
895:- Level 1: `20 wood`
896:- Level 2: `35 wood`
897:- Level 3: `30 wood + 5 iron`
898:- Level 4: `40 wood + 10 iron`
899:- Level 5: `50 wood + 15 iron`
909:- Level 2: `40 wood + 20 wheat`
910:- Level 3: `60 wood + 5 iron + 30 wheat`
911:- Level 4: `80 wood + 10 iron + 40 wheat`
912:- Level 5: `100 wood + 15 iron + 50 wheat`
927:- Level 1: `30 wood + 20 wheat`
928:- Level 2: `50 wood + 30 wheat`
929:- Level 3: `70 wood + 40 wheat + 5 iron`
930:- Level 4: `90 wood + 50 wheat + 10 iron`
931:- Level 5: `120 wood + 60 wheat + 15 iron`
932:- Level 6: `150 wood + 80 wheat + 20 iron`
947:- walls may lose levels from winter cold damage and bandit pressure
991:This is approximately three winters under the current winter cadence.
1097:- `20e18` wood
1164:- only vault resources count for upkeep and building
1189:- starvation weakens but does not kill outside Winter
1194:- winter every 110 ticks for 10 ticks
1195:- cold damage reset each winter

exec
/bin/bash -lc "git show HEAD:docs/planning/clanworld_v4_3_schema_patch.md | nl -ba | sed -n '190,212p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
   190	---
   191	
   192	## H. Loot Value Getter Split
   193	
   194	### H.1 Two getter flavors
   195	The schema exposes two distinct loot value getters:
   196	
   197	- `quoteLootValueRaw(clanId)`
   198	- `quoteLootValueSettled(clanId)`
   199	
   200	### H.2 Raw getter
   201	`quoteLootValueRaw(clanId)`:
   202	- reads currently committed vault balances only
   203	- does not lazily simulate settlement
   204	- intended for lightweight UI/debug usage
   205	
   206	### H.3 Settled getter
   207	`quoteLootValueSettled(clanId)`:
   208	- simulates or uses settled-to-current-tick state
   209	- intended for target preview / strategic reasoning
   210	- bandit targeting semantics conceptually align with the settled value path
   211	
   212	---

exec
/bin/bash -lc "git branch -r | rg 'spec-audit-phase-5|phase-5|352|356'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
  origin/dev-phase-5-economy
  origin/dev-phase-5b-spec-alignment
  origin/docs/spec-audit-phase-5
  origin/feat/issue-352-phase5b-alignment-addendum

exec
/bin/bash -lc 'git show origin/docs/spec-audit-phase-5:docs/reviews/pr193-spec-compliance-uat.md | rg -n "DRIFT|Continuous|Wood base|Iron base|Fish docks|Wheat harvest|Winter|Starvation|Summary|Path A"' in /tmp/wt-superswarm-356
 succeeded in 0ms:
33:- **§4.7 Fish docks (W/E):** 25% chance of 1e18 fish per action tick
54:| **Continuous-action tick semantics (§3.10)** | gather actions yield once per tick, continuously, until stopped | gather actions have `getActionDuration = 4`; `_settleMissionForClansman` only calls `_resolveAction` when `tick >= settlesAtTick` (i.e. after 4 ticks elapse from `actionStartTick`); on each resolution the gather helpers credit `YIELD_PER_TICK * duration = 4 * YIELD_PER_TICK` to carry, then `_completeMission` (not continuous) | `ClanWorld.sol:341-344, 1796-1801, 478-665` | ❌ DRIFT — fundamentally not continuous. One gather order = one settlement = one batched yield, then mission ends + worker returns to WAITING. To gather more the Elder must submit a new mission (which incurs cooldown per A5). |
55:| **Per-clansman wood cap (§4.3, v4_2 §5)** | 15e18 | `WOOD_CAP = CLANSMAN_CARRY_CAP = 10e18` | `IClanWorld.sol:43-44` | ❌ DRIFT — 33% lower than spec |
59:| **Per-resource carry cap enforcement (§4.8)** | each resource has independent cap; clamp to remaining | wood gather only enforces `CLANSMAN_CARRY_CAP` against `cs.carryWood` (no cross-resource accounting). Iron / wheat / fish gather check the per-resource cap. Code comment in `IClanWorld.sol:43`: "only enforced for wood gather" | `IClanWorld.sol:43`, `ClanWorld.sol:487, 519, 559, 590, 621` | ⚠️ DRIFT — comment is misleading (other resources DO check per-resource caps); but `WOOD_CAP` aliasing to a generic `CLANSMAN_CARRY_CAP` (10e18) and applying only to wood is structurally fragile if Phase 5.x adds aggregate-carry rules later |
60:| **Wood base yield (§4.7)** | 2e18 wood per action tick | `WOOD_YIELD_PER_TICK = 1e18`; per-call yield = `1e18 × 4 = 4e18` (because action duration = 4 ticks). **Net per-tick rate = 1e18, half of spec's 2e18.** | `IClanWorld.sol:50, 54`, `ClanWorld.sol:493` | ❌ DRIFT — sustained per-tick wood rate is half of spec |
61:| **Wood crit chance (§4.7)** | 20% | `WOOD_CRIT_BPS = 1000` (= 10%) | `IClanWorld.sol:55` | ❌ DRIFT — half of spec |
62:| **Wood crit shape (§4.7)** | crit ADDS `+1e18` (additive) → total 3e18 (or 2e18 base) | impl multiplies yield `*= 2` → on crit = `8e18` per call (not `2e18 + 1e18 = 3e18` per tick equivalent) | `ClanWorld.sol:495-497` | ❌ DRIFT — wrong math shape AND wrong magnitude (impl crit DOUBLES, spec crit adds 50% of base on top) |
63:| **Iron base yield (§4.7)** | 0.5e18 per action tick | `IRON_YIELD_PER_TICK = 1.25e17`; per-call yield = `1.25e17 × 4 = 5e17 = 0.5e18`. **Net per-tick rate = 0.125e18, ¼ of spec's 0.5e18.** | `IClanWorld.sol:57-58`, `ClanWorld.sol:524` | ❌ DRIFT — sustained per-tick iron rate is ¼ of spec |
66:| **Iron gold bonus rolled per call vs per tick** | spec implies per action tick (continuous) | impl rolls once per call (i.e. once per 4 ticks) | `ClanWorld.sol:539-548` | ❌ DRIFT — bonus opportunity rate is ¼ of spec (combined with the per-tick rate drift = ¼ overall iron-gold yield) |
67:| **Fish docks rate (§4.7)** | 25% chance of 1e18 fish per action tick | `FISH_DOCKS_BPS = 2500`; on success yield = `25e16 × 4 = 1e18` per call. Roll happens once per call. **Sustained rate = 25% × 1e18 / 4 ticks = 0.0625e18 per tick, ¼ of spec's 0.25e18 per tick.** | `IClanWorld.sol:65, 63`, `ClanWorld.sol:563-578` | ❌ DRIFT — sustained fish-docks rate is ¼ of spec |
68:| **Fish deep sea rate (§4.7)** | 75% chance of 1e18 fish per action tick | `FISH_DEEP_BPS = 7500`; same shape. **Sustained = 0.1875e18 per tick, ¼ of spec's 0.75e18 per tick.** | `IClanWorld.sol:66, 63`, `ClanWorld.sol:594-609` | ❌ DRIFT — sustained fish-deep rate is ¼ of spec |
69:| **Wheat harvest rate (§4.9)** | 20e18 per action tick | `WHEAT_YIELD_PER_TICK = 5e18`; per-call yield = `5e18 × 4 = 20e18`. **Sustained per-tick = 5e18, ¼ of spec's 20e18.** | `IClanWorld.sol:62`, `ClanWorld.sol:646` | ❌ DRIFT — sustained wheat rate is ¼ of spec |
77:| **Winter wheat plot lockdown (§7.4)** | "during winter: wheat plots are unavailable; harvesting wheat is not allowed" | NOT IMPLEMENTED. `_gatherWheat` does not check `_world.winterActive`. `_settleClan` per-tick wheat-plot regrow loop has no `WinterLocked` transition. | `ClanWorld.sol:376-383, 612-665` | ❌ MISSING — wheat plots remain harvestable during winter |
78:| **WheatPlotState enum has WinterLocked** | yes (v4_2 §7.4) | enum has 3 states: `Harvestable, Regrowing, WinterLocked` | `IClanWorld.sol:123-127` | ⚠️ PARTIAL — schema present, behavior absent (dead enum value) |
79:| **Per-clansman vault upkeep order (§3.14)** | order: 1. upkeep, 2. starvation flag, 3. travel, 4. continuous, 5. single-tick effects, 6. terminal | `_settleClan` does: 1. `_applyUpkeep(tick)` → 2. wheat-plot regrow → 3-6. for each clansman `_settleMissionForClansman` (which combines travel + ACTING + resolve in one inline loop). Starvation flag is set inside `_applyUpkeep`. **Same order as spec for upkeep + starvation, but plot regrow happens BEFORE traveling/acting.** | `ClanWorld.sol:371-389, 397-425` | ⚠️ DRIFT — plot regrow inserted between upkeep and travel; not strictly spec-mandated, but plot state could change mid-tick relative to clansman action. Functionally OK because actions resolve on `tick >= settlesAtTick` boundary, not mid-tick. |
84:| **Starvation flag set on next tick (§4.11)** | "starvation status begins on the **next tick**" | `if (starving) clan.starvationStartsAtTick = tick;` (i.e. on the SAME tick as the failure, not next tick); reading code uses `_isStarving = starvationStartsAtTick != 0 && starvationStartsAtTick <= currentTick` so a clan starving as of `tick T` reports `_isStarving == true` IMMEDIATELY at tick T | `ClanWorld.sol:418-419, 428-430` | ❌ DRIFT — starvation activates same tick as failure, not next tick. Spec §4.11 is explicit: "starvation status begins on the **next tick**." |
86:| **Starvation recovery (§4.12)** | "Starvation remains active until a later clan settlement determines that required food supply is again sustainable" | `if (!starving && clan.starvationStartsAtTick != 0) clan.starvationStartsAtTick = 0;` (clears flag once vault can pay both wheat+fish in same tick) | `ClanWorld.sol:421-424` | ✅ MATCHES |
89:| **Winter wheat consumption multiplier (§7.3)** | 2× during winter | NOT IMPLEMENTED. `_applyUpkeep` uses flat `WHEAT_UPKEEP_PER_CLANSMAN` regardless of `_world.winterActive` | `ClanWorld.sol:400-401` | ❌ MISSING — Phase 5.6 surface but constant `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` exists unused |
90:| **Winter fish consumption multiplier (§7.3)** | 2× during winter | NOT IMPLEMENTED — same as wheat | `ClanWorld.sol:400-401` | ❌ MISSING |
91:| **Winter wood burn (§7.3)** | 1e18 wood per base per tick during winter | NOT IMPLEMENTED. `_applyUpkeep` does not touch `vaultWood` and does not check `winterActive`. Constant `WINTER_WOOD_BURN_PER_BASE = 1e18` declared but unused. | `IClanWorld.sol:71`, `ClanWorld.sol:397-425` | ❌ MISSING — dead constant |
92:| **Winter wheat plot lockdown (§7.4)** | plots become unavailable during winter | NOT IMPLEMENTED (already flagged above) | (no code) | ❌ MISSING |
93:| **Winter cold damage / wall collapse (§7.5, alluded by v4_1 A10)** | not Phase-5 directly but coupled | NOT IMPLEMENTED — `Clan.coldDamage` field is reset to 0 but never incremented anywhere in this branch | `ClanWorld.sol:1033`, `IClanWorld.sol:249` | ❌ MISSING (Phase-5.6 / Phase-7-winter scope; flagged for context) |
94:| **Wheat-plot WinterLocked transition at winter start (v4_2 §7.4)** | "at winter start: plots enter `WinterLocked`" | NOT IMPLEMENTED — heartbeat does not set plot state to `WinterLocked`; the enum value is dead. | `ClanWorld.sol:376-383, 1043-1054` | ❌ MISSING |
95:| **Wheat-plot WinterLocked → Regrowing at winter end (v4_2 §7.4)** | "at winter end: `WinterLocked → Regrowing`" | NOT IMPLEMENTED | (no code) | ❌ MISSING |
114:### Summary of mechanic verification
119:| ⚠️ DRIFT (close-but-different) | 3 |
120:| ❌ DRIFT/MISSING (significant) | 14 |
160:| **Starvation onset at next-tick boundary (§4.11)** | Direct spec contradiction. Test should assert: tick T → upkeep fails → at end of tick T `_isStarving == false`; at start of tick T+1 `_isStarving == true`. Current impl flips immediately at tick T. | Phase 5.6 (starvation upkeep) — but constant declared in 5.0; impl already wires the wrong semantics |
161:| **Continuous gathering across multiple action ticks (§3.10)** | Spec says continuous tick-by-tick yield. Test should verify 8 ticks of gathering → 8 × yield, no mission-end / cooldown reset between yields. Current impl ends mission after one batched pay-out → forces re-submit + cooldown. | Phase 5.1 (impl is fundamentally batched not continuous) |
167:| **Winter wheat plot lockdown (§7.4)** | Plot must enter `WinterLocked` at winter start. Zero tests. | Phase 5.4 / Phase 7 winter |
168:| **Winter upkeep 2× multiplier (§7.3)** | Vault drains twice as fast. Zero tests; constant `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` declared and unused. | Phase 5.6 / Phase 7 |
169:| **Winter wood burn (§7.3, 1e18/base/tick)** | Critical economy mechanic. Zero tests; constant declared and unused. | Phase 5.6 / Phase 7 |
177:| **Starvation recovery transition** | Test: vault drained → starving → fill vault → next-tick upkeep → starvation cleared. Code path exists but no test. |
181:| **Fish docks vs deep sea probability separation** | Different `BPS` constants. Only one test for docks; deep-sea has no per-tick test. |
199:### Scenario 1 — Continuous gathering vs batched
217:### Scenario 4 — Starvation onset off-by-one
231:**Expected per spec:** mission rejected OR completes with 0 yield; plot state = `WinterLocked`.
232:**Actual per impl:** mission accepts, plot still Harvestable, yields normal 20e18 wheat. Winter wood burn doesn't fire (also missing).
233:**He should verify:** call `getWheatPlots(clanId)` during winter — both plots will report `state = Harvestable` (impl) instead of `WinterLocked` (spec).
235:### Scenario 7 — Winter upkeep 2× multiplier missing
251:**SPEC DRIFT IS SUBSTANTIAL — RECOMMEND PATH A (RATIFY IMPL AS-IS, UPDATE SPEC) BEFORE LIAM UAT.**
261:4. **Winter mechanics absent:** wood burn, upkeep doubling, wheat plot lockdown — all unwired. Phase 5.6 / Phase 7 are explicitly downstream, but the constants exist so far in `IClanWorld.sol` that they are effectively dead code right now.
263:5. **Starvation off-by-one:** flag activates at end of failure-tick instead of start of next tick. One-line fix (`starvationStartsAtTick = tick + 1`), but consumers (e.g. defenders contributing 0 in `_resolveBanditAttack`) would change behavior, so worth a careful regression test.
267:**Path A — Ratify impl as canonical, update spec:** Phase 5 has clearly evolved into a batched-action economy where yield calibration is geared to action-size × duty-cycle, not per-tick continuous flow. Drafting `clanworld_v4_6_phase5_economy_alignment.md` documenting (a) batched-action semantics, (b) recalibrated per-action yields equivalent to spec per-action-tick numbers, (c) the 10e18 wood cap, (d) starvation-tick semantics — formalizes the as-built. Phase 5.6 / Phase 7 winter mechanics still need impl per the same addendum or separate Phase-7 ticket.
271:**Recommended next step (before Liam runs UAT):** Liam decides Path A or Path B with knowledge that the cloud reviewers have already reviewed and approved the impl as internally consistent (5 reviewers, 1 R1 fix-round landed = `9b67414`). The R1 round did NOT include a spec-vs-impl alignment pass — it caught ABI bugs and per-tick yield migration parity bugs (= migration was done correctly, but only matches the impl's old shape, not the spec).
279:## 6. Path A / Path B recommendation
281:**Recommendation: Path A — ratify impl, draft v4.6 economy alignment addendum.**
288:  - **Trivial drift (1):** `WOOD_CAP = 10e18` vs spec 15e18 — orchestrator can fix directly, one line in `IClanWorld.sol`. (Optional — Path A may ratify 10e18.)
289:  - **Substantial drift (13):** continuous-vs-batched action lifecycle, wood crit shape, all four per-tick yield rates, starvation onset tick, winter wheat lockdown, winter upkeep multiplier, winter wood burn, wheat WinterLocked transitions (start + end), cold damage path. All require either an impl rewrite (Path B) or spec acceptance (Path A).
291:If Path A is approved: file a single `clanworld_v4_6_phase5_economy_alignment.md` ADR draft and proceed to UAT against the new spec. Phase 5.6 (starvation upkeep) and Phase 7 (winter) remain open issues that will need to address the missing winter mechanics regardless of A or B.

exec
/bin/bash -lc 'git show origin/docs/spec-audit-phase-5:docs/reviews/pr193-spec-compliance-uat.md | wc -l' in /tmp/wt-superswarm-356
 succeeded in 0ms:
315

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '1620,1685p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
  1620	        }
  1621	
  1622	        // ChopWood: must go to Forest
  1623	        if (action == ActionType.ChopWood) {
  1624	            if (gotoRegion != ClanWorldConstants.REGION_FOREST) return StatusCode.ERR_INVALID_REGION;
  1625	        }
  1626	        // MineIron: must go to Mountains
  1627	        if (action == ActionType.MineIron) {
  1628	            if (gotoRegion != ClanWorldConstants.REGION_MOUNTAINS) return StatusCode.ERR_INVALID_REGION;
  1629	        }
  1630	        // FishDocks: must go to WestDocks or EastDocks
  1631	        if (action == ActionType.FishDocks) {
  1632	            if (
  1633	                gotoRegion != ClanWorldConstants.REGION_WEST_DOCKS && gotoRegion != ClanWorldConstants.REGION_EAST_DOCKS
  1634	            ) {
  1635	                return StatusCode.ERR_INVALID_REGION;
  1636	            }
  1637	        }
  1638	        // FishDeepSea: must go to DeepSea
  1639	        if (action == ActionType.FishDeepSea) {
  1640	            if (gotoRegion != ClanWorldConstants.REGION_DEEP_SEA) return StatusCode.ERR_INVALID_REGION;
  1641	        }
  1642	        // HarvestWheat: must go to WestFarms or EastFarms
  1643	        if (action == ActionType.HarvestWheat) {
  1644	            if (
  1645	                gotoRegion != ClanWorldConstants.REGION_WEST_FARMS && gotoRegion != ClanWorldConstants.REGION_EAST_FARMS
  1646	            ) {
  1647	                return StatusCode.ERR_INVALID_REGION;
  1648	            }
  1649	        }
  1650	
  1651	        if (action == ActionType.DefendBase) {
  1652	            return _validateDefendBaseOrder(clan, order, gotoRegion);
  1653	        }
  1654	
  1655	        // MarketBuy/MarketSell: must target Unicorn Town
  1656	        if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
  1657	            if (_treasury.woodToken == address(0)) return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
  1658	            if (gotoRegion != ClanWorldConstants.REGION_UNICORN_TOWN) {
  1659	                return StatusCode.ERR_INVALID_REGION;
  1660	            }
  1661	            if (order.marketAmount == 0) return StatusCode.ERR_MARKET_ZERO_AMOUNT;
  1662	            // Validate token is a supported resource token (not gold itself)
  1663	            address tok = order.marketToken;
  1664	            if (tok == address(0) || tok == _treasury.goldToken) {
  1665	                return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
  1666	            }
  1667	            if (
  1668	                tok != _treasury.woodToken && tok != _treasury.ironToken && tok != _treasury.wheatToken
  1669	                    && tok != _treasury.fishToken
  1670	            ) {
  1671	                return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
  1672	            }
  1673	            // Market orders are always enqueued for the arrivalTick FIFO queue.
  1674	            // _resolveAction records mission completion but does not execute any swap.
  1675	            if (cs.currentRegion == ClanWorldConstants.REGION_UNICORN_TOWN && cs.state == ClansmanState.WAITING) {
  1676	                // Already at Unicorn Town — arrivalTick == currentTick, queued for next heartbeat.
  1677	            }
  1678	        }
  1679	
  1680	        cs; // suppress unused warning
  1681	        return StatusCode.OK;
  1682	    }
  1683	
  1684	    function _validateDefendBaseOrder(Clan storage clan, ClanOrder calldata order, uint8 gotoRegion)
  1685	        internal

exec
/bin/bash -lc 'git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | rg -n "ERR_CARRY_FULL|carryWood|carryIron|carryWheat|carryFish|REGION_FOREST|REGION_MOUNTAINS|REGION_WEST_DOCKS|REGION_DEEP_SEA|REGION_WEST_FARMS"' in /tmp/wt-superswarm-356
 succeeded in 0ms:
487:        if (cs.carryWood >= ClanWorldConstants.CLANSMAN_CARRY_CAP) {
492:        uint256 remaining = ClanWorldConstants.CLANSMAN_CARRY_CAP - cs.carryWood;
501:        cs.carryWood += yield;
505:        if (cs.carryWood >= ClanWorldConstants.CLANSMAN_CARRY_CAP) {
519:        uint256 remaining = ClanWorldConstants.IRON_CAP - cs.carryIron;
527:        cs.carryIron += yield;
534:        if (cs.carryIron >= ClanWorldConstants.IRON_CAP) {
559:        uint256 remaining = ClanWorldConstants.FISH_CAP - cs.carryFish;
573:            cs.carryFish += yield;
576:        if (cs.carryFish >= ClanWorldConstants.FISH_CAP) {
590:        uint256 remaining = ClanWorldConstants.FISH_CAP - cs.carryFish;
604:            cs.carryFish += yield;
607:        if (cs.carryFish >= ClanWorldConstants.FISH_CAP) {
621:        uint256 remaining = ClanWorldConstants.WHEAT_CAP - cs.carryWheat;
629:        if (region == ClanWorldConstants.REGION_WEST_FARMS) {
651:        cs.carryWheat += yield;
661:        if (cs.carryWheat >= ClanWorldConstants.WHEAT_CAP || plot.remainingWheat == 0) {
675:        bool hasAnything = cs.carryWood > 0 || cs.carryIron > 0 || cs.carryWheat > 0 || cs.carryFish > 0;
682:        uint256 woodDelta = cs.carryWood;
683:        uint256 ironDelta = cs.carryIron;
684:        uint256 wheatDelta = cs.carryWheat;
685:        uint256 fishDelta = cs.carryFish;
692:        cs.carryWood = 0;
693:        cs.carryIron = 0;
694:        cs.carryWheat = 0;
695:        cs.carryFish = 0;
1011:            ClanWorldConstants.REGION_FOREST,
1012:            ClanWorldConstants.REGION_MOUNTAINS,
1013:            ClanWorldConstants.REGION_WEST_FARMS,
1015:            ClanWorldConstants.REGION_WEST_DOCKS,
1045:            region: ClanWorldConstants.REGION_WEST_FARMS,
1066:            cs.carryWood = 0;
1067:            cs.carryIron = 0;
1068:            cs.carryWheat = 0;
1069:            cs.carryFish = 0;
1624:            if (gotoRegion != ClanWorldConstants.REGION_FOREST) return StatusCode.ERR_INVALID_REGION;
1628:            if (gotoRegion != ClanWorldConstants.REGION_MOUNTAINS) return StatusCode.ERR_INVALID_REGION;
1633:                gotoRegion != ClanWorldConstants.REGION_WEST_DOCKS && gotoRegion != ClanWorldConstants.REGION_EAST_DOCKS
1640:            if (gotoRegion != ClanWorldConstants.REGION_DEEP_SEA) return StatusCode.ERR_INVALID_REGION;
1645:                gotoRegion != ClanWorldConstants.REGION_WEST_FARMS && gotoRegion != ClanWorldConstants.REGION_EAST_FARMS
1832:            carryWood: 0,
1833:            carryIron: 0,
1834:            carryWheat: 0,
1835:            carryFish: 0
2080:            carryWood: 0,
2081:            carryIron: 0,
2082:            carryWheat: 0,
2083:            carryFish: 0,

exec
/bin/bash -lc "git show origin/dev-phase-5-economy:packages/contracts/src/ClanWorld.sol | nl -ba | sed -n '1270,1292p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
  1270	        m.nonce = ctx.newNonce;
  1271	        m.clansmanId = cs.clansmanId;
  1272	        m.submittedAtTick = _world.currentTick;
  1273	        m.executesAtTick = ctx.arrivalTick;
  1274	        m.settlesAtTick = order.action == ActionType.DefendBase
  1275	            ? type(uint64).max
  1276	            : _addTicksClamped(ctx.arrivalTick, getActionDuration(order.action));
  1277	        m.startRegion = ctx.fromRegion;
  1278	        m.targetRegion = ctx.gotoRegion;
  1279	        m.action = order.action;
  1280	        m.startTick = _world.currentTick;
  1281	        m.arrivalTick = ctx.arrivalTick;
  1282	        m.actionStartTick = ctx.arrivalTick;
  1283	        m.missionSeed = keccak256(abi.encode(_world.currentTickSeed, cs.clansmanId, ctx.newNonce));
  1284	        m.marketMode = (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell)
  1285	            ? MarketExecutionMode.Scheduled
  1286	            : MarketExecutionMode.None;
  1287	        m.targetClanId = ctx.targetClanId;
  1288	        m.marketToken = order.marketToken;
  1289	        m.marketAmount = order.marketAmount;
  1290	        m.maxGoldIn = order.maxGoldIn;
  1291	    }
  1292	

exec
/bin/bash -lc "rg -n \"Phase 5\\.6|Phase 7|Phase 10|winter|Winter|wood burn|upkeep multiplier|cold damage\" docs BUILD_PLAN.md packages | head -160" in /tmp/wt-superswarm-356
 succeeded in 0ms:
docs/reviews/pr136-review-claude-opus.md:64:| 22 | (commit history) | — | **Several commits missing `(#N)` issue refs.** Affects: `feat(runner): add ClanWorld runner daemon prototype`, `fix(runner): fix-round PR #93`, `feat(runner): Phase 7/8`, `fix(runner): narrow heartbeat error upgrade`. | Conventions |
docs/planning/ClanWorldCockpit_BrainstormingMock.jsx:243:GAMMA: { strategy: ‘Survive winter. Convert wheat surplus into defense contracts.’,
docs/planning/ClanWorldCockpit_BrainstormingMock.jsx:246:goals: [‘Survive winter’, ‘Stabilize food’] },
docs/planning/ClanWorldCockpit_BrainstormingMock.jsx:503:{ icon: <Skull size={11} />, text: ‘GAMMA STARVING · cold damage accruing’, color: T.statusDanger },
docs/planning/battleplan-v1.txt:6:	•	Demo cadence: 20s/tick. Six-minute season at 18 ticks gets you through 1–2 winters’ worth of drama without burning judges’ attention.
packages/agents/src/seams/IElderMemoryStore.ts:5: * Phase 7: 0G iNFT memory (ERC-7857 linked storage per clan; survives ownership transfer)
docs/planning/clanworld_numbered_implementation_plan.md:207:### 4.4 Add winter / season timers to world state
docs/planning/clanworld_numbered_implementation_plan.md:210:- winter timing
docs/planning/clanworld_numbered_implementation_plan.md:218:**Cut line:** if needed, winter logic can still be stubbed here.
docs/planning/clanworld_numbered_implementation_plan.md:241:- winter interaction hook
docs/planning/clanworld_numbered_implementation_plan.md:311:## Phase 7 — OTC transfer surface
docs/planning/clanworld_numbered_implementation_plan.md:413:## Phase 10 — winter and elimination
docs/planning/clanworld_numbered_implementation_plan.md:415:### 10.1 Implement winter schedule
docs/planning/clanworld_numbered_implementation_plan.md:416:- first winter at tick 110
docs/planning/clanworld_numbered_implementation_plan.md:420:### 10.2 Implement winter upkeep
docs/planning/clanworld_numbered_implementation_plan.md:422:- wood burn
docs/planning/clanworld_numbered_implementation_plan.md:424:### 10.3 Implement cold damage
docs/planning/clanworld_numbered_implementation_plan.md:428:- reset at winter end
docs/planning/clanworld_numbered_implementation_plan.md:430:### 10.4 Implement crop winter transitions
docs/planning/clanworld_numbered_implementation_plan.md:432:- lock during winter
docs/planning/clanworld_numbered_implementation_plan.md:433:- restart regrow after winter
docs/planning/clanworld_numbered_implementation_plan.md:441:- winter can kill clans and end runs
docs/planning/clanworld_numbered_implementation_plan.md:451:- approximately 3 winters
docs/planning/clanworld_numbered_implementation_plan.md:507:6. optional winter hardship
docs/planning/clanworld_numbered_implementation_plan.md:537:- winter
docs/planning/clanworld_numbered_implementation_plan.md:564:12. winter  
docs/planning/clanworld_v1_implementation_profile.md:224:- only vault contents count for upkeep/building/winter
docs/planning/clanworld_v1_implementation_profile.md:242:- winter
docs/planning/clanworld_v1_implementation_profile.md:299:- winter
docs/planning/clanworld_v1_implementation_profile.md:300:- cold damage
docs/planning/clanworld_v4_1_addendum.md:20:## A2. First winter timing
docs/planning/clanworld_v4_1_addendum.md:22:The first winter begins at **tick 110**.
docs/planning/clanworld_v4_1_addendum.md:24:Thereafter, winter begins every 110 ticks:
docs/planning/clanworld_v4_1_addendum.md:30:Each winter lasts **10 ticks**, as already specified in v4.
docs/planning/clanworld_v4_1_addendum.md:81:## A6. Just-in-time winter logistics are intentionally punitive
docs/planning/clanworld_v4_1_addendum.md:91:This means that during winter:
docs/planning/clanworld_v4_1_addendum.md:96:then the base **still takes the winter wood-burn failure / cold-damage consequence for that tick**.
docs/planning/clanworld_v4_1_addendum.md:168:Starvation outside winter does **not** directly kill clansmen.
docs/planning/clanworld_v4_1_addendum.md:170:While starving outside winter:
docs/planning/clanworld_v4_1_addendum.md:174:Clansman death from deprivation occurs only through the winter cold-damage / wall-collapse pathway already specified in v4.
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:43:- winter cadence and cold damage
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:84:- winter boundary transitions
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:204:- winter burn
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:222:- winter burn
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:342:    bool winterActive;
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:343:    uint64 winterStartsAtTick;   // first winter start is tick 110
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:344:    uint64 winterEndsAtTick;     // 0 if not active
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:391:    uint16 coldDamage;             // resets to 0 at winter end
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:416:Winter transition semantics:
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:417:- at winter start: plots enter `WinterLocked`
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:418:- at winter end: `WinterLocked -> Regrowing`
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:818:Because upkeep is applied before deposit effects, a worker arriving home with wood/food in carry does **not** save the base from that same tick’s winter burn or upkeep shortage.
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:833:Outside winter, starvation is nonlethal.
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:838:- does not lose workers directly from starvation outside winter
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:886:event WinterStarted(uint64 indexed tick);
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:887:event WinterEnded(uint64 indexed tick);
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:933:- only vault resources count for upkeep, winter burn, building, and bandit target value
docs/planning/clanworld_v4_3_schema_patch.md:321:- winter transition checks
docs/planning/clanworld_v4_4_ui_indexer_getters.md:57:    bool   winterActive;
docs/planning/clanworld_v4_4_ui_indexer_getters.md:58:    uint64 winterStartsAtTick;
docs/planning/clanworld_v4_4_ui_indexer_getters.md:59:    uint64 winterEndsAtTick;
docs/planning/clanworld_v4_4_ui_indexer_getters.md:84:- Drives: top HUD bar, season clock, winter indicator, leaderboard panel, bandit summary
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:37:**Out of scope:** all non-economy mechanics. Bandit interactions with vault state (loot value getter — see `clanworld_v4_6_bandit_phase9_redesign.md`), winter mechanics (deferred — §9), market mechanics (Phase 6), deaths (Phase 10), gold/blueprint payouts. The rest of the v4 spec remains canonical unless overridden by a later addendum.
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:209:- No death from starvation outside winter (summer starvation = debuff only, matches A10)
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:225:| `WinterLocked` | Winter active (see §9) | **Not wired in impl** — enum value declared, behavior deferred |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:260:## 9. Winter mechanics — deferred (Phase 5.6 / Phase 7)
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:262:The following winter mechanics are declared in constants but **not wired in the implementation**. They are explicitly out of scope for Phase 5B and will be implemented under Phase 5.6 (starvation upkeep) and Phase 7 (winter season):
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:266:| Winter wheat plot lockdown (§7.4) | plots enter `WinterLocked` at winter start; no harvest | NOT IMPLEMENTED — `_gatherWheat` does not check `winterActive`; `WinterLocked` enum value is dead | `WheatPlotState.WinterLocked` in `IClanWorld.sol:125` |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:267:| Winter upkeep 2× (§7.3) | wheat + fish consumption doubles during winter | NOT IMPLEMENTED — `_applyUpkeep` uses flat rate regardless of `winterActive` | `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` in `IClanWorld.sol` (unused) |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:268:| Winter wood burn (§7.3) | 1e18 wood per base per tick during winter | NOT IMPLEMENTED — `_applyUpkeep` does not touch `vaultWood`; no winter check | `WINTER_WOOD_BURN_PER_BASE = 1e18` in `IClanWorld.sol:71` (unused) |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:269:| WinterLocked → Regrowing at winter end (v4_2 §7.4) | on winter end, locked plots → Regrowing | NOT IMPLEMENTED | — |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:271:**Behavior during winter (as-built):** Gathering and deposit work exactly as described in §2–§7 above, regardless of whether winter is active. Upkeep rates are flat (non-doubled). Wood burn does not fire.
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:291:| 11 | **Winter wheat plot lockdown** (§7.4) — plots enter `WinterLocked` at winter start; no harvest | `WinterLocked` enum state declared, not wired | Small–Medium — wire winter-start heartbeat to set plot state; add check in `_gatherWheat`; wire winter-end → Regrowing |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:292:| 12 | **Winter upkeep 2× multiplier** (§7.3) — wheat + fish consumption doubles in winter | Flat rate; `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` declared, unused | Small — multiply upkeep by `WINTER_UPKEEP_MULTIPLIER_BPS` when `winterActive` in `_applyUpkeep` |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:293:| 13 | **Winter wood burn 1e18/base/tick** (§7.3) | Not implemented; `WINTER_WOOD_BURN_PER_BASE = 1e18` declared, unused | Small — add wood burn branch in `_applyUpkeep` when `winterActive` |
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:296:Items 11–13 partially overlap with Phase 5.6 (starvation upkeep) and Phase 7 (winter season) scope. Those phases will address them regardless.
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:339:- ✅ Wheat plots remain harvestable during winter (WinterLocked NOT wired)
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:340:- ✅ Winter upkeep doubling NOT active; flat upkeep rates apply year-round
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:341:- ✅ Winter wood burn NOT active
docs/planning/clanworld_v4_6_phase5_economy_alignment.md:343:If a UAT scenario expects v4-spec continuous yields, per-tick rates, or winter lockdown behavior, it will fail against this contract. Use this addendum as the oracle.
docs/planning/clanworld_v4_spec.md:5:**Scope:** World layout, tick semantics, settlement rules, missions, resources, market execution, bandits, winter, building, victory, human steering, trust model, spawn rules, elimination rules, pool seeding, and season lifecycle.
docs/planning/clanworld_v4_spec.md:11:ClanWorld is an autonomous strategy game in which each player owns a homebase iNFT and an Elder agent that directs a small clan of workers across a shared world. Workers travel between regions, gather and deposit materials, defend bases, survive winter, trade assets, and compete to build the tallest monument.
docs/planning/clanworld_v4_spec.md:403:- winter wood burn
docs/planning/clanworld_v4_spec.md:484:Outside Winter, starvation does **not** directly kill clansmen in v1.
docs/planning/clanworld_v4_spec.md:823:# 7. Winter Rules
docs/planning/clanworld_v4_spec.md:825:## 7.1 Winter cadence
docs/planning/clanworld_v4_spec.md:826:Winter occurs every `110` ticks.
docs/planning/clanworld_v4_spec.md:828:## 7.2 Winter duration
docs/planning/clanworld_v4_spec.md:829:Winter lasts `10` ticks.
docs/planning/clanworld_v4_spec.md:831:## 7.3 Winter upkeep
docs/planning/clanworld_v4_spec.md:832:During winter, each clan consumes:
docs/planning/clanworld_v4_spec.md:835:- wood burn = `1e18` wood per base per tick
docs/planning/clanworld_v4_spec.md:837:## 7.4 Winter farming rule
docs/planning/clanworld_v4_spec.md:838:During winter:
docs/planning/clanworld_v4_spec.md:841:- regrowth does not complete during winter
docs/planning/clanworld_v4_spec.md:843:At winter start:
docs/planning/clanworld_v4_spec.md:845:- both plots restart regrowing after winter ends
docs/planning/clanworld_v4_spec.md:846:- both plots become harvestable again `4` ticks after winter ends
docs/planning/clanworld_v4_spec.md:848:## 7.5 Winter gathering outside farming
docs/planning/clanworld_v4_spec.md:849:During winter:
docs/planning/clanworld_v4_spec.md:854:## 7.6 Winter failure: cold damage
docs/planning/clanworld_v4_spec.md:855:If a base cannot pay the required winter wood burn for a tick:
docs/planning/clanworld_v4_spec.md:866:`coldDamage` resets to `0` at the end of each Winter.
docs/planning/clanworld_v4_spec.md:868:Cold damage does **not** persist across winters.
docs/planning/clanworld_v4_spec.md:870:Wall damage and clansman deaths caused by earlier winter cold still persist, but the temporary cold-damage accumulator does not carry into the next winter cycle.
docs/planning/clanworld_v4_spec.md:947:- walls may lose levels from winter cold damage and bandit pressure
docs/planning/clanworld_v4_spec.md:991:This is approximately three winters under the current winter cadence.
docs/planning/clanworld_v4_spec.md:1189:- starvation weakens but does not kill outside Winter
docs/planning/clanworld_v4_spec.md:1194:- winter every 110 ticks for 10 ticks
docs/planning/clanworld_v4_spec.md:1195:- cold damage reset each winter
docs/reviews/pr356-codereview-codex-5-5.md:39:   - P10 winter: §9 declares wood burn / upkeep multiplier / wheat WinterLocked as DEFERRED. Is that consistent with PR #341 v4.6 bandit redesign which also deferred winter mechanics?
docs/reviews/pr356-codereview-codex-5-5.md:109:**Out of scope:** all non-economy mechanics. Bandit interactions with vault state (loot value getter — see `clanworld_v4_6_bandit_phase9_redesign.md`), winter mechanics (deferred — §9), market mechanics (Phase 6), deaths (Phase 10), gold/blueprint payouts. The rest of the v4 spec remains canonical unless overridden by a later addendum.
docs/reviews/pr356-codereview-codex-5-5.md:281:- No death from starvation outside winter (summer starvation = debuff only, matches A10)
docs/reviews/pr356-codereview-codex-5-5.md:297:| `WinterLocked` | Winter active (see §9) | **Not wired in impl** — enum value declared, behavior deferred |
docs/reviews/pr356-codereview-codex-5-5.md:332:## 9. Winter mechanics — deferred (Phase 5.6 / Phase 7)
docs/reviews/pr356-codereview-codex-5-5.md:334:The following winter mechanics are declared in constants but **not wired in the implementation**. They are explicitly out of scope for Phase 5B and will be implemented under Phase 5.6 (starvation upkeep) and Phase 7 (winter season):
docs/reviews/pr356-codereview-codex-5-5.md:338:| Winter wheat plot lockdown (§7.4) | plots enter `WinterLocked` at winter start; no harvest | NOT IMPLEMENTED — `_gatherWheat` does not check `winterActive`; `WinterLocked` enum value is dead | `WheatPlotState.WinterLocked` in `IClanWorld.sol:125` |
docs/reviews/pr356-codereview-codex-5-5.md:339:| Winter upkeep 2× (§7.3) | wheat + fish consumption doubles during winter | NOT IMPLEMENTED — `_applyUpkeep` uses flat rate regardless of `winterActive` | `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` in `IClanWorld.sol` (unused) |
docs/reviews/pr356-codereview-codex-5-5.md:340:| Winter wood burn (§7.3) | 1e18 wood per base per tick during winter | NOT IMPLEMENTED — `_applyUpkeep` does not touch `vaultWood`; no winter check | `WINTER_WOOD_BURN_PER_BASE = 1e18` in `IClanWorld.sol:71` (unused) |
docs/reviews/pr356-codereview-codex-5-5.md:341:| WinterLocked → Regrowing at winter end (v4_2 §7.4) | on winter end, locked plots → Regrowing | NOT IMPLEMENTED | — |
docs/reviews/pr356-codereview-codex-5-5.md:343:**Behavior during winter (as-built):** Gathering and deposit work exactly as described in §2–§7 above, regardless of whether winter is active. Upkeep rates are flat (non-doubled). Wood burn does not fire.
docs/reviews/pr356-codereview-codex-5-5.md:363:| 11 | **Winter wheat plot lockdown** (§7.4) — plots enter `WinterLocked` at winter start; no harvest | `WinterLocked` enum state declared, not wired | Small–Medium — wire winter-start heartbeat to set plot state; add check in `_gatherWheat`; wire winter-end → Regrowing |
docs/reviews/pr356-codereview-codex-5-5.md:364:| 12 | **Winter upkeep 2× multiplier** (§7.3) — wheat + fish consumption doubles in winter | Flat rate; `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` declared, unused | Small — multiply upkeep by `WINTER_UPKEEP_MULTIPLIER_BPS` when `winterActive` in `_applyUpkeep` |
docs/reviews/pr356-codereview-codex-5-5.md:365:| 13 | **Winter wood burn 1e18/base/tick** (§7.3) | Not implemented; `WINTER_WOOD_BURN_PER_BASE = 1e18` declared, unused | Small — add wood burn branch in `_applyUpkeep` when `winterActive` |
docs/reviews/pr356-codereview-codex-5-5.md:368:Items 11–13 partially overlap with Phase 5.6 (starvation upkeep) and Phase 7 (winter season) scope. Those phases will address them regardless.
docs/reviews/pr356-codereview-codex-5-5.md:411:- ✅ Wheat plots remain harvestable during winter (WinterLocked NOT wired)
docs/reviews/pr356-codereview-codex-5-5.md:412:- ✅ Winter upkeep doubling NOT active; flat upkeep rates apply year-round
docs/reviews/pr356-codereview-codex-5-5.md:413:- ✅ Winter wood burn NOT active
docs/reviews/pr356-codereview-codex-5-5.md:415:If a UAT scenario expects v4-spec continuous yields, per-tick rates, or winter lockdown behavior, it will fail against this contract. Use this addendum as the oracle.
docs/reviews/pr356-codereview-codex-5-5.md:449:| `docs/planning/clanworld_v4_spec.md` | §3 (mission model, action categories, per-tick local settlement order); §3.7–3.8 (terminal states, deposit-with-empty-cargo); §4.2–4.13 (resources, carry caps, vault model, deposit rule, gathering yields, gather overflow, wheat plots, consumption, starvation trigger, starvation effects, lazy starvation tracking); §6.9 (loot-value formula — same getter Phase 5 must serve to bandits); §7.3–7.5 (winter upkeep doubling, winter wood burn, winter wheat lockdown); §12.4–12.5 (starting vault + gold) |
docs/reviews/pr356-codereview-codex-5-5.md:450:| `docs/planning/clanworld_v4_1_addendum.md` | A5 (cooldown on every accepted submission, including gather+deposit); A6 (winter just-in-time logistics — vault upkeep applies BEFORE deposit in same tick); A10 (summer starvation effects: 50% gather + 0 defense, no death); A11 (clansman-granular drop split — touches gathering only insofar as defenders gain loot, not Phase-5-direct) |
docs/reviews/pr356-codereview-codex-5-5.md:471:- **§4.12** while starving: gather output ÷2, defense → 0; outside winter no death
docs/reviews/pr356-codereview-codex-5-5.md:473:- **§7.3** winter doubles wheat + fish consumption AND adds 1e18 wood-burn per base per tick
docs/reviews/pr356-codereview-codex-5-5.md:474:- **§7.4** during winter: wheat plots locked, no harvest
docs/reviews/pr356-codereview-codex-5-5.md:475:- **A6** winter upkeep applies BEFORE same-tick deposit lands → carry doesn't save you that tick
docs/reviews/pr356-codereview-codex-5-5.md:509:| **Winter wheat plot lockdown (§7.4)** | "during winter: wheat plots are unavailable; harvesting wheat is not allowed" | NOT IMPLEMENTED. `_gatherWheat` does not check `_world.winterActive`. `_settleClan` per-tick wheat-plot regrow loop has no `WinterLocked` transition. | `ClanWorld.sol:376-383, 612-665` | ❌ MISSING — wheat plots remain harvestable during winter |
docs/reviews/pr356-codereview-codex-5-5.md:510:| **WheatPlotState enum has WinterLocked** | yes (v4_2 §7.4) | enum has 3 states: `Harvestable, Regrowing, WinterLocked` | `IClanWorld.sol:123-127` | ⚠️ PARTIAL — schema present, behavior absent (dead enum value) |
docs/reviews/pr356-codereview-codex-5-5.md:519:| **No summer starvation death (§4.12, A10)** | death only via winter cold-damage path | `_applyUpkeep` does not kill clansmen; upkeep failure only flips starvation flag | `ClanWorld.sol:397-425` | ✅ MATCHES |
docs/reviews/pr356-codereview-codex-5-5.md:521:| **Winter wheat consumption multiplier (§7.3)** | 2× during winter | NOT IMPLEMENTED. `_applyUpkeep` uses flat `WHEAT_UPKEEP_PER_CLANSMAN` regardless of `_world.winterActive` | `ClanWorld.sol:400-401` | ❌ MISSING — Phase 5.6 surface but constant `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` exists unused |
docs/reviews/pr356-codereview-codex-5-5.md:522:| **Winter fish consumption multiplier (§7.3)** | 2× during winter | NOT IMPLEMENTED — same as wheat | `ClanWorld.sol:400-401` | ❌ MISSING |
docs/reviews/pr356-codereview-codex-5-5.md:523:| **Winter wood burn (§7.3)** | 1e18 wood per base per tick during winter | NOT IMPLEMENTED. `_applyUpkeep` does not touch `vaultWood` and does not check `winterActive`. Constant `WINTER_WOOD_BURN_PER_BASE = 1e18` declared but unused. | `IClanWorld.sol:71`, `ClanWorld.sol:397-425` | ❌ MISSING — dead constant |
docs/reviews/pr356-codereview-codex-5-5.md:524:| **Winter wheat plot lockdown (§7.4)** | plots become unavailable during winter | NOT IMPLEMENTED (already flagged above) | (no code) | ❌ MISSING |
docs/reviews/pr356-codereview-codex-5-5.md:525:| **Winter cold damage / wall collapse (§7.5, alluded by v4_1 A10)** | not Phase-5 directly but coupled | NOT IMPLEMENTED — `Clan.coldDamage` field is reset to 0 but never incremented anywhere in this branch | `ClanWorld.sol:1033`, `IClanWorld.sol:249` | ❌ MISSING (Phase-5.6 / Phase-7-winter scope; flagged for context) |
docs/reviews/pr356-codereview-codex-5-5.md:526:| **Wheat-plot WinterLocked transition at winter start (v4_2 §7.4)** | "at winter start: plots enter `WinterLocked`" | NOT IMPLEMENTED — heartbeat does not set plot state to `WinterLocked`; the enum value is dead. | `ClanWorld.sol:376-383, 1043-1054` | ❌ MISSING |
docs/reviews/pr356-codereview-codex-5-5.md:527:| **Wheat-plot WinterLocked → Regrowing at winter end (v4_2 §7.4)** | "at winter end: `WinterLocked → Regrowing`" | NOT IMPLEMENTED | (no code) | ❌ MISSING |
docs/reviews/pr356-codereview-codex-5-5.md:528:| **Just-in-time logistics (A6 — winter case)** | "carried resources do not save a base from upkeep until they are actually deposited" | settlement order is 1. upkeep, 2. plot regrow, 3-6. clansmen. Deposit resolves in step 3-6 (well after upkeep), so a same-tick deposit doesn't rescue upkeep — matches A6 even though winter wood burn isn't applied yet. | `ClanWorld.sol:371-389` | ✅ MATCHES (architecturally; void of winter wood burn impl) |
docs/reviews/pr356-codereview-codex-5-5.md:554:**The implementation has correctly wired the deposit pipeline, the gather → carry → vault flow, the wheat-plot regrow cycle, the starvation accounting skeleton, and all RNG domain keys. The drift cluster is concentrated in two places: (1) yield rates per-tick are 1/2 to 1/4 of spec because gather actions are batched-not-continuous, with each batch paying spec's per-tick value × 4-tick action duration as a one-shot, then ending the mission; (2) every winter mechanic (wood burn, upkeep doubling, plot lockdown, cold damage) is unwired — Phase 5.6 starvation upkeep work has explicitly NOT been implemented yet and Phase 7 winter is downstream.**
docs/reviews/pr356-codereview-codex-5-5.md:592:| **Starvation onset at next-tick boundary (§4.11)** | Direct spec contradiction. Test should assert: tick T → upkeep fails → at end of tick T `_isStarving == false`; at start of tick T+1 `_isStarving == true`. Current impl flips immediately at tick T. | Phase 5.6 (starvation upkeep) — but constant declared in 5.0; impl already wires the wrong semantics |
docs/reviews/pr356-codereview-codex-5-5.md:599:| **Winter wheat plot lockdown (§7.4)** | Plot must enter `WinterLocked` at winter start. Zero tests. | Phase 5.4 / Phase 7 winter |
docs/reviews/pr356-codereview-codex-5-5.md:600:| **Winter upkeep 2× multiplier (§7.3)** | Vault drains twice as fast. Zero tests; constant `WINTER_UPKEEP_MULTIPLIER_BPS = 20000` declared and unused. | Phase 5.6 / Phase 7 |
docs/reviews/pr356-codereview-codex-5-5.md:601:| **Winter wood burn (§7.3, 1e18/base/tick)** | Critical economy mechanic. Zero tests; constant declared and unused. | Phase 5.6 / Phase 7 |
docs/reviews/pr356-codereview-codex-5-5.md:608:| **Gather during winter still pays out (no spec lockdown for non-wheat)** | Spec only locks wheat plots in winter; wood/iron/fish should still work. No test. |
docs/reviews/pr356-codereview-codex-5-5.md:625:**Headline gap count:** 11 MUST-COVER, 8 SHOULD-COVER, 5 NICE-TO-HAVE. About half of MUST-COVER are spec-drift findings (current impl is internally consistent but doesn't match spec). The other half are in-flight Phase 5.6 / Phase 7 winter scope that is intentionally out of PR #193.
docs/reviews/pr356-codereview-codex-5-5.md:661:### Scenario 6 — Wheat plot continues during winter
docs/reviews/pr356-codereview-codex-5-5.md:662:**Setup:** Wait until tick 100 (= winter start per `mintClan` constructor `winterStartsAtTick = 100`). Submit `HarvestWheat` to West Farms during winter.
docs/reviews/pr356-codereview-codex-5-5.md:663:**Expected per spec:** mission rejected OR completes with 0 yield; plot state = `WinterLocked`.
docs/reviews/pr356-codereview-codex-5-5.md:664:**Actual per impl:** mission accepts, plot still Harvestable, yields normal 20e18 wheat. Winter wood burn doesn't fire (also missing).
docs/reviews/pr356-codereview-codex-5-5.md:665:**He should verify:** call `getWheatPlots(clanId)` during winter — both plots will report `state = Harvestable` (impl) instead of `WinterLocked` (spec).
docs/reviews/pr356-codereview-codex-5-5.md:667:### Scenario 7 — Winter upkeep 2× multiplier missing
docs/reviews/pr356-codereview-codex-5-5.md:668:**Setup:** Run heartbeat to tick 100 (winter start). Have a 4-clansman clan with vault wheat = 8e18 (just enough for 2 ticks of summer upkeep at 4 × 1e18 = 4e18 / tick).

exec
/bin/bash -lc "git show HEAD:docs/planning/clanworld_numbered_implementation_plan.md | nl -ba | sed -n '1,150p'" in /tmp/wt-superswarm-356
 succeeded in 0ms:
     1	# Clanworld — Numbered Implementation Plan with Phases and Cut Lines
     2	
     3	This document is the execution-oriented build plan for Clanworld v1.
     4	
     5	It is designed for a time-constrained implementation environment.
     6	The main goal is to ensure there is always:
     7	- a working core
     8	- a clear next step
     9	- a clear cut line when behind
    10	
    11	---
    12	
    13	## Phase 0 — repo, skeleton, and execution environment
    14	
    15	### 0.1 Set up contract repo structure
    16	Create:
    17	- `contracts/`
    18	- `test/`
    19	- `script/`
    20	- `docs/`
    21	
    22	Suggested contracts:
    23	- `ClanworldCore.sol`
    24	- `ClanworldMarket.sol`
    25	- `ClanworldTokenBoundary.sol` or helper module
    26	- `ClanworldLib.sol`
    27	- `IClanworld.sol`
    28	
    29	### 0.2 Lock toolchain
    30	Choose and lock:
    31	- Solidity version
    32	- framework (Foundry strongly preferred if already comfortable)
    33	- OpenZeppelin version
    34	- Uniswap integration version
    35	
    36	### 0.3 Add CI basics
    37	At minimum:
    38	- compile
    39	- tests
    40	- formatting
    41	- lint if practical
    42	
    43	### 0.4 Set up local heartbeat runner
    44	A tiny dev script should be able to:
    45	- call heartbeat every 60s equivalent in local test mode
    46	- optionally accelerate tick speed for demo/testing
    47	
    48	**Cut line:** none. This phase is mandatory.
    49	
    50	---
    51	
    52	## Phase 1 — core data model and read surface
    53	
    54	### 1.1 Implement enums, constants, structs
    55	Add:
    56	- region ids
    57	- action types
    58	- states
    59	- status codes
    60	- world/clan/clansman/mission/bandit/wheat plot structs
    61	
    62	### 1.2 Implement core storage layout
    63	Add canonical mappings:
    64	- clans
    65	- clansmen
    66	- active mission by clansman
    67	- defender registry
    68	- scheduled actions by tick
    69	- season/world state
    70	
    71	### 1.3 Implement raw getters
    72	Add:
    73	- `getWorldStateRaw`
    74	- `getClanRaw`
    75	- `getClansmanRaw`
    76	- `getBanditTroopRaw`
    77	- `getScheduledMarketActionsForTick`
    78	
    79	### 1.4 Implement derived getters
    80	Add:
    81	- `getClanDerivedState`
    82	- `getClansmanDerivedState`
    83	- `quoteTravel`
    84	- `quoteLootValueRaw`
    85	- `quoteLootValueSettled`
    86	- `getBanditTargetPreview`
    87	
    88	**Definition of done**
    89	- contracts compile
    90	- getters return sane data
    91	- no game logic yet, but storage shape is stable
    92	
    93	**Cut line:** none. This phase is mandatory.
    94	
    95	---
    96	
    97	## Phase 2 — clan mint / spawn lifecycle
    98	
    99	### 2.1 Implement clan minting
   100	Lock:
   101	- payment handling
   102	- clan id assignment
   103	- owner assignment
   104	- spawn region RNG
   105	- initial state creation
   106	
   107	### 2.2 Spawn workers
   108	Create initial workers per clan:
   109	- starting region = homebase region
   110	- waiting state
   111	- zero carry
   112	- no active mission
   113	- cooldown clear
   114	
   115	### 2.3 Initialize starting balances
   116	Apply:
   117	- starting vault resources
   118	- starting gold
   119	- base/wall/monument starting levels
   120	- wheat plot starting state
   121	
   122	### 2.4 Add access control rules
   123	Implement:
   124	- clan owner / operator checks for order submission
   125	- admin for pool seeding
   126	- finalize permissions
   127	- dead clan restrictions on OTC
   128	
   129	**Definition of done**
   130	- minting a clan gives a fully initialized playable clan
   131	- getters show coherent initial state
   132	
   133	**Cut line:** if behind, prize pot routing can be stubbed or deferred.
   134	
   135	---
   136	
   137	## Phase 3 — mission assignment and lazy settlement core
   138	
   139	### 3.1 Implement order submission
   140	Implement:
   141	- per-clansman validation
   142	- partial success return pattern
   143	- cooldown checks
   144	- mission overwrite semantics
   145	- same-region / noop bypass
   146	
   147	### 3.2 Implement lazy settlement engine
   148	Implement settlement for:
   149	- travel
   150	- wait

exec
/bin/bash -lc 'git show HEAD:docs/planning/clanworld_numbered_implementation_plan.md | rg -n "Phase 5|Phase 7|Phase 10|Winter|winter|cold|upkeep"' in /tmp/wt-superswarm-356
 succeeded in 0ms:
153:- local upkeep
207:### 4.4 Add winter / season timers to world state
210:- winter timing
218:**Cut line:** if needed, winter logic can still be stubbed here.
222:## Phase 5 — gathering, deposits, and resource economy
241:- winter interaction hook
311:## Phase 7 — OTC transfer surface
413:## Phase 10 — winter and elimination
415:### 10.1 Implement winter schedule
416:- first winter at tick 110
420:### 10.2 Implement winter upkeep
421:- doubled food upkeep
424:### 10.3 Implement cold damage
428:- reset at winter end
430:### 10.4 Implement crop winter transitions
432:- lock during winter
433:- restart regrow after winter
441:- winter can kill clans and end runs
451:- approximately 3 winters
507:6. optional winter hardship
537:- winter
564:12. winter  

codex
# Phase Super-Swarm Review — PR #356 (head 732120b) — Phase 5B v4.6 economy alignment addendum

## SUMMARY
NEEDS_FIXES. The addendum is broadly faithful to the PR #193 audit and Path A is defensible against `origin/dev-phase-5-economy`, but one canonical lifecycle statement misdescribes actual gather validation behavior. I would merge after fixing that spec inaccuracy plus the broken/misaligned doc references below.

## HIGH severity findings

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:60` says gather submission validation includes “carry not already full.” That is not what the contract does. `_validateAction` only validates gather target regions at `ClanWorld.sol:1622-1649`; no carry-full check happens there. Full carry is handled inside gather resolution, e.g. wood completes at `ClanWorld.sol:487-490`, iron at `519-523`, fish at `559-563` / `590-594`, wheat at `621-625`. Because `_processOrder` starts cooldown on accepted submission at `ClanWorld.sol:1230-1231` and `_completeMission` refreshes cooldown again at `856-859`, the actual behavior is: full-carry gather orders can be accepted, then later settle as no-yield completions and refresh cooldown. The canonical lifecycle should say “target-region validation; carry-full checked at resolution,” not “validation: carry not already full.”

## MEDIUM severity findings

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:260-262,296` routes deferred winter work to “Phase 5.6 / Phase 7.” The repo’s implementation plan identifies winter and elimination as Phase 10 (`docs/planning/clanworld_numbered_implementation_plan.md:413-433`), and the contract itself labels winter transitions as “timer only; mechanics = Phase 10” at `ClanWorld.sol:952`. Phase 7 is OTC transfer surface in the current plan. This should be reworded to “Phase 10 winter/elimination” unless there is a newer phase plan being merged with this PR.

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:349-350` links to two docs that are not present in this PR’s `HEAD`: `docs/reviews/pr193-spec-compliance-uat.md` and `docs/planning/clanworld_v4_6_bandit_phase9_redesign.md`. I verified the audit exists on `origin/docs/spec-audit-phase-5` and the bandit addendum exists on `origin/docs/spec-v4-6-bandit-redesign`, but neither is in this branch. Either include those docs, retarget after they merge, or change the references to non-local tracking references.

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:307` says `WOOD_CRIT_BONUS` has “no separate constant.” Actual `IClanWorld.sol:52-54` declares `WOOD_CRIT_BONUS = WOOD_YIELD_PER_TICK`, even though `_gatherWood` implements the crit as `yield *= 2` at `ClanWorld.sol:495-497`. The canonical statement should distinguish “constant exists but is not the implementation mechanism” from “no separate constant.”

## LOW severity findings

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:266` cites `WheatPlotState.WinterLocked` at `IClanWorld.sol:125`, but line 125 is `Regrowing`; `WinterLocked` is line 126.

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:322` cites `WINTER_UPKEEP_MULTIPLIER_BPS` as `IClanWorld.sol` without a line; it is `IClanWorld.sol:72`.

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:174` says “generic `WOOD_CAP = CLANSMAN_CARRY_CAP` constant.” That should be “generic `CLANSMAN_CARRY_CAP` constant.”

## Cross-cutting observations

Path A is defensible. The code at `9b67414f87ab6c83cf848fbe8a8bd7e3dcc03218` really is batched: gather actions return duration `4` at `ClanWorld.sol:1796-1801`, resolve once at `339-344`, and use `YIELD_PER_TICK * getActionDuration(...)` in the gather helpers. The yield/cap/starvation/winter drift tables mostly match the audit and actual code.

Downstream surfaces look stable: `quoteLootValueRaw/Settled` still consume vault fields via `wood + wheat + 2*fish + 4*iron` at `ClanWorld.sol:1943-1954`, and this addendum does not change vault field shape. For P6 market calibration, the per-batch language is clear enough for contract behavior, but a follow-up sentence would help: calibrate economy throughput from “per accepted batch plus travel/cooldown,” not from continuous per-tick rates.
2026-04-30T11:29:00.937184Z ERROR codex_core::session: failed to record rollout items: thread 019dde23-61ff-7482-93e9-ff9d1efc4e1f not found
tokens used
117,597
# Phase Super-Swarm Review — PR #356 (head 732120b) — Phase 5B v4.6 economy alignment addendum

## SUMMARY
NEEDS_FIXES. The addendum is broadly faithful to the PR #193 audit and Path A is defensible against `origin/dev-phase-5-economy`, but one canonical lifecycle statement misdescribes actual gather validation behavior. I would merge after fixing that spec inaccuracy plus the broken/misaligned doc references below.

## HIGH severity findings

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:60` says gather submission validation includes “carry not already full.” That is not what the contract does. `_validateAction` only validates gather target regions at `ClanWorld.sol:1622-1649`; no carry-full check happens there. Full carry is handled inside gather resolution, e.g. wood completes at `ClanWorld.sol:487-490`, iron at `519-523`, fish at `559-563` / `590-594`, wheat at `621-625`. Because `_processOrder` starts cooldown on accepted submission at `ClanWorld.sol:1230-1231` and `_completeMission` refreshes cooldown again at `856-859`, the actual behavior is: full-carry gather orders can be accepted, then later settle as no-yield completions and refresh cooldown. The canonical lifecycle should say “target-region validation; carry-full checked at resolution,” not “validation: carry not already full.”

## MEDIUM severity findings

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:260-262,296` routes deferred winter work to “Phase 5.6 / Phase 7.” The repo’s implementation plan identifies winter and elimination as Phase 10 (`docs/planning/clanworld_numbered_implementation_plan.md:413-433`), and the contract itself labels winter transitions as “timer only; mechanics = Phase 10” at `ClanWorld.sol:952`. Phase 7 is OTC transfer surface in the current plan. This should be reworded to “Phase 10 winter/elimination” unless there is a newer phase plan being merged with this PR.

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:349-350` links to two docs that are not present in this PR’s `HEAD`: `docs/reviews/pr193-spec-compliance-uat.md` and `docs/planning/clanworld_v4_6_bandit_phase9_redesign.md`. I verified the audit exists on `origin/docs/spec-audit-phase-5` and the bandit addendum exists on `origin/docs/spec-v4-6-bandit-redesign`, but neither is in this branch. Either include those docs, retarget after they merge, or change the references to non-local tracking references.

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:307` says `WOOD_CRIT_BONUS` has “no separate constant.” Actual `IClanWorld.sol:52-54` declares `WOOD_CRIT_BONUS = WOOD_YIELD_PER_TICK`, even though `_gatherWood` implements the crit as `yield *= 2` at `ClanWorld.sol:495-497`. The canonical statement should distinguish “constant exists but is not the implementation mechanism” from “no separate constant.”

## LOW severity findings

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:266` cites `WheatPlotState.WinterLocked` at `IClanWorld.sol:125`, but line 125 is `Regrowing`; `WinterLocked` is line 126.

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:322` cites `WINTER_UPKEEP_MULTIPLIER_BPS` as `IClanWorld.sol` without a line; it is `IClanWorld.sol:72`.

- `docs/planning/clanworld_v4_6_phase5_economy_alignment.md:174` says “generic `WOOD_CAP = CLANSMAN_CARRY_CAP` constant.” That should be “generic `CLANSMAN_CARRY_CAP` constant.”

## Cross-cutting observations

Path A is defensible. The code at `9b67414f87ab6c83cf848fbe8a8bd7e3dcc03218` really is batched: gather actions return duration `4` at `ClanWorld.sol:1796-1801`, resolve once at `339-344`, and use `YIELD_PER_TICK * getActionDuration(...)` in the gather helpers. The yield/cap/starvation/winter drift tables mostly match the audit and actual code.

Downstream surfaces look stable: `quoteLootValueRaw/Settled` still consume vault fields via `wood + wheat + 2*fish + 4*iron` at `ClanWorld.sol:1943-1954`, and this addendum does not change vault field shape. For P6 market calibration, the per-batch language is clear enough for contract behavior, but a follow-up sentence would help: calibrate economy throughput from “per accepted batch plus travel/cooldown,” not from continuous per-tick rates.
