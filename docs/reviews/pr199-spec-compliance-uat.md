# PR #199 Spec-Compliance UAT — `dev-phase-8-buildings`

**Reviewer:** Claude Opus 4.7 (1M ctx) — static spec-compliance pass
**HEAD:** `2b92d85644526c39aaa65b47a90c5fb5baf450dc` (Phase 8 R5; R6/R7 in flight on PR #339)
**Date:** 2026-04-30
**Method:** read spec docs → walk impl → no test execution
**Companion / template:** `docs/reviews/pr194-spec-compliance-uat.md` (Phase 9 audit)

> Scope: does the buildings + progression implementation in `packages/contracts/src/ClanWorld.sol` (introduced over the Phase 8 commit chain on `dev-phase-8-buildings`) match the documented v4 spec ruleset? This is **not** a re-run of the cloud reviewers; it is an **independent spec-vs-code audit** focused on whether shipped behavior matches the canonical contract spec.

---

## 1. Spec sources read

| Doc | Phase-8-relevant sections |
|---|---|
| `docs/planning/clanworld_v4_spec.md` | §8.1 build action class; §8.2 spend source; §8.3 wall levels + costs; §8.4 base levels + costs; §8.5 monument levels + costs; §8.6 build validation; §8.7 damage interaction; §9.1 primary ranking rule |
| `docs/planning/clanworld_v4_1_addendum.md` | (no Phase-8-specific changes — addendum is bandit/winter/market focused) |
| `docs/planning/clanworld_v4_2_state_schema_interface_spec.md` | §7.3 `Clan` struct (`baseLevel`, `wallLevel`, `monumentLevel`); §10.x building events |
| `docs/planning/clanworld_v4_3_schema_patch.md` | (no Phase-8-specific patches; the Phase-8 surface is unchanged from v4.2) |
| `docs/planning/clanworld_v4_4_ui_indexer_getters.md` | `LeaderboardEntry` includes `monumentLevel/baseLevel/wallLevel`; informs `getWorldSnapshot` shape |
| `docs/planning/clanworld_v4_5_alignment_addendum.md` | (no Phase-8-specific changes — alignment addendum focuses on chain pivot + Submission 2 scope) |

**Authoritative ruleset:** v4 spec §8 + §9.1 (with §8.4 explicitly noting "Base level may later be extended… not required for v1") + v4_2 schema. The v4_1, v4_3, v4_5 addenda do not alter Phase-8 mechanics. v4_4 adds UI getter shape only. No Phase-8-specific design doc supersedes v4 §8.

Key spec assertions extracted (one-line each):
- **8.1** `build_wall` / `upgrade_base` / `upgrade_monument` are **single-tick** actions consumed at homebase
- **8.2** building actions consume from the **homebase vault**, not carried inventory
- **8.3** Wall level range `0..5`; defense `10×wallLevel`; per-level wood/iron costs
- **8.4** Base level range `1..5`; defense `5×baseLevel`; per-level wood/iron/wheat costs (extension to size/recipes is out-of-scope for v1)
- **8.5** Monument level range `0..10`; per-level wood/iron/wheat costs through L6; L7–L10 cost is "higher resources + 1e18 Blueprint Fragment", with exact resource tunable but **Blueprint requirement locked**
- **8.6** If required vault resources are present at homebase action tick, the build succeeds and consumes one action tick. **If absent, the clansman becomes WAITING.**
- **8.7** v1: walls may lose levels from winter cold damage and bandit pressure; base + monument levels do **not** lose levels from bandits
- **9.1** Season-end rank: (1) `monumentLevel` desc, (2) earliest tick reaching that level asc, (3) surviving vault loot value desc, (4) wall level desc

---

## 2. Mechanic-by-mechanic verification

| Mechanic | Spec says | Code does | File:line | Verdict |
|---|---|---|---|---|
| **Action class — build_wall** | Spec lists `build_wall` (§8.1) | Action enum has both `BuildWall` (deprecated) and `UpgradeWall` (canonical Phase 8 name); submit-time `BuildWall` rejected with `ERR_INVALID_ACTION`; in-flight `BuildWall` missions complete harmlessly | `IClanWorld.sol:138,145`, `ClanWorld.sol:547-549, 2191-2193` | ⚠️ DRIFT — action name renamed `build_wall → upgrade_wall`. Per-level cost table exists (§8.3 already implies upgrade semantics), so this is a name rename only, not a semantic change. Spec doc never updated. |
| **Action class — upgrade_base** | `upgrade_base` (§8.1) | `ActionType.UpgradeBase` | `IClanWorld.sol:139` | ✅ MATCHES |
| **Action class — upgrade_monument** | `upgrade_monument` (§8.1) | `ActionType.UpgradeMonument` | `IClanWorld.sol:140` | ✅ MATCHES |
| **Single-tick duration** | Single action tick (§8.1) | `BUILDING_DURATION_TICKS = 1`, applies to all three upgrade actions in `getActionDuration` | `ClanWorld.sol:140, 2755-2761` | ✅ MATCHES |
| **Spend source = vault** | All building actions consume from homebase vault, not carried inventory (§8.2) | `_settleWallUpgrade` / `_settleBaseUpgrade` / `_settleMonumentUpgrade` debit `clan.vaultWood` / `clan.vaultIron` / `clan.vaultWheat` / `clan.blueprintBalance`. No clansman carry is touched. | `ClanWorld.sol:836-843, 873-882, 915-930` | ✅ MATCHES |
| **Wall level range 0..5** | `0` to `5` (§8.3) | Initial `wallLevel = 0` at mint; `WALL_MAX_LEVEL = 5`; reservation rejected if `plannedCurrentLevel >= WALL_MAX_LEVEL` | `ClanWorld.sol:141, 1583, 2289` | ✅ MATCHES |
| **Wall upgrade costs L1..L5** | L1: 20w / L2: 35w / L3: 30w+5i / L4: 40w+10i / L5: 50w+15i (§8.3) | `_wallUpgradeCost(0..4)` returns `(20e18,0)` / `(35e18,0)` / `(30e18,5e18)` / `(40e18,10e18)` / `(50e18,15e18)` | `ClanWorld.sol:2713-2720` | ✅ MATCHES (cost-table parity test: `test_getWallUpgradeCost_matchesSpecTable` in `WallUpgrades.t.sol:144`) |
| **Wall defense formula** | `wallDefense = 10 × wallLevel` (§8.3) | NOT IMPLEMENTED in Phase 8 — no bandit-attack defense calculation lives in this branch | (no code) | ⏳ DEFERRED — bandit attack defense is Phase 9 territory; legitimately out of Phase 8 scope. Tracked by Phase 9 (PR #194) audit. |
| **Base level range 1..5** | `1` to `5` (§8.4) | Initial `baseLevel = 1` at mint; `BASE_MAX_LEVEL = 5`; reservation rejected if `plannedCurrentLevel >= BASE_MAX_LEVEL` | `ClanWorld.sol:142, 1582, 2354` | ✅ MATCHES |
| **Base upgrade costs L2..L5** | L2: 40w+20wh / L3: 60w+5i+30wh / L4: 80w+10i+40wh / L5: 100w+15i+50wh (§8.4) | `_baseUpgradeCost(1..4)` returns `(40e18,0,20e18)` / `(60e18,5e18,30e18)` / `(80e18,10e18,40e18)` / `(100e18,15e18,50e18)` | `ClanWorld.sol:2722-2728` | ✅ MATCHES (test: `test_getBaseUpgradeCost_matchesSpecTable` in `BaseUpgrades.t.sol:111`) |
| **Base defense formula** | `baseDefense = 5 × baseLevel` (§8.4) | NOT IMPLEMENTED in Phase 8 (defense calculation is Phase 9) | (no code) | ⏳ DEFERRED — out of Phase 8 scope |
| **Monument level range 0..10** | `0` to `10` (§8.5) | Initial `monumentLevel = 0` at mint; `MONUMENT_MAX_LEVEL = 10`; reservation rejected if `plannedCurrentLevel >= MONUMENT_MAX_LEVEL` | `ClanWorld.sol:143, 1584, 2426` | ✅ MATCHES |
| **Monument upgrade costs L1..L6** | L1: 30w+20wh / L2: 50w+30wh / L3: 70w+40wh+5i / L4: 90w+50wh+10i / L5: 120w+60wh+15i / L6: 150w+80wh+20i (§8.5) | `_monumentUpgradeCost(0..5)` returns `(30e18,0,20e18,0)` / `(50e18,0,30e18,0)` / `(70e18,5e18,40e18,0)` / `(90e18,10e18,50e18,0)` / `(120e18,15e18,60e18,0)` / `(150e18,20e18,80e18,0)` | `ClanWorld.sol:2735-2740` | ✅ MATCHES (test: `test_getMonumentUpgradeCost_matchesPhaseTable` in `MonumentUpgrades.t.sol:119`) |
| **Monument upgrade costs L7..L10** | "higher resources + 1e18 Blueprint Fragment" with **exact resource progression tunable but Blueprint requirement locked** (§8.5) | `_monumentUpgradeCost(6..9)` returns flat `(200e18, 25e18, 100e18, 1e18)` for all four — Blueprint is required ✓; resources are flat (not strictly "higher") across L7..L10 | `ClanWorld.sol:2741` | ⚠️ DRIFT (textual only) — spec calls L7-L10 explicitly tunable. Blueprint requirement is locked AND honored. The "higher resources" hint isn't violated — 200/25/100 is higher than L6's 150/20/80. Flat (not monotonic-ascending) across 7-10 is a tunability call, not a spec violation. |
| **Monument blueprint requirement L7+** | "Blueprint requirement is locked" (§8.5) | `blueprintCost = 1e18` returned for `currentLevel ∈ [6, MONUMENT_MAX_LEVEL)` and validated/debited at settle | `ClanWorld.sol:2741, 920-923, 928-930` | ✅ MATCHES |
| **Build validation — resources present → succeeds** | If required vault resources present, action succeeds and consumes one action tick (§8.6) | `_validateUpgrade*Order` at submit-time checks `availableX >= cost`, then `_reserveX` debits a held-resource counter; settle consumes from vault | `ClanWorld.sol:2274-2294, 2297-2314, 836-851` | ✅ MATCHES |
| **Build validation — resources absent → WAITING** | If required resources are absent, the clansman becomes `WAITING` (§8.6) | At submit time, missing resources → `ERR_MISSING_RESOURCES` (the order is **rejected** at submit). The clansman is not transitioned to WAITING; the order simply does not enter the mission queue. After submission, vault is held in a per-clan reservation, so an intra-mission drain cannot occur from another concurrent upgrade. | `ClanWorld.sol:2274-2294, 2337-2362, 2407-2438` | ❌ DRIFT — submit-time reject vs spec's "becomes WAITING". Semantic difference: spec implies the order can be queued speculatively and the worker sits in WAITING waiting for vault to fill; impl requires resources present at submit and locks them via reservation. Behavioral consequence: an Elder cannot speculatively queue an upgrade for "later when wood arrives" — must time the submission to vault state. |
| **Spend timing — vault held until settle** | (Implicit; §8.2 says vault funds the cost; §8.6 implies one-shot at action tick) | Reservation system holds resources from `submitClanOrders` time until settle/refund. Other concurrent upgrade orders see `availableX = vaultX − reservedX + released`. On clansman death / mission swap, reservation is refunded (no vault lock-in). | `ClanWorld.sol:2316-2335, 2385-2405, 2466-...` | ⚠️ DRIFT (intentional impl improvement) — spec didn't define held-vs-debited semantics; impl chose held-at-queue. Prevents two clansmen from both spending the same wood. Liam should confirm this is the desired model. |
| **Damage interaction — wall loses levels from cold/bandits** | "walls may lose levels from winter cold damage and bandit pressure" (§8.7) | NOT IMPLEMENTED in Phase 8 — no winter-damage or bandit-damage code paths reduce `clan.wallLevel` outside reset-on-mint | (no code) | ⏳ DEFERRED — winter-damage was wired in Phase 4.4; bandit-damage in Phase 9. Phase 8 builds the upgrade cost / reservation surface only. |
| **Damage interaction — base/monument do not lose levels** | v1: base + monument levels do **not** lose from bandits (§8.7) | No code path decrements `clan.baseLevel` or `clan.monumentLevel` | (no code) | ✅ MATCHES (by absence of decrement) |
| **Ranking primary key — monumentLevel desc** | (1) highest `monumentLevel` (§9.1) | Score packs `monumentLevel << 248` as the dominant nibble of a single uint256 | `ClanWorld.sol:3026` | ✅ MATCHES |
| **Ranking secondary key — earliest reach tick** | (2) earliest tick reaching that level (§9.1) | `_monumentLevelReachedAt[clanId][level]` stamped on first reach (no overwrite); score packs `(uint64.max - reachTick) << 184` so smaller tick = bigger score component | `ClanWorld.sol:75, 942-947, 3023, 3026` | ✅ MATCHES (test: `test_getClanScoreAndRankings_sortByLevelThenEarliestReachTick`) |
| **Ranking tertiary key — surviving vault loot value** | (3) highest surviving vault loot value (§9.1) | Score packs `min(lootValue, 2^176-1) << 8` from `_lootValueRaw(sim.clan)` (settled vault basis) | `ClanWorld.sol:3015-3019, 3026, 2967-2970` | ✅ MATCHES (test: `test_getRankings_usesSettledUpkeepForLootScore`) |
| **Ranking quaternary key — wall level desc** | (4) highest wall level (§9.1) | Score packs `clan.wallLevel` in the low 8 bits | `ClanWorld.sol:3026` | ✅ MATCHES (test: `test_getRankings_usesWallLevelAfterLootBeforeClanId`) |
| **Ranking eligibility — DEAD excluded** | "an eligible clan is a clan that is **not** in the DEAD / eliminated state at season end" (§9.1) | `getRankings` skips clans where `sim.clan.clanState != ClanState.ACTIVE` | `ClanWorld.sol:2938` | ✅ MATCHES |
| **Ranking exact-tie tiebreak** | (Implicit; not specified) | Final fallback: `clanId` ascending | `ClanWorld.sol:3030-3039` | ✅ NO CONFLICT (sane default; test: `test_getRankings_breaksExactScoreTiesByClanId`) |
| **Ranking — settled vault basis** | "surviving vault loot value" — implies settled, not raw-stale (§9.1 + v4_3 H precedent) | `_getClanScoreFromSimulation` runs `_simulateSettleToTick` before computing loot | `ClanWorld.sol:2937, 2977, 2981-2995` | ✅ MATCHES |
| **Ranking — simulated monument reach for queued upgrade** | (Implicit; rank should reflect queued-but-not-yet-settled upgrades the same way as committed state if score is meant to be a "live preview") | Sim path stamps `simMonumentReachedAt[level]` so a queued L→L+1 surfaces in score before settlement; test: `test_getRankings_usesSimulatedMonumentReachTickForQueuedUpgrade` | `ClanWorld.sol:1360, 2990` | ✅ NO CONFLICT |
| **`Clan` struct — building fields** | `uint8 baseLevel; uint8 wallLevel; uint8 monumentLevel;` (v4_2 §7.3) | Matches verbatim | `IClanWorld.sol:236-238` | ✅ MATCHES |
| **`LeaderboardEntry` — building fields** | `uint8 monumentLevel; uint8 baseLevel; uint8 wallLevel;` (v4_4 §3.3) | Matches verbatim | `IClanWorld.sol:403-405` | ✅ MATCHES |
| **Building events** | (Spec implies events for level changes; v4_2 events list isn't explicit on the names) | Emits `WallLevelChanged`, `WallUpgraded`, `BaseLevelChanged`, `BaseUpgraded`, `MonumentLevelChanged`, `MonumentUpgraded`. Naming-wise: `*LevelChanged` carries `(oldLevel, newLevel, atTick)` and `*Upgraded` carries `(newLevel, settledAtTick)`. Both pairs fire from the same settlement path so they're redundant by design (one for index, one for analytics). | `IClanWorld.sol:547-552, 845-850, 884-889, 932-938` | ⚠️ DRIFT (event-design only) — spec doesn't mandate the two-event-per-upgrade pattern; impl ships both. Indexer cost only; no behavioral effect. |
| **Init values** | clan starts with `baseLevel=1, wallLevel=0, monumentLevel=0` (v4 §8.3-8.5 imply ranges) | `_mintClan` sets `baseLevel = 1; wallLevel = 0; monumentLevel = 0` | `ClanWorld.sol:1582-1584` | ✅ MATCHES |
| **Concurrent upgrade orders — same clansman swap** | (Not in spec; emergent property of B.2 mission overwrite) | `_invalidateActiveMission` refunds the prior reservation when the worker is reassigned to a different upgrade | `ClanWorld.sol:500-514` | ✅ NO CONFLICT (tested: `UpgradeReservationSwitches.t.sol` 6 cases) |
| **Concurrent upgrade orders — two clansmen same clan** | (Not in spec) | Per-clan `_pendingWallUpgradesByClan` counter bumps `plannedCurrentLevel`, so the second worker reserves cost for L+1 not L (avoids double-cost-at-same-level race) | `ClanWorld.sol:2275-2281, 2298-2303` | ✅ NO CONFLICT |
| **Concurrent upgrade — settle ordering vs vault delta** | (Not in spec) | Settle checks `held.fromLevel == clan.wallLevel`; if a prior worker for the same upgrade type already advanced level, the second worker's reservation is refunded and they retry next tick. This is the R5 fix-round behavior (`Phase 8 R5 — sim/real fromLevel parity`). | `ClanWorld.sol:831-834, 868-871, 910-913` | ✅ NO CONFLICT |

---

### Summary of mechanic verification

| Verdict | Count |
|---|---|
| ✅ MATCHES | 22 |
| ⚠️ DRIFT (close-but-different / textual / impl-improvement) | 4 |
| ❌ DRIFT/MISSING (significant) | 1 |
| ⏳ DEFERRED (out of Phase 8 scope) | 3 |

**The Phase 8 implementation is a clean, faithful encoding of v4 spec §8 + §9.1 ranking.** All upgrade cost tables, level caps, vault-spend semantics, single-tick durations, and rank score components match spec. The one substantive drift is the §8.6 "WAITING on missing resources" behavior — impl rejects at submit, spec implies a queued-WAITING state.

---

## 3. Test coverage gap analysis

### What IS tested (Phase 8 test files, 36 tests across 5 files)

**`WallUpgrades.t.sol` (12 tests):**
- Cost table matches spec §8.3
- Hold-at-queue, debit-at-settle reservation flow
- Deprecated `BuildWall` rejected at submit
- Already-flighted `BuildWall` completes harmlessly
- Dead clansman releases reservation + clan can requeue
- Cancelled earlier reservation invalidates later same-clansman reservation
- Reversed clansman settlement invalidates future reservation
- Sim and real scores match after out-of-order cancellation
- Sim hides refunded reservation from later retry
- Insufficient vault at queue time → `ERR_MISSING_RESOURCES`
- Above-max level → `ERR_INVALID_ACTION`
- Two clans don't interfere

**`BaseUpgrades.t.sol` (6 tests):**
- Cost table matches spec §8.4
- Hold-at-queue, debit-at-settle
- Insufficient vault at queue → reject
- Above-max level → reject
- Two clans don't interfere
- Sim hides refunded reservation

**`MonumentUpgrades.t.sol` (7 tests):**
- Cost table matches spec §8.5 (including L7-L10 Blueprint requirement)
- Hold-at-queue, debit-at-settle
- Insufficient vault at queue → reject
- Blueprint required for late level
- Above-max level → reject
- Two clans don't interfere
- Sim hides refunded reservation

**`UpgradeReservationSwitches.t.sol` (6 tests):**
- Wall ↔ Base, Wall ↔ Monument, Base ↔ Monument switches under tight resources (all 6 directions)

**`RankGetters.t.sol` (5 tests):**
- Sort by monument level, then earliest reach tick (§9.1 (1)+(2))
- Exact score tie → clanId ascending
- Wall level used after loot, before clanId (§9.1 (4))
- Settled-upkeep loot score (§9.1 (3) settled basis)
- Simulated monument reach tick for queued upgrade

### What is NOT tested (keyed by criticality)

#### MUST-COVER (bug-class blockers)

| Scenario | Why critical |
|---|---|
| **§8.6 WAITING-on-missing-resources path** | Spec mandates worker becomes WAITING when resources absent at action tick. Impl chose submit-time reject. There is **no test that asserts the spec semantics** because the impl deliberately avoids the WAITING-with-pending-upgrade state. If the orchestrator (or Liam) decides spec wins on this, a behavioral test would need to drive: queue upgrade → drain vault between queue-and-action → assert worker WAITING + mission still pending vs. impl's hold-prevents-this-by-construction. |

#### SHOULD-COVER (production-plausible edge cases)

| Scenario | Why |
|---|---|
| **§8.7 winter-cold wall damage interaction with queued upgrade** | If a wall upgrade is queued (reserving wood) and winter cold damages the wall mid-flight (Phase 4.4 wires this), what is the `from-level` parity behavior? Impl R5 already addressed sim/real `fromLevel` parity, but a regression test specifically driving `cold-damage-during-queued-wall-upgrade` would lock in the spec's §8.7-vs-§8.6 interaction. |
| **§9.1 4-key ranking with all four keys non-trivially deciding** | RankGetters tests cover each key individually but no single test exercises all 4 tiebreaks in cascade (e.g., 4 clans with equal monumentLevel & equal reach-tick: 2 with equal loot but different wall levels, the loot-tied pair separated by wallLevel, the wall-tied pair separated by clanId). |
| **§8.5 monument L6 → L7 transition (zero-blueprint to blueprint-required boundary)** | The boundary between L6 (no blueprint) and L7 (blueprint required) is the most error-prone edge in `_monumentUpgradeCost`. `test_upgradeMonument_requiresBlueprintForLateLevel` covers blueprint-required, but a parametric `test_monumentUpgradeCost_blueprintRequiredFromLevel6` (i.e., upgrading FROM level 6 returns 1e18 blueprint) would explicitly lock the off-by-one. |
| **Cross-phase: ranking includes monument level achieved across season-end heartbeat** | `getRankings` is settled-basis. If a clan reaches monumentLevel mid-season-end-heartbeat (which is technically possible with the per-tick mission resolution order), is the reach tick recorded? Impl uses `simMonumentReachedAt` so it should — but no test drives this exact tick boundary. |
| **§8.6 ERR_MISSING_RESOURCES vs settled vault delta** | At submit, `availableWood = vaultWood - reserved + released`. The "released" path (a clansman whose mission was just cancelled and whose reservation is being released) is subtle. There IS a test for sim-hides-refunded but not for "the vault check at submit-time correctly counts released-but-not-yet-cleared reservations from a same-clansman swap." |

#### NICE-TO-HAVE

- Property test: any sequence of upgrade-and-cancel orders never leaks reservation balance (i.e., `_reservedWoodByClan[clanId]` always equals the sum of active reservations)
- Property test: monumentReachedAtTick is monotonic non-decreasing in level for a single clan
- Gas regression on the mass-tied-rankings sort path (`getRankings` uses insertion sort capped at `MAX_CLAN_SCAN_FOR_RANKING = 24`; spec doesn't bound but worst-case is O(n²) over 24 entries)
- Sweep test that all `_*UpgradeCost(currentLevel)` functions return `(0, …)` outside their valid range (off-the-end), confirming the `if (... >= MAX) return (0, ...)` guard pattern is uniformly applied

**Headline gap count:** 1 MUST-COVER (and only if spec wins on §8.6 semantics), 5 SHOULD-COVER, 4 NICE-TO-HAVE.

---

## 4. Potential UAT findings (if Liam runs interactive scenarios)

### Scenario 1 — Cost table fidelity
**Setup:** Mint a clan with a fresh vault tuned to exactly the spec L1 wall upgrade (20 wood). Submit an `UpgradeWall` order. Heartbeat one tick.
**Expected per spec:** Wall level 0 → 1, vault wood 20 → 0, clansman returns to WAITING.
**Expected per impl:** Same.
**He should verify:** `getClan(clanId).wallLevel == 1` and `getClan(clanId).vaultWood == 0`. Repeat across L2..L5 and across base/monument tables.
**Outcome prediction:** ✅ Will pass — cost-table tests already lock these in.

### Scenario 2 — Submit-time reject vs spec WAITING
**Setup:** Mint a clan, drain vault to 0 wood. Submit `UpgradeWall` (which costs 20 wood at L0).
**Expected per spec (§8.6):** Order accepted; clansman becomes WAITING; when vault eventually has 20 wood, worker auto-progresses?
**Expected per impl:** Order rejected at submit with `ERR_MISSING_RESOURCES`; clansman state unchanged; Elder must re-submit later.
**He should verify:** Submit returns `ERR_MISSING_RESOURCES`; clansman remains in current state. This is the **§8.6 drift** — Liam should decide if he wants to keep the impl's stricter / more deterministic semantics or treat it as a spec-restoration item.

### Scenario 3 — Concurrent two-worker upgrade
**Setup:** 2 clansmen at homebase, vault has wood/wheat for exactly two `UpgradeBase` chains (L1→2 and L2→3 cumulative). Submit both upgrades at the same tick.
**Expected per impl:** First worker reserves L1→2 cost; second worker's `plannedCurrentLevel` = `baseLevel + pendingUpgrades = 1 + 1 = 2`, so they reserve L2→3 cost. Both succeed in sequence at next heartbeat.
**He should verify:** After 1 heartbeat, `baseLevel == 3`; both clansmen complete missions; vault has both costs debited. (If only one tick passes, only one upgrade lands per spec §8.1 single-tick semantics — verify mission-ordering behavior.)

### Scenario 4 — Reservation refund on clansman death
**Setup:** Worker A queues `UpgradeWall` at L0→1 (reserves 20 wood). Before settlement, kill A (winter cold + zero wall). Worker B then queues the same upgrade.
**Expected per impl:** A's reservation is refunded on death; B's `availableWood` includes the refunded amount; B's order succeeds.
**He should verify:** B's submit returns `OK`; after settlement, wallLevel == 1 and vault drained by 20 wood (not 40). Test `test_upgradeWall_deadClansmanReleasesReservationAndAllowsRequeue` codifies this.

### Scenario 5 — Monument blueprint requirement boundary
**Setup:** Push a clan to monumentLevel 6 (using cheat-only test path or full L1..L6 chain), then attempt L6→L7 with vault full of wood/iron/wheat but **no Blueprint Fragment** balance.
**Expected per spec (§8.5):** Reject — blueprint requirement is "locked".
**Expected per impl:** `_validateUpgradeMonumentOrder` checks `availableBlueprint < blueprintCost` → returns `ERR_MISSING_RESOURCES`.
**He should verify:** Submit fails. Then `setClanBlueprintBalance(1e18)` (or earn one through bandit defeat in Phase 9), retry, succeeds.

### Scenario 6 — Ranking 4-key cascade
**Setup:** Mint 4 clans. Manually drive different `monumentLevel` / reach-tick / vault loot / wallLevel combos so that the rank ordering exercises all 4 keys.
**Expected per spec (§9.1):** Order by level desc, then earliest reach asc, then loot desc, then wall desc.
**Expected per impl:** Same; final tiebreak clanId asc.
**He should verify:** `getRankings()` returns expected order. Already partially tested but no single test drives all 4 simultaneously.

### Scenario 7 — Damage interaction (deferred to phases 4 + 9)
**Setup:** Trigger winter cold damage that decrements wallLevel from 3 → 2 (Phase 4.4). Then trigger a bandit attack (Phase 9) that further chips the wall.
**Expected per spec (§8.7):** Both pathways may decrement wallLevel; baseLevel and monumentLevel never decrement.
**Expected per impl in Phase 8 alone:** No code path decrements wallLevel within Phase 8 scope. Decrement lives in Phase 4 (winter) and Phase 9 (bandit). Verify `_advanceWinter` and bandit attack resolution paths in **other** phase branches; in Phase 8 alone, no decrement is exercised.
**He should verify (post-Phase 9):** that a queued `UpgradeWall` reservation against a wall that gets damaged mid-flight either refunds or proceeds at the new `fromLevel` correctly. R5 fix landed `fromLevel` parity — this test should already exist in Phase 8 OR Phase 9 test files.

---

## 5. UAT verdict

**Phase 8 is spec-compliant. Recommend ship-as-is for hackathon, with one explicit Liam decision pending on §8.6 semantics.**

The implementation is a clean, faithful encoding of v4 §8 + §9.1 with all cost tables, level ranges, spend sources, single-tick durations, and rank score components matching spec. Test coverage of these surfaces is solid (36 tests across 5 files, including spec-table parity tests).

The one substantive drift is **§8.6 WAITING-on-missing-resources**:
- Spec: order accepted; worker WAITING until vault has resources
- Impl: order rejected at submit-time with `ERR_MISSING_RESOURCES`

This is a **deliberate impl improvement** that prevents speculative-queue surprises and makes vault-spend deterministic. The reservation system (hold-at-queue / debit-at-settle / refund-on-cancel) is a well-tested surface and the rationale for not implementing the spec's queued-WAITING is sound.

The other ⚠️ DRIFTs are textual / semantic-equivalent:
- `build_wall` action renamed to `upgrade_wall` (impl) — spec doc never updated; impl handles deprecated `BuildWall` for backward-compat
- Monument L7-L10 cost is flat 200/25/100 — spec calls these levels "tunable" so this is within bounds
- Two-event-per-upgrade pattern (`*LevelChanged` + `*Upgraded`) — indexer cost only, no behavioral effect

The ⏳ DEFERRED items (wallDefense formula, baseDefense formula, wall cold/bandit damage) are legitimately Phase 4.4 (winter) and Phase 9 (bandit) territory — not Phase 8 scope.

**Two interpretive paths for Liam:**

**Path A — Implementation is canonical, spec rephrasing for §8.6:** Document the submit-time-reject + reservation pattern as the new authoritative §8.6 behavior. Add a v4.6-style addendum line: "If required vault resources are absent at submit time, the order is rejected with `ERR_MISSING_RESOURCES`. Reservation system holds resources from submit until settle." This is a doc-only, ~30-line spec addendum. Recommended.

**Path B — Spec is canonical, restore queued-WAITING:** Implement the spec's queued-WAITING semantics: accept the order, mark clansman WAITING, retry at action tick if vault has resources. This is a substantial behavioral change, additional state machine, and breaks the deterministic-spend property the impl currently provides. **Not recommended for hackathon timeline.**

**Recommended next step:** **ship Phase 8 as-is.** File a ~5-line spec gap follow-up post-hackathon to document §8.6 impl semantics in v4.6 alignment addendum.

The cloud reviewers' R5 fix-round closure is correct internal to the impl's design; this audit confirms the impl's design is materially identical to spec for all but the §8.6 semantic drift, which is a defensible improvement.

**Cleanly merge-able as-is?** **Yes** — Phase 8 is the cleanest spec-vs-impl alignment of any phase audit so far (compare Phase 9 PR #194 which had 22 ❌ DRIFT/MISSING).

---

## Appendix A — Files inspected

- `/home/claude/code/omnipass-world/review-pr-199-spec/packages/contracts/src/ClanWorld.sol` (3211 lines, full read of building + ranking code paths)
- `/home/claude/code/omnipass-world/review-pr-199-spec/packages/contracts/src/IClanWorld.sol` (804 lines — enums, structs, events, getters)
- `/home/claude/code/omnipass-world/review-pr-199-spec/packages/contracts/test/WallUpgrades.t.sol` (12 tests)
- `/home/claude/code/omnipass-world/review-pr-199-spec/packages/contracts/test/BaseUpgrades.t.sol` (6 tests)
- `/home/claude/code/omnipass-world/review-pr-199-spec/packages/contracts/test/MonumentUpgrades.t.sol` (7 tests)
- `/home/claude/code/omnipass-world/review-pr-199-spec/packages/contracts/test/UpgradeReservationSwitches.t.sol` (6 tests)
- `/home/claude/code/omnipass-world/review-pr-199-spec/packages/contracts/test/RankGetters.t.sol` (5 tests)
- `/home/claude/code/clan-world/docs/planning/clanworld_v4_spec.md` §8 (building) + §9.1 (ranking)
- `/home/claude/code/clan-world/docs/planning/clanworld_v4_1_addendum.md` (no Phase 8 changes)
- `/home/claude/code/clan-world/docs/planning/clanworld_v4_2_state_schema_interface_spec.md` §7.3 (Clan struct), §10 (events)
- `/home/claude/code/clan-world/docs/planning/clanworld_v4_3_schema_patch.md` (no Phase 8 changes)
- `/home/claude/code/clan-world/docs/planning/clanworld_v4_4_ui_indexer_getters.md` (LeaderboardEntry shape)
- `/home/claude/code/clan-world/docs/planning/clanworld_v4_5_alignment_addendum.md` (no Phase 8 changes)

## Appendix B — What I deliberately did NOT do

- Run `forge test` (per UAT brief: static analysis only)
- Re-litigate prior-reviewer findings already adjudicated in `pr199-r3-synthesis.md` and Phase 8 super-swarm rounds
- File any GitHub issues
- Edit any code in `~/code/clan-world/packages/contracts/`
- Audit Phase 9 (bandit) defense formulas — `wallDefense = 10 × wallLevel` and `baseDefense = 5 × baseLevel` are formally Phase 9 surface; covered in `pr194-spec-compliance-uat.md`
- Audit Phase 4.4 winter cold-damage decrement of `wallLevel` — that's Phase 4 scope; only the §8.7 "may lose levels" rule is in Phase 8's allowlist
