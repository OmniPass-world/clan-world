# EIP-2535 Diamond Architecture — ClanWorld

**Status:** Design proposal — awaiting Liam go/no-go before any code migration  
**Author:** pm-dobot  
**Issue:** #337  
**Date:** 2026-04-30

---

## 1. Executive Summary

### Why Diamond (EIP-2535) over the hybrid split plan

The previous plan (`clanworld-eip170-split-plan.md`) proposed extracting internal libraries and an external `delegatecall`-linked market library to shrink `ClanWorld.sol` under the EIP-170 24,576-byte limit. Two independent DA reviews (Codex, Gemini Pro) both rejected the plan. The six core risks they identified:

1. **Internal library savings are illusory.** `internal` library functions are inlined by `solc`/`via_ir`. The plan claimed 1.5–4 KB from Travel + token-routing extraction; both DAs rated this "WISHFUL THINKING" — real savings likely 0 KB.

2. **`try/catch` + `delegatecall` is a game-halting footgun.** The heartbeat's `try this._executeMarketSellExternal(...)` boundary relies on exact error bubbling. With `delegatecall` in the call chain, revert data encoding changes subtly. A single failing market order could revert the entire heartbeat and freeze the game loop for all users.

3. **Savings math is coupon-summed, not compound.** The plan adds 1.5 + 3 + 2.5 + 7 KB as independent credits. Compiler optimizations are not linear. If estimates are 30% off, the post-split contract lands at 25–27 KB — still over the limit after weeks of work.

4. **Test coverage is inadequate for EVM-level refactors.** Existing tests cover outcomes, not call-context, revert-surface, or event-origin changes. The split introduces library linkage failures, `delegatecall` context mix-ups, and gas regressions invisible to functional tests.

5. **< 1 KB post-split safety margin.** Even on the optimistic path, the plan leaves less than 1 KB headroom. The first Phase 9 feature restores the crisis.

6. **Storage layout fragility.** External `delegatecall` libraries must perfectly mirror the monolith's storage layout. Adding one variable to a struct in a future phase, without recompiling + relinking every library, silently overwrites wrong storage slots — catastrophic data corruption.

### Final decision: EIP-2535 Diamond with single AppStorage

Diamond (EIP-2535) solves the problem at the root: each facet is an independent contract (≤24,576 B) that shares storage through a deterministic pointer. There is no `delegatecall`-over-library fragility, no inlining guesswork, no 1 KB margin. The ABI surface (`IClanWorld`) stays byte-stable.

**Off-chain compatibility note:** The Diamond proxy is deployed at a new address. All off-chain consumers (indexers, frontends, bots) must update their contract address. Additionally: (1) events are emitted with `address = Diamond proxy`, not the facet — indexers that filter by contract address need no change if they target the proxy; (2) revert strings bubble through the proxy unchanged; (3) gas profiles change (~700 gas overhead per external call through proxy). Off-chain gas estimation scripts must be recalibrated after migration.

The reference implementation (Nick Mudgen's Diamond-3) is battle-tested in production (Aavegotchi, DeFi protocols). The pattern is well-understood by Solidity auditors.

---

## 2. Current State

| Metric | Value |
|---|---|
| `ClanWorld` runtime bytecode | **34,792 bytes** |
| EIP-170 limit | 24,576 bytes |
| Deficit (must eliminate) | **10,216 bytes** |
| `via_ir = true` already required | Yes (without it, even larger) |
| Base Sepolia deployment | Blocked — contract cannot be deployed |

The 34,792-byte measurement was taken from `forge build --sizes` on the `dev` HEAD (`6cf6f39`) with `optimizer = true, optimizer_runs = 200, via_ir = true`.

The `ClanWorldTestHarness` (34,871 B) and `HeartbeatOrderingHarness` (35,011 B) are both over limit too — they inherit from `ClanWorld` and are test-only; they are not deployed to Base Sepolia.

---

## 3. Proposed Facet Boundaries

The goal: partition `ClanWorld.sol`'s 2,124 lines into facets each well under 24,576 bytes. Each facet gets exclusive ownership of its primary concern. All facets share `AppStorage` (see §4).

### Actual compiled skeleton sizes (from `forge build --sizes`)

These are real measurements from `feat/issue-337-diamond-design` HEAD, not estimates:

| Contract | Runtime bytes | Init code bytes | Headroom vs 24,576 |
|---|---|---|---|
| `Diamond` (proxy) | 225 | 4,953 | 24,351 B headroom |
| `DiamondCutFacet` | 4,800 | 4,826 | 19,776 B headroom |
| `DiamondLoupeFacet` | 1,866 | 1,892 | 22,710 B headroom |
| `CoreFacet` (empty shell) | 647 | 673 | 23,929 B headroom |
| `MarketFacet` (empty shell) | 720 | 746 | 23,856 B headroom |
| `GatheringFacet` (empty shell) | 115 | 139 | 24,461 B headroom |
| `ViewsFacet` (read-only) | 5,617 | 5,643 | 18,959 B headroom |
| `BanditsFacet` (stub) | 57 | 81 | 24,519 B headroom |
| `WintersFacet` (stub) | 57 | 81 | 24,519 B headroom |

**Key observations:**
- `ViewsFacet` skeleton already compiles to 5,617 B because it includes real view logic from ClanWorld. This is the expected shape — views are dense.
- Shell facets (CoreFacet, MarketFacet, GatheringFacet) are 115–720 B today. They will grow substantially when business logic migrates. See projected sizes below.
- `via_ir` optimizer deduplication applies within a single compilation unit. Splitting facets may reduce per-facet optimization — total deployed bytecode will be higher than the 34,792 B monolith. This is expected and acceptable (EIP-170 is per-contract, not total).

### Size projections after business logic migration

Projections use ClanWorld's compiled density (~16 B/source line, `via_ir`) applied to function-count estimates per facet. These must be re-measured with `forge build --sizes` before merging each migration PR.

| Facet | Responsibility | Est. Lines | Projected Size | Margin vs 24,576 |
|---|---|---|---|---|
| `CoreFacet` | World clock, heartbeat dispatch shell, clan lifecycle, order submission, travel | ~700 | ~16–18 KB | 6–8 KB margin |
| `MarketFacet` | Market execution (sell/buy), treasury init/seed, pool routing, OTC stubs | ~420 | ~8–10 KB | large |
| `GatheringFacet` | Settlement core (`_settleClan`, `_settleMissionForClansman`), all gather helpers, deposit, building upgrades | ~600 | ~13–15 KB | comfortable |
| `ViewsFacet` | All `pure`/`view` aggregators: `getWorldSnapshot`, `getClanFullView`, `getMarketState`, `getRegionPopulation`, derived state | ~380 | ~8–10 KB | large |
| `BanditsFacet` | Phase 9 bandit attack/defense — full Phase 9 implementation landing zone | ~50 stub today | ~2–3 KB stub | very large |
| `WintersFacet` | Phase 10 winter damage, elimination, `finalizeSeason` — full Phase 10 implementation landing zone | ~30 stub today | ~1–2 KB stub | very large |

**CoreFacet growth risk (Phase 9/10):** CoreFacet holds ~700 lines today projecting to 16–18 KB. Phase 9 (Bandits) + Phase 10 (Winters) logic will NOT land in CoreFacet — they have dedicated facets (`BanditsFacet`, `WintersFacet`). These facets are not speculative pre-stubs; they are load-bearing separations that prevent CoreFacet from growing past the 24,576 B limit. If CoreFacet measures over 20 KB after business logic migration, extract `_buildPath` + `_distMatrix` + `_travelTicks` into a `TravelFacet` (pure functions, ~2–3 KB). This split is pre-approved — no additional design review needed.

**Total deployed bytecode note:** All facets together (~50–57 KB of business logic) plus infrastructure (~7 KB for Diamond proxy + DiamondCut + Loupe) = ~57–64 KB total deployed across all contracts, vs. 34,792 B today. This is intentional and acceptable. EIP-170 limits each individual contract to 24,576 B; there is no limit on the total bytecode across all contracts in a deployment.

> **Mandatory size check:** Before merging any migration PR (PR 2–6), run `forge build --sizes` and confirm each facet's runtime bytes is under 20,000 B (leaving ≥4 KB headroom). If any facet approaches 20 KB, split before merging.

### Cross-facet execution model

EIP-2535 facets are separate deployed contracts. `CoreFacet` cannot call `GatheringFacet._settleCompletingMissions()` as an internal function. There are two patterns for cross-facet execution:

**Pattern A: Shared internal library (preferred for pure/stateless helpers)**  
Logic that is stateless or has no external-call risk moves into a `library` (e.g., `LibTravel`, `LibGathering`). Libraries are inlined by `via_ir` at the call site — no cross-contract call, no gas overhead, no reentrancy risk. Storage-touching logic in libraries is safe because libraries execute in the caller's storage context via `delegatecall`.

**Pattern B: External self-call through proxy (for state-writing cross-facet dispatch)**  
`CoreFacet.heartbeat()` calls `IClanWorld(address(this))._executeScheduledMarketActions(tick)`. Under `delegatecall`, `address(this)` is the Diamond proxy. The proxy routes the call to the correct facet. This is an external call — it adds ~700 gas overhead and is subject to reentrancy considerations (see §Heartbeat Failure Model).

**Decision for ClanWorld:**
- Pure computation helpers (`_buildPath`, `_distMatrix`, `_travelTicks`): Pattern A — move to `LibTravel`
- Settlement core (`_settleClan`, `_settleCompletingMissions`): Pattern A — move to `LibSettlement` (if stateless enough) OR exposed as external selectors on GatheringFacet (Pattern B)
- Market execution loop: Pattern B — `_executeScheduledMarketActions` becomes an external selector on MarketFacet, called from heartbeat via `IClanWorld(address(this))`
- State-reading shared logic (`_poolReserves`): Pattern A — move to `LibMarket` (pure computation against treasury state)

**Note:** Functions in Pattern A (library) do NOT appear in the Diamond's selector table. Functions in Pattern B (external self-calls) DO appear as selectors and can be called by anyone unless access-controlled. All Pattern B functions that modify state must be access-controlled to `address(this)` only.

### Function assignment by facet

#### CoreFacet — world clock, heartbeat shell, clan lifecycle, order dispatch

From `ClanWorld.sol`:
- `heartbeat()` — calls GatheringFacet via Pattern B for `_settleCompletingMissions`, calls MarketFacet via Pattern B for market loop, calls `_resolveWorldEvents` internally
- `_resolveWorldEvents(uint64 closedTick)`
- `settleClan(uint32 clanId)` → delegates to `_settleClan` in GatheringFacet
- `settleClansman(uint32 csId)` → delegates to `_settleClan` in GatheringFacet
- `finalizeSeason()` — stub, moves to WintersFacet later
- `mintClan(address to)`
- `submitClanOrders(uint32 clanId, ClanOrder[] calldata orders)`
- `_processOrder(...)` 
- `_installMission(...)`
- `_enqueueScheduledMarketAction(...)`
- `_registerDefender(...)`, `_clearDefender(...)`
- `_validateAction(...)`, `_validateDefendBaseOrder(...)`
- `_distMatrix(...)`, `_buildPath(...)`, `_travelTicks(...)`, `_addTicksClamped(...)`
- `getActionDuration(...)`, `getTravelTicks(...)`

Storage primarily accessed: `_world`, `_clans`, `_clansmen`, `_missions`, `_allClanIds`, `_clanClansmanIds`, `_nextClanId`, `_nextClansmanId`, `_scheduledMarketActions`, `_defendingClansByRegion`, `_defenderCountByRegionClan`, `_clansmanDefendingRegion`, `_wheatPlots`, `_tickSeeds`

#### MarketFacet — market execution, treasury, pools, OTC stubs

From `ClanWorld.sol`:
- `_executeScheduledMarketActions(uint64 tick)` — called by heartbeat
- `_executeMarketSellExternal(...)`, `_executeMarketSell(...)`
- `_executeMarketBuyExternal(...)`, `_executeMarketBuy(...)`
- `_sortScheduledMarketActionsByCommitSequence(...)`
- `_poolFor(address token)`, `_addToVault(...)`, `_deductFromVault(...)`
- `_poolReserves(...)` — shared with ViewsFacet (duplicate or extracted to LibMarket)
- `initTreasury(address[6] calldata tokens, address[4] calldata pools)`
- `seedPools(PoolSeedConfig calldata cfg)`
- `transferGold(...)`, `transferVaultResource(...)`, `transferBlueprint(...)`, `transferBundle(...)` — OTC stubs (pure revert)

Storage primarily accessed: `_treasury`, `_clans`, `_clansmen`, `_missions`, `_scheduledMarketActions`

#### GatheringFacet — settlement engine, all gathering, deposit, buildings

From `ClanWorld.sol`:
- `_settleClan(uint32 clanId)`
- `_settleMissionForClansman(...)`
- `_settleCompletingMissions(uint64 tick)`
- `_applyUpkeep(Clan storage clan, uint64 tick)`
- `_isStarving(Clan storage clan)`
- `_resolveAction(...)` — dispatch hub for gathering
- `_gatherWood(...)`, `_gatherIron(...)`, `_rollIronGoldBonus(...)`
- `_gatherFishDocks(...)`, `_gatherFishDeepSea(...)`
- `_gatherWheat(...)`
- `_doDeposit(...)`, `_doWithdraw(...)` (future)
- `_doBuilding(...)`, `_tryBuildWall(...)`, `_tryUpgradeBase(...)`, `_tryUpgradeMonument(...)`
- `_completeMission(...)`

Storage primarily accessed: `_clans`, `_clansmen`, `_missions`, `_wheatPlots`, `_allClanIds`, `_clanClansmanIds`, `_tickSeeds`

#### ViewsFacet — all pure/view aggregators

From `ClanWorld.sol`:
- `getWorldState()`, `getTreasuryState()`
- `getClan(uint32)`, `getClansman(uint32)`, `getActiveMission(uint32)`, `getMissionTiming(...)`
- `getBanditTroop(uint32)` — stub
- `getWheatPlots(uint32)`
- `getScheduledMarketActionsForTick(uint64)`
- `getActiveDefenders(uint32)`, `getDefendingClans(uint8)`
- `getDerivedClanState(uint32)`, `getDerivedClansmanState(uint32)`
- `getBanditTargetPreview(uint32)` — stub
- `quoteTravel(uint8, uint8)`
- `quoteLootValueRaw(uint32)`, `quoteLootValueSettled(uint32)`
- `_lootValueRaw(Clan memory)` — pure helper
- `getWorldSnapshot()`
- `getClanFullView(uint32)`
- `getMarketState()`
- `_poolReserves(...)` — pure computation against treasury state
- `getActiveBanditView()` — stub
- `getRegionPopulation(uint8)`

Storage primarily accessed: read-only access to all AppStorage fields (no writes)

#### BanditsFacet — Phase 9 bandit mechanics

BanditsFacet is a **load-bearing future separation**, not speculative pre-scaffolding. Phase 9 bandit logic must land here (not in CoreFacet) to prevent CoreFacet from exceeding 24,576 B. Stub shell exists now; full implementation lands in PR 5 / Phase 9 migration.

Functions (stubs in ClanWorld.sol that will grow here):
- `spawnBandit(...)` — Phase 9
- `resolveBanditAttack(...)` — Phase 9
- `_pickBanditTarget(...)` — Phase 9

Storage primarily accessed: `_world.activeBanditId`, `_world.nextBanditSpawnEligibleTick`, future `_bandits` mapping

#### WintersFacet — Phase 10 winter damage + elimination

WintersFacet is a **load-bearing future separation** for the same reasons as BanditsFacet. Winter logic belongs here, not in CoreFacet.

Functions:
- `finalizeSeason()` — currently stub in CoreFacet, moves here when Phase 10 ships
- `_applyWinterDamage(...)` — Phase 10
- `_eliminateClan(...)` — Phase 10

Storage primarily accessed: `_world.winterActive`, `_clans`, winter-specific counters

---

## 4. AppStorage Layout Decision

### Options compared

**Option A: Single `AppStorage` struct in `LibStorage.sol`**
- One canonical struct containing all state variables
- Accessed via `LibStorage.appStorage()` returning a pointer at deterministic storage slot
- All facets import `LibStorage` and call `s = LibStorage.appStorage()`
- Pattern: Diamond-3 reference, Aavegotchi, most production Diamonds

**Option B: Per-facet storage structs at deterministic slots**
- Each facet declares its own storage struct at a unique `bytes32` slot
- More modular, but requires careful slot management
- More complex for shared state (clan data is read by every facet)

### Decision: Option A — single AppStorage struct

ClanWorld has deeply shared state. `_clans`, `_clansmen`, `_missions`, `_tickSeeds` are read and written by CoreFacet, GatheringFacet, MarketFacet, and ViewsFacet simultaneously. Per-facet storage would require duplicating access patterns or adding cross-facet read helpers, both of which are more error-prone than a single shared struct.

The single `AppStorage` pattern is:
- Simpler to audit (one source of truth for all state)
- Consistent with the existing ClanWorld storage layout (direct mapping)
- The dominant pattern in production Diamond contracts

**Why not per-facet storage slots?** Per-facet slots (Option B) would require each reading facet to import every other facet's storage lib — or move shared state to a "common" struct anyway. ClanWorld's state is too interconnected for clean per-facet partitioning: `_clans` is written by CoreFacet, GatheringFacet, and MarketFacet. Attempting per-facet isolation would produce a single `LibSharedStorage` covering 90% of the struct, which is Option A by another name with extra verbosity. Single AppStorage is the correct choice for this architecture.

### AppStorage struct fields

All state variables from `ClanWorld.sol` map 1:1 into `AppStorage`:

```solidity
struct AppStorage {
    // -------------------------------------------------------------------------
    // World state (was: WorldState private _world)
    // -------------------------------------------------------------------------
    WorldState world;

    // -------------------------------------------------------------------------
    // Treasury (was: TreasuryState private _treasury)
    // -------------------------------------------------------------------------
    TreasuryState treasury;

    // -------------------------------------------------------------------------
    // Clan registry
    // -------------------------------------------------------------------------
    mapping(uint32 => Clan) clans;                    // clanId => Clan
    uint32 nextClanId;
    uint32[] allClanIds;

    // -------------------------------------------------------------------------
    // Clansman registry
    // -------------------------------------------------------------------------
    mapping(uint32 => Clansman) clansmen;              // clansmanId => Clansman
    uint32 nextClansmanId;
    mapping(uint32 => uint32[]) clanClansmanIds;       // clanId => clansmanId[]

    // -------------------------------------------------------------------------
    // Mission state
    // -------------------------------------------------------------------------
    mapping(uint32 => Mission) missions;               // keyed by clansmanId

    // -------------------------------------------------------------------------
    // Wheat plots
    // -------------------------------------------------------------------------
    mapping(uint32 => WheatPlot[2]) wheatPlots;        // clanId => [west, east]

    // -------------------------------------------------------------------------
    // Scheduled market actions
    // -------------------------------------------------------------------------
    mapping(uint64 => ScheduledMarketAction[]) scheduledMarketActions; // tick => actions

    // -------------------------------------------------------------------------
    // Defense registries
    // -------------------------------------------------------------------------
    mapping(uint8 => uint32[]) defendingClansByRegion;             // region => clanIds
    mapping(uint8 => mapping(uint32 => uint256)) defenderCountByRegionClan; // region => clanId => count
    mapping(uint32 => uint8) clansmanDefendingRegion;              // clansmanId => region

    // -------------------------------------------------------------------------
    // RNG seeds
    // -------------------------------------------------------------------------
    mapping(uint64 => bytes32) tickSeeds;              // tick => seed

    // -------------------------------------------------------------------------
    // Reentrancy guard (shared across all facets — see §Development Invariants)
    // -------------------------------------------------------------------------
    uint256 reentrancyStatus;                          // 1 = not entered, 2 = entered

    // -------------------------------------------------------------------------
    // Initialization guard + ownership (set atomically in DiamondInit._init())
    // -------------------------------------------------------------------------
    bool initialized;                                  // true after first init; prevents re-init
    address owner;                                     // DiamondCut owner / multisig address

    // -------------------------------------------------------------------------
    // Constants stored at deploy time (not in IClanWorld; inline here for Diamond)
    // -------------------------------------------------------------------------
    // Note: WHEAT_HARVEST_RATE and MAX_MARKET_ACTIONS_PER_TICK are contract-level
    // constants in ClanWorld.sol; keep as Solidity constants in a shared library,
    // not in AppStorage (constants don't occupy storage slots).
}
// IMPORTANT: any future field additions go HERE (after `owner`), never above.
// Append-only — see §Storage Safety.
```

**Storage slot:** `LibStorage.appStorage()` uses the deterministic slot:
```solidity
bytes32 constant STORAGE_SLOT = keccak256("clan.world.app.storage.v1");
```

This avoids slot 0 collision with any future inherited contracts and matches EIP-2535 best practice.

---

## 5. Storage Safety

### The single most critical correctness rule for AppStorage

The AppStorage struct is the shared state backbone across all facets. Corrupting it silently corrupts the entire game state. Two rules are non-negotiable:

### Rule 1: Append-only struct modification

**New fields MUST be added at the END of `AppStorage`. Never insert a field mid-struct. Never reorder fields.**

Rationale: In a `delegatecall` context, the EVM computes storage slot positions by sequential layout of the struct. Adding a field at position N shifts every field after N to a new slot. Existing on-chain data at those slots now maps to the wrong variable. The Solidity compiler does NOT catch this — it will compile cleanly and silently corrupt state.

```solidity
// CORRECT — append at end
struct AppStorage {
    // ... existing fields ...
    mapping(uint64 => bytes32) tickSeeds;   // slot N (existing)
    uint256 reentrancyStatus;               // slot N+1 (existing)
    // New field added in Phase 9:
    mapping(uint32 => BanditData) bandits;  // ALWAYS append here
}

// WRONG — never do this
struct AppStorage {
    WorldState world;
    mapping(uint32 => BanditData) bandits;  // inserted mid-struct — corrupts all downstream slots
    TreasuryState treasury;
    // ...
}
```

### Rule 2: Storage layout snapshot in CI

Every PR that touches `LibStorage.sol` (or any struct used inside `AppStorage`) MUST include an updated storage layout snapshot. Procedure:

```bash
# From packages/contracts:
# Inspect a facet that imports LibStorage — this captures the AppStorage struct layout
# because the facet declares it as an inline type reference:
forge inspect CoreFacet storageLayout --json > test/snapshots/storage-layout.json
```

**Important:** `forge inspect Diamond storageLayout` will NOT capture `AppStorage` because the Diamond proxy accesses it via a hashed slot (`keccak256("clan.world.app.storage.v1")`), not as normal declared contract storage. Always inspect a facet (e.g., `CoreFacet`) that has the `AppStorage` struct in scope — this returns the struct's field layout, which is what matters for slot calculations.

The snapshot file is committed to the repo at `packages/contracts/test/snapshots/storage-layout.json`. CI runs a diff check: if the snapshot diverges from `forge inspect CoreFacet storageLayout` output, the PR fails.

**Enforcement:** A `Makefile` target `make storage-snapshot-check` will be added in PR 2. Until then, enforce manually: every LibStorage change requires the reviewer to run `forge inspect CoreFacet` and confirm slot positions are unchanged for existing fields.

### Rule 3: No struct-field reordering, ever

Even "harmless" reordering (swapping two adjacent fields of the same type) changes slot assignments for all fields below them. There is no safe reorder. If a field is in the wrong logical position, add a comment — do not move it.

### Rule 4: Nested struct modification is equally dangerous

Rule 1 says "append to `AppStorage`." Rule 4 extends this: the same append-only constraint applies to **all structs nested inside `AppStorage`**, including `WorldState`, `TreasuryState`, `Clan`, `Clansman`, `Mission`, and `WheatPlot`.

Adding a field inside `WorldState` shifts the storage slots of every `AppStorage` field that comes after it, just as if you had inserted a field in `AppStorage` directly. The snapshot check covers this: `forge inspect` reports the full recursive layout, so any nested-struct change shows up as a diff.

### Stack depth mitigation for large AppStorage

`AppStorage` contains 15+ mappings and structs. Complex facets (GatheringFacet, CoreFacet) that access many fields in one function may hit Solidity's "Stack Too Deep" limit, even with `via_ir = true`.

Mitigation pattern — cache fields into local memory variables at function entry:

```solidity
function _settleClan(uint32 clanId) internal {
    AppStorage storage s = LibStorage.appStorage();
    // Cache frequently accessed fields to reduce stack references:
    Clan storage clan = s.clans[clanId];
    uint64 currentTick = s.world.currentTick;
    // ... function body uses `clan` and `currentTick`, not `s.clans[clanId]` repeatedly
}
```

If a function still hits the stack limit after caching, split it into sub-functions. `via_ir` handles this well — each sub-function is a separate optimizer scope.

**Pre-migration validation (required before PR 2):** Deploy a `MockCoreFacet` that imports the full `AppStorage` and performs a complex calculation accessing 10+ struct fields. If this compiles and passes tests without stack errors, the single-struct approach is confirmed viable. If it hits stack limits, the struct must be split before migration begins.

<!-- TODO: add forge storage-layout snapshot CI step (Makefile target) in PR 2 -->

---

## 6. Heartbeat Failure Model

### Current monolith behavior

In `ClanWorld.sol`, `heartbeat()` is a single transaction. If any internal call reverts, the entire heartbeat reverts. This is the existing behavior — the game loop can be blocked by a bad order or bad state.

### Diamond behavior under delegatecall

In the Diamond, `heartbeat()` lives in CoreFacet. It calls GatheringFacet and MarketFacet via internal Diamond routing (through the proxy's fallback). All calls share the same transaction context via `delegatecall`. This means:

**Revert propagation model:**
- If `GatheringFacet._settleCompletingMissions()` reverts → entire `heartbeat()` tx reverts (same as monolith)
- If `MarketFacet._executeScheduledMarketActions()` reverts → entire `heartbeat()` tx reverts (same as monolith)
- The Diamond does NOT automatically isolate failures between facets. Revert behavior is **identical** to the monolith.

### Isolation improvement opportunity (not in scope for PR 1–3)

The original hybrid plan's heartbeat fragility (DA finding #2 in §1) applies equally here — if a bad market order causes MarketFacet to revert, the heartbeat reverts.

The correct fix is a `try/catch` boundary at the CoreFacet level for the market execution loop:

```solidity
// In CoreFacet.heartbeat():
try IClanWorld(address(this))._executeScheduledMarketActions(tick) {
    // market execution succeeded
} catch (bytes memory reason) {
    emit MarketExecutionFailed(tick, reason);
    // heartbeat continues — market orders dropped for this tick
}
```

This requires `_executeScheduledMarketActions` to be an `external` function (called via the proxy, not as an internal call). Under `delegatecall`, `address(this)` resolves to the Diamond proxy, so this pattern is safe and standard.

### Reentrancy guard interaction with try/catch self-calls

**This is a known architectural constraint.** The `nonReentrant` modifier uses `AppStorage.reentrancyStatus` (set to 2 on entry, reset to 1 on exit). If `heartbeat()` is `nonReentrant` and it calls `_executeScheduledMarketActions` via `IClanWorld(address(this))`, the self-call goes through the Diamond proxy as a new external call — but `reentrancyStatus` is already 2 from the outer `heartbeat()`, causing the inner call to revert.

**Resolution for Phase 3:**

Option A — `heartbeat()` is NOT `nonReentrant`; market executor IS `nonReentrant`.  
Rationale: `heartbeat()` is permissioned (only the engine/cron can call it). The reentrancy risk on `heartbeat()` is negligible. The state-writing inner loop (`_executeScheduledMarketActions`) is the protection target.

Option B — `heartbeat()` IS `nonReentrant`; `_executeScheduledMarketActions` uses an `internalReentrant` flag exempt from the cross-call check.  
More complex — avoid unless Option A has a concrete exploit path.

**Recommended: Option A.** Implement in Phase 3. The Development Invariants rule (§Development Invariants) is adjusted to: "every `external` state-writing function MUST be `nonReentrant` UNLESS it is an orchestrator entry-point that is already access-controlled by role/address check."

**External token callback risk with Option A:** `MarketFacet._executeScheduledMarketActions` calls external token contracts (ERC-20 transfers, pool interactions). A malicious ERC-20 token could call back into `heartbeat()` during the transfer. Since `heartbeat()` is NOT `nonReentrant` under Option A, this is a re-entry vector IF the attacker can cause a malicious token to be added to the treasury.

Mitigation: the treasury token set is set at init time and can only be changed by the owner via `initTreasury`. If all treasury tokens are trusted (owner-controlled, vetted ERC-20s), the callback risk is negligible. **Production constraint: only audited ERC-20 tokens should be registered in the treasury.** If the game ever adds user-supplied token addresses, the reentrancy model must be revisited and Option B applied.

**Current scope:** The `try/catch` isolation is NOT implemented in Phase 1 (skeleton) or Phase 2 (CoreFacet migration). It is a Phase 3 follow-up once the facet split is stable. Rationale: the monolith has the same failure mode today; adding isolation during the migration would conflate two architectural changes.

**Phase 3 action item:** When migrating MarketFacet (PR 3), add `try/catch` isolation for the market execution loop in `heartbeat()`. Use Option A reentrancy model. Document the revert vs. drop decision for each market action type.

<!-- TODO: add try/catch heartbeat isolation in MarketFacet PR (Phase 3) -->

---

## 7. Upgrade Policy Decision

### Options compared

**Mutable Diamond (cuts allowed post-deploy)**
- `DiamondCutFacet` remains in the Diamond, guarded by an owner/multisig
- Future phases (Phase 9 bandits, Phase 10 winter) can be added via `diamondCut` without redeployment
- Requires a key holder (multisig) — adds governance overhead
- Auditors must account for upgrade surface
- Pattern used by: Aavegotchi, many production gaming contracts

**Immutable Diamond (no cuts after deploy)**
- After deploy, remove or zero-out the DiamondCut facet
- Simpler trust model — contract is frozen at deploy bytecode
- If a bug is found, a new Diamond must be deployed (game reset risk)
- Audit surface is smaller (no upgrade key risk)
- Pattern used by: some DeFi protocols where immutability is the selling point

### Decision: Mutable Diamond with 2-of-3 multisig + tiered timelock

ClanWorld is a live game with ongoing phase development (Phase 9 bandits, Phase 10 winter, Phase 11+). Requiring a full game reset to add bandit mechanics is not viable. The mutable pattern is appropriate.

**Tiered timelock policy:**

| Change type | Timelock | Authorization |
|---|---|---|
| Functional upgrade (new facet, feature addition) | 48 hours | 2-of-3 multisig |
| Emergency security patch | 0 hours | 2-of-3 multisig + mandatory post-mortem within 72h |
| Immutable freeze (remove DiamondCut) | 48 hours | 2-of-3 multisig |

**Emergency bypass rationale:** A 48h timelock on a live bug means 2 days of potential game state corruption or fund loss. Teams under pressure bypass governance if no emergency path exists — making the timelock theater. The 2-of-3 emergency bypass with mandatory post-mortem is the responsible pattern. It keeps accountability (all 3 keyholders know an emergency cut happened) while enabling rapid response.

**Hackathon velocity note:** During active pre-mainnet development (current phase), the 48h timelock MAY be reduced to 0 via multisig vote. This must be explicitly re-enabled before any mainnet or public-testnet deployment. Document the timelock state in `packages/contracts/DEPLOYMENT.md`.

Additional safeguards:
1. **2-of-3 multisig guardian** for `diamondCut` ownership. Three keyholders; no single-key risk.
2. **Loupe facet** (ERC-165 + `facets()`, `facetFunctionSelectors()`) stays in the Diamond permanently — any observer can audit the current facet set.

**Open question for Liam:** Does the current team structure support a 2-of-3 multisig? If not, a 1-of-1 owner key + timelock is a viable interim while keeping the mutable path.

---

## 8. Operational Safety

### Initializer locking — atomic via `diamondCut` `_init` parameter

The Diamond standard's `diamondCut` function accepts `_init` (address) and `_calldata` (bytes) parameters. When non-zero, the Diamond calls `_init.delegatecall(_calldata)` in the same transaction as the cut. This is the correct, front-run-proof initialization pattern.

**Do NOT use a separate post-cut `initialize()` call.** If initialization is executed as a separate transaction after `diamondCut`, an attacker can front-run it on any public testnet (or mainnet) and set themselves as owner or corrupt initial treasury state. The window between `diamondCut` succeeding and `initialize()` being called is publicly observable in the mempool.

**Correct pattern:**

```solidity
// DiamondInit.sol — deployed as a separate contract, used once
contract DiamondInit {
    function init(
        address owner,
        address[6] calldata tokens,
        address[4] calldata pools
    ) external {
        AppStorage storage s = LibStorage.appStorage();
        require(!s.initialized, "ClanWorld: already initialized");
        s.initialized = true;
        s.owner = owner;
        // ... set initial treasury, world config ...
    }
}

// In DeployDiamond.s.sol:
DiamondInit diamondInit = new DiamondInit();
bytes memory initData = abi.encodeCall(DiamondInit.init, (owner, tokens, pools));
IDiamondCut(address(diamond)).diamondCut(facetCuts, address(diamondInit), initData);
// ^ initialization happened atomically in the same tx as the cut
```

The `initialized` flag in `AppStorage` prevents re-initialization if a second `diamondCut` call passes a non-zero `_init`. The `DiamondInit` contract is a one-shot helper — it does not need to remain registered as a facet.

<!-- TODO: confirm whether DiamondInit is a standalone contract or the first CoreFacet setup function — decision in PR 2 -->

### Emergency pause policy

ClanWorld does not currently have a pause mechanism. The Diamond's `diamondCut` IS the emergency pause mechanism: replacing CoreFacet's `heartbeat()` selector with a no-op or revert function halts game progression without state migration.

For a more granular pause (e.g., pause market only):
- Replace `MarketFacet` with a `PausedMarketFacet` stub that reverts all market calls
- This is a zero-delay emergency cut (see tiered timelock policy above)

<!-- TODO: consider adding explicit `paused` flag to AppStorage for simpler per-module pause in Phase 5+ -->

### Rollback procedure

If a bad `diamondCut` ships (wrong function selector mapping, broken facet bytecode):

1. **Identify:** `IDiamondLoupe(diamond).facets()` returns current facet set. Compare to last known-good snapshot in `packages/contracts/deployments/`.
2. **Rollback:** Issue a new `diamondCut` that replaces the broken facet with the previous facet deployment address. Old facet deployments are immutable — they remain on-chain.
3. **Timelock:** If timelock is active, rollback cut also requires the timelock delay. This is unavoidable with a standard timelock. The emergency bypass path (2-of-3 multisig, no delay) can be used here.
4. **State:** Facet replacement does NOT revert state changes made by the broken facet. If the broken facet corrupted storage, state repair requires a StorageRepairFacet (custom migration — treat as incident response).

### Ownership transfer

Diamond owner key transfer:
1. New owner prepares transfer via `Ownable.transferOwnership(newOwner)` (or multisig equivalent)
2. 48h timelock applies (functional upgrade tier)
3. New owner accepts transfer
4. Update `packages/contracts/DEPLOYMENT.md` with new owner address

Never transfer ownership to address(0) without first confirming immutable-diamond intent and removing the DiamondCut facet.

---

## 9. Test Migration Strategy

### Current test structure

| File | What it tests |
|---|---|
| `ClanWorld.t.sol` | Main behavior suite — deploy `ClanWorld`, cast to `IClanWorld` |
| `ClanWorldStub.t.sol` | Stub sanity checks |
| `DefendBase.t.sol` | Defense registration / clearing |
| `HeartbeatOrdering.t.sol` | Market tick ordering, heartbeat sequencing |
| `MissionTiming.t.sol` | Mission tick math |
| `Reentrancy.t.sol` | Reentrancy guard verification |
| `RNG.t.sol` | RNG seed distribution |

### Required test categories post-Diamond

The Diamond migration is an architectural rewrite. "Tests mostly need a new deploy helper" understates the requirement. The full test matrix:

| Test category | What it validates | New file / existing file update |
|---|---|---|
| **Deploy helper** | `DeployDiamond.deploy()` returns a functioning `IClanWorld`; all 6 facets registered; all selectors present via Loupe | New: `test/helpers/DeployDiamond.sol` |
| **Selector collision** | No two facets register the same 4-byte selector; `diamondCut` with a duplicate selector reverts | New: `test/DiamondSelectors.t.sol` |
| **Storage layout snapshot** | `forge inspect` output matches committed `test/snapshots/storage-layout.json`; any struct reorder fails the check | New: `test/StorageLayout.t.sol` + snapshot file |
| **Initializer idempotency** | `initialize()` succeeds on first call; reverts on second call; cannot be called by non-owner | New test in `test/DiamondUpgrade.t.sol` |
| **Upgrade (diamondCut)** | Replacing a facet installs new selectors; old selectors removed; state persists across cut | New: `test/DiamondUpgrade.t.sol` |
| **Cross-facet reentrancy** | Reentrancy attempt through GatheringFacet → MarketFacet path is blocked by shared `reentrancyStatus` in AppStorage | New test in `Reentrancy.t.sol` |
| **Revert-data parity** | Key revert strings from monolith surface correctly through Diamond proxy (delegatecall revert bubbling) | New: `test/RevertParity.t.sol` |
| **Facet replacement** | After replacing MarketFacet with a new version, behavior changes as expected; GatheringFacet + CoreFacet unaffected | `test/DiamondUpgrade.t.sol` |
| **Heartbeat isolation** | (Phase 3 follow-up) A reverting market order does not revert the entire heartbeat when `try/catch` isolation is added | `HeartbeatOrdering.t.sol` — add after Phase 3 |
| **Existing behavior suite** | All existing behavior tests pass unchanged (only deploy helper swap needed) | All existing `*.t.sol` files — swap `new ClanWorld()` → `DeployDiamond.deploy()` |
| **Gas regression baseline** | `delegatecall` adds ~700 gas per external call; heartbeat gas must be measured and documented post-migration as the new baseline | New: `test/GasBaseline.t.sol` |

### How existing tests change post-Diamond

**ABI surface is byte-stable.** `IClanWorld` selectors don't change. The same `IClanWorld` interface can be cast to the Diamond proxy address — all existing test assertions remain valid.

**What changes:**
1. **Deploy helper.** All test files currently do:
   ```solidity
   ClanWorld world = new ClanWorld();
   ```
   Post-Diamond, this becomes a `DeployDiamond` helper that deploys all facets + Diamond proxy + runs the initial `diamondCut`. The helper is called once per test setup.

2. **`DeployDiamond.t.sol` helper.** Add `packages/contracts/test/helpers/DeployDiamond.sol`:
   - Deploys `DiamondCutFacet`, `DiamondLoupeFacet`
   - Deploys `CoreFacet`, `MarketFacet`, `GatheringFacet`, `ViewsFacet`, `BanditsFacet`, `WintersFacet`
   - Deploys `Diamond(owner, initialCuts)`
   - Returns `IClanWorld(address(diamond))`
   - Existing test `setUp()` calls are updated to use this helper

3. **Gas fixtures.** `delegatecall` adds ~700 gas per external call through the Diamond. Any test that asserts exact gas consumption needs updating. Tests that only assert behavior (state changes, events) need no changes.

4. **`msg.sender` checks.** The `_executeMarketSellExternal`/`_executeMarketBuyExternal` guards check `msg.sender == address(this)`. In the Diamond, these calls come from the proxy (`address(diamond)`), not the facet. The guard must be updated to check `msg.sender == address(this)` where `this` is the Diamond proxy — this is correct under `delegatecall` since `address(this)` resolves to the proxy.

5. **`nonReentrant` guard.** `ReentrancyGuard` uses a storage slot. In the Diamond it must live in `AppStorage` (add a `uint256 reentrancyStatus` field) so all facets share the same guard. Otherwise each facet has its own reentrancy slot and the guard is ineffective cross-facet.

### Concrete test file changes required

| File | Change needed |
|---|---|
| `ClanWorld.t.sol` | Replace `new ClanWorld()` with `DeployDiamond.deploy()` in `setUp()` |
| `DefendBase.t.sol` | Same deploy change |
| `HeartbeatOrdering.t.sol` | Same deploy change + review gas assertions |
| `MissionTiming.t.sol` | Same deploy change |
| `Reentrancy.t.sol` | Same deploy change; verify cross-facet reentrancy guard works; add cross-facet test |
| `RNG.t.sol` | Same deploy change |
| `ClanWorldStub.t.sol` | No change (tests the stub, not the Diamond) |

---

## 10. Deploy Script Approach

**File:** `packages/contracts/script/DeployDiamond.s.sol`

**Sequence:**
1. Deploy `DiamondCutFacet`
2. Deploy `DiamondLoupeFacet`
3. Deploy `CoreFacet`
4. Deploy `MarketFacet`
5. Deploy `GatheringFacet`
6. Deploy `ViewsFacet`
7. Deploy `BanditsFacet` (stub)
8. Deploy `WintersFacet` (stub)
9. Deploy `DiamondInit` — one-shot initialization contract
10. Assemble `initialDiamondCut` array (all facets) + encode `DiamondInit.init(owner, tokens, pools)` calldata
11. Deploy `Diamond(owner, initialDiamondCut, address(diamondInit), initCalldata)` — all facets cut + state initialized atomically in constructor
12. Verify: call `IDiamondLoupe(diamond).facets()` to confirm all selectors registered

**Note:** `initTreasury()` is NOT called as a separate transaction. Token addresses and pool config are passed to `DiamondInit.init()` which runs atomically in the same tx as `diamondCut`. If token addresses are not known at deploy time (e.g., tokens deployed separately), pass zero addresses to init and use `initTreasury()` as a one-time setup call that checks `s.treasury.initialized == false`.

**Base Sepolia:** The existing `foundry.toml` already has:
```toml
[rpc_endpoints]
base_sepolia = "${RPC_URL_PRIMARY}"
```
No changes needed to `foundry.toml` for the deploy script — the RPC config is already in place.

**Reference pattern:** Nick Mudgen's Diamond-3 (`github.com/mudgen/diamond-3-hardhat`) — the `scripts/deploy.js` shows the single-tx multi-facet cut pattern. The Foundry equivalent uses `IDiamondCut.FacetCut[]` assembled in the script and passed to the `Diamond` constructor.

<!-- TODO: Etherscan/Basescan verification for Diamond artifacts requires per-facet `forge verify-contract` calls — standard single-contract verification flow does not work for proxies. Document verification procedure in DEPLOYMENT.md (PR 6). -->

---

## 11. Development Invariants

These rules apply to ALL contributors on ALL PRs touching facets or LibStorage. Violation of any of these is a blocking PR review finding.

### Checklist

- [ ] **Storage append-only:** New fields added at END of `AppStorage` only. No mid-struct inserts. No field reordering. (See §Storage Safety.)
- [ ] **Storage snapshot updated:** If `LibStorage.sol` or any embedded struct is modified, `test/snapshots/storage-layout.json` is regenerated and committed.
- [ ] **`nonReentrant` on all state-writing externals:** Every `external` function that writes AppStorage state MUST use the `nonReentrant` modifier (backed by `AppStorage.reentrancyStatus`), UNLESS it is an orchestrator entry-point access-controlled by role or address check (e.g., `heartbeat()` which is engine-only). If a facet reads state only (`pure`/`view`), the modifier is not required.
- [ ] **Reentrancy guard is shared:** The `nonReentrant` implementation MUST read/write `AppStorage.reentrancyStatus`. Per-facet reentrancy guards are FORBIDDEN — they do not protect cross-facet re-entry through the Diamond proxy.
- [ ] **No `nonReentrant` on heartbeat orchestrator functions** that use `try/catch` self-calls through the proxy (see §Heartbeat Failure Model — Reentrancy guard interaction). The inner state-writing functions they call ARE `nonReentrant`.
- [ ] **Size check before merge:** Run `forge build --sizes` before opening any migration PR. Confirm each facet runtime bytes < 20,000 B (≥4 KB headroom). If any facet is 20–24 KB, split before merging.
- [ ] **No `ClanWorld.sol` modifications during migration:** The monolith stays untouched until PR 6. All migration PRs add new facet files only.

### Note on library bytecode duplication

Every facet that imports `LibStorage` or other shared helpers gets that library's bytecode compiled into its deployment artifact. Total deployed bytecode across all facets will be higher than the 34,792 B monolith — approximately 57–64 KB total. This is expected and acceptable. EIP-170's 24,576 B limit applies per-contract, not to the sum of all deployed contracts. The goal is per-facet compliance, not minimizing total deployed bytes.

---

## 12. Migration Plan — Phased PRs

| PR | Branch | Content | Criteria |
|---|---|---|---|
| **PR 1** (this PR) | `feat/issue-337-diamond-design` | Design doc + Diamond skeleton (proxy, LibStorage, interfaces, empty facets) | Liam go/no-go on architecture |
| **PR 2** | `feat/issue-337-core-facet` | Migrate CoreFacet (heartbeat shell, clan lifecycle, order submission, travel) + `DeployDiamond` helper + storage snapshot CI + **selector collision tests start here** | All core tests pass; size check clean; no selector collisions |
| **PR 3** | `feat/issue-337-market-gathering` | Migrate MarketFacet + GatheringFacet (settlement engine, gathering, market execution) + heartbeat `try/catch` isolation | Heartbeat + market tests pass; cross-facet reentrancy test passes |
| **PR 4** | `feat/issue-337-buildings-views` | Migrate BuildingsFacet logic into GatheringFacet + ViewsFacet (all aggregators) | Full test suite passes |
| **PR 5** | `feat/issue-337-bandits-winters` | BanditsFacet stub + WintersFacet stub with Phase 9/10 landing zones; upgrade tests | Stubs deploy clean; all new test categories pass |
| **PR 6** | `feat/issue-337-deploy-sepolia` | `DeployDiamond.s.sol`, invariant tests, Base Sepolia deploy + verification | Deployed + verified on Base Sepolia |

After each PR merges to `dev`, the prior `ClanWorld.sol` monolith remains in the repo until PR 6 is merged — at that point it's archived or removed.

---

## 13. Open Questions for Liam

These decisions need explicit sign-off before code migration begins (PR 2+):

1. **Multisig approach for DiamondCut.** Does the current team support a 2-of-3 multisig? If not, is a single owner key + 48h timelock acceptable for the hackathon phase? (The timelock can be reduced to 0 for iteration speed during active development, re-added at mainnet.)

2. **Single AppStorage struct** — confirmed as the approach? (Recommendation: yes, see §4. The alternative adds significant complexity for no benefit given ClanWorld's shared state.)

3. **BanditsFacet scope.** Phase 9 code is not in the repo. Should `BanditsFacet` at PR 5 be: (a) a minimal stub with function signatures only, (b) a full Phase 9 implementation, or (c) deferred entirely to a post-hackathon PR?

4. **WintersFacet scope.** Same question as bandits — Phase 10 winter damage is not yet implemented. PR 5 stub or full Phase 10 in PR 5?

5. **Immutable-Diamond option.** If you prefer a simpler trust model (no upgrade key), we can deploy an immutable Diamond at PR 6 (remove DiamondCut after initial facet registration). Tradeoff: adding Phase 9 bandits requires deploying a new Diamond + migrating state. Confirm mutable vs immutable before PR 2.

6. **`via_ir` flag.** Post-Diamond, each facet is a separate compilation unit. We may be able to drop `via_ir = true` on the facets (significant compile-time reduction). Confirm we should remove it from `foundry.toml` after migration, or keep it for consistency.

---

## 14. Known Limitations

- **Bus factor / onboarding complexity:** Diamond pattern requires developers to understand EIP-2535 routing, AppStorage layout rules, and delegatecall semantics. Mitigated by this doc + Development Invariants checklist. <!-- TODO: add onboarding doc in DEPLOYMENT.md (PR 6) -->
- **Event debugging across facets:** Events emitted by MarketFacet have `address` = Diamond proxy, not the facet. Debugging requires knowing which facet owns which selector. `IDiamondLoupe` makes this queryable. <!-- TODO: add event attribution note to DEPLOYMENT.md -->
- **Etherscan/Basescan verification:** Per-facet verification requires separate `forge verify-contract` calls. Standard proxy verification UI may not display all facet source. Document in DEPLOYMENT.md (PR 6). <!-- TODO: PR 6 -->
- **Alternatives considered:** Satellite pattern (one hub contract dispatching to independently-deployed contracts via interface calls) and custom dispatcher (manual selector→address mapping without EIP-2535) were evaluated. Both require explicit interface stitching that EIP-2535 + Loupe provides natively. Diamond was selected for battle-tested reference implementations and auditor familiarity.

---

## 15. DA History

### Round 1 — 2026-04-30

**Engines:** Codex + Gemini Pro

**Findings summary:**

| ID | Severity | Finding | Disposition |
|---|---|---|---|
| H1 | CRITICAL | Storage layout safety model absent — no append-only rule, no CI snapshot, silent corruption risk | **ADDRESSED** in §Storage Safety |
| H2 | HIGH | Facet size projections are line-count based — no actual compiled measurements | **ADDRESSED** in §Facet Boundaries — actual `forge build --sizes` output added |
| H3 | HIGH | CoreFacet growth risk: Phase 9/10 will blow past limit with zero headroom | **ADDRESSED** — BanditsFacet + WintersFacet explicitly documented as load-bearing separations, not pre-speculative stubs |
| H4 | HIGH | Heartbeat failure isolation not addressed — same game-halt risk as hybrid plan | **ADDRESSED** in §Heartbeat Failure Model — current behavior documented, `try/catch` path specified as Phase 3 follow-up |
| H5 | HIGH | Test plan understated — "tests mostly just need a new deploy helper" is wrong | **ADDRESSED** in §Test Migration Strategy — full 11-category test matrix added |
| M1 | MED | Operational model incomplete — no initializer locking, pause policy, rollback, ownership transfer | **ADDRESSED** in §Operational Safety |
| M2 | MED | Timelock vs. hackathon velocity tension — 48h timelock makes emergency response impossible | **ADDRESSED** in §Upgrade Policy — tiered timelock: 48h functional, 0h emergency with mandatory post-mortem |
| M3 | MED | Library bytecode duplication — total deployed bytecode >80 KB, not acknowledged | **ADDRESSED** in §Development Invariants and §Facet Boundaries — explicitly noted as acceptable, EIP-170 per-contract not total |
| M4 | MED | Reentrancy guard across facets — per-facet guard ineffective for cross-facet re-entry | **ADDRESSED** — `reentrancyStatus` added to AppStorage; invariant rule added in §Development Invariants |
| M5 | MED | Per-facet Diamond Storage not evaluated | **ADDRESSED** in §AppStorage Decision Rationale — explicit comparison + rationale for single AppStorage |
| L1–L5 | LOW | Etherscan verification, bus factor, event debugging, alternatives considered | **DEFERRED** — inline TODO comments added; §Known Limitations added |

### Round 2 — 2026-04-30

**Engines:** Codex + Gemini Pro (gemini-2.5-pro-preview-05-06)

Both engines returned NEEDS WORK on R1 revision.

**Findings summary:**

| ID | Severity | Engine | Finding | Disposition |
|---|---|---|---|---|
| R2-H1 | HIGH | Codex | `nonReentrant` + `try/catch` self-call conflict — heartbeat `try IClanWorld(address(this))._executeScheduledMarketActions` trips shared reentrancy guard if both caller and callee are `nonReentrant` | **ADDRESSED** in §Heartbeat Failure Model — explicit Option A resolution: `heartbeat()` exempt from `nonReentrant`, inner executor is protected; Development Invariants updated |
| R2-H2 | HIGH | Codex + Gemini | Initialization atomicity — post-cut `initialize()` call is front-runnable on public testnet | **ADDRESSED** in §Operational Safety — atomic `_init` parameter in `diamondCut` documented; separate post-cut initialize explicitly forbidden |
| R2-H3 | HIGH | Gemini | Stack Too Deep risk — large single `AppStorage` struct may hit Solidity stack limits in complex facets | **ADDRESSED** in §Storage Safety — cache-into-memory mitigation pattern documented; pre-migration `MockCoreFacet` validation step added |
| R2-H4 | HIGH | Gemini | Nested struct modification equally dangerous — `WorldState` field reorder same risk as top-level `AppStorage` reorder; not covered in R1 | **ADDRESSED** in §Storage Safety Rule 4 |
| R2-M1 | MED | Codex | Off-chain compatibility understated — events, gas profiles, deployment addresses all change, not just ABI | **ADDRESSED** in §Executive Summary — off-chain compatibility note added |
| R2-M2 | MED | Gemini | Multisig deadlock during hackathon — velocity concern; 1-of-1 "God Key" likely in practice | **EXISTING** — §Upgrade Policy already acknowledges 1-of-1 interim option; no further doc change needed |
| R2-L1 | LOW | Codex + Gemini | Size projections still optimistic for CoreFacet/GatheringFacet | Deferred — pre-merge size check gate in Development Invariants already addresses this |
| R2-L2 | LOW | Codex | Delayed Phase 3 heartbeat isolation keeps fragile model during migration | Deferred — acknowledged explicitly in §Heartbeat Failure Model; same failure mode as monolith today |
| R2-L3 | LOW | Codex + Gemini | Alternatives (minimal dispatcher, logic-only facets, data-first redesign) | Deferred — brief note in §Known Limitations |
| R2-L4 | LOW | Gemini | `via_ir` retention for per-facet compilation | Deferred — existing Open Question #6 for Liam |

### Round 3 — 2026-04-30

**Engines:** Codex + Gemini Pro (gemini-2.5-pro-preview-05-06)

Both engines returned NEEDS WORK on R2 revision.

**Findings summary:**

| ID | Severity | Engine | Finding | Disposition |
|---|---|---|---|---|
| R3-H1 | HIGH | Codex | Cross-facet execution model unspecified — "CoreFacet calls GatheringFacet internally" is impossible across contract boundaries; must be library or external self-call | **ADDRESSED** in §Facet Boundaries — "Cross-facet execution model" subsection added; Pattern A (library) vs Pattern B (external self-call) documented; function assignment updated |
| R3-H2 | HIGH | Codex | `forge inspect Diamond` won't capture hashed-slot `AppStorage` — wrong inspect target in §Storage Safety | **ADDRESSED** in §Storage Safety Rule 2 — `forge inspect CoreFacet` specified as correct target; rationale explained |
| R3-H3 | HIGH | Codex | `s.initialized` and `s.owner` referenced in §8 but absent from AppStorage struct definition | **ADDRESSED** — `initialized` and `owner` fields added to AppStorage struct in §4 |
| R3-H4 | MED→HIGH | Codex | Deploy step 11 contradicts atomic init — post-cut `initTreasury()` call violates §8's front-run protection rule | **ADDRESSED** — deploy sequence rewritten; `DiamondInit` handles treasury atomically; conditional path for unknown-token-at-deploy noted |
| R3-H5 | HIGH | Gemini | External token callback re-entry risk with Option A (`heartbeat()` exempt from `nonReentrant`) | **ADDRESSED** in §Heartbeat Failure Model — explicit constraint: treasury tokens must be audited; user-supplied token addresses trigger revisit of reentrancy model |
| R3-M1 | MED | Codex | Selector collision tests deferred to PR 5 — too late, collisions should be caught from PR 2 onward | **ADDRESSED** — migration plan updated; selector collision tests start in PR 2 |
| R3-L1 | LOW | Codex + Gemini | Stack Too Deep concern (same as R2 H3) — caching mitigation insufficient | MockCoreFacet validation step already added in R2; `via_ir` genuinely helps; defer to implementation |
| R3-L2 | LOW | Gemini | DiamondCut race condition — emergency 0h bypass could be overwritten by pending 48h cut | Deferred — operational edge case; document in DEPLOYMENT.md (PR 6) |
| R3-L3 | LOW | Codex + Gemini | "Solve EIP-170 but not runtime scaling/liveness" | Out of scope for this PR; correct observation but architectural restructure not required here |
| R3-L4 | LOW | Codex | Governance model aspirational not engineered | Pending Liam sign-off on multisig approach (Open Question #1); implementation deferred to PR 6 |

---

## References

- [EIP-2535: Diamond Standard](https://eips.ethereum.org/EIPS/eip-2535)
- [Nick Mudgen's Diamond-3 reference implementation](https://github.com/mudgen/diamond-3-hardhat)
- [Aavegotchi Diamond deployment](https://github.com/aavegotchi/aavegotchi-contracts) — largest production Diamond
- DA synthesis: `/home/claude/claudes-world/tmp/20260430-eip170-da-synthesis.md`
- Codex DA raw: `/tmp/da-eip170-codex.txt`
- Gemini Pro DA raw: `/tmp/da-eip170-gemini.txt`
