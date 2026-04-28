# Phase 3 — Foundry Test Specification

**Status:** pre-stage (Phase 3 not yet dispatched; Phase 2 PR #91 gate pending)
**Target file:** `packages/contracts/test/ClanWorld.t.sol` (extend existing suite)
**Spec references:** v4.2 §2.4, §7.7, §7.9-7.11, §8.2, §11.1, §15; dispatch brief `plans/drafts/20260426-phase3-dispatch-brief.md`
**Existing test count:** 19 (Phase 1 + Phase 2); Phase 3 adds ~39 cases below.

---

## Conventions

Helpers assumed available in the extended test contract:

```solidity
function _mintClan() internal returns (uint32 clanId)
function _advanceTick() internal          // vm.warp + heartbeat()
function _advanceTicks(uint n) internal   // repeat n times
function _submitDefend(uint32 clanId, uint32 csId, uint32 targetClanId) internal
function _submitOrder(uint32 clanId, uint32 csId, uint8 gotoRegion, ActionType action) internal
```

Region constants (from `ClanWorldConstants` or inline):
- `REGION_UNICORN_TOWN` — excluded from bandit spawn
- `REGION_DEEP_SEA` — excluded from bandit spawn

Tick advancement uses `vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS)` before each `world.heartbeat()`.

---

## 3.E1 — Bandit spawn / camp / attack

### test_banditSpawn_rejectsUnicornTownAndDeepSea

**Setup:** Deploy fresh `ClanWorld`. Force spawn probability to 100% (set `currentBanditSpawnChanceBps = 10_000`). Manipulate `tickSeed` (via known block hash / `vm.roll`) so region selection would land on Unicorn Town.

**Action:** Advance tick (heartbeat). Observe region assigned to spawned bandit (or absence of spawn).

**Assert:** Either (a) no bandit spawns (spawn skipped due to excluded region) OR (b) bandit's `currentRegion` is NOT Unicorn Town and NOT Deep Sea.

**Edge cases:**
- Seed produces Deep Sea — same assertion.
- Seed cycles through all excluded regions — no spawn until a valid region is available.

---

### test_banditSpawn_maxOneActiveBanditAtOnce

**Setup:** Spawn one bandit (probability 100%, valid region). Confirm `activeBanditId != 0`.

**Action:** Advance tick again with spawn probability 100%.

**Assert:** `WorldState.activeBanditId` unchanged (same bandit ID); no second bandit created. (v4.2 §15 invariant.)

---

### test_banditSpawn_setsStateAndNextActionTick

**Setup:** 100% spawn probability, valid region, known tick N.

**Action:** Advance tick → bandit spawns.

**Assert:**
- `BanditTroop.state == BanditState.Camping`
- `BanditTroop.nextActionTick == N + CAMPING_DURATION` (e.g. 2 or 3 per implementation)
- `BanditTroop.stateEnteredTick == N`
- `BanditTroop.currentRegion` is a valid non-excluded region.

---

### test_banditCamping_doesNotAdvanceBeforeNextActionTick

**Setup:** Spawn bandit at tick N with `nextActionTick = N + 3`.

**Action:** Advance 1 tick (tick N+1), advance 2 ticks (N+2).

**Assert:** Both times, `BanditTroop.state == BanditState.Camping`.

---

### test_banditTransition_campingToAttacking_atNextActionTick

**Setup:** Spawn bandit at tick N, `nextActionTick = N + 2`. Mint a clan in the bandit's region (so target selection can succeed).

**Action:** Advance to tick N + 2.

**Assert:** `BanditTroop.state == BanditState.Attacking`.

---

### test_banditSpawn_nextEligibleTickAdvances

**Setup:** After bandit spawns, read `WorldState.nextBanditSpawnEligibleTick`.

**Assert:** `nextBanditSpawnEligibleTick > currentTick` (spawn cooldown is set).

---

## 3.E2 — Eager settlement of touched clans

### test_eagerSettle_banditTargetVaultReflectsSettledState

**Setup:**
- Mint two clans, both in same region as incoming bandit.
- Clan A has workers gathering — unsettled resource surplus exists.
- Clan B has starvation developing — unsettled penalty.
- Spawn bandit, advance to attack tick.

**Action:** Heartbeat resolves the attack.

**Assert:**
- At attack resolution, vault values used for target-selection / loot reflect settled state (not stale lazy state).
- Specifically: if Clan A's vault would be higher post-settle and that increases its loot value, the bandit targeted it (or loot drawn is the correct settled amount).

**Note:** This test is correctness-sensitive per v4.2 §2.4 — lazy targeting = wrong outcome.

---

### test_eagerSettle_defendersInRegionAreSettledBeforeTargetPick

**Setup:**
- Clan A in region R (homebase).
- Clan B has a worker registered as defender at Clan A's base.
- Bandit targets region R.

**Assert:** At bandit target-pick step, Clan B's worker is included in defender registry with correct `defensePoints` (earned via prior settle).

---

## 3.E3 — Defender registry

### test_defenderRegistry_addOnDefendBaseMissionArrival

**Setup:** Mint defender clan, send worker to target clan's base (`DefendBase(targetClanId)`). Travel duration = 1 tick.

**Action:** Advance tick (worker arrives).

**Assert:**
- `getActiveDefenders(targetClanId)` includes the worker's clansman ID.
- `defendingBaseOfClansman[csId] == targetClanId`.
- `defenderIndexPlusOne[csId] != 0`.

---

### test_defenderRegistry_removedOnMissionInterrupt

**Setup:** Register worker as defender. Confirm in registry.

**Action:** Submit new mission for that worker (interrupting DefendBase). Advance tick.

**Assert:**
- `getActiveDefenders(targetClanId)` no longer includes worker.
- `defendingBaseOfClansman[csId] == 0`.
- `defenderIndexPlusOne[csId] == 0`.

---

### test_defenderRegistry_swapPopIntegrity_middleRemoval

**Setup:** Register 3 workers (A, B, C) as defenders of same base. Confirm registry = [A, B, C].

**Action:** Interrupt worker B (middle of array).

**Assert:**
- Registry has 2 entries.
- No duplicate IDs.
- No zero-ID entries (swap-pop replaced B with C correctly).
- `defenderIndexPlusOne` for A and C are updated; B's entry is 0.

---

### test_defenderRegistry_removedOnWorkerDeath

**Setup:** Register worker as defender. Set worker HP to 0 (or advance starvation until death).

**Action:** Trigger worker death (via heartbeat starvation or forced state).

**Assert:** Worker removed from defender registry (`getActiveDefenders` excludes it).

---

### test_defenderRegistry_persistsAcrossMultipleBanditCycles

**Setup:** Register worker W as defender of Clan A. Let bandit attack and resolve (defender wins or loses). Do not interrupt W.

**Action:** Advance several ticks. Let second bandit spawn and attack same base.

**Assert:** W is still in `getActiveDefenders(A)` for the second attack. (v4.2 §8.2 — DefendBase is continuous.)

---

### test_defenderRegistry_removedOnClanDeath

**Setup:** Register worker of Clan B as defender of Clan A. Kill Clan A (set workers = 0 / mark dead).

**Assert:** Worker is removed from `activeDefendersByBase[A]`.

---

## 3.E4 — Deterministic combat

### test_combat_defenderWins_whenTotalDefenseGeAttackPower

**Setup:**
- Mint attacker clan, mint defender clan.
- Register N defenders at defender clan's base; their combined `defensePoints` > bandit's `attackPower`.
- Spawn bandit targeting defender clan.

**Action:** Advance to attack tick.

**Assert:**
- `BanditTroop.state == BanditState.Defeated`.
- `BanditAttackResolved` event emitted with `defended == true`.
- Defender clan vault unchanged (no vault damage).

---

### test_combat_attackerWins_whenTotalDefenseLtAttackPower

**Setup:**
- Defender clan has 0 defenders registered (or weak defenders: `totalDefense < attackPower`).
- Spawn bandit.

**Action:** Advance to attack tick.

**Assert:**
- `BanditTroop.state == BanditState.Retreating` (or `Defeated` per implementation).
- Defender clan wall HP decremented.
- Defender clan vault decremented by bandit carry amount.
- `BanditAttackResolved` event emitted with `defended == false`.

---

### test_combat_determinism_sameSeedSameOutcome

**Setup:**
- Snapshot full state at start of tick T (bandit + defenders + seed).
- Record outcome (winner, loot amounts, any randomized values like wound chance).

**Action:** Re-fork same block via `vm.snapshot` / `vm.revertTo`. Replay heartbeat.

**Assert:** Outcome byte-for-byte identical. (v4.2 §11.1 — tickSeed as sole randomness source.)

---

### test_combat_determinism_differentSeedDifferentOutcome

**Setup:** Same bandit + defender state, but different `tickSeed` (advance one extra block to change block hash before deriving seed).

**Assert:** At least one randomized outcome differs (e.g. crit, wound chance). Confirms seed is actually wired into resolution logic.

---

### test_combat_noReentrancy_defenderCallbackHarmless

**Setup:** Deploy a mock defender that re-enters `heartbeat()` on `BanditAttackResolved` callback.

**Assert:** Reentrancy guard triggers (revert) or re-entry has no effect on state consistency. (v4.2 §11.4.)

---

## 3.E5 — Loot split / wall damage / blueprint reward

### test_lootDistribution_proportionalToDefensePoints

**Setup:**
- Two defenders: Clansman A with `defensePoints = 3`, Clansman B with `defensePoints = 1`.
- Bandit carry: 100 wood (total loot = 100).
- Defenders win (combined 4 > bandit attack power).

**Action:** Advance to attack resolution.

**Assert:**
- Clansman A's clan receives 75 wood.
- Clansman B's clan receives 25 wood.
- Proportional split within ±1 rounding error.

---

### test_lootDistribution_blueprintAwardedToTopContributor

**Setup:** Three defenders, Clansman X has highest `defensePoints`. Defenders win.

**Assert:** `BlueprintAwarded` event emitted with `clanId == X.clanId`.

---

### test_lootDistribution_contributionsClearedAfterResolution

**Setup:** Resolve one bandit attack. Read `defenseContributionsByBanditId[banditId]`.

**Assert:** Array is empty after resolution. (v4.2 §7.11 — entries cleared after distribution.)

---

### test_wallDamage_onDefenderLoss

**Setup:** Defender clan with `wallHpCurrent = 100`. Bandit attack power exceeds defense.

**Action:** Attack resolves (defender loses).

**Assert:** `Clan.wallHpCurrent < 100`. (Exact delta per implementation formula.)

---

### test_vaultLoss_onDefenderLoss

**Setup:** Defender clan vault has 200 wood. Bandit `attackPower` overshoot carries 50 wood.

**Assert:** Defender clan vault decremented by 50 wood. Bandit `carryWood` incremented by 50.

---

### test_vaultLoss_cappedAtVaultContents

**Setup:** Defender clan vault has 10 wood. Bandit carry capacity exceeds vault.

**Assert:** Bandit takes at most 10 wood (no underflow). Vault reaches 0, not negative.

---

### test_lootSnapshot_usesContributionAtAttackNotCurrentRegistry

**Setup:**
- Register defender D at base of Clan A at tick T.
- At tick T+1 (before attack resolves): interrupt D's mission.
- Attack resolves at tick T+2.

**Assert:** D's `defensePoints` contribution IS included in loot distribution (snapshot was taken at attack initiation, not at resolution). (Per dispatch brief §3.E5.)

---

## 3.E6 — Wall / base / monument upgrades

### test_buildWall_incrementsTierAndResetsHp

**Setup:** Clan starts at `wallTier = 0`, `wallHpCurrent = 0`. Clan has required stone in vault.

**Action:** Submit `BuildWall` mission. Advance until complete.

**Assert:**
- `Clan.wallTier == 1`.
- `Clan.wallHpCurrent == Clan.wallHpMax` (reset to max).

---

### test_repairWall_resetsHpWithoutChangingTier

**Setup:** Clan has `wallTier = 2`, `wallHpCurrent = 50` (damaged). Sufficient stone in vault.

**Action:** Submit `RepairWall`. Advance until complete.

**Assert:**
- `Clan.wallTier == 2` (unchanged).
- `Clan.wallHpCurrent == Clan.wallHpMax`.

---

### test_upgradeBase_incrementsTier

**Setup:** Clan has `baseTier = 0`. Sufficient wood + stone.

**Action:** Submit `UpgradeBase`.

**Assert:** `Clan.baseTier == 1`.

---

### test_buildMonument_incrementsTier

**Setup:** Clan has `monumentTier = 0`. Sufficient gold + blueprints.

**Action:** Submit `BuildMonument`.

**Assert:** `Clan.monumentTier == 1`.

---

### test_upgrade_rejectsInsufficientResources

**Setup:** Clan vault has 0 stone. Attempt `BuildWall`.

**Assert:** Revert (or order result error). State unchanged.

---

### test_upgrade_costScalesWithTier

**Setup:** Upgrade wall from tier 0 → 1 (cost C0). Record cost. Upgrade from tier 1 → 2 (cost C1).

**Assert:** `C1 > C0`. Confirms geometric cost scaling.

---

## 3.E7 — Leaderboard

### test_leaderboard_rankConsistentWithCompositeScore

**Setup:** Mint 3 clans with different gold, worker count, wallTier, monumentTier. Set known values so expected score order is deterministic.

**Action:** Call `getLeaderboard()`.

**Assert:** Returned clan order matches descending composite score:
```
score = vaultGold + (workers * N) + (wallTier * M) + (monumentTier * K) - banditDamageTaken
```

---

### test_leaderboard_rankUpdatesAfterBanditAttack

**Setup:** Clan A has higher score than Clan B. Bandit attacks Clan A (defender loss) — Clan A takes vault loss.

**Action:** Call `getLeaderboard()` post-attack.

**Assert:** Scores reflect vault/wall damage. Rank may have changed if Clan B now scores higher.

---

### test_getClanRank_matchesLeaderboardPosition

**Setup:** Leaderboard returns [C3, C1, C2] (rank 1, 2, 3).

**Assert:** `getClanRank(C3) == 1`, `getClanRank(C1) == 2`, `getClanRank(C2) == 3`.

---

### test_leaderboard_handlesMaxClans

**Setup:** Mint 12 clans (canonical map cap).

**Action:** Call `getLeaderboard()`.

**Assert:** Returns 12 entries, no revert, correct sort. Confirms gas-acceptable for ≤12 clans.

---

## 3.E8 — Integration / invariant harness

### test_integration_fullBanditCycle_twoClansDefend

End-to-end script per dispatch brief exit criteria:

**Setup:**
- Mint Clan A, Clan B.
- Both deposit resources into vaults.
- Clan A sends 2 defenders to Clan B's base.
- Set spawn probability 100%, seed into valid region (Clan B's region).

**Actions (in order):**
1. Advance tick → bandit spawns in Clan B's region.
2. Advance `CAMPING_DURATION` ticks → bandit transitions to Attacking.
3. Submit additional defender orders if needed.
4. Advance tick → attack resolution heartbeat.
5. Call `getLeaderboard()`.

**Assert:**
- Bandit state is `Defeated` (defenders win) OR `Retreating` (defender loss) — no stuck state.
- Loot/damage events emitted.
- Leaderboard reflects post-attack scores.
- `defenseContributionsByBanditId[banditId]` empty after resolution.
- `activeBanditId == 0` (bandit cleared from world state on defeat/retreat).

---

### test_invariant_atMostOneBanditAtOnce

**Fuzzer:** For any sequence of heartbeats, `WorldState.activeBanditId != 0` for at most one bandit ID at any point.

Implement as Foundry invariant test (Foundry `invariant_*` naming) with a handler that calls `heartbeat()` with varying `vm.warp` increments.

---

### test_invariant_banditNeverInExcludedRegion

**Fuzzer:** For any spawned bandit, `BanditTroop.currentRegion != REGION_UNICORN_TOWN && != REGION_DEEP_SEA`.

Implement as invariant test.

---

## Test count summary

| Deliverable | Tests |
|-------------|-------|
| 3.E1 Bandit spawn | 6 |
| 3.E2 Eager settle | 2 |
| 3.E3 Defender registry | 6 |
| 3.E4 Deterministic combat | 5 |
| 3.E5 Loot / wall damage | 7 |
| 3.E6 Upgrades | 6 |
| 3.E7 Leaderboard | 4 |
| 3.E8 Integration / invariants | 3 |
| **Total** | **39** |

Existing Phase 1/2 suite: 19. Post-Phase-3: **58 tests**.

---

## Implementation notes for the implementor

- All randomness must come from `WorldState.currentTickSeed` (v4.2 §11.1). Tests that verify determinism should use `vm.snapshot` / `vm.revertTo` to replay the same tick.
- The `_eagerSettleForBandit(banditId)` call MUST happen before target selection AND before damage application (3.E2). Tests 3.E2-a and 3.E2-b directly verify this ordering.
- Swap-pop integrity in `defenderIndexPlusOne` is critical — get 3.E3 middle-removal test passing before integration tests.
- Loot snapshot (3.E5 last test) verifies that `defenseContributionsByBanditId` is populated at mission-start not resolution — this affects test setup sequence.
- For 3.E7 gas test: `getLeaderboard()` with 12 clans must not revert. If it does, the view function needs gas optimization (insertion-sort rather than bubble-sort).
- `NEVER_CUT` per dispatch brief: 3.E1-3.E4, 3.E2 eager-settle, 3.E8 combat-determinism + registry-integrity tests.
