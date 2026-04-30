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

Diamond (EIP-2535) solves the problem at the root: each facet is an independent contract (≤24,576 B) that shares storage through a deterministic pointer. There is no `delegatecall`-over-library fragility, no inlining guesswork, no 1 KB margin. The ABI surface (`IClanWorld`) stays byte-stable. Off-chain consumers see no change.

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

### Size projection methodology

`ClanWorld` = 34,792 B compiled. Rough line-count distribution:
- Travel / path utilities (lines 103–292): ~190 lines
- Settlement core / gathering (lines 293–860): ~570 lines
- World progression / heartbeat (lines 863–996): ~134 lines
- Clan lifecycle / order submission (lines 999–1356): ~358 lines
- Market execution (lines 1358–1692): ~335 lines
- Treasury / OTC stubs (lines 1694–1757): ~64 lines
- Raw getters (lines 1759–1887): ~129 lines
- Derived / aggregator views (lines 1889–2124): ~236 lines

Diamond proxy itself (~600–800 B) + DiamondCut facet (~2–3 KB) + Loupe facet (~2–3 KB) are infrastructure overhead, not ClanWorld logic.

| Facet | Responsibility | Est. Lines | Projected Size | Margin |
|---|---|---|---|---|
| `CoreFacet` | World clock, heartbeat dispatch shell, clan lifecycle, order submission, travel | ~700 | ~16–18 KB | comfortable |
| `MarketFacet` | Market execution (sell/buy), treasury init/seed, pool routing, OTC stubs | ~420 | ~8–10 KB | large |
| `GatheringFacet` | Settlement core (`_settleClan`, `_settleMissionForClansman`), all gather helpers, deposit, building upgrades | ~600 | ~13–15 KB | comfortable |
| `ViewsFacet` | All `pure`/`view` aggregators: `getWorldSnapshot`, `getClanFullView`, `getMarketState`, `getRegionPopulation`, derived state | ~380 | ~8–10 KB | large |
| `BanditsFacet` | Phase 9 bandit attack/defense (stub for now — `getBanditTroop`, `getActiveBanditView`, `getBanditTargetPreview`) | ~50 stub | ~2–3 KB | very large |
| `WintersFacet` | Phase 10 winter damage, elimination, `finalizeSeason` (stub for now) | ~30 stub | ~1–2 KB | very large |

**Projected total post-Diamond bytecode (excluding infrastructure):** ~50–57 KB spread across 6 facets, each individually under 24,576 B.

Notes:
- Estimates are based on `ClanWorld`'s compiled density (~16 B per source line under `via_ir`). Individual facets may be measurably smaller because smaller compilation units give `via_ir` less to optimize across.
- BanditsFacet and WintersFacet are stubs today. They act as landing zones for Phase 9 and Phase 10 code. Their current compiled size will be tiny (2–3 KB each).
- If `CoreFacet` measures over 20 KB after splitting, move `_buildPath` + `_distMatrix` + `_travelTicks` into a small `TravelFacet` (pure functions only, ~2–3 KB).

### Function assignment by facet

#### CoreFacet — world clock, heartbeat shell, clan lifecycle, order dispatch

From `ClanWorld.sol`:
- `heartbeat()` — calls into GatheringFacet for `_settleCompletingMissions`, delegates market loop to MarketFacet, calls `_resolveWorldEvents`
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

#### BanditsFacet — Phase 9 bandit mechanics (stub now)

Phase 9 is not yet implemented. This facet is a landing zone.

Functions (stubs in ClanWorld.sol that will grow here):
- `spawnBandit(...)` — Phase 9
- `resolveBanditAttack(...)` — Phase 9
- `_pickBanditTarget(...)` — Phase 9

Storage primarily accessed: `_world.activeBanditId`, `_world.nextBanditSpawnEligibleTick`, future `_bandits` mapping

#### WintersFacet — Phase 10 winter damage + elimination (stub now)

Phase 10 is not yet implemented. This facet is a landing zone.

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
    // Constants stored at deploy time (not in IClanWorld; inline here for Diamond)
    // -------------------------------------------------------------------------
    // Note: WHEAT_HARVEST_RATE and MAX_MARKET_ACTIONS_PER_TICK are contract-level
    // constants in ClanWorld.sol; keep as Solidity constants in a shared library,
    // not in AppStorage (constants don't occupy storage slots).
}
```

**Storage slot:** `LibStorage.appStorage()` uses the deterministic slot:
```solidity
bytes32 constant STORAGE_SLOT = keccak256("clan.world.app.storage.v1");
```

This avoids slot 0 collision with any future inherited contracts and matches EIP-2535 best practice.

---

## 5. Upgrade Policy Decision

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

### Decision: Mutable Diamond with 2-of-3 multisig + 48h timelock

ClanWorld is a live game with ongoing phase development (Phase 9 bandits, Phase 10 winter, Phase 11+). Requiring a full game reset to add bandit mechanics is not viable. The mutable pattern is appropriate.

Safeguards to make the mutable pattern trustworthy:
1. **2-of-3 multisig guardian** for `diamondCut` ownership. Three keyholders; no single-key risk.
2. **48-hour timelock** on all cut proposals. The community can observe and react before any facet is replaced.
3. **Loupe facet** (ERC-165 + `facets()`, `facetFunctionSelectors()`) stays in the Diamond permanently — any observer can audit the current facet set.

This mirrors Aavegotchi's approach and is the recommended pattern for game contracts with ongoing feature development.

**Open question for Liam:** Does the current team structure support a 2-of-3 multisig? If not, a 1-of-1 owner key + timelock is a viable interim while keeping the mutable path.

---

## 6. Test Migration Strategy

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

### How tests change post-Diamond

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
| `Reentrancy.t.sol` | Same deploy change; verify cross-facet reentrancy guard works |
| `RNG.t.sol` | Same deploy change |
| `ClanWorldStub.t.sol` | No change (tests the stub, not the Diamond) |

---

## 7. Deploy Script Approach

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
9. Deploy `Diamond(owner, initialDiamondCut)` — all facets added in one tx
10. Verify: call `IDiamondLoupe(diamond).facets()` to confirm all selectors registered
11. Call `IClanWorld(diamond).initTreasury(...)` (if tokens known at deploy time)

**Base Sepolia:** The existing `foundry.toml` already has:
```toml
[rpc_endpoints]
base_sepolia = "${RPC_URL_PRIMARY}"
```
No changes needed to `foundry.toml` for the deploy script — the RPC config is already in place.

**Reference pattern:** Nick Mudgen's Diamond-3 (`github.com/mudgen/diamond-3-hardhat`) — the `scripts/deploy.js` shows the single-tx multi-facet cut pattern. The Foundry equivalent uses `IDiamondCut.FacetCut[]` assembled in the script and passed to the `Diamond` constructor.

---

## 8. Migration Plan — Phased PRs

| PR | Branch | Content | Criteria |
|---|---|---|---|
| **PR 1** (this PR) | `feat/issue-337-diamond-design` | Design doc + Diamond skeleton (proxy, LibStorage, interfaces, empty facets) | Liam go/no-go on architecture |
| **PR 2** | `feat/issue-337-core-facet` | Migrate CoreFacet (heartbeat shell, clan lifecycle, order submission, travel) | All core tests pass |
| **PR 3** | `feat/issue-337-market-gathering` | Migrate MarketFacet + GatheringFacet (settlement engine, gathering, market execution) | Heartbeat + market tests pass |
| **PR 4** | `feat/issue-337-buildings-views` | Migrate BuildingsFacet logic into GatheringFacet + ViewsFacet (all aggregators) | Full test suite passes |
| **PR 5** | `feat/issue-337-bandits-winters` | BanditsFacet stub + WintersFacet stub with Phase 9/10 landing zones | Stubs deploy clean |
| **PR 6** | `feat/issue-337-deploy-sepolia` | `DeployDiamond.s.sol`, invariant tests, Base Sepolia deploy + verification | Deployed + verified on Base Sepolia |

After each PR merges to `dev`, the prior `ClanWorld.sol` monolith remains in the repo until PR 6 is merged — at that point it's archived or removed.

---

## 9. Open Questions for Liam

These decisions need explicit sign-off before code migration begins (PR 2+):

1. **Multisig approach for DiamondCut.** Does the current team support a 2-of-3 multisig? If not, is a single owner key + 48h timelock acceptable for the hackathon phase? (The timelock can be removed for iteration speed during active development, re-added at mainnet.)

2. **Single AppStorage struct** — confirmed as the approach? (Recommendation: yes, see §4. The alternative adds significant complexity for no benefit given ClanWorld's shared state.)

3. **BanditsFacet scope.** Phase 9 code is not in the repo. Should `BanditsFacet` at PR 5 be: (a) a minimal stub with function signatures only, (b) a full Phase 9 implementation, or (c) deferred entirely to a post-hackathon PR?

4. **WintersFacet scope.** Same question as bandits — Phase 10 winter damage is not yet implemented. PR 5 stub or full Phase 10 in PR 5?

5. **Immutable-Diamond option.** If you prefer a simpler trust model (no upgrade key), we can deploy an immutable Diamond at PR 6 (remove DiamondCut after initial facet registration). Tradeoff: adding Phase 9 bandits requires deploying a new Diamond + migrating state. Confirm mutable vs immutable before PR 2.

6. **`via_ir` flag.** Post-Diamond, each facet is a separate compilation unit. We may be able to drop `via_ir = true` on the facets (significant compile-time reduction). Confirm we should remove it from `foundry.toml` after migration, or keep it for consistency.

---

## References

- [EIP-2535: Diamond Standard](https://eips.ethereum.org/EIPS/eip-2535)
- [Nick Mudgen's Diamond-3 reference implementation](https://github.com/mudgen/diamond-3-hardhat)
- [Aavegotchi Diamond deployment](https://github.com/aavegotchi/aavegotchi-contracts) — largest production Diamond
- DA synthesis: `/home/claude/claudes-world/tmp/20260430-eip170-da-synthesis.md`
- Codex DA raw: `/tmp/da-eip170-codex.txt`
- Gemini Pro DA raw: `/tmp/da-eip170-gemini.txt`
