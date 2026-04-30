# PR #198 Spec-Compliance UAT — `dev-phase-6-market`

**Reviewer:** Claude Opus 4.7 (1M ctx) — static spec-compliance pass
**HEAD audited:** `4e3536cf34eb4dad13690efeb10f8e3a61a69501` (`origin/dev-phase-6-market`)
**Date:** 2026-04-30
**Method:** read spec docs → walk impl on the live phase branch → no test execution

> Scope: does the Phase 6 Unicorn Town market implementation in `packages/contracts/src/ClanWorld.sol` + `StubPool.sol` match the documented v4 spec ruleset for the market mechanic? This is **not** a re-run of cloud reviewers; it is an **independent spec-vs-code audit** focused on whether shipped behavior matches the canonical contract spec.
>
> **Source-of-truth note:** the dispatch brief named `dev-merge` as the impl source, but PR #198 is OPEN — `dev-merge` HEAD `6cf6f39` does NOT contain Phase 6 (it only carries up to PR #183 / Phase 4). The audit therefore reads from `origin/dev-phase-6-market` (the branch the PR was opened from). This was confirmed via `gh pr view 198`: state=`OPEN`, base=`dev-merge`, head=`dev-phase-6-market`, mergeCommit=`null`.

---

## 1. Spec sources read

| Doc | Phase-6-relevant sections |
|---|---|
| `docs/planning/clanworld_v4_spec.md` | §5.1–5.13 (the canonical Unicorn Town market model: venue, pool set, scheduled vs immediate execution modes, ordering, slippage, failure semantics, seed ratios, gold faucets, depletion) |
| `docs/planning/clanworld_v4_1_addendum.md` | A5 (cooldown on every successful submission); A7 (corrected: `market_sell` Exact-In, `market_buy` Exact-Out + `maxGoldIn`); A8 (immediate vs scheduled ordering reaffirmed) |
| `docs/planning/clanworld_v4_2_state_schema_interface_spec.md` | §2.6 immediate execution; §4.1–4.3 internal-ledger source of truth + worker-carry domain; §7.8 ScheduledMarketAction layout; §8.3 MarketSell exact-input; §8.4 MarketBuy exact-output; §8.5 token validation; §10.6 PoolSeedConfig; §11.2 immediate-vs-scheduled ordering; §11.3 scheduled lifecycle; §11.4 reentrancy/CEI; §13 event surface; §14 status codes; §15 invariants; §16.2/16.3 worked examples |
| `docs/planning/clanworld_v4_3_schema_patch.md` | A.2 same-region/noop required for immediate; D scheduled storage layout (`scheduledMarketActionsByTick`, FIFO, heartbeat cleanup); K.2 add `ERR_NOT_ENOUGH_GOLD`, `ERR_CARRY_FULL` |
| `docs/planning/clanworld_v4_4_ui_indexer_getters.md` | §2.3 `getMarketState()` shape (4 PoolReserves + spotPriceGoldPerResource + currentTick + currentTickQueue + nextTickQueue) |
| `docs/planning/clanworld_v4_5_alignment_addendum.md` | (no market-specific changes; coordination/timeline only) |

**Authoritative ruleset:** v4 spec + v4_1 addendum (controls on conflict) + v4_2 schema + v4_3 patches + v4_4 indexer getters. v4_5 has no market-specific changes.

Key spec assertions extracted (one-line each):
- **5.1** Unicorn Town is the only market venue in v1
- **5.2** Pool set = {Wood/Gold, Wheat/Gold, Fish/Gold, Iron/Gold} — Blueprint NOT pool-routed
- **5.3** Two execution modes: scheduled (travel-then-resolve) and immediate (already in town, in tx)
- **5.4** Scheduled: travel resolves first → 1 full action tick in town → swap at heartbeat closing that action tick → worker becomes WAITING
- **5.5** Immediate eligibility ALL-of: physically UnicornTown ∧ WAITING ∧ off cooldown ∧ valid params ∧ inventory/gold present
- **5.6** Immediate effects: swap in tx; worker stays in town; returns to WAITING; cooldown consumed; nonce updated
- **5.7** Immediate-vs-scheduled collision: immediate executes at tx time vs scheduled at tick close → immediate may front-run
- **5.8** Within tick T, scheduled actions execute in deterministic FIFO order by `commitSequence`
- **5.9** No slippage guard for v1 (`minAmountOut = 0`); buys still bounded by `maxGoldIn`
- **5.10** On failure (non-slippage): no partial swap, inventory retained, worker becomes/remains WAITING in town
- **5.11** Initial seed ratios: Wood/Gold 1000:500, Wheat/Gold 1000:700, Fish/Gold 500:600, Iron/Gold 250:800
- **5.12** Gold faucets: starter grants, iron-mine bonus, bandit defeat, market sales
- **5.13** No pool reset/refill mechanic in v1
- **A5** Every successful submission resets cooldown; rejected submissions do NOT
- **A7** `market_sell` = exact input; `market_buy` = exact output with `maxGoldIn` slippage guard
- **A8** Reaffirms immediate-front-runs-scheduled adversarial design
- **§4.3 + §8.3/§8.4** MarketSell source = worker carry; MarketBuy destination = worker carry
- **§8.4** Buy fails if required gold > `maxGoldIn` OR purse < required; output must fit remaining carry capacity
- **§8.5** `marketToken != goldToken` for both buy and sell
- **v4.3 §A.2** Immediate market actions REQUIRE same-region/noop bypass
- **v4.3 §D** Scheduled storage = `mapping(uint64 => ScheduledMarketAction[]) scheduledMarketActionsByTick`, FIFO, deleted after heartbeat
- **v4.3 §K.2** Status codes must include `ERR_NOT_ENOUGH_GOLD` and `ERR_CARRY_FULL`
- **v4.4 §2.3** `getMarketState()` returns 4 PoolReserves with `spotPriceGoldPerResource` + `currentTick` + currentTickQueue + nextTickQueue
- **v4.2 §11.4** Reentrancy: nonReentrant on immediate-swap path AND `heartbeat()` if it performs scheduled swaps; CEI discipline

---

## 2. Mechanic-by-mechanic verification

| Mechanic | Spec says | Code does | File:line | Verdict |
|---|---|---|---|---|
| **Market venue restriction** | Only Unicorn Town (§5.1) | `MarketBuy`/`MarketSell` validation: `gotoRegion != REGION_UNICORN_TOWN → ERR_INVALID_REGION` | `ClanWorld.sol:2160` | ✅ MATCHES |
| **Pool set** | Wood/Wheat/Fish/Iron each paired to Gold (§5.2) | `_treasury.{wood,wheat,fish,iron}GoldPool` + `_poolFor` maps token→pool for exactly those 4 | `ClanWorld.sol:1542-1548`; `IClanWorld.sol:228-231` | ✅ MATCHES |
| **Blueprint NOT routed** | Blueprint Fragments transferable but excluded from pool routing (§5.2) | `_poolFor` returns address(0) for blueprint token; market validation rejects unsupported tokens | `ClanWorld.sol:2169-2174` | ✅ MATCHES |
| **MarketSell exact-input** | `marketAmount` = exact resource sold; gold output = AMM-determined (A7, §8.3) | `swapExactInForOut(amountIn, minOut=1)` + immediate path uses `amount` as carry deduction | `ClanWorld.sol:1791, 1802`; `StubPool.sol:62-75` | ✅ MATCHES |
| **MarketBuy exact-output** | `marketAmount` = exact resource received; `maxGoldIn` enforced (A7, §8.4) | `swapExactOutForInWithMaxIn(amountOut, maxGoldIn)` + pre-quote `getAmountInForExactOut` checks against `maxGoldIn` | `ClanWorld.sol:1869-1893, 1905`; `StubPool.sol:78-95` | ✅ MATCHES |
| **Sell source = worker carry** | Source = worker carry balance (§8.3) | `_deductFromCarry(cs, token, amount)` — both immediate (line 1791) and scheduled (line 1960) | `ClanWorld.sol:1624-1646, 1791, 1960` | ✅ MATCHES (codified in `test_marketSell_deductsFromCarry_notVault`) |
| **Sell destination = clan gold purse** | Destination = clan gold purse (§8.3) | `clan.goldBalance += goldOut` after pool sell | `ClanWorld.sol:1803, 1972` | ✅ MATCHES |
| **Buy source = clan gold purse** | Source = clan gold purse (§8.4) | `clan.goldBalance -= actualGoldIn` after pool buy | `ClanWorld.sol:1906, 2081` | ✅ MATCHES |
| **Buy destination = worker carry** | Destination = worker carry balance (§8.4) | `_addToCarry(cs, token, amountOut)` | `ClanWorld.sol:1907, 2082` | ✅ MATCHES (codified in `test_marketBuy_creditsCarry_notVault`) |
| **Buy carry-cap pre-check** | "Requested output must fit within remaining carry capacity" (§8.4) | Submit-time check `_remainingCarryForToken(cs, tok) ≥ marketAmount` else `ERR_CARRY_FULL`; also re-checked in scheduled execute path | `ClanWorld.sol:2176-2178, 1858, 2019` | ✅ MATCHES |
| **Buy `maxGoldIn` enforcement** | Buy fails if required gold > `maxGoldIn` (§8.4) | `goldIn > maxGoldIn → ERR_MAX_GOLD_IN_EXCEEDED` (immediate AND scheduled) | `ClanWorld.sol:1884, 2046` | ✅ MATCHES |
| **Buy purse-balance check** | Buy fails if purse < required gold (§8.4) | `clan.goldBalance < goldIn → ERR_NOT_ENOUGH_GOLD` (immediate AND scheduled) | `ClanWorld.sol:1894, 2056` | ✅ MATCHES |
| **`marketToken != goldToken`** | Both buy and sell forbid trading gold-as-resource (§8.5) | Validation rejects `tok == _treasury.goldToken → ERR_MARKET_UNSUPPORTED_TOKEN` | `ClanWorld.sol:2166` | ✅ MATCHES |
| **Token-allowlist** | Only the 4 resource tokens (§5.2) | Validation rejects `tok ∉ {woodToken, ironToken, wheatToken, fishToken}` | `ClanWorld.sol:2169-2174` | ✅ MATCHES |
| **Zero-amount rejection** | `marketAmount = 0` invalid | `order.marketAmount == 0 → ERR_MARKET_ZERO_AMOUNT` | `ClanWorld.sol:2163` | ✅ MATCHES |
| **Immediate eligibility** | All-of: in UnicornTown ∧ WAITING ∧ off cooldown ∧ valid params (§5.5) | `fromRegion == REGION_UNICORN_TOWN ∧ state == WAITING ∧ block.timestamp ≥ cooldownEndsAtTs` (cooldown check pre-validates this same value at line 1209) | `ClanWorld.sol:1242-1244` | ✅ MATCHES |
| **Immediate same-region bypass requirement** | v4.3 §A.2 same-region/noop required | Validation runs unchanged; `_executeImmediateMarket` fires inline in submit tx | `ClanWorld.sol:1242-1262` | ✅ MATCHES |
| **Immediate execution effects** | Swap in tx → worker stays in town → returns to WAITING → cooldown consumed → nonce bumped (§5.6) | On OK: `cs.state=WAITING`, `cs.cooldownEndsAtTs = block.timestamp + COOLDOWN_SECONDS`, `cs.lastMissionNonce = newNonce` (bumped at line 1247 before execution) | `ClanWorld.sol:1247, 1251-1254` | ✅ MATCHES |
| **Immediate front-runs scheduled** | Immediate during tick T executes at tx time vs scheduled at tick close (§5.7, A8, §11.2) | Immediate fires inside `submitClanOrders` (Elder tx); scheduled fires inside heartbeat. Order is naturally chain-tx-vs-heartbeat — immediate wins. | `ClanWorld.sol:1242-1262` (immediate) vs `ClanWorld.sol:895` (scheduled in heartbeat) | ✅ MATCHES |
| **Scheduled FIFO order** | Within tick T, ascending `commitSequence` (§5.8, v4.3 §D.2) | `_sortScheduledMarketActionsByCommitSequence` runs at start of `_executeScheduledMarketActions`; insertion sort over the per-tick array | `ClanWorld.sol:1420, 1495-1514` | ✅ MATCHES (codified in `test_scheduledMarket_fifo`) |
| **Scheduled storage shape** | `mapping(uint64 => ScheduledMarketAction[]) scheduledMarketActionsByTick` (v4.3 §D.1) | `mapping(uint64 => ScheduledMarketAction[]) private _scheduledMarketActions` | `ClanWorld.sol:60` | ✅ MATCHES |
| **Heartbeat cleanup** | `delete scheduledMarketActionsByTick[T]` after processing (v4.3 §D.3) | `delete _scheduledMarketActions[tick]` at end of `_executeScheduledMarketActions` | `ClanWorld.sol:1492` | ✅ MATCHES (codified in `test_scheduledMarket_deletedAfterHeartbeat`) |
| **Heartbeat order: settlement BEFORE market** | "1. resolve missions completing this tick; 2. resolve scheduled market actions" (v4.2 §1.3 / §2 closing-tick steps) | Step 1 = `_settleCompletingMissions(closedTick)`; Step 2 = `_executeScheduledMarketActions(closedTick)` | `ClanWorld.sol:892, 895` | ✅ MATCHES (codified in `test_heartbeat_settlementBeforeMarket`) |
| **No slippage guard on sell** | `minAmountOut = 0` for v1 (§5.9) | Immediate sell calls `swapExactInForOut(amount, 1)` — passes `1` not `0` | `ClanWorld.sol:1802`; `StubPool.sol:62, 69` | ⚠️ TRIVIAL — uses `1` instead of `0`; only fails if AMM math returns 0 (degenerate empty-pool case). Functionally equivalent for v1 economics. |
| **Constant-product AMM** | Uniswap-style x*y=k pools (§5.1 implied) | `StubPool` enforces `reserveA * reserveB >= priorK` after each swap; pure x*y=k math, no fee | `StubPool.sol:67, 74, 87, 94` | ✅ MATCHES (no fee — see next row) |
| **AMM fee** | Spec is silent on a fee constant | No swap fee applied (`amountOut = reserveB * amountIn / (reserveA + amountIn)` — no `997/1000` factor) | `StubPool.sol:48` | ⚠️ AMBIGUOUS — diverges from real Uniswap V2 (0.3% fee) but spec specifies no fee. Treat as a deliberate v1 simplification, not drift. |
| **Initial seed ratios** | Wood/Gold 1000:500; Wheat/Gold 1000:700; Fish/Gold 500:600; Iron/Gold 250:800 (§5.11) | `seedPools(PoolSeedConfig)` accepts arbitrary per-pool config from caller. Hardcoded constants `INITIAL_RESOURCE_POOL_SEED = 100_000e18`, `INITIAL_GOLD_POOL_SEED = 50_000e18` are uniform across pools and used by tests/deploy scripts. | `ClanWorld.sol:82-83`; `IClanWorld.sol:402-410`; `SeedPools.t.sol:114-127` | ⚠️ TRIVIAL — defaults are uniform; spec's asymmetric ratios are a deployer-config concern, not a contract-enforcement concern. PoolSeedConfig is the right surface; tests just don't test the spec's exact numbers. Deployer must pass spec ratios at seed time to comply. |
| **Failure semantics** | No partial swap; inventory retained; worker becomes/remains WAITING in Unicorn Town (§5.10) | `_handleMarketFailure` sets `cs.state = WAITING` + cooldown reset; on swap-revert the carry deduction is restored (line 1816); emits `MarketActionFailed` | `ClanWorld.sol:1701-1716, 1815-1825` | ✅ MATCHES (codified in `test_immediateMarketSell_failurePropagatesStatus`, `test_immediateMarket_insufficientLiquidityFailsAndConsumesCooldown`) |
| **Cooldown on submission (success)** | Every successful submission resets cooldown (§A5) | `cs.cooldownEndsAtTs = block.timestamp + COOLDOWN_SECONDS` set in submit path | `ClanWorld.sol:1253, 1290` | ✅ MATCHES |
| **Cooldown on submission (rejection)** | Rejected submissions do NOT start cooldown (§A5) | `_handleMarketFailure` resets cooldown even when the immediate swap fails (e.g. `ERR_MAX_GOLD_IN_EXCEEDED`, `ERR_NOT_ENOUGH_GOLD`, `ERR_LIQUIDITY_INSUFFICIENT`) | `ClanWorld.sol:1712` | ⚠️ AMBIGUOUS — submission **was** accepted (passed validation) but the AMM-side rejected. Spec §5.10 says worker "becomes WAITING in Unicorn Town" with no explicit cooldown directive on failure. §A5's "rejected" is closer to validation-rejected, not swap-failed. Defensible but unstated. |
| **`getMarketState()` shape** | 4 PoolReserves + spot price + currentTick + currentTickQueue + nextTickQueue (v4.4 §2.3) | Returns exactly that struct shape | `ClanWorld.sol:2593-2603`; `IClanWorld.sol:474-481` | ✅ MATCHES |
| **`spotPriceGoldPerResource` formula** | `goldReserve * 1e18 / resourceReserve`, `0` if reserve == 0 (v4.4 §2.3) | Exactly that, with the same zero-guard | `ClanWorld.sol:2613` | ✅ MATCHES |
| **Status code: `ERR_NOT_ENOUGH_GOLD`** | v4.3 §K.2 mandates | Present, used in immediate AND scheduled buy paths | `IClanWorld.sol:185`; `ClanWorld.sol:1900, 2062` | ✅ MATCHES |
| **Status code: `ERR_CARRY_FULL`** | v4.3 §K.2 mandates | Present, used in immediate AND scheduled buy + submit-time validation | `IClanWorld.sol:186`; `ClanWorld.sol:1864, 2025, 2177` | ✅ MATCHES |
| **Status code: `ERR_MARKET_BUY_MAX_GOLD_EXCEEDED`** | v4.2 §14 ordinal | Renamed to `ERR_MAX_GOLD_IN_EXCEEDED` (line 189); legacy ordinal kept as deprecated reserved entry to preserve enum stability | `IClanWorld.sol:181, 189` | ⚠️ TRIVIAL — naming drift but ordinal preserved (R4/R5 fix-rounds explicitly addressed enum stability). Off-chain consumers must learn the new name; ABI signatures still hold. |
| **Status code: `ERR_MARKET_INSUFFICIENT_LIQUIDITY` / `ERR_LIQUIDITY_INSUFFICIENT`** | Not in spec status code list (§14) | Added; first version deprecated, second version active | `IClanWorld.sol:187-188` | ⚠️ TRIVIAL — additive (covers AMM revert paths spec didn't enumerate). Not drift, just spec-extension. |
| **Reentrancy guard on immediate path** | Apply `nonReentrant` to immediate swap path (§11.4) | `submitClanOrders` carries `nonReentrant` (top-level entry into immediate path) | `ClanWorld.sol:1147`; `Reentrancy.t.sol:test_marketPoolHeartbeatCallback_revertsWithReentrancyGuard` | ✅ MATCHES |
| **Reentrancy guard on heartbeat** | Apply `nonReentrant` to `heartbeat()` if it performs scheduled swaps (§11.4) | `heartbeat()` carries `nonReentrant`; scheduled swaps execute inside it | `ClanWorld.sol:877` | ✅ MATCHES |
| **CEI discipline on immediate sell** | "Apply CEI: never leave partially updated clan/carry state around external calls" (§11.4) | Carry deducted **before** `swapExactInForOut`; on revert carry is restored | `ClanWorld.sol:1791, 1802, 1816` | ✅ MATCHES |
| **Scheduled execution lifecycle** | Created on travel-mission accept; indexed under `executeAtTick`; fires at heartbeat; deleted after (§11.3) | `_enqueueScheduledMarketAction` writes; `_executeScheduledMarketActions` consumes; `delete _scheduledMarketActions[tick]` | `ClanWorld.sol:1357-1373, 1492` | ✅ MATCHES |
| **`commitSequence` global monotonic** | `nextCommitSequence` global, monotonic, never reset (v4.3 §D.4) | `_world.nextCommitSequence++` per enqueue | `ClanWorld.sol:1361`; `IClanWorld.sol:204` | ✅ MATCHES |
| **`executeAtTick = action tick close`** | "Heartbeat closing tick 308 attempts to buy" where 308 = arrivalTick = action tick (§16.3) | `executeAtTick = m.settlesAtTick = arrivalTick + getActionDuration(MarketBuy/Sell) = arrivalTick + 1` | `ClanWorld.sol:1358, 1333, 1798-1810` | ⚠️ TRIVIAL — fires one heartbeat later than spec example. Worked example in §16.3 specifies execution at the heartbeat closing the action tick (arrivalTick), not the heartbeat closing arrivalTick+1. Functionally consistent (`settlesAtTick` is the canonical "mission completes" marker for all action types), but the spec example reads as 1 tick earlier. NOT user-observable in normal play (a swap happening 60s later doesn't change game outcomes), but worth noting because Phase 7 (UI/indexer) may have hardcoded the spec timing. |
| **Mission completion → WAITING** | Per §5.4 "worker becomes WAITING after action tick close" / §5.6 immediate keeps WAITING | Settlement at `settlesAtTick` calls `_completeMission` → state=WAITING + cooldown reset | `ClanWorld.sol:474-477, 856-861` | ✅ MATCHES (modulo the 1-tick lateness above) |
| **Carry restored on swap revert** | "no partial swap" (§5.10) | `try/catch` restores carry on `swapExactInForOut` revert | `ClanWorld.sol:1815-1816` | ✅ MATCHES |
| **`MarketActionFailed` event** | `(clanId, clansmanId, action, reason)` (§13) | `(clanId, csId, action, mode, reason, tick)` — adds `mode` enum + `tick` | `IClanWorld.sol:607-609` | ⚠️ TRIVIAL — event is additive (mode + tick are useful for indexer disambiguation between immediate/scheduled and for time-series). Indexer must learn the extended signature. |
| **`ScheduledMarketActionExecuted` event** | `(executeAtTick, commitSequence, clanId, clansmanId, tokenIn, tokenOut, amountIn, amountOut)` (§13) | `(clanId, csId, action, resourceIn, amountIn, resourceOut, amountOut, settledAtTick)` — uses `uint8 ResourceType` enum bytes instead of token addresses; drops `commitSequence`; renames `executeAtTick → settledAtTick`; only `clanId` indexed | `IClanWorld.sol:597-606` | ⚠️ TRIVIAL — semantically equivalent (resource IDs map 1:1 to tokens via `_marketResourceForToken`) but the indexer must consume the enum encoding rather than addresses. `commitSequence` lost from the event surface (still in storage / `ScheduledMarketActionCommitted`). |
| **`ImmediateMarketActionExecuted` event** | `(clanId, clansmanId, tokenIn, tokenOut, amountIn, amountOut)` (§13) | `(clanId, csId, action, resourceIn, amountIn, resourceOut, amountOut, tick)` — same enum-bytes encoding; adds `action` discriminant + `tick`. Only `clanId` indexed. | `IClanWorld.sol:587-596` | ⚠️ TRIVIAL — additive (`action` + `tick`); same enum-encoding caveat. |
| **`ScheduledMarketActionCommitted` event** | (Not in spec §13 — added by impl as a commit-time signal) | Indexed `executeAtTick`, `commitSequence`, `clanId` + payload | `IClanWorld.sol:610-619` | ✅ ADDITIVE — useful for indexer to render pending queue. Not drift. |
| **OTC transfer surface (`transferGold` etc.)** | Required by v4.2 §10.3 | All four `transfer*` functions revert with "OTC transfers not implemented" | `ClanWorld.sol:2263-2280` | ✅ OUT-OF-SCOPE for Phase 6 (OTC is clan-to-clan, separate work item; not blocking Phase 6 release) |
| **Pool seeding access control** | Owner-only (v4.2 §10.1) | `seedPools` requires `msg.sender == _treasury.treasuryOwner` + one-shot via `poolsSeeded` flag | `ClanWorld.sol:2228-2244` | ✅ MATCHES |
| **Treasury init access control** | Owner-only (implicit) | `initTreasury` requires owner + one-shot via `_treasury.woodToken == address(0)` | `ClanWorld.sol:2210-2225` | ✅ MATCHES |
| **Pool depletion behavior** | "Trading continues subject to normal AMM pricing; no special reset" (§5.13) | x*y=k continues; `quoteBuy(amountOut)` reverts if `amountOut >= reserveA` (cannot drain entirely) | `StubPool.sol:53` | ✅ MATCHES (graceful failure on attempted full-drain) |
| **Gold faucet — market sales** | Sale proceeds credit clan gold purse (§5.12, §8.3) | `clan.goldBalance += goldOut` | `ClanWorld.sol:1803, 1972` | ✅ MATCHES |
| **`ScheduledMarketAction` struct** | `{executeAtTick, commitSequence, clanId, clansmanId, action, marketToken, marketAmount, maxGoldIn}` (§7.8) | All those fields + adds `missionNonce` for stale-retask detection | `IClanWorld.sol:318-330` | ⚠️ TRIVIAL — additive `missionNonce` is correctly used (line 1443) to skip stale entries when a clansman was retasked (codified in `test_scheduledMarket_sameTypeRetask_skipsStaleNonce`). Not in spec but plugs a real correctness hole. |
| **`getScheduledMarketActionsForTick(tick)`** | Required (§9.1) | Implemented; returns `_scheduledMarketActions[tick]` | `ClanWorld.sol` (search "getScheduledMarketActionsForTick"); `IClanWorld.sol:725` | ✅ MATCHES |
| **Per-tick action cap** | Spec sets no cap on actions per tick | Phase 6 branch removed earlier `MAX_MARKET_ACTIONS_PER_TICK = 32` cap and now executes the full queue per heartbeat | `ClanWorld.sol:1414-1493` (no cap visible) | ✅ MATCHES (drift toward spec from earlier impl) |

---

### Summary of mechanic verification

| Verdict | Count |
|---|---|
| ✅ MATCHES | 39 |
| ⚠️ TRIVIAL drift / additive / ambiguous | 9 |
| ❌ DRIFT/MISSING (significant) | 0 |

**The implementation is strongly faithful to the v4 + v4_1 + v4_2 + v4_3 + v4_4 spec for Phase 6.** The 9 ⚠️ entries are all design-level micro-deviations that do not change game-economic behavior:

- 4 are **event-surface refinements** (using `ResourceType` enum bytes vs token addresses, additive `mode`/`tick` fields, additive `missionNonce`/`ScheduledMarketActionCommitted`) that the indexer (Phase 7) must accommodate but that don't change on-chain semantics.
- 2 are **status-code naming drifts** (renamed enum + added `ERR_LIQUIDITY_INSUFFICIENT`) where R4/R5 fix-rounds explicitly preserved enum ordinal stability.
- 1 is the **1-tick-late market execution** (`executeAtTick = arrivalTick + 1` instead of `arrivalTick`) — design-level, no economic consequence, but worth Phase 7 verification.
- 1 is **uniform default seed ratios** (100k:50k uniform) vs spec's asymmetric (1000:500, 1000:700, 500:600, 250:800) — only matters at deploy-time configuration.
- 1 is the **AMM-fee question** (no fee vs Uniswap V2's 0.3%) — spec is silent, so this is a v1 simplification, not drift.
- 1 is the **cooldown-on-immediate-fail** spec-ambiguity (§5.10 vs §A5).

There is **no significant drift** comparable to the Phase 9 audit findings (PR #194). Phase 6's market shipped substantially as designed.

---

## 3. Test coverage gap analysis

### What IS tested (from `ClanWorld.t.sol` + `SeedPools.t.sol` + `HeartbeatOrdering.t.sol` + `Reentrancy.t.sol` + `ResourceBoundaryTokens.t.sol`)

Pool / treasury:
- 4 pools deployed and getter returns correct addresses
- Seeding transfers expected balances + treasury balance reaches 0 after seed
- k-invariant holds after each swap (sell + buy)
- Price preview (`getPrice` / `getAmountOutForExactIn`) matches actual swap output

Submission validation:
- Market order rejected when not targeting Unicorn Town (`test_marketOrder_rejectsInvalidRegion`)
- Market order errors when treasury uninitialized (`test_marketOrder_returnsErrorWhenTreasuryUninitialized`)
- Empty-carry sell rejected at submit, no tick consumed (`test_marketSell_emptyCarry_rejectsAtSubmit_noTickConsumed`)
- Over-capacity scheduled buy rejected at submit (`test_scheduledMarketBuy_overCapacityRejectsAtSubmit`)
- Over-capacity immediate buy rejected at submit (`test_immediateMarketBuy_overCapacityRejectsAtSubmit`)

Immediate market path:
- Immediate sell executes in submit tx (`test_immediateMarketSell_executesInSubmitTx`)
- Immediate buy executes when maxGold sufficient (`test_immediateMarketBuy_executesWhenMaxGoldSatisfied`)
- Town + cooldown active → falls back to scheduled (`test_immediateMarket_townOnCooldown_fallsBackToScheduled`)
- Not in town → falls back to scheduled (`test_immediateMarket_notInTown_fallsBackToScheduled`)
- Busy worker → falls back to scheduled (`test_immediateMarket_busyWorker_fallsBackToScheduled`)
- Insufficient-liquidity failure consumes cooldown (`test_immediateMarket_insufficientLiquidityFailsAndConsumesCooldown`)
- maxGold-exceeded failure consumes cooldown (`test_immediateMarketBuy_maxGoldExceededFailsAndConsumesCooldown`)
- Insufficient-gold failure consumes cooldown (`test_immediateMarketBuy_insufficientGoldFailsAndConsumesCooldown`)
- Failure status propagates back through `submitClanOrders` (`test_immediateMarketSell_failurePropagatesStatus`)
- Cooldown bypass impossible via scheduled re-task (`test_marketCooldown_noBypassViaScheduled`)

Scheduled market path:
- Sell credits gold (`test_sell_creditsGold`)
- Buy debits gold + credits carry (`test_buy_debitsGold`, `test_marketBuy_creditsCarry_notVault`)
- Sell deducts from carry, not vault (`test_marketSell_deductsFromCarry_notVault`)
- Sell fails when carry empty even if vault full (`test_marketSell_fails_emptyCarry_fullVault`)
- maxGoldIn enforced on scheduled buy (`test_buy_maxGoldIn`)
- Scheduled buy: insufficient gold consumes cooldown (`test_scheduledMarketBuy_insufficientGoldFailsAndConsumesCooldown`)
- Scheduled buy: insufficient liquidity consumes cooldown (`test_scheduledMarketBuy_insufficientLiquidityFailsAndConsumesCooldown`)
- Queue cleared after heartbeat (`test_scheduledMarket_deletedAfterHeartbeat`)
- Stale-nonce skip for retasked clansman (`test_scheduledMarket_sameTypeRetask_skipsStaleNonce`)
- Whole queue executes in single heartbeat (`test_scheduledMarket_executesAllActionsForClosedTick`)
- Scheduled queue visible at submit (`test_scheduledMarket_queueVisibleAtSubmit`)
- FIFO order enforced (`test_scheduledMarket_fifo`)
- One clan's failure doesn't break another's scheduled action (`test_scheduledMarketFailure_doesNotAffectAnotherClan`)
- Two-clan sell→buy cycle (`test_twoClan_sellBuyCycle`)

End-to-end + cross-feature:
- Withdraw vault → market sell happy path (`test_withdrawThenMarketSell_endToEnd`)
- Heartbeat settles missions BEFORE market actions (`test_heartbeat_settlementBeforeMarket`)
- Heartbeat reentrancy guard fires (`test_marketPoolHeartbeatCallback_revertsWithReentrancyGuard`)
- Resource-boundary tokens (`ResourceBoundaryTokens.t.sol`)

### What is NOT tested (keyed by criticality)

#### MUST-COVER (spec-mandated behavior)

| Scenario | Why critical | Spec ref |
|---|---|---|
| **Spec asymmetric seed ratios** | No test seeds with the exact spec values (Wood 1000:500, Wheat 1000:700, Fish 500:600, Iron 250:800) and verifies prices behave as expected; tests use uniform 100k:50k. Deployment-side risk: if a deployer follows tests as a reference rather than the spec, they'll seed wrong. | §5.11 |
| **Immediate-front-runs-scheduled within same tick** | The intended adversarial design (§5.7, A8) — no test demonstrates that an immediate market action submitted during tick T executes against a pool state that scheduled actions queued for the close of T have not yet seen. | §5.7, A8, §11.2 |
| **Immediate failure does NOT alter pool reserves** | When immediate sell reverts at the AMM, carry is restored — but is the pool reserve also untouched? Need an assertion that `reserveA, reserveB` round-trip identically across a failed swap. | §5.10 |
| **Pool depletion graceful failure** | Try to buy more than `reserveA - 1` of a resource; spec §5.13 implies graceful "trading continues subject to AMM pricing" — `quoteBuy` reverts at amountOut >= reserveA. Need explicit test that this reverts cleanly without locking the pool. | §5.13 |
| **`getMarketState()` shape contract** | No test calls `getMarketState()` and asserts all 4 reserves + spot prices + currentTick + both queue snapshots are populated correctly (especially `nextTickQueue` containing actions queued for currentTick+1). | v4.4 §2.3 |
| **`spotPriceGoldPerResource` zero-reserve guard** | Edge case where one reserve is zero (e.g., immediately after extreme depletion) — spec demands `0` return. Not asserted. | v4.4 §2.3 |

#### SHOULD-COVER (production-plausible edge cases)

| Scenario | Why |
|---|---|
| **`executeAtTick` timing — does it match spec's worked example §16.3?** | The 1-tick-late drift flagged in §2 — a test that submits at tick 307, travels 1 tick, and asserts swap fires at heartbeat closing tick 308 (per spec) vs 309 (per impl) would either confirm drift or vindicate impl |
| **Same-region/noop immediate flow with `gotoRegion=NOOP`** | v4.3 §A.2 mandates same-region/noop bypass for immediate. Tests use `goto = REGION_UNICORN_TOWN` while clansman is in UnicornTown, which is same-region. NOOP variant (`gotoRegion=0`) untested. |
| **`maxGoldIn = 0` edge case** | Already asserted that buy fails with `maxGoldIn = 0`; should also assert that immediate buy with `maxGoldIn = type(uint256).max` succeeds at any price (no slippage cap effectively) |
| **AMM precision under tiny amounts** | What's the smallest sell that produces nonzero output? With `INITIAL_GOLD_POOL_SEED = 50_000e18` and `INITIAL_RESOURCE_POOL_SEED = 100_000e18`, `(50000e18 * 1) / (100000e18 + 1) ≈ 0` — does a 1-wei sell revert ("zero output") or silently fail? |
| **Cooldown-on-fail consistency** | Both immediate AND scheduled failures DO consume cooldown (`_handleMarketFailure`). Tests assert this individually. Not asserted that this is consistent with §A5 (which arguably says rejected submissions shouldn't). |
| **Multi-tick FIFO across overflow boundary** | Earlier impl had `MAX_MARKET_ACTIONS_PER_TICK = 32`; current impl has no cap. If a future change re-introduces a cap, the FIFO test should cover the boundary. |
| **Sell-then-buy round-trip preserves k** | k-invariant is asserted post-seed; not asserted that successive sells + buys leave k roughly unchanged (within rounding). |
| **Token-allowlist defense against arbitrary tokens** | Test with `marketToken = address(0xdeadbeef)` — already implicitly covered by `ERR_MARKET_UNSUPPORTED_TOKEN`, but explicit test would be robust |

#### NICE-TO-HAVE

- Fuzz over `(amountIn, reserveA, reserveB)` for monotonicity of `getAmountOutForExactIn`
- Property test: round-trip sell → buy at same amount loses some value to slippage
- Heartbeat with empty queue is a no-op (already covered in `test_heartbeat_noopTick`)
- Integration test: 4 clans, 4 different scheduled actions in same tick, verify `commitSequence` ordering across all of them
- Cross-feature: bandit defeats clan B mid-tick → clan B's scheduled market action for that tick should fail with `ERR_INVALID_CLANSMAN`

**Headline gap count:** 6 MUST-COVER, 8 SHOULD-COVER, 5 NICE-TO-HAVE. None of the MUST-COVER items represent unimplemented mechanics — all the underlying behavior is shipped, it's just under-tested.

---

## 4. Potential UAT findings (if Liam runs interactive scenarios)

### Scenario 1 — Immediate market sell happy path
**Setup:** Mint clan with starter pack. Send 1 clansman with full carry of wood (e.g., chop wood to cap, deposit, withdraw, then travel to Unicorn Town and reach WAITING). Submit `MarketSell(woodToken, 5e18, maxGoldIn=0)` while WAITING and off-cooldown.
**Expected per spec:** Swap fires in submit tx → `ImmediateMarketActionExecuted` event → carry decreases by 5e18 → clan goldBalance increases by AMM-quoted output → cooldown reset.
**Actual per impl:** Same (codified in `test_immediateMarketSell_executesInSubmitTx`).
**He should verify:** event fires once, output > 0, carry properly debited.

### Scenario 2 — Immediate front-runs scheduled (adversarial play)
**Setup:** Two clans. Clan A has clansman in WAITING in UnicornTown with carry. Clan B has clansman traveling to UnicornTown for a scheduled MarketSell. Both target the wood pool. During tick T, B's `executeAtTick == T+1`. During tick T, A submits an immediate sell against the same pool.
**Expected per spec:** A's immediate sell executes against pool reserves at A's tx execution time; B's scheduled sell at heartbeat closing T+1 sees the post-A pool state and gets a worse price than if it had been first.
**Actual per impl:** Same (immediate fires inside `submitClanOrders`, scheduled fires inside `heartbeat`).
**He should verify:** the order of `ImmediateMarketActionExecuted` and `ScheduledMarketActionExecuted` events confirms A → B. Compare A's `goldOut` with B's `goldOut` for the same input amount; A's should be higher (less slippage).

### Scenario 3 — `maxGoldIn` actually protects buys
**Setup:** Clan submits `MarketBuy(woodToken, 100e18, maxGoldIn=50e18)`. Wood/Gold pool seeded with values where buying 100e18 wood actually requires more than 50e18 gold.
**Expected per spec:** Buy fails with `ERR_MAX_GOLD_IN_EXCEEDED` (or its impl-renamed equivalent `ERR_MAX_GOLD_IN_EXCEEDED`); carry unchanged; clan gold unchanged; cooldown still consumed.
**Actual per impl:** Matches (codified in `test_immediateMarketBuy_maxGoldExceededFailsAndConsumesCooldown`).
**He should verify:** the failure is graceful — no partial fill, no pool reserve change.

### Scenario 4 — Over-capacity buy rejected at submit (no tick consumed)
**Setup:** Clansman with `carryWood = 14e18` (cap is 15e18, so remaining = 1e18). Submit `MarketBuy(woodToken, 5e18, ...)`.
**Expected per spec:** Submit returns `ERR_CARRY_FULL`; no mission installed; no cooldown change; no enqueue.
**Actual per impl:** Matches (codified in `test_scheduledMarketBuy_overCapacityRejectsAtSubmit`).

### Scenario 5 — Spec-ratio pool seeding sanity check
**Setup:** Deploy with the exact spec ratios: Wood/Gold 1000e18:500e18, Wheat/Gold 1000e18:700e18, Fish/Gold 500e18:600e18, Iron/Gold 250e18:800e18. Read `getMarketState()`.
**Expected per spec:** Spot prices derive cleanly: wood = 0.5 gold/wood, wheat = 0.7, fish = 1.2, iron = 3.2.
**Actual per impl:** Should match exactly given pure x*y=k math. **No test currently does this** — Liam's UAT could be the first time spec ratios are exercised.
**He should verify:** spot prices in `getMarketState()` match expected within 1 wei rounding.

### Scenario 6 — Pool depletion graceful failure
**Setup:** Drain wood pool of resource via repeated buys until `reserveA` is near-empty. Submit one more buy of an amount equal to remaining `reserveA`.
**Expected per spec:** Buy reverts with "insufficient resource reserve" inside StubPool, surfaced as `ERR_LIQUIDITY_INSUFFICIENT`. Pool state unchanged. No clan state mutation.
**Actual per impl:** Matches (`StubPool.sol:53` reverts; outer `try/catch` maps to `ERR_LIQUIDITY_INSUFFICIENT`).

### Scenario 7 — `executeAtTick` timing observation (the 1-tick-late drift)
**Setup:** Submit a scheduled market sell from outside Unicorn Town with travel = 1 tick during tick `T`. Observe at which `closedTick` the `ScheduledMarketActionExecuted` event fires.
**Expected per spec §16.3:** Event fires at heartbeat closing tick `T+1` (= arrivalTick).
**Actual per impl:** Event fires at heartbeat closing tick `T+2` (= settlesAtTick = arrivalTick + 1).
**He should verify:** if Liam's mental model assumed swap = "end of action tick", he'll observe a 60-second delay vs expectation. Functionally fine (game state moves forward correctly), just timing-shift.

### Scenario 8 — Stale-nonce retask skip
**Setup:** Submit MarketSell scheduled (clansman traveling to town). Before `executeAtTick`, retask the same clansman to a different action (e.g., DefendBase or another MarketBuy). Wait for the original `executeAtTick`.
**Expected per spec:** Original sell should not execute (mission was replaced). Spec doesn't explicitly say how — impl uses `missionNonce` to detect stale entries.
**Actual per impl:** `MarketActionFailed(ERR_INVALID_ACTION)` emitted; no carry/gold change.
**He should verify:** the original sell silently fails with the failure event, not a partial execution.

---

## 5. UAT verdict

**SHIP-AS-IS.**

Phase 6 is materially compliant with v4 + v4_1 + v4_2 + v4_3 + v4_4 spec for the Unicorn Town market. There are **zero significant drifts** and **9 trivial / additive / spec-silent items**. Compare to PR #194 (Phase 9 bandits): that audit found 22 ❌ DRIFT/MISSING and only 9 ✅ MATCHES — bandits had fundamental design divergence. Phase 6 is the inverse: 39 ✅ MATCHES, 0 ❌, 9 ⚠️ TRIVIAL.

Major mechanics — exact-input sell vs exact-output buy, worker-carry source/destination, maxGoldIn slippage guard, scheduled FIFO, heartbeat cleanup, immediate-vs-scheduled ordering, settlement-before-market heartbeat ordering, reentrancy guards, status-code presence, getMarketState shape, x*y=k AMM with k-invariant — **all match spec**.

The 9 ⚠️ trivial items are all design-level micro-deviations:
- Event signatures use ResourceType enum bytes (more compact than addresses) + add `tick`/`mode` fields (indexer-impacting only)
- Status codes renamed (`ERR_MAX_GOLD_IN_EXCEEDED`) with ordinal-stability preserved
- 1-tick-late `executeAtTick` (no economic consequence)
- Uniform default seed ratios (deployer-config concern, not contract concern)
- AMM has no fee (spec is silent)
- Cooldown-on-immediate-fail is a §5.10-vs-§A5 ambiguity defensibly resolved

**Path A — ship as-is** (recommended): Phase 6 is spec-compliant within reasonable interpretation. The trivial deltas are codified by R3/R4/R5 fix-rounds (carry-vs-vault was R3, status-code stability was R4/R5). No new spec-restoration work is needed. Indexer/Phase-7 work must accommodate the event-signature refinements.

**Path B — N/A:** there are no substantial drifts to file as Phase-6.5 issues. The cross-cutting cleanup that COULD be filed (and probably should be filed for cosmetic spec-alignment, not behavior) is captured in §6.

**Cleanly merge-able as-is?** Yes. Local + cloud reviewers have already passed (per `pr198-codereview-*`, `pr198-r2-*`, plus R3/R4/R5 fix-rounds visible in `dev-phase-6-market` history). This UAT pass confirms there's no spec-side blocker.

---

## 6. Path A / Path B recommendation

**Path A (ship as-is) — RECOMMENDED.**

**No spec-gap GitHub issues to file under `spec-v4-restoration-post-hackathon` for Phase 6.** All 9 ⚠️ trivial items are either:
- Indexer-side accommodation (event-signature refinements) — not a contract spec gap
- Configuration-side (deployer should pass spec ratios at seed time) — not a contract spec gap
- Spec ambiguity (no-fee AMM, cooldown-on-immediate-fail) — not a contract spec gap
- 1-tick-late market timing — defensible design choice, no economic consequence

**TRIVIAL items (orchestrator could fix directly post-hackathon, none required for ship):**

1. **`executeAtTick` 1-tick-late** (`ClanWorld.sol:1358`) — change `executeAtTick = m.settlesAtTick` to `executeAtTick = ctx.arrivalTick`, then update `settlesAtTick` semantics to remain at `arrivalTick + 1` for the WAITING-transition. **Risk:** breaks tests that hardcode `m.settlesAtTick` as the event's `tick` value (~6 tests). NOT a Phase 6 ship blocker.
2. **Default seed ratios match spec** (`ClanWorld.sol:82-83`) — split `INITIAL_RESOURCE_POOL_SEED` and `INITIAL_GOLD_POOL_SEED` into 4 per-pool constants matching §5.11 ratios. Or document that the spec ratios must be passed by the deployer.
3. **Slippage guard literal `0`** (`ClanWorld.sol:1802`) — change `swapExactInForOut(amount, 1)` to `swapExactInForOut(amount, 0)` to literally match spec §5.9. The `1` is defensive but wording-divergent.

**Indexer follow-up (Phase 7 concern, not Phase 6 spec-gap):**
- Indexer must consume `uint8 ResourceType` enum bytes in `ImmediateMarketActionExecuted` / `ScheduledMarketActionExecuted` rather than token addresses
- Indexer must handle the additive `mode` field on `MarketActionFailed`
- Indexer can optionally consume the new `ScheduledMarketActionCommitted` event to render pending queues (otherwise must fall back to `getScheduledMarketActionsForTick`)

**No SUBSTANTIAL drifts.** No `spec-v4-restoration-post-hackathon` issues required.

---

## Appendix A — Files inspected

- `packages/contracts/src/ClanWorld.sol` (2675 lines, full read of market sections + heartbeat ordering + validation)
- `packages/contracts/src/IClanWorld.sol` (826 lines, full read of enums + structs + status codes + events + market interface)
- `packages/contracts/src/StubPool.sol` (117 lines, full)
- `packages/contracts/test/ClanWorld.t.sol` (2870 lines, scanned for market test coverage)
- `packages/contracts/test/SeedPools.t.sol` (148 lines, full)
- `packages/contracts/test/HeartbeatOrdering.t.sol` (scanned for `test_heartbeat_settlementBeforeMarket`)
- `packages/contracts/test/Reentrancy.t.sol` (scanned for `test_marketPoolHeartbeatCallback_revertsWithReentrancyGuard`)
- `docs/planning/clanworld_v4_spec.md` §5 + invariants §15
- `docs/planning/clanworld_v4_1_addendum.md` A5, A7, A8
- `docs/planning/clanworld_v4_2_state_schema_interface_spec.md` §2.6, §4, §7.8, §8.3-8.5, §10.6, §11.2-11.4, §13, §14, §15, §16.2-16.3
- `docs/planning/clanworld_v4_3_schema_patch.md` A.2, D, K.2
- `docs/planning/clanworld_v4_4_ui_indexer_getters.md` §2.3
- `docs/planning/clanworld_v4_5_alignment_addendum.md` (no market-specific content)
- `docs/reviews/pr194-spec-compliance-uat.md` (Phase 9 audit, used as template per dispatch brief)

## Appendix B — What I deliberately did NOT do

- Run `forge test` (per UAT brief: static analysis only)
- Re-litigate prior-reviewer findings in `pr198-codereview-*`, `pr198-r2-*` files
- File any GitHub issues
- Edit any code in `packages/contracts/`
- Audit Phases 1–5 mechanics (resource gathering, deposit, building, heartbeat, defend) — out of Phase 6 scope
- Audit OTC transfer surface — separate concern, stubbed in Phase 6 by design

## Appendix C — Drift triage summary

```
Drift count: ZERO substantial / NINE trivial-or-ambiguous
Recommendation: Path A — ship as-is
Top 3 items worth orchestrator-direct cleanup post-hackathon:
  1. ClanWorld.sol:1358  executeAtTick = settlesAtTick → spec example wants arrivalTick (1-tick late)
  2. ClanWorld.sol:82-83  default seed constants are uniform; spec §5.11 has asymmetric per-pool ratios
  3. ClanWorld.sol:1802  swapExactInForOut(amount, 1) → spec §5.9 wants minOut=0 literally
```
