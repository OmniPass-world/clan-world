Reading additional input from stdin...
OpenAI Codex v0.125.0 (research preview)
--------
workdir: /tmp/wt-superswarm-357
model: gpt-5.5
provider: openai
approval: never
sandbox: read-only
reasoning effort: high
reasoning summaries: none
session id: 019dde2c-ae6d-7411-a700-71dd982ee751
--------
user
Read the prompt and content from stdin. Use parallel tool calls aggressively to verify enum stability, executeAtTick cascade, slippage guard placement, and pool seed migration completeness against the actual code at /tmp/wt-superswarm-357. Output the full review to stdout in the requested markdown format.

<stdin>
You are a senior staff engineer doing the FINAL pre-merge review for PR #357 — Phase 6B spec cleanup (Solidity contracts).

PR: fix(contracts): Phase 6B — spec cleanup (seed ratios + executeAtTick + slippage)
Head SHA: 79879ce
Branch: feat/issue-353-phase6b-spec-cleanup → dev-phase-6b-spec-cleanup
Audit source: docs/reviews/pr198-spec-compliance-uat.md (PR #350, on branch docs/spec-audit-phase-6)

## Context

Three trivial drift fixes from PR #198 audit, Path A:
1. Default market seed ratios match v4 spec §5.11 — replaced uniform `INITIAL_RESOURCE_POOL_SEED=100_000e18` / `INITIAL_GOLD_POOL_SEED=50_000e18` with 8 asymmetric per-resource constants:
   - INITIAL_WOOD_POOL_SEED=1_000e18, GOLD_FOR_WOOD=500e18
   - INITIAL_WHEAT_POOL_SEED=1_000e18, GOLD_FOR_WHEAT=700e18
   - INITIAL_FISH_POOL_SEED=500e18, GOLD_FOR_FISH=600e18
   - INITIAL_IRON_POOL_SEED=250e18, GOLD_FOR_IRON=800e18
2. `executeAtTick` 1-tick-late off-by-one (§16.3): MarketBuy/MarketSell now have `m.executesAtTick = ctx.arrivalTick` AND `m.settlesAtTick = ctx.arrivalTick`. Non-market actions unchanged.
3. New `ERR_SLIPPAGE_REQUIRED` enum entry (index 31, appended) + propose-time guard rejecting `MarketBuy` with `maxGoldIn == 0`.

Forge: 226 tests pass. Local 3-tier swarm: CLEAN (Gemini ✓ + Codex ✓ via orchestrator dispatch; Claude via codex's inner swarm).

## Your task — FINAL gate review

This is the orchestrator's super-swarm gate before Liam UAT (per Liam directive 2026-04-30 11:07 ET — no cloud reviews). Look for:

1. **Cross-cutting bugs** — anything missed by per-file review. Does the executeAtTick change break market scheduled queue? Does it interact with cooldown logic (cooldown is set on submit)? Does `_resolveScheduledAction` need to know about the new timing?

2. **Enum ordinal stability** — `ERR_SLIPPAGE_REQUIRED` should be at index 31 (appended after `ERR_MAX_GOLD_IN_EXCEEDED` at 30). If inserted earlier, it'd shift `ERR_MAX_GOLD_IN_EXCEEDED` and break ABI. Verify by reading `IClanWorld.sol` enum block + `StatusCodeEnumStability.t.sol` test.

3. **Slippage guard correctness** — `if (action == ActionType.MarketBuy && order.maxGoldIn == 0) return ERR_SLIPPAGE_REQUIRED;` — does this run BEFORE or AFTER the carry-cap check? Does it apply to immediate AND scheduled MarketBuy? Bypass-able via direct contract call? What about MarketSell — should it have an analogous guard (maxGoldOut?) or is asymmetry intentional?

4. **Pool seed migration** — all call sites updated? Search for `INITIAL_RESOURCE_POOL_SEED` and `INITIAL_GOLD_POOL_SEED` to verify no leftover uses.

5. **Test coverage** — 226 tests pass, but is the coverage adequate for the 3 changes? Specifically: scheduled MarketBuy (delayed) with maxGoldIn=0, market timing edge cases (arrival at heartbeat boundary), per-resource pool depletion under asymmetric seeds.

6. **Reentrancy / atomicity** — does the new propose-time guard interact with the reentrancy guard? Does it return early in a way that leaves clan state mid-mutation?

7. **Documentation** — should this PR also update `clanworld_v4_spec.md` §5.11 (or note that the v4 spec is now the canonical spec for this constant)? Does it conflict with the in-flight Phase 6 audit doc PR #350?

USE PARALLEL TOOL CALLS aggressively. The worktree at /tmp/wt-superswarm-357 has the PR head checked out — read the actual code, not just the diff.

## Output format

# Super-Swarm Review — PR #357 (head 79879ce) — Phase 6B spec cleanup

## SUMMARY
2-4 sentences: verdict (CLEAN | NEEDS_FIXES), top concerns, merge recommendation.

## HIGH severity findings
(real bugs, security issues, ABI breaks, wrong-behavior)

## MEDIUM severity findings
(should-fix; missed test coverage, design quality, defensive holes)

## LOW severity findings
(defer-OK; nits, follow-up issues)

## Cross-cutting observations
(themes across the diff, architectural drift)

If clean, say "CLEAN — no findings" under each section.

DIFF + AUDIT FOLLOW BELOW.
---

## DIFF:

diff --git a/packages/contracts/script/Deploy.s.sol b/packages/contracts/script/Deploy.s.sol
index 5e54cd7..70c3661 100644
--- a/packages/contracts/script/Deploy.s.sol
+++ b/packages/contracts/script/Deploy.s.sol
@@ -50,32 +50,38 @@ contract Deploy is Script {
 
         game.initTreasury(tokens, pools);
 
-        uint256 resSeed = game.INITIAL_RESOURCE_POOL_SEED();
-        uint256 goldSeed = game.INITIAL_GOLD_POOL_SEED();
-        uint256 totalGoldSeed = goldSeed * 4;
+        uint256 woodSeed = game.INITIAL_WOOD_POOL_SEED();
+        uint256 wheatSeed = game.INITIAL_WHEAT_POOL_SEED();
+        uint256 fishSeed = game.INITIAL_FISH_POOL_SEED();
+        uint256 ironSeed = game.INITIAL_IRON_POOL_SEED();
+        uint256 goldForWood = game.INITIAL_GOLD_SEED_FOR_WOOD();
+        uint256 goldForWheat = game.INITIAL_GOLD_SEED_FOR_WHEAT();
+        uint256 goldForFish = game.INITIAL_GOLD_SEED_FOR_FISH();
+        uint256 goldForIron = game.INITIAL_GOLD_SEED_FOR_IRON();
+        uint256 totalGoldSeed = goldForWood + goldForWheat + goldForFish + goldForIron;
 
-        wood.seedTreasury(treasury, resSeed);
-        wheat.seedTreasury(treasury, resSeed);
-        fish.seedTreasury(treasury, resSeed);
-        iron.seedTreasury(treasury, resSeed);
+        wood.seedTreasury(treasury, woodSeed);
+        wheat.seedTreasury(treasury, wheatSeed);
+        fish.seedTreasury(treasury, fishSeed);
+        iron.seedTreasury(treasury, ironSeed);
         gold.seedTreasury(treasury, totalGoldSeed);
 
-        wood.approve(address(game), resSeed);
-        wheat.approve(address(game), resSeed);
-        fish.approve(address(game), resSeed);
-        iron.approve(address(game), resSeed);
+        wood.approve(address(game), woodSeed);
+        wheat.approve(address(game), wheatSeed);
+        fish.approve(address(game), fishSeed);
+        iron.approve(address(game), ironSeed);
         gold.approve(address(game), totalGoldSeed);
 
         game.seedPools(
             PoolSeedConfig({
-                woodSeed: resSeed,
-                wheatSeed: resSeed,
-                fishSeed: resSeed,
-                ironSeed: resSeed,
-                goldSeedForWood: goldSeed,
-                goldSeedForWheat: goldSeed,
-                goldSeedForFish: goldSeed,
-                goldSeedForIron: goldSeed
+                woodSeed: woodSeed,
+                wheatSeed: wheatSeed,
+                fishSeed: fishSeed,
+                ironSeed: ironSeed,
+                goldSeedForWood: goldForWood,
+                goldSeedForWheat: goldForWheat,
+                goldSeedForFish: goldForFish,
+                goldSeedForIron: goldForIron
             })
         );
 
diff --git a/packages/contracts/src/ClanWorld.sol b/packages/contracts/src/ClanWorld.sol
index e1eb6c7..08388e0 100644
--- a/packages/contracts/src/ClanWorld.sol
+++ b/packages/contracts/src/ClanWorld.sol
@@ -79,8 +79,14 @@ contract ClanWorld is IClanWorld, ReentrancyGuard {
 
     uint64 private constant DEPOSIT_DURATION_TICKS = 1;
     uint256 private constant WHEAT_HARVEST_RATE = 20e18;
-    uint256 public constant INITIAL_RESOURCE_POOL_SEED = 100_000e18;
-    uint256 public constant INITIAL_GOLD_POOL_SEED = 50_000e18;
+    uint256 public constant INITIAL_WOOD_POOL_SEED = 1_000e18;
+    uint256 public constant INITIAL_WHEAT_POOL_SEED = 1_000e18;
+    uint256 public constant INITIAL_FISH_POOL_SEED = 500e18;
+    uint256 public constant INITIAL_IRON_POOL_SEED = 250e18;
+    uint256 public constant INITIAL_GOLD_SEED_FOR_WOOD = 500e18;
+    uint256 public constant INITIAL_GOLD_SEED_FOR_WHEAT = 700e18;
+    uint256 public constant INITIAL_GOLD_SEED_FOR_FISH = 600e18;
+    uint256 public constant INITIAL_GOLD_SEED_FOR_IRON = 800e18;
     // =========================================================================
     // CONSTRUCTOR
     // =========================================================================
@@ -1330,7 +1336,9 @@ contract ClanWorld is IClanWorld, ReentrancyGuard {
         m.executesAtTick = ctx.arrivalTick;
         m.settlesAtTick = order.action == ActionType.DefendBase
             ? type(uint64).max
-            : _addTicksClamped(ctx.arrivalTick, getActionDuration(order.action));
+            : (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell)
+                ? ctx.arrivalTick
+                : _addTicksClamped(ctx.arrivalTick, getActionDuration(order.action));
         m.startRegion = ctx.fromRegion;
         m.targetRegion = ctx.gotoRegion;
         m.action = order.action;
@@ -2172,6 +2180,10 @@ contract ClanWorld is IClanWorld, ReentrancyGuard {
             ) {
                 return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
             }
+            // MarketBuy uses maxGoldIn as its explicit slippage bound; zero would mean no protection.
+            if (action == ActionType.MarketBuy && order.maxGoldIn == 0) {
+                return StatusCode.ERR_SLIPPAGE_REQUIRED;
+            }
             // Over-capacity buys are rejected at submission; no partial fills or overflow refunds.
             if (action == ActionType.MarketBuy && order.marketAmount > _remainingCarryForToken(cs, tok)) {
                 return StatusCode.ERR_CARRY_FULL;
diff --git a/packages/contracts/src/IClanWorld.sol b/packages/contracts/src/IClanWorld.sol
index e806717..a886f69 100644
--- a/packages/contracts/src/IClanWorld.sol
+++ b/packages/contracts/src/IClanWorld.sol
@@ -186,7 +186,8 @@ enum StatusCode {
     ERR_CARRY_FULL,
     ERR_MARKET_INSUFFICIENT_LIQUIDITY, // Deprecated/reserved legacy ordinal (replaced by ERR_LIQUIDITY_INSUFFICIENT); kept only to preserve enum ordinal stability.
     ERR_LIQUIDITY_INSUFFICIENT,
-    ERR_MAX_GOLD_IN_EXCEEDED
+    ERR_MAX_GOLD_IN_EXCEEDED,
+    ERR_SLIPPAGE_REQUIRED
 }
 
 // =============================================================================
diff --git a/packages/contracts/test/ClanWorld.t.sol b/packages/contracts/test/ClanWorld.t.sol
index 2405ed7..b1cd296 100644
--- a/packages/contracts/test/ClanWorld.t.sol
+++ b/packages/contracts/test/ClanWorld.t.sol
@@ -93,7 +93,7 @@ contract ClanWorldTest is Test {
 
     /// @dev Deploy tokens + pools, call initTreasury + seedPools. Returns wood token address.
     function _setupMarket() internal returns (address woodAddr) {
-        return _setupMarketWithWoodSeed(world.INITIAL_RESOURCE_POOL_SEED());
+        return _setupMarketWithWoodSeed(world.INITIAL_WOOD_POOL_SEED());
     }
 
     function _setupMarketWithWoodSeed(uint256 woodSeed) internal returns (address woodAddr) {
@@ -122,32 +122,36 @@ contract ClanWorldTest is Test {
 
         world.initTreasury(tokens, pools);
 
-        // Seed: 100,000 resource + 50,000 gold per pool (spot price 0.5 gold / resource).
-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
-        uint256 totalGoldSeed = goldSeed * 4;
+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
+        uint256 totalGoldSeed = goldForWood + goldForWheat + goldForFish + goldForIron;
 
         woodToken.seedTreasury(address(this), woodSeed);
-        wheatToken.seedTreasury(address(this), resSeed);
-        fishToken.seedTreasury(address(this), resSeed);
-        ironToken.seedTreasury(address(this), resSeed);
+        wheatToken.seedTreasury(address(this), wheatSeed);
+        fishToken.seedTreasury(address(this), fishSeed);
+        ironToken.seedTreasury(address(this), ironSeed);
         goldToken.seedTreasury(address(this), totalGoldSeed);
 
         woodToken.approve(address(world), woodSeed);
-        wheatToken.approve(address(world), resSeed);
-        fishToken.approve(address(world), resSeed);
-        ironToken.approve(address(world), resSeed);
+        wheatToken.approve(address(world), wheatSeed);
+        fishToken.approve(address(world), fishSeed);
+        ironToken.approve(address(world), ironSeed);
         goldToken.approve(address(world), totalGoldSeed);
 
         PoolSeedConfig memory cfg = PoolSeedConfig({
             woodSeed: woodSeed,
-            wheatSeed: resSeed,
-            fishSeed: resSeed,
-            ironSeed: resSeed,
-            goldSeedForWood: goldSeed,
-            goldSeedForWheat: goldSeed,
-            goldSeedForFish: goldSeed,
-            goldSeedForIron: goldSeed
+            wheatSeed: wheatSeed,
+            fishSeed: fishSeed,
+            ironSeed: ironSeed,
+            goldSeedForWood: goldForWood,
+            goldSeedForWheat: goldForWheat,
+            goldSeedForFish: goldForFish,
+            goldSeedForIron: goldForIron
         });
         world.seedPools(cfg);
 
@@ -925,7 +929,7 @@ contract ClanWorldTest is Test {
         internal
         returns (ClanWorldTestHarness harness, address woodAddr, uint32 clanId, uint32 csId)
     {
-        return _setupHarnessClanAtWithWoodSeed(state, region, cooldownEndsAtTs, world.INITIAL_RESOURCE_POOL_SEED());
+        return _setupHarnessClanAtWithWoodSeed(state, region, cooldownEndsAtTs, world.INITIAL_WOOD_POOL_SEED());
     }
 
     function _setupHarnessClanAtWithWoodSeed(
@@ -1063,6 +1067,25 @@ contract ClanWorldTest is Test {
         assertFalse(world.getActiveMission(csId).active, "immediate buy should not install a mission");
     }
 
+    function test_marketBuy_zeroMaxGoldInRejectsAtSubmit() public {
+        (, address woodAddr, uint32 clanId, uint32 csId) =
+            _setupHarnessClanAt(ClansmanState.WAITING, ClanWorldConstants.REGION_UNICORN_TOWN, 0);
+
+        Clan memory beforeClan = world.getClan(clanId);
+        Clansman memory beforeCs = world.getClansman(csId);
+
+        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 0);
+
+        Clan memory afterClan = world.getClan(clanId);
+        Clansman memory afterCs = world.getClansman(csId);
+        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), "zero maxGoldIn is ambiguous");
+        assertEq(uint8(r[0].marketMode), uint8(MarketExecutionMode.None), "rejected buy has no mode");
+        assertEq(afterClan.goldBalance, beforeClan.goldBalance, "rejected buy should not debit gold");
+        assertEq(afterCs.carryWood, beforeCs.carryWood, "rejected buy should not credit carry");
+        assertEq(afterCs.cooldownEndsAtTs, beforeCs.cooldownEndsAtTs, "rejected buy should not consume cooldown");
+        assertFalse(world.getActiveMission(csId).active, "rejected buy should not install a mission");
+    }
+
     function test_immediateMarket_insufficientLiquidityFailsAndConsumesCooldown() public {
         (, address woodAddr, uint32 clanId, uint32 csId) =
             _setupHarnessClanAtWithWoodSeed(ClansmanState.WAITING, ClanWorldConstants.REGION_UNICORN_TOWN, 0, 5e18);
@@ -1112,7 +1135,7 @@ contract ClanWorldTest is Test {
             StatusCode.ERR_MAX_GOLD_IN_EXCEEDED,
             world.getWorldState().currentTick
         );
-        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 0);
+        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 1);
 
         Clan memory afterClan = world.getClan(clanId);
         Clansman memory cs = world.getClansman(csId);
@@ -1317,8 +1340,8 @@ contract ClanWorldTest is Test {
         uint32 clanId = _mintClan();
         uint32 csId = _firstCs(clanId);
 
-        // maxGoldIn = 0 (will always be exceeded for any nonzero buy)
-        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 0);
+        // maxGoldIn = 1 wei (will always be exceeded for any nonzero buy)
+        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 1);
         assertEq(uint8(r[0].status), uint8(StatusCode.OK), "order submission should succeed");
 
         Mission memory m = world.getActiveMission(csId);
@@ -1553,15 +1576,14 @@ contract ClanWorldTest is Test {
             totalQueued += _submitAllClanMarketSells(distOneClans[i], woodAddr);
         }
 
-        uint64 executeAtTick = 3;
+        uint64 executeAtTick = 2;
         bytes32 executedSig =
             keccak256("ScheduledMarketActionExecuted(uint32,uint32,uint8,uint8,uint256,uint8,uint256,uint64)");
 
         _advanceTick(); // close tick 1
-        _advanceTick(); // close tick 2
 
         vm.recordLogs();
-        _advanceTick(); // close tick 3 and execute every scheduled action for the tick
+        _advanceTick(); // close tick 2 and execute every scheduled action for the tick
         Vm.Log[] memory logs = vm.getRecordedLogs();
 
         uint256 executedCount;
@@ -1755,7 +1777,7 @@ contract ClanWorldTest is Test {
         // Give csId2 carry wood so the sell succeeds
         harness.setCarry(csId2, 10e18, 0, 0, 0);
 
-        OrderResult[] memory buyFail = _submitMarketOrder(clanId1, csId1, ActionType.MarketBuy, woodAddr, 1e18, 0);
+        OrderResult[] memory buyFail = _submitMarketOrder(clanId1, csId1, ActionType.MarketBuy, woodAddr, 1e18, 1);
         assertEq(uint8(buyFail[0].status), uint8(StatusCode.OK), "failing buy should enqueue");
 
         ClanOrder[] memory sellOrders = new ClanOrder[](1);
diff --git a/packages/contracts/test/HeartbeatOrdering.t.sol b/packages/contracts/test/HeartbeatOrdering.t.sol
index b4c1241..24654ac 100644
--- a/packages/contracts/test/HeartbeatOrdering.t.sol
+++ b/packages/contracts/test/HeartbeatOrdering.t.sol
@@ -152,31 +152,37 @@ contract HeartbeatOrderingTest is Test {
         address[4] memory pools = [address(woodPool), address(wheatPool), address(fishPool), address(ironPool)];
         world.initTreasury(tokens, pools);
 
-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
-        uint256 totalGoldSeed = goldSeed * 4;
-
-        woodToken.seedTreasury(address(this), resSeed);
-        wheatToken.seedTreasury(address(this), resSeed);
-        fishToken.seedTreasury(address(this), resSeed);
-        ironToken.seedTreasury(address(this), resSeed);
+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
+        uint256 totalGoldSeed = goldForWood + goldForWheat + goldForFish + goldForIron;
+
+        woodToken.seedTreasury(address(this), woodSeed);
+        wheatToken.seedTreasury(address(this), wheatSeed);
+        fishToken.seedTreasury(address(this), fishSeed);
+        ironToken.seedTreasury(address(this), ironSeed);
         goldToken.seedTreasury(address(this), totalGoldSeed);
 
-        woodToken.approve(address(world), resSeed);
-        wheatToken.approve(address(world), resSeed);
-        fishToken.approve(address(world), resSeed);
-        ironToken.approve(address(world), resSeed);
+        woodToken.approve(address(world), woodSeed);
+        wheatToken.approve(address(world), wheatSeed);
+        fishToken.approve(address(world), fishSeed);
+        ironToken.approve(address(world), ironSeed);
         goldToken.approve(address(world), totalGoldSeed);
 
         PoolSeedConfig memory cfg = PoolSeedConfig({
-            woodSeed: resSeed,
-            wheatSeed: resSeed,
-            fishSeed: resSeed,
-            ironSeed: resSeed,
-            goldSeedForWood: goldSeed,
-            goldSeedForWheat: goldSeed,
-            goldSeedForFish: goldSeed,
-            goldSeedForIron: goldSeed
+            woodSeed: woodSeed,
+            wheatSeed: wheatSeed,
+            fishSeed: fishSeed,
+            ironSeed: ironSeed,
+            goldSeedForWood: goldForWood,
+            goldSeedForWheat: goldForWheat,
+            goldSeedForFish: goldForFish,
+            goldSeedForIron: goldForIron
         });
         world.seedPools(cfg);
     }
@@ -189,7 +195,7 @@ contract HeartbeatOrderingTest is Test {
     //   - cs0 is placed at Unicorn Town (region 3). Deposit to homebase Forest
     //     (region 1) = 2 ticks travel. arrivalTick = T0+2, settlesAtTick = T0+3.
     //   - cs1 at Forest submits MarketSell to UT (region 3) = 2 ticks travel.
-    //     settlesAtTick = T0+3. (Same tick as cs0 settles.)
+    //     settlesAtTick = T0+2, matching the market action's arrival tick.
     //   - vault starts at 0; cs0 has carry wood.
     //   - Heartbeat at T0+2: Step 1 deposits cs0 carry wood to vault, Step 2 sells
     //     it. Gold increases only if Step 1 ran first (vault was 0 before Step 1).
@@ -222,18 +228,16 @@ contract HeartbeatOrderingTest is Test {
         assertEq(world.getClan(clanId).vaultWood, 0, "vault wood must be 0 before test tick");
 
         // cs1: at Forest. Submit MarketSell to UT. Forest→UT = 2 ticks.
-        // settlesAtTick = t0+3. Same tick as deposit settles.
+        // Market actions execute at the heartbeat closing their arrival tick.
         OrderResult[] memory r1 = _submitMarketOrder(clanId, csId1, ActionType.MarketSell, address(woodToken), 5e18, 0);
         assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "market sell order must enqueue");
         Mission memory sellMission = world.getActiveMission(csId1);
         assertEq(sellMission.arrivalTick, t0 + 2, "sell arrivalTick must be t0+2");
-        assertEq(sellMission.settlesAtTick, t0 + 3, "sell settlesAtTick must be t0+3");
+        assertEq(sellMission.settlesAtTick, t0 + 2, "sell settlesAtTick must be t0+2");
 
         uint256 goldBefore = world.getClan(clanId).goldBalance;
 
-        // Advance to tick t0+4. The heartbeat closing t0+3 runs:
-        //   Step 1: _settleCompletingMissions(t0+3) → deposit fires, cs0 carry 10e18 → vault
-        //   Step 2: _executeScheduledMarketActions(t0+3) → sell fires, cs1 carry 5e18 → gold
+        // Advance past both the market sale at t0+2 and the deposit completion at t0+3.
         _advanceToTick(t0 + 4);
 
         uint256 goldAfter = world.getClan(clanId).goldBalance;
@@ -320,11 +324,10 @@ contract HeartbeatOrderingTest is Test {
     // -------------------------------------------------------------------------
     // test_heartbeat_multipleStepsInOneTick
     //
-    // Proves that when a mission settles at tick T AND a market action is queued at
-    // tick T, both fire in the same heartbeat without conflict.
+    // Proves that adjacent heartbeat work can process a scheduled market action
+    // at its arrival tick and a normal mission at its later settlement tick.
     //   - cs0 placed at Unicorn Town, deposits to Forest homebase: settlesAtTick = T0+3
-    //   - cs1 sells wood to UT from Forest: settlesAtTick = T0+3
-    //   Both succeed in the same heartbeat call at T0+3.
+    //   - cs1 sells wood to UT from Forest: settlesAtTick = T0+2
     // -------------------------------------------------------------------------
     function test_heartbeat_multipleStepsInOneTick() public {
         _setupMarket();
@@ -343,20 +346,20 @@ contract HeartbeatOrderingTest is Test {
         assertEq(uint8(r0[0].status), uint8(StatusCode.OK), "deposit must succeed");
         assertEq(world.getActiveMission(csId0).settlesAtTick, t0 + 3, "deposit settlesAtTick must be t0+3");
 
-        // cs1: at Forest, sells wood to UT. Forest→UT = 2 ticks. settlesAtTick = t0+3.
+        // cs1: at Forest, sells wood to UT. Forest→UT = 2 ticks. settlesAtTick = t0+2.
         // Give cs1 carry wood — sell draws from carry (not vault).
         world.setCarryWood(csId1, 10e18);
         OrderResult[] memory r1 = _submitMarketOrder(clanId, csId1, ActionType.MarketSell, address(woodToken), 5e18, 0);
         assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "market sell must enqueue");
         assertEq(world.getActiveMission(csId1).arrivalTick, t0 + 2, "sell arrivalTick must be t0+2");
-        assertEq(world.getActiveMission(csId1).settlesAtTick, t0 + 3, "sell settlesAtTick must be t0+3");
+        assertEq(world.getActiveMission(csId1).settlesAtTick, t0 + 2, "sell settlesAtTick must be t0+2");
 
         uint256 goldBefore = world.getClan(clanId).goldBalance;
 
-        // Advance to tick t0+4 (the heartbeat closing t0+3 runs step1+step2 together).
+        // Advance past the sell at t0+2 and the deposit at t0+3.
         _advanceToTick(t0 + 4);
 
-        // Both cs0 deposit (settled at T0+3) and cs1 sell (at T0+3) must have fired.
+        // Both cs0 deposit (settled at T0+3) and cs1 sell (settled at T0+2) must have fired.
         assertEq(world.getClansman(csId0).carryWood, 0, "deposit settled: carry cleared");
         assertGt(world.getClan(clanId).goldBalance, goldBefore, "sell executed: gold increased");
         assertFalse(world.getActiveMission(csId0).active, "deposit mission must be complete");
diff --git a/packages/contracts/test/Reentrancy.t.sol b/packages/contracts/test/Reentrancy.t.sol
index b77c253..8b73952 100644
--- a/packages/contracts/test/Reentrancy.t.sol
+++ b/packages/contracts/test/Reentrancy.t.sol
@@ -169,31 +169,37 @@ contract ReentrancyTest is Test {
         address[4] memory pools = [address(woodPool), address(wheatPool), address(fishPool), address(ironPool)];
         world.initTreasury(tokens, pools);
 
-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
-        uint256 totalGoldSeed = goldSeed * 4;
-
-        woodToken.seedTreasury(address(this), resSeed);
-        wheatToken.seedTreasury(address(this), resSeed);
-        fishToken.seedTreasury(address(this), resSeed);
-        ironToken.seedTreasury(address(this), resSeed);
+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
+        uint256 totalGoldSeed = goldForWood + goldForWheat + goldForFish + goldForIron;
+
+        woodToken.seedTreasury(address(this), woodSeed);
+        wheatToken.seedTreasury(address(this), wheatSeed);
+        fishToken.seedTreasury(address(this), fishSeed);
+        ironToken.seedTreasury(address(this), ironSeed);
         goldToken.seedTreasury(address(this), totalGoldSeed);
 
-        woodToken.approve(address(world), resSeed);
-        wheatToken.approve(address(world), resSeed);
-        fishToken.approve(address(world), resSeed);
-        ironToken.approve(address(world), resSeed);
+        woodToken.approve(address(world), woodSeed);
+        wheatToken.approve(address(world), wheatSeed);
+        fishToken.approve(address(world), fishSeed);
+        ironToken.approve(address(world), ironSeed);
         goldToken.approve(address(world), totalGoldSeed);
 
         PoolSeedConfig memory cfg = PoolSeedConfig({
-            woodSeed: resSeed,
-            wheatSeed: resSeed,
-            fishSeed: resSeed,
-            ironSeed: resSeed,
-            goldSeedForWood: goldSeed,
-            goldSeedForWheat: goldSeed,
-            goldSeedForFish: goldSeed,
-            goldSeedForIron: goldSeed
+            woodSeed: woodSeed,
+            wheatSeed: wheatSeed,
+            fishSeed: fishSeed,
+            ironSeed: ironSeed,
+            goldSeedForWood: goldForWood,
+            goldSeedForWheat: goldForWheat,
+            goldSeedForFish: goldForFish,
+            goldSeedForIron: goldForIron
         });
         world.seedPools(cfg);
     }
diff --git a/packages/contracts/test/SeedPools.t.sol b/packages/contracts/test/SeedPools.t.sol
index 0252a89..f6065e2 100644
--- a/packages/contracts/test/SeedPools.t.sol
+++ b/packages/contracts/test/SeedPools.t.sol
@@ -59,13 +59,18 @@ contract SeedPoolsTest is Test {
     }
 
     function test_treasurySeedingTransfersExpectedPoolBalances() public {
-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
-
-        _assertPoolSeeded(woodToken, woodPool, resSeed, goldSeed, "wood");
-        _assertPoolSeeded(wheatToken, wheatPool, resSeed, goldSeed, "wheat");
-        _assertPoolSeeded(fishToken, fishPool, resSeed, goldSeed, "fish");
-        _assertPoolSeeded(ironToken, ironPool, resSeed, goldSeed, "iron");
+        _assertPoolSeeded(
+            woodToken, woodPool, world.INITIAL_WOOD_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WOOD(), "wood"
+        );
+        _assertPoolSeeded(
+            wheatToken, wheatPool, world.INITIAL_WHEAT_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WHEAT(), "wheat"
+        );
+        _assertPoolSeeded(
+            fishToken, fishPool, world.INITIAL_FISH_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_FISH(), "fish"
+        );
+        _assertPoolSeeded(
+            ironToken, ironPool, world.INITIAL_IRON_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_IRON(), "iron"
+        );
         assertEq(goldToken.balanceOf(address(this)), 0, "treasury gold fully seeded");
     }
 
@@ -94,35 +99,39 @@ contract SeedPoolsTest is Test {
     }
 
     function _seedTreasuryAndApprove() internal {
-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
-        uint256 totalGoldSeed = goldSeed * 4;
-
-        woodToken.seedTreasury(address(this), resSeed);
-        wheatToken.seedTreasury(address(this), resSeed);
-        fishToken.seedTreasury(address(this), resSeed);
-        ironToken.seedTreasury(address(this), resSeed);
+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
+        uint256 totalGoldSeed = goldForWood + goldForWheat + goldForFish + goldForIron;
+
+        woodToken.seedTreasury(address(this), woodSeed);
+        wheatToken.seedTreasury(address(this), wheatSeed);
+        fishToken.seedTreasury(address(this), fishSeed);
+        ironToken.seedTreasury(address(this), ironSeed);
         goldToken.seedTreasury(address(this), totalGoldSeed);
 
-        woodToken.approve(address(world), resSeed);
-        wheatToken.approve(address(world), resSeed);
-        fishToken.approve(address(world), resSeed);
-        ironToken.approve(address(world), resSeed);
+        woodToken.approve(address(world), woodSeed);
+        wheatToken.approve(address(world), wheatSeed);
+        fishToken.approve(address(world), fishSeed);
+        ironToken.approve(address(world), ironSeed);
         goldToken.approve(address(world), totalGoldSeed);
     }
 
     function _seedConfig() internal view returns (PoolSeedConfig memory) {
-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
         return PoolSeedConfig({
-            woodSeed: resSeed,
-            wheatSeed: resSeed,
-            fishSeed: resSeed,
-            ironSeed: resSeed,
-            goldSeedForWood: goldSeed,
-            goldSeedForWheat: goldSeed,
-            goldSeedForFish: goldSeed,
-            goldSeedForIron: goldSeed
+            woodSeed: world.INITIAL_WOOD_POOL_SEED(),
+            wheatSeed: world.INITIAL_WHEAT_POOL_SEED(),
+            fishSeed: world.INITIAL_FISH_POOL_SEED(),
+            ironSeed: world.INITIAL_IRON_POOL_SEED(),
+            goldSeedForWood: world.INITIAL_GOLD_SEED_FOR_WOOD(),
+            goldSeedForWheat: world.INITIAL_GOLD_SEED_FOR_WHEAT(),
+            goldSeedForFish: world.INITIAL_GOLD_SEED_FOR_FISH(),
+            goldSeedForIron: world.INITIAL_GOLD_SEED_FOR_IRON()
         });
     }
 
diff --git a/packages/contracts/test/StatusCodeEnumStability.t.sol b/packages/contracts/test/StatusCodeEnumStability.t.sol
index cde6873..356d7ad 100644
--- a/packages/contracts/test/StatusCodeEnumStability.t.sol
+++ b/packages/contracts/test/StatusCodeEnumStability.t.sol
@@ -37,5 +37,6 @@ contract StatusCodeEnumStabilityTest is Test {
         assertEq(uint8(StatusCode.ERR_MARKET_INSUFFICIENT_LIQUIDITY), 28, "ERR_MARKET_INSUFFICIENT_LIQUIDITY");
         assertEq(uint8(StatusCode.ERR_LIQUIDITY_INSUFFICIENT), 29, "ERR_LIQUIDITY_INSUFFICIENT");
         assertEq(uint8(StatusCode.ERR_MAX_GOLD_IN_EXCEEDED), 30, "ERR_MAX_GOLD_IN_EXCEEDED");
+        assertEq(uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), 31, "ERR_SLIPPAGE_REQUIRED");
     }
 }

## AUDIT SOURCE (docs/reviews/pr198-spec-compliance-uat.md from docs/spec-audit-phase-6 branch):

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
</stdin>
warning: Codex could not find bubblewrap on PATH. Install bubblewrap with your OS package manager. See the sandbox prerequisites: https://developers.openai.com/codex/concepts/sandboxing#prerequisites. Codex will use the vendored bubblewrap in the meantime.
codex
I’ll verify this against the checked-out Solidity code directly, with the four risky seams split across parallel reads: enum ordinals, market scheduling, validation ordering, and seed constant migration.
exec
/bin/bash -lc 'rg -n "enum StatusCode|ERR_MAX_GOLD_IN_EXCEEDED|ERR_SLIPPAGE_REQUIRED|StatusCodeEnumStability" packages/contracts/src/IClanWorld.sol packages/contracts/test/StatusCodeEnumStability.t.sol' in /tmp/wt-superswarm-357
 succeeded in 0ms:
packages/contracts/src/IClanWorld.sol:158:enum StatusCode {
packages/contracts/src/IClanWorld.sol:181:    ERR_MARKET_BUY_MAX_GOLD_EXCEEDED, // Deprecated/reserved legacy ordinal (replaced by ERR_MAX_GOLD_IN_EXCEEDED); kept only to preserve enum ordinal stability.
packages/contracts/src/IClanWorld.sol:189:    ERR_MAX_GOLD_IN_EXCEEDED,
packages/contracts/src/IClanWorld.sol:190:    ERR_SLIPPAGE_REQUIRED
packages/contracts/test/StatusCodeEnumStability.t.sol:7:contract StatusCodeEnumStabilityTest is Test {
packages/contracts/test/StatusCodeEnumStability.t.sol:39:        assertEq(uint8(StatusCode.ERR_MAX_GOLD_IN_EXCEEDED), 30, "ERR_MAX_GOLD_IN_EXCEEDED");
packages/contracts/test/StatusCodeEnumStability.t.sol:40:        assertEq(uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), 31, "ERR_SLIPPAGE_REQUIRED");

exec
/bin/bash -lc "rg -n \"executeAtTick|settlesAtTick|_enqueueScheduledMarketAction|_resolveScheduledAction|_executeScheduledMarketActions|_settleCompletingMissions|heartbeat\\(\" packages/contracts/src/ClanWorld.sol packages/contracts/test/ClanWorld.t.sol packages/contracts/test/HeartbeatOrdering.t.sol" in /tmp/wt-superswarm-357
 succeeded in 0ms:
packages/contracts/src/ClanWorld.sol:346:            // Path 3: ACTING at/past settlesAtTick → resolve
packages/contracts/src/ClanWorld.sol:347:            if (cs.state == ClansmanState.ACTING && tick >= m.settlesAtTick) {
packages/contracts/src/ClanWorld.sol:916:    function heartbeat() external override nonReentrant {
packages/contracts/src/ClanWorld.sol:929:        // Step 1: Settle missions that complete this tick (settlesAtTick == closedTick).
packages/contracts/src/ClanWorld.sol:931:        _settleCompletingMissions(closedTick);
packages/contracts/src/ClanWorld.sol:934:        _executeScheduledMarketActions(closedTick);
packages/contracts/src/ClanWorld.sol:950:    /// @dev Settle missions that complete exactly at `tick` (settlesAtTick == tick).
packages/contracts/src/ClanWorld.sol:953:    function _settleCompletingMissions(uint64 tick) internal {
packages/contracts/src/ClanWorld.sol:966:                if (m.settlesAtTick != tick) continue; // not due this tick
packages/contracts/src/ClanWorld.sol:1324:            _enqueueScheduledMarketAction(clanId, cs.clansmanId, existingM);
packages/contracts/src/ClanWorld.sol:1337:        m.settlesAtTick = order.action == ActionType.DefendBase
packages/contracts/src/ClanWorld.sol:1365:    function _enqueueScheduledMarketAction(uint32 clanId, uint32 clansmanId, Mission storage m) internal {
packages/contracts/src/ClanWorld.sol:1366:        uint64 executeAtTick = m.settlesAtTick;
packages/contracts/src/ClanWorld.sol:1368:            executeAtTick: executeAtTick,
packages/contracts/src/ClanWorld.sol:1378:        _scheduledMarketActions[executeAtTick].push(sma);
packages/contracts/src/ClanWorld.sol:1380:            executeAtTick, sma.commitSequence, clanId, clansmanId, m.action, m.marketToken, m.marketAmount, m.maxGoldIn
packages/contracts/src/ClanWorld.sol:1423:    function _executeScheduledMarketActions(uint64 tick) internal {
packages/contracts/src/ClanWorld.sol:2353:        return (m.submittedAtTick, m.executesAtTick, m.settlesAtTick);
packages/contracts/test/ClanWorld.t.sol:195:        world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:253:        world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:256:        world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:262:        world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:278:        world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:287:        world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:302:        world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:316:            world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:580:            mission.settlesAtTick,
packages/contracts/test/ClanWorld.t.sol:750:        uint64 executeAtTick = world.getActiveMission(csId).settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:751:        while (world.getWorldState().currentTick <= executeAtTick) {
packages/contracts/test/ClanWorld.t.sol:761:        uint64 returnTick = world.getActiveMission(csId).settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1009:        assertEq(world.getScheduledMarketActionsForTick(m.settlesAtTick).length, 1, "scheduled action queues at submit");
packages/contracts/test/ClanWorld.t.sol:1023:        assertEq(world.getScheduledMarketActionsForTick(m.settlesAtTick).length, 1, "scheduled action queues at submit");
packages/contracts/test/ClanWorld.t.sol:1035:        assertEq(world.getScheduledMarketActionsForTick(m.settlesAtTick).length, 1, "queue visible immediately");
packages/contracts/test/ClanWorld.t.sol:1265:        uint64 executeAtTick = m.settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1268:        // Advance ticks until the heartbeat before executeAtTick
packages/contracts/test/ClanWorld.t.sol:1270:        for (uint256 i = 0; i < uint256(executeAtTick - curTick); i++) {
packages/contracts/test/ClanWorld.t.sol:1283:            executeAtTick
packages/contracts/test/ClanWorld.t.sol:1316:        uint64 executeAtTick = m.settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1319:        uint256 ticksNeeded = uint256(executeAtTick - curTick) + 1;
packages/contracts/test/ClanWorld.t.sol:1348:        uint64 executeAtTick = m.settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1352:        if (executeAtTick > curTick) {
packages/contracts/test/ClanWorld.t.sol:1353:            for (uint256 i = 0; i < uint256(executeAtTick - curTick); i++) {
packages/contracts/test/ClanWorld.t.sol:1358:        // Now the next heartbeat will close executeAtTick — that's when MarketActionFailed fires
packages/contracts/test/ClanWorld.t.sol:1367:            executeAtTick
packages/contracts/test/ClanWorld.t.sol:1377:        assertEq(world.getScheduledMarketActionsForTick(executeAtTick).length, 0, "queue should be deleted");
packages/contracts/test/ClanWorld.t.sol:1389:        uint64 executeAtTick = m.settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1392:        _advanceUntilNextHeartbeatCloses(executeAtTick);
packages/contracts/test/ClanWorld.t.sol:1400:            executeAtTick
packages/contracts/test/ClanWorld.t.sol:1410:        assertEq(world.getScheduledMarketActionsForTick(executeAtTick).length, 0, "queue should be deleted");
packages/contracts/test/ClanWorld.t.sol:1447:        uint64 executeAtTick = m.settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1450:        _advanceUntilNextHeartbeatCloses(executeAtTick);
packages/contracts/test/ClanWorld.t.sol:1458:            executeAtTick
packages/contracts/test/ClanWorld.t.sol:1468:        assertEq(world.getScheduledMarketActionsForTick(executeAtTick).length, 0, "queue should be deleted");
packages/contracts/test/ClanWorld.t.sol:1487:        uint64 executeAtTick = m.settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1490:        uint256 ticksNeeded = uint256(executeAtTick - curTick) + 1;
packages/contracts/test/ClanWorld.t.sol:1497:            world.getScheduledMarketActionsForTick(executeAtTick).length, 0, "queue should be empty after heartbeat"
packages/contracts/test/ClanWorld.t.sol:1513:        uint64 oldExecuteAtTick = oldMission.settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1521:        uint64 newExecuteAtTick = newMission.settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1579:        uint64 executeAtTick = 2;
packages/contracts/test/ClanWorld.t.sol:1596:            if (settledAtTick != executeAtTick) continue;
packages/contracts/test/ClanWorld.t.sol:1601:        assertEq(world.getScheduledMarketActionsForTick(executeAtTick).length, 0, "queue should be deleted");
packages/contracts/test/ClanWorld.t.sol:1639:        uint64 executeAtTick = m.settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1643:        while (world.getWorldState().currentTick < executeAtTick) {
packages/contracts/test/ClanWorld.t.sol:1658:            if (settledAtTick != executeAtTick) continue;
packages/contracts/test/ClanWorld.t.sol:1721:        uint64 maxTick = m1.settlesAtTick > m2.settlesAtTick ? m1.settlesAtTick : m2.settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1798:        uint64 tick1 = world.getActiveMission(csId1).settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:1799:        uint64 tick2 = world.getActiveMission(csId2).settlesAtTick;
packages/contracts/test/ClanWorld.t.sol:2261:        harness.heartbeat();
packages/contracts/test/ClanWorld.t.sol:2333:    // Path 3: ACTING + tick >= settlesAtTick → resolves action
packages/contracts/test/ClanWorld.t.sol:2560:        // Phase 4.2: heartbeat eagerly settles missions at settlesAtTick (step 1 of heartbeat).
packages/contracts/test/ClanWorld.t.sol:2562:        assertGt(world.getClansman(csId).carryIron, 0, "onDemand: heartbeat settled mission at settlesAtTick");
packages/contracts/test/ClanWorld.t.sol:2694:            world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:2699:        world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:2720:            world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:2735:            world.heartbeat();
packages/contracts/test/ClanWorld.t.sol:2751:        world.heartbeat();
packages/contracts/test/HeartbeatOrdering.t.sol:66:        world.heartbeat();
packages/contracts/test/HeartbeatOrdering.t.sol:196:    //     (region 1) = 2 ticks travel. arrivalTick = T0+2, settlesAtTick = T0+3.
packages/contracts/test/HeartbeatOrdering.t.sol:198:    //     settlesAtTick = T0+2, matching the market action's arrival tick.
packages/contracts/test/HeartbeatOrdering.t.sol:216:        // cs0: submit Deposit. arrivalTick = t0+2, settlesAtTick = t0+3.
packages/contracts/test/HeartbeatOrdering.t.sol:221:        assertEq(depositMission.settlesAtTick, t0 + 3, "deposit settlesAtTick must be t0+3");
packages/contracts/test/HeartbeatOrdering.t.sol:236:        assertEq(sellMission.settlesAtTick, t0 + 2, "sell settlesAtTick must be t0+2");
packages/contracts/test/HeartbeatOrdering.t.sol:261:        world.heartbeat();
packages/contracts/test/HeartbeatOrdering.t.sol:273:        world.heartbeat();
packages/contracts/test/HeartbeatOrdering.t.sol:296:            world.heartbeat();
packages/contracts/test/HeartbeatOrdering.t.sol:318:        world.heartbeat();
packages/contracts/test/HeartbeatOrdering.t.sol:329:    //   - cs0 placed at Unicorn Town, deposits to Forest homebase: settlesAtTick = T0+3
packages/contracts/test/HeartbeatOrdering.t.sol:330:    //   - cs1 sells wood to UT from Forest: settlesAtTick = T0+2
packages/contracts/test/HeartbeatOrdering.t.sol:341:        // Deposit: arrivalTick = t0+2, settlesAtTick = t0+3.
packages/contracts/test/HeartbeatOrdering.t.sol:347:        assertEq(world.getActiveMission(csId0).settlesAtTick, t0 + 3, "deposit settlesAtTick must be t0+3");
packages/contracts/test/HeartbeatOrdering.t.sol:349:        // cs1: at Forest, sells wood to UT. Forest→UT = 2 ticks. settlesAtTick = t0+2.
packages/contracts/test/HeartbeatOrdering.t.sol:355:        assertEq(world.getActiveMission(csId1).settlesAtTick, t0 + 2, "sell settlesAtTick must be t0+2");

exec
/bin/bash -lc 'rg -n "ERR_SLIPPAGE_REQUIRED|maxGoldIn|ERR_CARRY_FULL|_validate|MarketBuy|MarketSell|remainingCarry" packages/contracts/src/ClanWorld.sol packages/contracts/test/ClanWorld.t.sol' in /tmp/wt-superswarm-357
 succeeded in 0ms:
packages/contracts/src/ClanWorld.sol:480:        } else if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
packages/contracts/src/ClanWorld.sol:1192:            StatusCode defendErr = _validateDefendBaseOrder(clan, order, order.gotoRegion);
packages/contracts/src/ClanWorld.sol:1211:        bool isMarketAction = order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell;
packages/contracts/src/ClanWorld.sol:1242:        StatusCode actionErr = _validateAction(clan, cs, order, ctx.gotoRegion);
packages/contracts/src/ClanWorld.sol:1339:            : (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell)
packages/contracts/src/ClanWorld.sol:1349:        m.marketMode = (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell)
packages/contracts/src/ClanWorld.sol:1355:        m.maxGoldIn = order.maxGoldIn;
packages/contracts/src/ClanWorld.sol:1376:            maxGoldIn: m.maxGoldIn
packages/contracts/src/ClanWorld.sol:1380:            executeAtTick, sma.commitSequence, clanId, clansmanId, m.action, m.marketToken, m.marketAmount, m.maxGoldIn
packages/contracts/src/ClanWorld.sol:1463:            if (sma.action == ActionType.MarketSell) {
packages/contracts/src/ClanWorld.sol:1464:                try this._executeMarketSellExternal(
packages/contracts/src/ClanWorld.sol:1480:            } else if (sma.action == ActionType.MarketBuy) {
packages/contracts/src/ClanWorld.sol:1481:                try this._executeMarketBuyExternal(
packages/contracts/src/ClanWorld.sol:1482:                    tick, sma.clanId, sma.clansmanId, sma.marketToken, sma.marketAmount, sma.maxGoldIn
packages/contracts/src/ClanWorld.sol:1524:    /// @dev External wrapper for _executeMarketSell — enables try/catch from heartbeat loop.
packages/contracts/src/ClanWorld.sol:1525:    function _executeMarketSellExternal(
packages/contracts/src/ClanWorld.sol:1533:        return _executeMarketSell(closedTick, clanId, clansmanId, token, amount);
packages/contracts/src/ClanWorld.sol:1536:    /// @dev External wrapper for _executeMarketBuy — enables try/catch from heartbeat loop.
packages/contracts/src/ClanWorld.sol:1537:    function _executeMarketBuyExternal(
packages/contracts/src/ClanWorld.sol:1543:        uint256 maxGoldIn
packages/contracts/src/ClanWorld.sol:1546:        return _executeMarketBuy(closedTick, clanId, clansmanId, token, amountOut, maxGoldIn);
packages/contracts/src/ClanWorld.sol:1726:    function _remainingCarryForToken(Clansman storage cs, address token) internal view returns (uint256) {
packages/contracts/src/ClanWorld.sol:1753:        if (order.action == ActionType.MarketSell) {
packages/contracts/src/ClanWorld.sol:1754:            return _executeImmediateMarketSell(clanId, clansmanId, order.marketToken, order.marketAmount);
packages/contracts/src/ClanWorld.sol:1756:        return _executeImmediateMarketBuy(clanId, clansmanId, order.marketToken, order.marketAmount, order.maxGoldIn);
packages/contracts/src/ClanWorld.sol:1759:    function _executeImmediateMarketSell(uint32 clanId, uint32 clansmanId, address token, uint256 amount)
packages/contracts/src/ClanWorld.sol:1767:                ActionType.MarketSell,
packages/contracts/src/ClanWorld.sol:1778:                ActionType.MarketSell,
packages/contracts/src/ClanWorld.sol:1791:                ActionType.MarketSell,
packages/contracts/src/ClanWorld.sol:1803:                ActionType.MarketSell,
packages/contracts/src/ClanWorld.sol:1815:                ActionType.MarketSell,
packages/contracts/src/ClanWorld.sol:1828:                ActionType.MarketSell,
packages/contracts/src/ClanWorld.sol:1836:    function _executeImmediateMarketBuy(
packages/contracts/src/ClanWorld.sol:1841:        uint256 maxGoldIn
packages/contracts/src/ClanWorld.sol:1847:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:1858:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:1866:        if (amountOut > _remainingCarryForToken(cs, token)) {
packages/contracts/src/ClanWorld.sol:1870:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:1872:                StatusCode.ERR_CARRY_FULL,
packages/contracts/src/ClanWorld.sol:1884:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:1892:        if (goldIn > maxGoldIn) {
packages/contracts/src/ClanWorld.sol:1896:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:1906:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:1913:        try StubPool(poolAddr).swapExactOutForInWithMaxIn(amountOut, maxGoldIn) returns (uint256 actualGoldIn) {
packages/contracts/src/ClanWorld.sol:1919:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:1931:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:1940:    function _executeMarketSell(uint64 closedTick, uint32 clanId, uint32 clansmanId, address token, uint256 amount)
packages/contracts/src/ClanWorld.sol:1948:                ActionType.MarketSell,
packages/contracts/src/ClanWorld.sol:1959:                ActionType.MarketSell,
packages/contracts/src/ClanWorld.sol:1972:                ActionType.MarketSell,
packages/contracts/src/ClanWorld.sol:1985:            ActionType.MarketSell,
packages/contracts/src/ClanWorld.sol:1996:    function _executeMarketBuy(
packages/contracts/src/ClanWorld.sol:2002:        uint256 maxGoldIn
packages/contracts/src/ClanWorld.sol:2008:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:2019:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:2027:        if (amountOut > _remainingCarryForToken(cs, token)) {
packages/contracts/src/ClanWorld.sol:2031:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:2033:                StatusCode.ERR_CARRY_FULL,
packages/contracts/src/ClanWorld.sol:2045:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:2054:        if (goldIn > maxGoldIn) {
packages/contracts/src/ClanWorld.sol:2058:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:2068:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:2076:        try StubPool(poolAddr).swapExactOutForInWithMaxIn(amountOut, maxGoldIn) returns (uint256 spentGold) {
packages/contracts/src/ClanWorld.sol:2082:                ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:2095:            ActionType.MarketBuy,
packages/contracts/src/ClanWorld.sol:2105:    function _validateAction(Clan storage clan, Clansman storage cs, ClanOrder calldata order, uint8 gotoRegion)
packages/contracts/src/ClanWorld.sol:2123:            if (!_hasCarryCapacityForWithdraw(cs, req)) return StatusCode.ERR_CARRY_FULL;
packages/contracts/src/ClanWorld.sol:2162:            return _validateDefendBaseOrder(clan, order, gotoRegion);
packages/contracts/src/ClanWorld.sol:2165:        // MarketBuy/MarketSell: must target Unicorn Town
packages/contracts/src/ClanWorld.sol:2166:        if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
packages/contracts/src/ClanWorld.sol:2183:            // MarketBuy uses maxGoldIn as its explicit slippage bound; zero would mean no protection.
packages/contracts/src/ClanWorld.sol:2184:            if (action == ActionType.MarketBuy && order.maxGoldIn == 0) {
packages/contracts/src/ClanWorld.sol:2185:                return StatusCode.ERR_SLIPPAGE_REQUIRED;
packages/contracts/src/ClanWorld.sol:2188:            if (action == ActionType.MarketBuy && order.marketAmount > _remainingCarryForToken(cs, tok)) {
packages/contracts/src/ClanWorld.sol:2189:                return StatusCode.ERR_CARRY_FULL;
packages/contracts/src/ClanWorld.sol:2191:            if (action == ActionType.MarketSell && !_hasCarryBalance(cs, tok, order.marketAmount)) {
packages/contracts/src/ClanWorld.sol:2206:    function _validateDefendBaseOrder(Clan storage clan, ClanOrder calldata order, uint8 gotoRegion)
packages/contracts/src/ClanWorld.sol:2370:                || action == ActionType.MarketBuy || action == ActionType.MarketSell
packages/contracts/test/ClanWorld.t.sol:215:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:240:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:400:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:411:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:460:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:710:        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_CARRY_FULL), "withdraw must fit carry cap");
packages/contracts/test/ClanWorld.t.sol:728:    function test_withdrawThenMarketSell_endToEnd() public {
packages/contracts/test/ClanWorld.t.sol:747:        OrderResult[] memory sell = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 5e18, 0);
packages/contracts/test/ClanWorld.t.sol:814:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:880:            maxGoldIn: maxGold,
packages/contracts/test/ClanWorld.t.sol:887:    function _submitAllClanMarketSells(uint32 clanId, address token) internal returns (uint256 count) {
packages/contracts/test/ClanWorld.t.sol:890:        return _submitFirstClanMarketSells(clanId, token, count);
packages/contracts/test/ClanWorld.t.sol:893:    function _submitFirstClanMarketSells(uint32 clanId, address token, uint256 count) internal returns (uint256) {
packages/contracts/test/ClanWorld.t.sol:901:                action: ActionType.MarketSell,
packages/contracts/test/ClanWorld.t.sol:905:                maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:949:    function test_immediateMarketSell_executesInSubmitTx() public {
packages/contracts/test/ClanWorld.t.sol:962:            ActionType.MarketSell,
packages/contracts/test/ClanWorld.t.sol:969:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 5e18, 0);
packages/contracts/test/ClanWorld.t.sol:992:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
packages/contracts/test/ClanWorld.t.sol:1003:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
packages/contracts/test/ClanWorld.t.sol:1017:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
packages/contracts/test/ClanWorld.t.sol:1031:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
packages/contracts/test/ClanWorld.t.sol:1039:    function test_immediateMarketBuy_executesWhenMaxGoldSatisfied() public {
packages/contracts/test/ClanWorld.t.sol:1051:            ActionType.MarketBuy,
packages/contracts/test/ClanWorld.t.sol:1058:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 2e18);
packages/contracts/test/ClanWorld.t.sol:1077:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 0);
packages/contracts/test/ClanWorld.t.sol:1081:        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), "zero maxGoldIn is ambiguous");
packages/contracts/test/ClanWorld.t.sol:1099:            ActionType.MarketBuy,
packages/contracts/test/ClanWorld.t.sol:1105:            _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 6e18, type(uint256).max);
packages/contracts/test/ClanWorld.t.sol:1123:    function test_immediateMarketBuy_maxGoldExceededFailsAndConsumesCooldown() public {
packages/contracts/test/ClanWorld.t.sol:1133:            ActionType.MarketBuy,
packages/contracts/test/ClanWorld.t.sol:1138:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 1);
packages/contracts/test/ClanWorld.t.sol:1154:    function test_immediateMarketBuy_insufficientGoldFailsAndConsumesCooldown() public {
packages/contracts/test/ClanWorld.t.sol:1164:            ActionType.MarketBuy,
packages/contracts/test/ClanWorld.t.sol:1169:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 7e18, 10e18);
packages/contracts/test/ClanWorld.t.sol:1183:    function test_immediateMarketBuy_overCapacityRejectsAtSubmit() public {
packages/contracts/test/ClanWorld.t.sol:1191:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 10e18);
packages/contracts/test/ClanWorld.t.sol:1196:        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_CARRY_FULL), "over-capacity buy should be rejected");
packages/contracts/test/ClanWorld.t.sol:1213:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
packages/contracts/test/ClanWorld.t.sol:1224:    function test_immediateMarketSell_failurePropagatesStatus() public {
packages/contracts/test/ClanWorld.t.sol:1233:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
packages/contracts/test/ClanWorld.t.sol:1260:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 5e18, 0);
packages/contracts/test/ClanWorld.t.sol:1278:            ActionType.MarketSell,
packages/contracts/test/ClanWorld.t.sol:1311:        // Submit buy order for 1e18 wood, maxGoldIn = generous 500e18
packages/contracts/test/ClanWorld.t.sol:1312:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 500e18);
packages/contracts/test/ClanWorld.t.sol:1335:    // Test 13: buy_maxGoldIn — buy fails with ERR_MAX_GOLD_IN_EXCEEDED
packages/contracts/test/ClanWorld.t.sol:1338:    function test_buy_maxGoldIn() public {
packages/contracts/test/ClanWorld.t.sol:1343:        // maxGoldIn = 1 wei (will always be exceeded for any nonzero buy)
packages/contracts/test/ClanWorld.t.sol:1344:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 1);
packages/contracts/test/ClanWorld.t.sol:1364:            ActionType.MarketBuy,
packages/contracts/test/ClanWorld.t.sol:1380:    function test_scheduledMarketBuy_insufficientGoldFailsAndConsumesCooldown() public {
packages/contracts/test/ClanWorld.t.sol:1385:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 7e18, 10e18);
packages/contracts/test/ClanWorld.t.sol:1397:            ActionType.MarketBuy,
packages/contracts/test/ClanWorld.t.sol:1413:    function test_scheduledMarketBuy_overCapacityRejectsAtSubmit() public {
packages/contracts/test/ClanWorld.t.sol:1423:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 10e18);
packages/contracts/test/ClanWorld.t.sol:1428:        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_CARRY_FULL), "over-capacity buy should be rejected");
packages/contracts/test/ClanWorld.t.sol:1437:    function test_scheduledMarketBuy_insufficientLiquidityFailsAndConsumesCooldown() public {
packages/contracts/test/ClanWorld.t.sol:1443:            _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 6e18, type(uint256).max);
packages/contracts/test/ClanWorld.t.sol:1455:            ActionType.MarketBuy,
packages/contracts/test/ClanWorld.t.sol:1483:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
packages/contracts/test/ClanWorld.t.sol:1510:        OrderResult[] memory r1 = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
packages/contracts/test/ClanWorld.t.sol:1518:        OrderResult[] memory r2 = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 2e18, 0);
packages/contracts/test/ClanWorld.t.sol:1570:            totalQueued += _submitAllClanMarketSells(distTwoClans[i], woodAddr);
packages/contracts/test/ClanWorld.t.sol:1576:            totalQueued += _submitAllClanMarketSells(distOneClans[i], woodAddr);
packages/contracts/test/ClanWorld.t.sol:1624:                action: ActionType.MarketSell,
packages/contracts/test/ClanWorld.t.sol:1628:                maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1693:            action: ActionType.MarketSell,
packages/contracts/test/ClanWorld.t.sol:1697:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1703:        // Clan 2: buy 1e18 wood with maxGoldIn = 100e18
packages/contracts/test/ClanWorld.t.sol:1708:            action: ActionType.MarketBuy,
packages/contracts/test/ClanWorld.t.sol:1712:            maxGoldIn: 100e18,
packages/contracts/test/ClanWorld.t.sol:1743:            if (eventClanId == clanId1 && eventCsId == csId1 && eventAction == ActionType.MarketSell) {
packages/contracts/test/ClanWorld.t.sol:1746:            if (eventClanId == clanId2 && eventCsId == csId2 && eventAction == ActionType.MarketBuy) {
packages/contracts/test/ClanWorld.t.sol:1780:        OrderResult[] memory buyFail = _submitMarketOrder(clanId1, csId1, ActionType.MarketBuy, woodAddr, 1e18, 1);
packages/contracts/test/ClanWorld.t.sol:1787:            action: ActionType.MarketSell,
packages/contracts/test/ClanWorld.t.sol:1791:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1828:            action: ActionType.MarketSell,
packages/contracts/test/ClanWorld.t.sol:1832:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1851:            action: ActionType.MarketSell,
packages/contracts/test/ClanWorld.t.sol:1855:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1865:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1899:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1972:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2005:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2128:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2251:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2439:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2511:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2616:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2628:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2640:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2652:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2779:            action: ActionType.MarketSell,
packages/contracts/test/ClanWorld.t.sol:2783:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2817:            action: ActionType.MarketSell,
packages/contracts/test/ClanWorld.t.sol:2821:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2848:            action: ActionType.MarketSell,
packages/contracts/test/ClanWorld.t.sol:2852:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2877:            action: ActionType.MarketBuy,
packages/contracts/test/ClanWorld.t.sol:2881:            maxGoldIn: type(uint256).max,

exec
/bin/bash -lc 'rg -n "INITIAL_RESOURCE_POOL_SEED|INITIAL_GOLD_POOL_SEED|INITIAL_WOOD_POOL_SEED|INITIAL_WHEAT_POOL_SEED|INITIAL_FISH_POOL_SEED|INITIAL_IRON_POOL_SEED|INITIAL_GOLD_SEED_FOR_" .' in /tmp/wt-superswarm-357
 succeeded in 0ms:
./packages/contracts/script/Deploy.s.sol:53:        uint256 woodSeed = game.INITIAL_WOOD_POOL_SEED();
./packages/contracts/script/Deploy.s.sol:54:        uint256 wheatSeed = game.INITIAL_WHEAT_POOL_SEED();
./packages/contracts/script/Deploy.s.sol:55:        uint256 fishSeed = game.INITIAL_FISH_POOL_SEED();
./packages/contracts/script/Deploy.s.sol:56:        uint256 ironSeed = game.INITIAL_IRON_POOL_SEED();
./packages/contracts/script/Deploy.s.sol:57:        uint256 goldForWood = game.INITIAL_GOLD_SEED_FOR_WOOD();
./packages/contracts/script/Deploy.s.sol:58:        uint256 goldForWheat = game.INITIAL_GOLD_SEED_FOR_WHEAT();
./packages/contracts/script/Deploy.s.sol:59:        uint256 goldForFish = game.INITIAL_GOLD_SEED_FOR_FISH();
./packages/contracts/script/Deploy.s.sol:60:        uint256 goldForIron = game.INITIAL_GOLD_SEED_FOR_IRON();
./packages/contracts/src/ClanWorld.sol:82:    uint256 public constant INITIAL_WOOD_POOL_SEED = 1_000e18;
./packages/contracts/src/ClanWorld.sol:83:    uint256 public constant INITIAL_WHEAT_POOL_SEED = 1_000e18;
./packages/contracts/src/ClanWorld.sol:84:    uint256 public constant INITIAL_FISH_POOL_SEED = 500e18;
./packages/contracts/src/ClanWorld.sol:85:    uint256 public constant INITIAL_IRON_POOL_SEED = 250e18;
./packages/contracts/src/ClanWorld.sol:86:    uint256 public constant INITIAL_GOLD_SEED_FOR_WOOD = 500e18;
./packages/contracts/src/ClanWorld.sol:87:    uint256 public constant INITIAL_GOLD_SEED_FOR_WHEAT = 700e18;
./packages/contracts/src/ClanWorld.sol:88:    uint256 public constant INITIAL_GOLD_SEED_FOR_FISH = 600e18;
./packages/contracts/src/ClanWorld.sol:89:    uint256 public constant INITIAL_GOLD_SEED_FOR_IRON = 800e18;
./packages/contracts/test/ClanWorld.t.sol:96:        return _setupMarketWithWoodSeed(world.INITIAL_WOOD_POOL_SEED());
./packages/contracts/test/ClanWorld.t.sol:125:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
./packages/contracts/test/ClanWorld.t.sol:126:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
./packages/contracts/test/ClanWorld.t.sol:127:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
./packages/contracts/test/ClanWorld.t.sol:128:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
./packages/contracts/test/ClanWorld.t.sol:129:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
./packages/contracts/test/ClanWorld.t.sol:130:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
./packages/contracts/test/ClanWorld.t.sol:131:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
./packages/contracts/test/ClanWorld.t.sol:932:        return _setupHarnessClanAtWithWoodSeed(state, region, cooldownEndsAtTs, world.INITIAL_WOOD_POOL_SEED());
./packages/contracts/test/HeartbeatOrdering.t.sol:155:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
./packages/contracts/test/HeartbeatOrdering.t.sol:156:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
./packages/contracts/test/HeartbeatOrdering.t.sol:157:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
./packages/contracts/test/HeartbeatOrdering.t.sol:158:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
./packages/contracts/test/HeartbeatOrdering.t.sol:159:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
./packages/contracts/test/HeartbeatOrdering.t.sol:160:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
./packages/contracts/test/HeartbeatOrdering.t.sol:161:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
./packages/contracts/test/HeartbeatOrdering.t.sol:162:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
./packages/contracts/test/Reentrancy.t.sol:172:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
./packages/contracts/test/Reentrancy.t.sol:173:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
./packages/contracts/test/Reentrancy.t.sol:174:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
./packages/contracts/test/Reentrancy.t.sol:175:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
./packages/contracts/test/Reentrancy.t.sol:176:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
./packages/contracts/test/Reentrancy.t.sol:177:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
./packages/contracts/test/Reentrancy.t.sol:178:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
./packages/contracts/test/Reentrancy.t.sol:179:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
./packages/contracts/test/SeedPools.t.sol:63:            woodToken, woodPool, world.INITIAL_WOOD_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WOOD(), "wood"
./packages/contracts/test/SeedPools.t.sol:66:            wheatToken, wheatPool, world.INITIAL_WHEAT_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WHEAT(), "wheat"
./packages/contracts/test/SeedPools.t.sol:69:            fishToken, fishPool, world.INITIAL_FISH_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_FISH(), "fish"
./packages/contracts/test/SeedPools.t.sol:72:            ironToken, ironPool, world.INITIAL_IRON_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_IRON(), "iron"
./packages/contracts/test/SeedPools.t.sol:102:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
./packages/contracts/test/SeedPools.t.sol:103:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
./packages/contracts/test/SeedPools.t.sol:104:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
./packages/contracts/test/SeedPools.t.sol:105:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
./packages/contracts/test/SeedPools.t.sol:106:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
./packages/contracts/test/SeedPools.t.sol:107:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
./packages/contracts/test/SeedPools.t.sol:108:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
./packages/contracts/test/SeedPools.t.sol:109:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
./packages/contracts/test/SeedPools.t.sol:127:            woodSeed: world.INITIAL_WOOD_POOL_SEED(),
./packages/contracts/test/SeedPools.t.sol:128:            wheatSeed: world.INITIAL_WHEAT_POOL_SEED(),
./packages/contracts/test/SeedPools.t.sol:129:            fishSeed: world.INITIAL_FISH_POOL_SEED(),
./packages/contracts/test/SeedPools.t.sol:130:            ironSeed: world.INITIAL_IRON_POOL_SEED(),
./packages/contracts/test/SeedPools.t.sol:131:            goldSeedForWood: world.INITIAL_GOLD_SEED_FOR_WOOD(),
./packages/contracts/test/SeedPools.t.sol:132:            goldSeedForWheat: world.INITIAL_GOLD_SEED_FOR_WHEAT(),
./packages/contracts/test/SeedPools.t.sol:133:            goldSeedForFish: world.INITIAL_GOLD_SEED_FOR_FISH(),
./packages/contracts/test/SeedPools.t.sol:134:            goldSeedForIron: world.INITIAL_GOLD_SEED_FOR_IRON()
./docs/reviews/pr357-codereview-codex-5-5.md:27:1. Default market seed ratios match v4 spec §5.11 — replaced uniform `INITIAL_RESOURCE_POOL_SEED=100_000e18` / `INITIAL_GOLD_POOL_SEED=50_000e18` with 8 asymmetric per-resource constants:
./docs/reviews/pr357-codereview-codex-5-5.md:28:   - INITIAL_WOOD_POOL_SEED=1_000e18, GOLD_FOR_WOOD=500e18
./docs/reviews/pr357-codereview-codex-5-5.md:29:   - INITIAL_WHEAT_POOL_SEED=1_000e18, GOLD_FOR_WHEAT=700e18
./docs/reviews/pr357-codereview-codex-5-5.md:30:   - INITIAL_FISH_POOL_SEED=500e18, GOLD_FOR_FISH=600e18
./docs/reviews/pr357-codereview-codex-5-5.md:31:   - INITIAL_IRON_POOL_SEED=250e18, GOLD_FOR_IRON=800e18
./docs/reviews/pr357-codereview-codex-5-5.md:47:4. **Pool seed migration** — all call sites updated? Search for `INITIAL_RESOURCE_POOL_SEED` and `INITIAL_GOLD_POOL_SEED` to verify no leftover uses.
./docs/reviews/pr357-codereview-codex-5-5.md:91:-        uint256 resSeed = game.INITIAL_RESOURCE_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:92:-        uint256 goldSeed = game.INITIAL_GOLD_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:94:+        uint256 woodSeed = game.INITIAL_WOOD_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:95:+        uint256 wheatSeed = game.INITIAL_WHEAT_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:96:+        uint256 fishSeed = game.INITIAL_FISH_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:97:+        uint256 ironSeed = game.INITIAL_IRON_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:98:+        uint256 goldForWood = game.INITIAL_GOLD_SEED_FOR_WOOD();
./docs/reviews/pr357-codereview-codex-5-5.md:99:+        uint256 goldForWheat = game.INITIAL_GOLD_SEED_FOR_WHEAT();
./docs/reviews/pr357-codereview-codex-5-5.md:100:+        uint256 goldForFish = game.INITIAL_GOLD_SEED_FOR_FISH();
./docs/reviews/pr357-codereview-codex-5-5.md:101:+        uint256 goldForIron = game.INITIAL_GOLD_SEED_FOR_IRON();
./docs/reviews/pr357-codereview-codex-5-5.md:153:-    uint256 public constant INITIAL_RESOURCE_POOL_SEED = 100_000e18;
./docs/reviews/pr357-codereview-codex-5-5.md:154:-    uint256 public constant INITIAL_GOLD_POOL_SEED = 50_000e18;
./docs/reviews/pr357-codereview-codex-5-5.md:155:+    uint256 public constant INITIAL_WOOD_POOL_SEED = 1_000e18;
./docs/reviews/pr357-codereview-codex-5-5.md:156:+    uint256 public constant INITIAL_WHEAT_POOL_SEED = 1_000e18;
./docs/reviews/pr357-codereview-codex-5-5.md:157:+    uint256 public constant INITIAL_FISH_POOL_SEED = 500e18;
./docs/reviews/pr357-codereview-codex-5-5.md:158:+    uint256 public constant INITIAL_IRON_POOL_SEED = 250e18;
./docs/reviews/pr357-codereview-codex-5-5.md:159:+    uint256 public constant INITIAL_GOLD_SEED_FOR_WOOD = 500e18;
./docs/reviews/pr357-codereview-codex-5-5.md:160:+    uint256 public constant INITIAL_GOLD_SEED_FOR_WHEAT = 700e18;
./docs/reviews/pr357-codereview-codex-5-5.md:161:+    uint256 public constant INITIAL_GOLD_SEED_FOR_FISH = 600e18;
./docs/reviews/pr357-codereview-codex-5-5.md:162:+    uint256 public constant INITIAL_GOLD_SEED_FOR_IRON = 800e18;
./docs/reviews/pr357-codereview-codex-5-5.md:210:-        return _setupMarketWithWoodSeed(world.INITIAL_RESOURCE_POOL_SEED());
./docs/reviews/pr357-codereview-codex-5-5.md:211:+        return _setupMarketWithWoodSeed(world.INITIAL_WOOD_POOL_SEED());
./docs/reviews/pr357-codereview-codex-5-5.md:220:-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:221:-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:223:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:224:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:225:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:226:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
./docs/reviews/pr357-codereview-codex-5-5.md:227:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
./docs/reviews/pr357-codereview-codex-5-5.md:228:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
./docs/reviews/pr357-codereview-codex-5-5.md:229:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
./docs/reviews/pr357-codereview-codex-5-5.md:273:-        return _setupHarnessClanAtWithWoodSeed(state, region, cooldownEndsAtTs, world.INITIAL_RESOURCE_POOL_SEED());
./docs/reviews/pr357-codereview-codex-5-5.md:274:+        return _setupHarnessClanAtWithWoodSeed(state, region, cooldownEndsAtTs, world.INITIAL_WOOD_POOL_SEED());
./docs/reviews/pr357-codereview-codex-5-5.md:359:-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:360:-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:367:+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:368:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:369:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:370:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:371:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
./docs/reviews/pr357-codereview-codex-5-5.md:372:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
./docs/reviews/pr357-codereview-codex-5-5.md:373:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
./docs/reviews/pr357-codereview-codex-5-5.md:374:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
./docs/reviews/pr357-codereview-codex-5-5.md:492:-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:493:-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:500:+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:501:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:502:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:503:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:504:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
./docs/reviews/pr357-codereview-codex-5-5.md:505:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
./docs/reviews/pr357-codereview-codex-5-5.md:506:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
./docs/reviews/pr357-codereview-codex-5-5.md:507:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
./docs/reviews/pr357-codereview-codex-5-5.md:554:-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:555:-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:562:+            woodToken, woodPool, world.INITIAL_WOOD_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WOOD(), "wood"
./docs/reviews/pr357-codereview-codex-5-5.md:565:+            wheatToken, wheatPool, world.INITIAL_WHEAT_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WHEAT(), "wheat"
./docs/reviews/pr357-codereview-codex-5-5.md:568:+            fishToken, fishPool, world.INITIAL_FISH_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_FISH(), "fish"
./docs/reviews/pr357-codereview-codex-5-5.md:571:+            ironToken, ironPool, world.INITIAL_IRON_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_IRON(), "iron"
./docs/reviews/pr357-codereview-codex-5-5.md:580:-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:581:-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:588:+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:589:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:590:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:591:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:592:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
./docs/reviews/pr357-codereview-codex-5-5.md:593:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
./docs/reviews/pr357-codereview-codex-5-5.md:594:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
./docs/reviews/pr357-codereview-codex-5-5.md:595:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
./docs/reviews/pr357-codereview-codex-5-5.md:616:-        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:617:-        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
./docs/reviews/pr357-codereview-codex-5-5.md:627:+            woodSeed: world.INITIAL_WOOD_POOL_SEED(),
./docs/reviews/pr357-codereview-codex-5-5.md:628:+            wheatSeed: world.INITIAL_WHEAT_POOL_SEED(),
./docs/reviews/pr357-codereview-codex-5-5.md:629:+            fishSeed: world.INITIAL_FISH_POOL_SEED(),
./docs/reviews/pr357-codereview-codex-5-5.md:630:+            ironSeed: world.INITIAL_IRON_POOL_SEED(),
./docs/reviews/pr357-codereview-codex-5-5.md:631:+            goldSeedForWood: world.INITIAL_GOLD_SEED_FOR_WOOD(),
./docs/reviews/pr357-codereview-codex-5-5.md:632:+            goldSeedForWheat: world.INITIAL_GOLD_SEED_FOR_WHEAT(),
./docs/reviews/pr357-codereview-codex-5-5.md:633:+            goldSeedForFish: world.INITIAL_GOLD_SEED_FOR_FISH(),
./docs/reviews/pr357-codereview-codex-5-5.md:634:+            goldSeedForIron: world.INITIAL_GOLD_SEED_FOR_IRON()
./docs/reviews/pr357-codereview-codex-5-5.md:736:| **Initial seed ratios** | Wood/Gold 1000:500; Wheat/Gold 1000:700; Fish/Gold 500:600; Iron/Gold 250:800 (§5.11) | `seedPools(PoolSeedConfig)` accepts arbitrary per-pool config from caller. Hardcoded constants `INITIAL_RESOURCE_POOL_SEED = 100_000e18`, `INITIAL_GOLD_POOL_SEED = 50_000e18` are uniform across pools and used by tests/deploy scripts. | `ClanWorld.sol:82-83`; `IClanWorld.sol:402-410`; `SeedPools.t.sol:114-127` | ⚠️ TRIVIAL — defaults are uniform; spec's asymmetric ratios are a deployer-config concern, not a contract-enforcement concern. PoolSeedConfig is the right surface; tests just don't test the spec's exact numbers. Deployer must pass spec ratios at seed time to comply. |
./docs/reviews/pr357-codereview-codex-5-5.md:861:| **AMM precision under tiny amounts** | What's the smallest sell that produces nonzero output? With `INITIAL_GOLD_POOL_SEED = 50_000e18` and `INITIAL_RESOURCE_POOL_SEED = 100_000e18`, `(50000e18 * 1) / (100000e18 + 1) ≈ 0` — does a 1-wei sell revert ("zero output") or silently fail? |
./docs/reviews/pr357-codereview-codex-5-5.md:966:2. **Default seed ratios match spec** (`ClanWorld.sol:82-83`) — split `INITIAL_RESOURCE_POOL_SEED` and `INITIAL_GOLD_POOL_SEED` into 4 per-pool constants matching §5.11 ratios. Or document that the spec ratios must be passed by the deployer.

codex
The first pass lines up with the PR description: the enum is appended, old seed constants only remain in review docs, and market actions now use `settlesAtTick == arrivalTick`. I’m drilling into the surrounding control flow now, because that’s where quiet review bugs usually hide.
exec
/bin/bash -lc "nl -ba packages/contracts/src/IClanWorld.sol | sed -n '150,195p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
   150	}
   151	
   152	enum MarketExecutionMode {
   153	    None,
   154	    Immediate,
   155	    Scheduled
   156	}
   157	
   158	enum StatusCode {
   159	    OK,
   160	    ERR_CLAN_DEAD,
   161	    ERR_CLAN_NOT_OWNED,
   162	    ERR_CLANSMAN_DEAD,
   163	    ERR_INVALID_CLANSMAN,
   164	    ERR_INVALID_REGION,
   165	    ERR_INVALID_ACTION,
   166	    ERR_INVALID_TARGET,
   167	    ERR_COOLDOWN_ACTIVE,
   168	    ERR_NOT_WAITING,
   169	    ERR_NOT_IN_UNICORN_TOWN,
   170	    ERR_NOT_AT_HOMEBASE,
   171	    ERR_NOT_AT_TARGET_BASE,
   172	    ERR_NOT_DEFENDABLE,
   173	    ERR_MISSING_RESOURCES,
   174	    ERR_EMPTY_CARGO,
   175	    ERR_PLOT_NOT_READY,
   176	    ERR_PLOT_EMPTY,
   177	    ERR_MARKET_ZERO_AMOUNT,
   178	    ERR_MARKET_UNSUPPORTED_TOKEN,
   179	    ERR_IMMEDIATE_MARKET_NOT_ELIGIBLE,
   180	    ERR_MARKET_BUY_OVER_CAPACITY,
   181	    ERR_MARKET_BUY_MAX_GOLD_EXCEEDED, // Deprecated/reserved legacy ordinal (replaced by ERR_MAX_GOLD_IN_EXCEEDED); kept only to preserve enum ordinal stability.
   182	    ERR_WORLD_TICK_MISMATCH,
   183	    ERR_NO_ACTIVE_BANDIT,
   184	    ERR_SEASON_ENDED,
   185	    ERR_NOT_ENOUGH_GOLD,
   186	    ERR_CARRY_FULL,
   187	    ERR_MARKET_INSUFFICIENT_LIQUIDITY, // Deprecated/reserved legacy ordinal (replaced by ERR_LIQUIDITY_INSUFFICIENT); kept only to preserve enum ordinal stability.
   188	    ERR_LIQUIDITY_INSUFFICIENT,
   189	    ERR_MAX_GOLD_IN_EXCEEDED,
   190	    ERR_SLIPPAGE_REQUIRED
   191	}
   192	
   193	// =============================================================================
   194	// CORE STATE STRUCTS (raw storage shape)
   195	// =============================================================================

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '1140,1390p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
  1140	                        status: StatusCode.ERR_INVALID_ACTION,
  1141	                        cooldownEndsAtTs: 0,
  1142	                        missionNonce: 0,
  1143	                        marketMode: MarketExecutionMode.None
  1144	                    });
  1145	                }
  1146	                return results;
  1147	            }
  1148	        }
  1149	
  1150	        // Lazy settle before processing orders
  1151	        _settleClan(clanId);
  1152	
  1153	        results = new OrderResult[](orders.length);
  1154	
  1155	        for (uint256 i = 0; i < orders.length; i++) {
  1156	            results[i] = _processOrder(clanId, clan, orders[i]);
  1157	        }
  1158	
  1159	        return results;
  1160	    }
  1161	
  1162	    struct OrderCtx {
  1163	        uint8 gotoRegion;
  1164	        uint8 fromRegion;
  1165	        bool isNoop;
  1166	        uint8 travelTicks;
  1167	        uint64 arrivalTick;
  1168	        uint64 newNonce;
  1169	        uint32 targetClanId;
  1170	        bool wasActive;
  1171	        uint64 oldNonce;
  1172	    }
  1173	
  1174	    function _processOrder(uint32 clanId, Clan storage clan, ClanOrder calldata order)
  1175	        internal
  1176	        returns (OrderResult memory result)
  1177	    {
  1178	        result.clansmanId = order.clansmanId;
  1179	
  1180	        // Validate clansman
  1181	        Clansman storage cs = _clansmen[order.clansmanId];
  1182	        if (cs.clansmanId == 0 || cs.clanId != clanId) {
  1183	            result.status = StatusCode.ERR_INVALID_CLANSMAN;
  1184	            return result;
  1185	        }
  1186	        if (cs.state == ClansmanState.DEAD) {
  1187	            result.status = StatusCode.ERR_CLANSMAN_DEAD;
  1188	            return result;
  1189	        }
  1190	
  1191	        if (order.action == ActionType.DefendBase) {
  1192	            StatusCode defendErr = _validateDefendBaseOrder(clan, order, order.gotoRegion);
  1193	            if (defendErr != StatusCode.OK) {
  1194	                result.status = defendErr;
  1195	                return result;
  1196	            }
  1197	
  1198	            uint32 defendTargetClanId = order.targetClanId == 0 ? clanId : order.targetClanId;
  1199	            Mission storage currentM = _missions[order.clansmanId];
  1200	            if (
  1201	                currentM.active && currentM.action == ActionType.DefendBase && currentM.targetRegion == order.gotoRegion
  1202	                    && currentM.targetClanId == defendTargetClanId
  1203	            ) {
  1204	                result.status = StatusCode.OK;
  1205	                result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
  1206	                result.missionNonce = currentM.nonce;
  1207	                return result;
  1208	            }
  1209	        }
  1210	
  1211	        bool isMarketAction = order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell;
  1212	
  1213	        // Cooldown check. Market orders may still fall back to the scheduled path;
  1214	        // only the immediate path requires the worker to be off cooldown.
  1215	        if (block.timestamp < cs.cooldownEndsAtTs) {
  1216	            result.status = StatusCode.ERR_COOLDOWN_ACTIVE;
  1217	            result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
  1218	            result.missionNonce = cs.lastMissionNonce;
  1219	            return result;
  1220	        }
  1221	
  1222	        OrderCtx memory ctx;
  1223	        ctx.fromRegion = cs.currentRegion;
  1224	        ctx.gotoRegion = order.gotoRegion;
  1225	        ctx.targetClanId =
  1226	            order.action == ActionType.DefendBase && order.targetClanId == 0 ? clanId : order.targetClanId;
  1227	
  1228	        // NOOP bypass: treat 0 as "stay here"; DefendBase requires explicit home region.
  1229	        ctx.isNoop = order.action != ActionType.DefendBase
  1230	            && (ctx.gotoRegion == ClanWorldConstants.REGION_NOOP || ctx.gotoRegion == ctx.fromRegion);
  1231	        if (ctx.isNoop) {
  1232	            ctx.gotoRegion = ctx.fromRegion;
  1233	        }
  1234	
  1235	        // Validate target region (1-8 or 0=noop)
  1236	        if (ctx.gotoRegion > 8) {
  1237	            result.status = StatusCode.ERR_INVALID_REGION;
  1238	            return result;
  1239	        }
  1240	
  1241	        // Validate action
  1242	        StatusCode actionErr = _validateAction(clan, cs, order, ctx.gotoRegion);
  1243	        if (actionErr != StatusCode.OK) {
  1244	            result.status = actionErr;
  1245	            return result;
  1246	        }
  1247	
  1248	        if (
  1249	            isMarketAction && ctx.fromRegion == ClanWorldConstants.REGION_UNICORN_TOWN
  1250	                && cs.state == ClansmanState.WAITING && block.timestamp >= cs.cooldownEndsAtTs
  1251	        ) {
  1252	            ctx.newNonce = cs.lastMissionNonce + 1;
  1253	            cs.lastMissionNonce = ctx.newNonce;
  1254	
  1255	            StatusCode marketStatus = _executeImmediateMarket(clanId, order, cs.clansmanId);
  1256	
  1257	            if (marketStatus == StatusCode.OK) {
  1258	                cs.state = ClansmanState.WAITING;
  1259	                cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
  1260	            }
  1261	            _clearDefender(cs.clansmanId);
  1262	
  1263	            result.status = marketStatus;
  1264	            result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
  1265	            result.missionNonce = ctx.newNonce;
  1266	            result.marketMode = MarketExecutionMode.Immediate;
  1267	            return result;
  1268	        }
  1269	
  1270	        // Capture existing mission state
  1271	        Mission storage existingM = _missions[order.clansmanId];
  1272	        ctx.wasActive = existingM.active;
  1273	        ctx.oldNonce = existingM.nonce;
  1274	
  1275	        // Compute travel from the clansman's current region to the order target.
  1276	        ctx.travelTicks = _travelTicks(ctx.fromRegion, ctx.gotoRegion);
  1277	        ctx.arrivalTick = _addTicksClamped(_world.currentTick, uint64(ctx.travelTicks));
  1278	
  1279	        // New nonce
  1280	        ctx.newNonce = cs.lastMissionNonce + 1;
  1281	        cs.lastMissionNonce = ctx.newNonce;
  1282	
  1283	        // Install mission via helper to keep stack shallow
  1284	        _installMission(existingM, order, cs, ctx);
  1285	
  1286	        // Update clansman state
  1287	        if (ctx.travelTicks > 0) {
  1288	            cs.state = ClansmanState.TRAVELING;
  1289	        } else {
  1290	            // NOOP / same-region: no traveling state per v4.3 §A
  1291	            cs.state = ClansmanState.ACTING;
  1292	            cs.currentRegion = ctx.gotoRegion;
  1293	        }
  1294	
  1295	        // Start cooldown
  1296	        cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
  1297	
  1298	        _clearDefender(cs.clansmanId);
  1299	
  1300	        if (order.action == ActionType.DefendBase && ctx.travelTicks == 0) {
  1301	            _registerDefender(ctx.gotoRegion, clanId, cs.clansmanId);
  1302	        }
  1303	
  1304	        if (ctx.wasActive) {
  1305	            emit MissionInterrupted(clanId, order.clansmanId, ctx.oldNonce, ctx.newNonce);
  1306	        }
  1307	
  1308	        emit MissionAssigned(
  1309	            clanId,
  1310	            order.clansmanId,
  1311	            ctx.newNonce,
  1312	            order.action,
  1313	            ctx.fromRegion,
  1314	            ctx.gotoRegion,
  1315	            _world.currentTick,
  1316	            ctx.arrivalTick
  1317	        );
  1318	
  1319	        result.status = StatusCode.OK;
  1320	        result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
  1321	        result.missionNonce = ctx.newNonce;
  1322	        result.marketMode = isMarketAction ? MarketExecutionMode.Scheduled : MarketExecutionMode.None;
  1323	        if (isMarketAction) {
  1324	            _enqueueScheduledMarketAction(clanId, cs.clansmanId, existingM);
  1325	        }
  1326	        return result;
  1327	    }
  1328	
  1329	    function _installMission(Mission storage m, ClanOrder calldata order, Clansman storage cs, OrderCtx memory ctx)
  1330	        internal
  1331	    {
  1332	        m.active = true;
  1333	        m.nonce = ctx.newNonce;
  1334	        m.clansmanId = cs.clansmanId;
  1335	        m.submittedAtTick = _world.currentTick;
  1336	        m.executesAtTick = ctx.arrivalTick;
  1337	        m.settlesAtTick = order.action == ActionType.DefendBase
  1338	            ? type(uint64).max
  1339	            : (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell)
  1340	                ? ctx.arrivalTick
  1341	                : _addTicksClamped(ctx.arrivalTick, getActionDuration(order.action));
  1342	        m.startRegion = ctx.fromRegion;
  1343	        m.targetRegion = ctx.gotoRegion;
  1344	        m.action = order.action;
  1345	        m.startTick = _world.currentTick;
  1346	        m.arrivalTick = ctx.arrivalTick;
  1347	        m.actionStartTick = ctx.arrivalTick;
  1348	        m.missionSeed = keccak256(abi.encode(_world.currentTickSeed, cs.clansmanId, ctx.newNonce));
  1349	        m.marketMode = (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell)
  1350	            ? MarketExecutionMode.Scheduled
  1351	            : MarketExecutionMode.None;
  1352	        m.targetClanId = ctx.targetClanId;
  1353	        m.marketToken = order.marketToken;
  1354	        m.marketAmount = order.marketAmount;
  1355	        m.maxGoldIn = order.maxGoldIn;
  1356	        m.withdrawResources = order.withdrawResources;
  1357	
  1358	        if (m.marketMode == MarketExecutionMode.Scheduled) {
  1359	            _marketMissionCommitSequence[cs.clansmanId] = _world.nextCommitSequence++;
  1360	        } else {
  1361	            delete _marketMissionCommitSequence[cs.clansmanId];
  1362	        }
  1363	    }
  1364	
  1365	    function _enqueueScheduledMarketAction(uint32 clanId, uint32 clansmanId, Mission storage m) internal {
  1366	        uint64 executeAtTick = m.settlesAtTick;
  1367	        ScheduledMarketAction memory sma = ScheduledMarketAction({
  1368	            executeAtTick: executeAtTick,
  1369	            commitSequence: _marketMissionCommitSequence[clansmanId],
  1370	            missionNonce: m.nonce,
  1371	            clanId: clanId,
  1372	            clansmanId: clansmanId,
  1373	            action: m.action,
  1374	            marketToken: m.marketToken,
  1375	            marketAmount: m.marketAmount,
  1376	            maxGoldIn: m.maxGoldIn
  1377	        });
  1378	        _scheduledMarketActions[executeAtTick].push(sma);
  1379	        emit ScheduledMarketActionCommitted(
  1380	            executeAtTick, sma.commitSequence, clanId, clansmanId, m.action, m.marketToken, m.marketAmount, m.maxGoldIn
  1381	        );
  1382	    }
  1383	
  1384	    function _registerDefender(uint8 region, uint32 clanId, uint32 clansmanId) internal {
  1385	        if (_clansmanDefendingRegion[clansmanId] == region) return;
  1386	        _clearDefender(clansmanId);
  1387	
  1388	        if (_defenderCountByRegionClan[region][clanId] == 0) {
  1389	            _defendingClansByRegion[region].push(clanId);
  1390	        }

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '916,990p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
   916	    function heartbeat() external override nonReentrant {
   917	        require(block.timestamp >= _world.nextHeartbeatAtTs, "ClanWorld: heartbeat rate limited");
   918	
   919	        uint64 closedTick = _world.currentTick;
   920	
   921	        // CEI: update rate-limit guard before any external calls
   922	        _world.nextHeartbeatAtTs = uint64(block.timestamp) + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS;
   923	
   924	        // Derive and publish seed for closedTick before step 1 (settlement reads it for RNG)
   925	        bytes32 newSeed = keccak256(abi.encode(block.prevrandao, _world.currentTickSeed, closedTick));
   926	        _tickSeeds[closedTick] = newSeed;
   927	        _world.currentTickSeed = newSeed;
   928	
   929	        // Step 1: Settle missions that complete this tick (settlesAtTick == closedTick).
   930	        // Bounded by 12-clan cap x 4 clansmen = 48 max iterations.
   931	        _settleCompletingMissions(closedTick);
   932	
   933	        // Step 2: Execute scheduled market actions for closedTick (may make external calls).
   934	        _executeScheduledMarketActions(closedTick);
   935	
   936	        // Step 3: Eager-settle clans touched by world events (Phase 3 bandit — stub).
   937	        // TODO Phase 3: _settleClansNearBandit(closedTick);
   938	
   939	        // Step 4: Resolve world events (season boundary, winter transitions).
   940	        _resolveWorldEvents(closedTick);
   941	
   942	        // Step 5: Increment tick and publish (seed already written above; complete the atomic pair).
   943	        uint64 newTick = closedTick + 1;
   944	        _world.currentTick = newTick;
   945	        _world.nextHeartbeatAtTick = newTick + 1;
   946	
   947	        emit TickAdvanced(closedTick, newTick, newSeed);
   948	    }
   949	
   950	    /// @dev Settle missions that complete exactly at `tick` (settlesAtTick == tick).
   951	    ///      Called from heartbeat before market execution and tick increment.
   952	    ///      Bounded by 12-clan cap x 4 clansmen = 48 max iterations.
   953	    function _settleCompletingMissions(uint64 tick) internal {
   954	        for (uint256 i = 0; i < _allClanIds.length; i++) {
   955	            uint32 clanId = _allClanIds[i];
   956	            Clan storage clan = _clans[clanId];
   957	            if (clan.clanState == ClanState.DEAD) continue;
   958	
   959	            uint32[] storage csIds = _clanClansmanIds[clanId];
   960	            for (uint256 j = 0; j < csIds.length; j++) {
   961	                Clansman storage cs = _clansmen[csIds[j]];
   962	                if (cs.state == ClansmanState.DEAD) continue;
   963	
   964	                Mission storage m = _missions[cs.clansmanId];
   965	                if (!m.active) continue;
   966	                if (m.settlesAtTick != tick) continue; // not due this tick
   967	
   968	                // Settle this mission using the single-tick range [tick, tick+1).
   969	                _settleMissionForClansman(clan, cs, clanId, tick, tick + 1);
   970	            }
   971	        }
   972	    }
   973	
   974	    /// @dev Resolve world events for the tick that was just closed.
   975	    ///      Uses closedTick+1 as the equivalent of the old `newTick` for transition checks.
   976	    function _resolveWorldEvents(uint64 closedTick) internal {
   977	        uint64 newTick = closedTick + 1;
   978	
   979	        // --- season boundary ---
   980	        if (newTick >= _world.seasonEndTick) {
   981	            _world.currentSeasonNumber += 1;
   982	            _world.seasonStartTick = _world.seasonEndTick;
   983	            _world.seasonEndTick = _world.seasonStartTick + ClanWorldConstants.SEASON_DURATION_TICKS;
   984	            // reset winter timers for new season
   985	            _world.winterActive = false;
   986	            _world.winterStartsAtTick = _world.seasonStartTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE
   987	                - ClanWorldConstants.WINTER_DURATION_TICKS;
   988	            _world.winterEndsAtTick = _world.seasonStartTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE;
   989	        }
   990	

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '1400,1555p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
  1400	        uint256 count = _defenderCountByRegionClan[region][clanId];
  1401	        if (count > 1) {
  1402	            _defenderCountByRegionClan[region][clanId] = count - 1;
  1403	        } else {
  1404	            delete _defenderCountByRegionClan[region][clanId];
  1405	            uint32[] storage clans = _defendingClansByRegion[region];
  1406	            for (uint256 i = 0; i < clans.length; i++) {
  1407	                if (clans[i] == clanId) {
  1408	                    clans[i] = clans[clans.length - 1];
  1409	                    clans.pop();
  1410	                    break;
  1411	                }
  1412	            }
  1413	        }
  1414	
  1415	        delete _clansmanDefendingRegion[clansmanId];
  1416	    }
  1417	
  1418	    // =========================================================================
  1419	    // MARKET EXECUTION (Phase 2)
  1420	    // =========================================================================
  1421	
  1422	    /// @dev Execute the full scheduled market queue for the given tick, then delete it.
  1423	    function _executeScheduledMarketActions(uint64 tick) internal {
  1424	        ScheduledMarketAction[] storage actions = _scheduledMarketActions[tick];
  1425	        uint256 len = actions.length;
  1426	        if (len == 0) return;
  1427	
  1428	        _sortScheduledMarketActionsByCommitSequence(actions);
  1429	
  1430	        for (uint256 i = 0; i < len; i++) {
  1431	            ScheduledMarketAction storage sma = actions[i];
  1432	
  1433	            // Validate clansman still belongs to the clan
  1434	            Clansman storage cs = _clansmen[sma.clansmanId];
  1435	            if (cs.clanId != sma.clanId || cs.state == ClansmanState.DEAD) {
  1436	                _emitMarketActionFailed(
  1437	                    sma.clanId,
  1438	                    sma.clansmanId,
  1439	                    sma.action,
  1440	                    MarketExecutionMode.Scheduled,
  1441	                    StatusCode.ERR_INVALID_CLANSMAN,
  1442	                    tick
  1443	                );
  1444	                continue;
  1445	            }
  1446	
  1447	            // Guard: clansman was re-tasked if mission action no longer matches the queued type.
  1448	            // Note: _completeMission sets m.active=false during settlement (by design), so we
  1449	            // cannot use m.active as a validity signal here — check action type and nonce.
  1450	            Mission storage m = _missions[sma.clansmanId];
  1451	            if (m.action != sma.action || m.nonce != sma.missionNonce) {
  1452	                _emitMarketActionFailed(
  1453	                    sma.clanId,
  1454	                    sma.clansmanId,
  1455	                    sma.action,
  1456	                    MarketExecutionMode.Scheduled,
  1457	                    StatusCode.ERR_INVALID_ACTION,
  1458	                    tick
  1459	                );
  1460	                continue;
  1461	            }
  1462	
  1463	            if (sma.action == ActionType.MarketSell) {
  1464	                try this._executeMarketSellExternal(
  1465	                    tick, sma.clanId, sma.clansmanId, sma.marketToken, sma.marketAmount
  1466	                ) returns (
  1467	                    StatusCode marketStatus
  1468	                ) {
  1469	                    marketStatus;
  1470	                } catch {
  1471	                    _handleMarketFailure(
  1472	                        sma.clanId,
  1473	                        sma.clansmanId,
  1474	                        sma.action,
  1475	                        MarketExecutionMode.Scheduled,
  1476	                        StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
  1477	                        tick
  1478	                    );
  1479	                }
  1480	            } else if (sma.action == ActionType.MarketBuy) {
  1481	                try this._executeMarketBuyExternal(
  1482	                    tick, sma.clanId, sma.clansmanId, sma.marketToken, sma.marketAmount, sma.maxGoldIn
  1483	                ) returns (
  1484	                    StatusCode marketStatus
  1485	                ) {
  1486	                    marketStatus;
  1487	                } catch {
  1488	                    _handleMarketFailure(
  1489	                        sma.clanId,
  1490	                        sma.clansmanId,
  1491	                        sma.action,
  1492	                        MarketExecutionMode.Scheduled,
  1493	                        StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
  1494	                        tick
  1495	                    );
  1496	                }
  1497	            }
  1498	        }
  1499	
  1500	        delete _scheduledMarketActions[tick];
  1501	    }
  1502	
  1503	    function _sortScheduledMarketActionsByCommitSequence(ScheduledMarketAction[] storage actions) internal {
  1504	        uint256 len = actions.length;
  1505	        if (len <= 1) return;
  1506	        ScheduledMarketAction[] memory arr = new ScheduledMarketAction[](len);
  1507	        for (uint256 i = 0; i < len; i++) {
  1508	            arr[i] = actions[i];
  1509	        }
  1510	        for (uint256 i = 1; i < len; i++) {
  1511	            ScheduledMarketAction memory key = arr[i];
  1512	            uint256 j = i;
  1513	            while (j > 0 && arr[j - 1].commitSequence > key.commitSequence) {
  1514	                arr[j] = arr[j - 1];
  1515	                j--;
  1516	            }
  1517	            arr[j] = key;
  1518	        }
  1519	        for (uint256 i = 0; i < len; i++) {
  1520	            actions[i] = arr[i];
  1521	        }
  1522	    }
  1523	
  1524	    /// @dev External wrapper for _executeMarketSell — enables try/catch from heartbeat loop.
  1525	    function _executeMarketSellExternal(
  1526	        uint64 closedTick,
  1527	        uint32 clanId,
  1528	        uint32 clansmanId,
  1529	        address token,
  1530	        uint256 amount
  1531	    ) external returns (StatusCode) {
  1532	        require(msg.sender == address(this), "ClanWorld: internal only");
  1533	        return _executeMarketSell(closedTick, clanId, clansmanId, token, amount);
  1534	    }
  1535	
  1536	    /// @dev External wrapper for _executeMarketBuy — enables try/catch from heartbeat loop.
  1537	    function _executeMarketBuyExternal(
  1538	        uint64 closedTick,
  1539	        uint32 clanId,
  1540	        uint32 clansmanId,
  1541	        address token,
  1542	        uint256 amountOut,
  1543	        uint256 maxGoldIn
  1544	    ) external returns (StatusCode) {
  1545	        require(msg.sender == address(this), "ClanWorld: internal only");
  1546	        return _executeMarketBuy(closedTick, clanId, clansmanId, token, amountOut, maxGoldIn);
  1547	    }
  1548	
  1549	    /// @dev Map a resource token address to its pool address.
  1550	    function _poolFor(address token) internal view returns (address pool) {
  1551	        if (token == _treasury.woodToken) return _treasury.woodGoldPool;
  1552	        if (token == _treasury.ironToken) return _treasury.ironGoldPool;
  1553	        if (token == _treasury.wheatToken) return _treasury.wheatGoldPool;
  1554	        if (token == _treasury.fishToken) return _treasury.fishGoldPool;
  1555	        return address(0);

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '1830,2108p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
  1830	                StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
  1831	                _world.currentTick
  1832	            );
  1833	        }
  1834	    }
  1835	
  1836	    function _executeImmediateMarketBuy(
  1837	        uint32 clanId,
  1838	        uint32 clansmanId,
  1839	        address token,
  1840	        uint256 amountOut,
  1841	        uint256 maxGoldIn
  1842	    ) internal returns (StatusCode) {
  1843	        if (!_treasury.poolsSeeded) {
  1844	            return _handleMarketFailure(
  1845	                clanId,
  1846	                clansmanId,
  1847	                ActionType.MarketBuy,
  1848	                MarketExecutionMode.Immediate,
  1849	                StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN,
  1850	                _world.currentTick
  1851	            );
  1852	        }
  1853	        address poolAddr = _poolFor(token);
  1854	        if (poolAddr == address(0)) {
  1855	            return _handleMarketFailure(
  1856	                clanId,
  1857	                clansmanId,
  1858	                ActionType.MarketBuy,
  1859	                MarketExecutionMode.Immediate,
  1860	                StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN,
  1861	                _world.currentTick
  1862	            );
  1863	        }
  1864	
  1865	        Clansman storage cs = _clansmen[clansmanId];
  1866	        if (amountOut > _remainingCarryForToken(cs, token)) {
  1867	            return _handleMarketFailure(
  1868	                clanId,
  1869	                clansmanId,
  1870	                ActionType.MarketBuy,
  1871	                MarketExecutionMode.Immediate,
  1872	                StatusCode.ERR_CARRY_FULL,
  1873	                _world.currentTick
  1874	            );
  1875	        }
  1876	
  1877	        uint256 goldIn;
  1878	        try StubPool(poolAddr).getAmountInForExactOut(amountOut) returns (uint256 quotedGoldIn) {
  1879	            goldIn = quotedGoldIn;
  1880	        } catch {
  1881	            return _handleMarketFailure(
  1882	                clanId,
  1883	                clansmanId,
  1884	                ActionType.MarketBuy,
  1885	                MarketExecutionMode.Immediate,
  1886	                StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
  1887	                _world.currentTick
  1888	            );
  1889	        }
  1890	
  1891	        Clan storage clan = _clans[clanId];
  1892	        if (goldIn > maxGoldIn) {
  1893	            return _handleMarketFailure(
  1894	                clanId,
  1895	                clansmanId,
  1896	                ActionType.MarketBuy,
  1897	                MarketExecutionMode.Immediate,
  1898	                StatusCode.ERR_MAX_GOLD_IN_EXCEEDED,
  1899	                _world.currentTick
  1900	            );
  1901	        }
  1902	        if (clan.goldBalance < goldIn) {
  1903	            return _handleMarketFailure(
  1904	                clanId,
  1905	                clansmanId,
  1906	                ActionType.MarketBuy,
  1907	                MarketExecutionMode.Immediate,
  1908	                StatusCode.ERR_NOT_ENOUGH_GOLD,
  1909	                _world.currentTick
  1910	            );
  1911	        }
  1912	
  1913	        try StubPool(poolAddr).swapExactOutForInWithMaxIn(amountOut, maxGoldIn) returns (uint256 actualGoldIn) {
  1914	            clan.goldBalance -= actualGoldIn;
  1915	            _addToCarry(cs, token, amountOut);
  1916	            emit ImmediateMarketActionExecuted(
  1917	                clanId,
  1918	                clansmanId,
  1919	                ActionType.MarketBuy,
  1920	                ClanWorldConstants.RESOURCE_GOLD,
  1921	                actualGoldIn,
  1922	                _marketResourceForToken(token),
  1923	                amountOut,
  1924	                _world.currentTick
  1925	            );
  1926	            return StatusCode.OK;
  1927	        } catch {
  1928	            return _handleMarketFailure(
  1929	                clanId,
  1930	                clansmanId,
  1931	                ActionType.MarketBuy,
  1932	                MarketExecutionMode.Immediate,
  1933	                StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
  1934	                _world.currentTick
  1935	            );
  1936	        }
  1937	    }
  1938	
  1939	    /// @dev Execute a scheduled market sell: deduct resource from vault, credit gold.
  1940	    function _executeMarketSell(uint64 closedTick, uint32 clanId, uint32 clansmanId, address token, uint256 amount)
  1941	        internal
  1942	        returns (StatusCode)
  1943	    {
  1944	        if (!_treasury.poolsSeeded) {
  1945	            return _handleMarketFailure(
  1946	                clanId,
  1947	                clansmanId,
  1948	                ActionType.MarketSell,
  1949	                MarketExecutionMode.Scheduled,
  1950	                StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN,
  1951	                closedTick
  1952	            );
  1953	        }
  1954	        address poolAddr = _poolFor(token);
  1955	        if (poolAddr == address(0)) {
  1956	            return _handleMarketFailure(
  1957	                clanId,
  1958	                clansmanId,
  1959	                ActionType.MarketSell,
  1960	                MarketExecutionMode.Scheduled,
  1961	                StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN,
  1962	                closedTick
  1963	            );
  1964	        }
  1965	
  1966	        Clan storage clan = _clans[clanId];
  1967	        Clansman storage cs = _clansmen[clansmanId];
  1968	        if (!_deductFromCarry(cs, token, amount)) {
  1969	            return _handleMarketFailure(
  1970	                clanId,
  1971	                clansmanId,
  1972	                ActionType.MarketSell,
  1973	                MarketExecutionMode.Scheduled,
  1974	                StatusCode.ERR_MISSING_RESOURCES,
  1975	                closedTick
  1976	            );
  1977	        }
  1978	
  1979	        uint256 goldOut = StubPool(poolAddr).sellResource(amount);
  1980	        clan.goldBalance += goldOut;
  1981	
  1982	        emit ScheduledMarketActionExecuted(
  1983	            clanId,
  1984	            clansmanId,
  1985	            ActionType.MarketSell,
  1986	            _marketResourceForToken(token),
  1987	            amount,
  1988	            ClanWorldConstants.RESOURCE_GOLD,
  1989	            goldOut,
  1990	            closedTick
  1991	        );
  1992	        return StatusCode.OK;
  1993	    }
  1994	
  1995	    /// @dev Execute a scheduled market buy: deduct gold from purse, credit resource to vault.
  1996	    function _executeMarketBuy(
  1997	        uint64 closedTick,
  1998	        uint32 clanId,
  1999	        uint32 clansmanId,
  2000	        address token,
  2001	        uint256 amountOut,
  2002	        uint256 maxGoldIn
  2003	    ) internal returns (StatusCode) {
  2004	        if (!_treasury.poolsSeeded) {
  2005	            return _handleMarketFailure(
  2006	                clanId,
  2007	                clansmanId,
  2008	                ActionType.MarketBuy,
  2009	                MarketExecutionMode.Scheduled,
  2010	                StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN,
  2011	                closedTick
  2012	            );
  2013	        }
  2014	        address poolAddr = _poolFor(token);
  2015	        if (poolAddr == address(0)) {
  2016	            return _handleMarketFailure(
  2017	                clanId,
  2018	                clansmanId,
  2019	                ActionType.MarketBuy,
  2020	                MarketExecutionMode.Scheduled,
  2021	                StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN,
  2022	                closedTick
  2023	            );
  2024	        }
  2025	
  2026	        Clansman storage cs = _clansmen[clansmanId];
  2027	        if (amountOut > _remainingCarryForToken(cs, token)) {
  2028	            return _handleMarketFailure(
  2029	                clanId,
  2030	                clansmanId,
  2031	                ActionType.MarketBuy,
  2032	                MarketExecutionMode.Scheduled,
  2033	                StatusCode.ERR_CARRY_FULL,
  2034	                closedTick
  2035	            );
  2036	        }
  2037	
  2038	        uint256 goldIn;
  2039	        try StubPool(poolAddr).quoteBuy(amountOut) returns (uint256 quotedGoldIn) {
  2040	            goldIn = quotedGoldIn;
  2041	        } catch {
  2042	            return _handleMarketFailure(
  2043	                clanId,
  2044	                clansmanId,
  2045	                ActionType.MarketBuy,
  2046	                MarketExecutionMode.Scheduled,
  2047	                StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
  2048	                closedTick
  2049	            );
  2050	        }
  2051	
  2052	        Clan storage clan = _clans[clanId];
  2053	
  2054	        if (goldIn > maxGoldIn) {
  2055	            return _handleMarketFailure(
  2056	                clanId,
  2057	                clansmanId,
  2058	                ActionType.MarketBuy,
  2059	                MarketExecutionMode.Scheduled,
  2060	                StatusCode.ERR_MAX_GOLD_IN_EXCEEDED,
  2061	                closedTick
  2062	            );
  2063	        }
  2064	        if (clan.goldBalance < goldIn) {
  2065	            return _handleMarketFailure(
  2066	                clanId,
  2067	                clansmanId,
  2068	                ActionType.MarketBuy,
  2069	                MarketExecutionMode.Scheduled,
  2070	                StatusCode.ERR_NOT_ENOUGH_GOLD,
  2071	                closedTick
  2072	            );
  2073	        }
  2074	
  2075	        uint256 actualGoldIn;
  2076	        try StubPool(poolAddr).swapExactOutForInWithMaxIn(amountOut, maxGoldIn) returns (uint256 spentGold) {
  2077	            actualGoldIn = spentGold;
  2078	        } catch {
  2079	            return _handleMarketFailure(
  2080	                clanId,
  2081	                clansmanId,
  2082	                ActionType.MarketBuy,
  2083	                MarketExecutionMode.Scheduled,
  2084	                StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
  2085	                closedTick
  2086	            );
  2087	        }
  2088	
  2089	        clan.goldBalance -= actualGoldIn;
  2090	        _addToCarry(cs, token, amountOut);
  2091	
  2092	        emit ScheduledMarketActionExecuted(
  2093	            clanId,
  2094	            clansmanId,
  2095	            ActionType.MarketBuy,
  2096	            ClanWorldConstants.RESOURCE_GOLD,
  2097	            actualGoldIn,
  2098	            _marketResourceForToken(token),
  2099	            amountOut,
  2100	            closedTick
  2101	        );
  2102	        return StatusCode.OK;
  2103	    }
  2104	
  2105	    function _validateAction(Clan storage clan, Clansman storage cs, ClanOrder calldata order, uint8 gotoRegion)
  2106	        internal
  2107	        view
  2108	        returns (StatusCode)

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '2105,2200p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
  2105	    function _validateAction(Clan storage clan, Clansman storage cs, ClanOrder calldata order, uint8 gotoRegion)
  2106	        internal
  2107	        view
  2108	        returns (StatusCode)
  2109	    {
  2110	        ActionType action = order.action;
  2111	
  2112	        if (action == ActionType.None) return StatusCode.ERR_INVALID_ACTION;
  2113	
  2114	        // DepositResources / WithdrawResources: must go to homebase
  2115	        if (action == ActionType.DepositResources) {
  2116	            if (gotoRegion != clan.baseRegion) return StatusCode.ERR_INVALID_REGION;
  2117	        }
  2118	        if (action == ActionType.WithdrawResources) {
  2119	            if (gotoRegion != clan.baseRegion) return StatusCode.ERR_NOT_AT_HOMEBASE;
  2120	            WithdrawResourcesData memory req = order.withdrawResources;
  2121	            if (!_hasWithdrawRequest(req)) return StatusCode.ERR_EMPTY_CARGO;
  2122	            if (!_hasVaultResources(clan, req)) return StatusCode.ERR_MISSING_RESOURCES;
  2123	            if (!_hasCarryCapacityForWithdraw(cs, req)) return StatusCode.ERR_CARRY_FULL;
  2124	        }
  2125	
  2126	        // BuildWall / UpgradeBase / UpgradeMonument: must go to homebase
  2127	        if (action == ActionType.BuildWall || action == ActionType.UpgradeBase || action == ActionType.UpgradeMonument)
  2128	        {
  2129	            if (gotoRegion != clan.baseRegion) return StatusCode.ERR_NOT_AT_HOMEBASE;
  2130	        }
  2131	
  2132	        // ChopWood: must go to Forest
  2133	        if (action == ActionType.ChopWood) {
  2134	            if (gotoRegion != ClanWorldConstants.REGION_FOREST) return StatusCode.ERR_INVALID_REGION;
  2135	        }
  2136	        // MineIron: must go to Mountains
  2137	        if (action == ActionType.MineIron) {
  2138	            if (gotoRegion != ClanWorldConstants.REGION_MOUNTAINS) return StatusCode.ERR_INVALID_REGION;
  2139	        }
  2140	        // FishDocks: must go to WestDocks or EastDocks
  2141	        if (action == ActionType.FishDocks) {
  2142	            if (
  2143	                gotoRegion != ClanWorldConstants.REGION_WEST_DOCKS && gotoRegion != ClanWorldConstants.REGION_EAST_DOCKS
  2144	            ) {
  2145	                return StatusCode.ERR_INVALID_REGION;
  2146	            }
  2147	        }
  2148	        // FishDeepSea: must go to DeepSea
  2149	        if (action == ActionType.FishDeepSea) {
  2150	            if (gotoRegion != ClanWorldConstants.REGION_DEEP_SEA) return StatusCode.ERR_INVALID_REGION;
  2151	        }
  2152	        // HarvestWheat: must go to WestFarms or EastFarms
  2153	        if (action == ActionType.HarvestWheat) {
  2154	            if (
  2155	                gotoRegion != ClanWorldConstants.REGION_WEST_FARMS && gotoRegion != ClanWorldConstants.REGION_EAST_FARMS
  2156	            ) {
  2157	                return StatusCode.ERR_INVALID_REGION;
  2158	            }
  2159	        }
  2160	
  2161	        if (action == ActionType.DefendBase) {
  2162	            return _validateDefendBaseOrder(clan, order, gotoRegion);
  2163	        }
  2164	
  2165	        // MarketBuy/MarketSell: must target Unicorn Town
  2166	        if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
  2167	            if (_treasury.woodToken == address(0)) return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
  2168	            if (gotoRegion != ClanWorldConstants.REGION_UNICORN_TOWN) {
  2169	                return StatusCode.ERR_INVALID_REGION;
  2170	            }
  2171	            if (order.marketAmount == 0) return StatusCode.ERR_MARKET_ZERO_AMOUNT;
  2172	            // Validate token is a supported resource token (not gold itself)
  2173	            address tok = order.marketToken;
  2174	            if (tok == address(0) || tok == _treasury.goldToken) {
  2175	                return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
  2176	            }
  2177	            if (
  2178	                tok != _treasury.woodToken && tok != _treasury.ironToken && tok != _treasury.wheatToken
  2179	                    && tok != _treasury.fishToken
  2180	            ) {
  2181	                return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
  2182	            }
  2183	            // MarketBuy uses maxGoldIn as its explicit slippage bound; zero would mean no protection.
  2184	            if (action == ActionType.MarketBuy && order.maxGoldIn == 0) {
  2185	                return StatusCode.ERR_SLIPPAGE_REQUIRED;
  2186	            }
  2187	            // Over-capacity buys are rejected at submission; no partial fills or overflow refunds.
  2188	            if (action == ActionType.MarketBuy && order.marketAmount > _remainingCarryForToken(cs, tok)) {
  2189	                return StatusCode.ERR_CARRY_FULL;
  2190	            }
  2191	            if (action == ActionType.MarketSell && !_hasCarryBalance(cs, tok, order.marketAmount)) {
  2192	                return StatusCode.ERR_MISSING_RESOURCES;
  2193	            }
  2194	            // Immediate market orders execute during submitClanOrders when the
  2195	            // worker is waiting in Unicorn Town and off cooldown. Other valid
  2196	            // market orders enqueue when the scheduled mission resolves.
  2197	            if (cs.currentRegion == ClanWorldConstants.REGION_UNICORN_TOWN && cs.state == ClansmanState.WAITING) {
  2198	                // Already at Unicorn Town — immediate if off cooldown, scheduled otherwise.
  2199	            }
  2200	        }

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '300,505p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
   300	
   301	    // =========================================================================
   302	    // INTERNAL SETTLEMENT
   303	    // =========================================================================
   304	
   305	    /// @dev Settle a single clansman's mission for the tick range [fromTick, toTick).
   306	    ///      Handles all 6 mission lifecycle paths. Called from _settleClan and settleClansman.
   307	    function _settleMissionForClansman(
   308	        Clan storage clan,
   309	        Clansman storage cs,
   310	        uint32 clanId,
   311	        uint64 fromTick,
   312	        uint64 toTick
   313	    ) internal {
   314	        Mission storage m = _missions[cs.clansmanId];
   315	
   316	        // Path 6: dead clansman — invalidate active mission if any
   317	        if (cs.state == ClansmanState.DEAD) {
   318	            if (m.active) {
   319	                if (m.action == ActionType.DefendBase) {
   320	                    _clearDefender(cs.clansmanId);
   321	                }
   322	                m.active = false; // silent invalidation; dead clansman gets no MissionCompleted
   323	            }
   324	            return;
   325	        }
   326	
   327	        if (!m.active) return; // no active mission — nothing to settle
   328	
   329	        bytes32 tickSeed;
   330	        for (uint64 tick = fromTick; tick < toTick; tick++) {
   331	            tickSeed = _tickSeeds[tick];
   332	
   333	            // Path 1 → Path 2 transition: TRAVELING → ACTING at arrivalTick
   334	            if (cs.state == ClansmanState.TRAVELING && tick >= m.arrivalTick) {
   335	                cs.state = ClansmanState.ACTING;
   336	                cs.currentRegion = m.targetRegion;
   337	                emit WorkerArrived(clanId, cs.clansmanId, m.targetRegion, tick);
   338	
   339	                if (m.action == ActionType.DefendBase) {
   340	                    _registerDefender(m.targetRegion, clanId, cs.clansmanId);
   341	                }
   342	            }
   343	
   344	            if (m.action == ActionType.DefendBase) continue; // persistent defender mission
   345	
   346	            // Path 3: ACTING at/past settlesAtTick → resolve
   347	            if (cs.state == ClansmanState.ACTING && tick >= m.settlesAtTick) {
   348	                _resolveAction(clan, cs, m, clanId, tick, tickSeed);
   349	                if (m.active && getActionDuration(m.action) > 0) {
   350	                    _completeMission(cs, m);
   351	                }
   352	            }
   353	
   354	            // If mission completed during this tick, stop iterating
   355	            if (!m.active) break;
   356	        }
   357	    }
   358	
   359	    /// @dev Lazy settlement of a clan forward to currentTick.
   360	    ///      Mutates storage. Called before order submission and by public settleClan().
   361	    function _settleClan(uint32 clanId) internal {
   362	        Clan storage clan = _clans[clanId];
   363	        if (clan.clanId == 0) return;
   364	
   365	        uint64 curTick = _world.currentTick;
   366	        uint64 fromTick = clan.lastSettledTick;
   367	        if (fromTick >= curTick) return;
   368	
   369	        // Cap ticks settled per call to prevent block gas limit issues
   370	        uint64 maxSettleTicks = 200;
   371	        if (curTick > fromTick + maxSettleTicks) {
   372	            curTick = fromTick + maxSettleTicks;
   373	        }
   374	
   375	        uint32[] storage clansmanIds = _clanClansmanIds[clanId];
   376	
   377	        // Settle tick by tick from fromTick to curTick - 1
   378	        // (curTick is still open; we settle through the last closed tick)
   379	        for (uint64 tick = fromTick; tick < curTick; tick++) {
   380	            // 1. Apply upkeep for this tick
   381	            _applyUpkeep(clan, tick);
   382	
   383	            // 2. Wheat plot regrow check (lazy, per tick)
   384	            for (uint256 pi = 0; pi < 2; pi++) {
   385	                WheatPlot storage plot = _wheatPlots[clanId][pi];
   386	                if (plot.state == WheatPlotState.Regrowing && tick >= plot.regrowUntilTick) {
   387	                    plot.state = WheatPlotState.Harvestable;
   388	                    plot.remainingWheat = ClanWorldConstants.WHEAT_PLOT_STARTING_WHEAT;
   389	                    plot.regrowUntilTick = 0;
   390	                }
   391	            }
   392	
   393	            // 3. Advance each clansman (single-tick range: [tick, tick+1))
   394	            for (uint256 i = 0; i < clansmanIds.length; i++) {
   395	                Clansman storage cs = _clansmen[clansmanIds[i]];
   396	                _settleMissionForClansman(clan, cs, clanId, tick, tick + 1);
   397	            }
   398	        }
   399	
   400	        clan.lastSettledTick = curTick;
   401	        emit ClanSettled(clanId, curTick);
   402	    }
   403	
   404	    /// @dev Apply one tick of upkeep. Marks starvation if insufficient food.
   405	    function _applyUpkeep(Clan storage clan, uint64 tick) internal {
   406	        if (clan.livingClansmen == 0) return;
   407	
   408	        uint256 wheatNeeded = uint256(clan.livingClansmen) * ClanWorldConstants.WHEAT_UPKEEP_PER_CLANSMAN;
   409	        uint256 fishNeeded = uint256(clan.livingClansmen) * ClanWorldConstants.FISH_UPKEEP_PER_CLANSMAN;
   410	
   411	        bool hadEnoughWheat = clan.vaultWheat >= wheatNeeded;
   412	        bool hadEnoughFish = clan.vaultFish >= fishNeeded;
   413	
   414	        if (hadEnoughWheat) {
   415	            clan.vaultWheat -= wheatNeeded;
   416	        } else {
   417	            clan.vaultWheat = 0;
   418	        }
   419	        if (hadEnoughFish) {
   420	            clan.vaultFish -= fishNeeded;
   421	        } else {
   422	            clan.vaultFish = 0;
   423	        }
   424	
   425	        bool starving = !hadEnoughWheat || !hadEnoughFish;
   426	        if (starving && clan.starvationStartsAtTick == 0) {
   427	            clan.starvationStartsAtTick = tick;
   428	            emit ClanStarvationChanged(clan.clanId, true, tick);
   429	        } else if (!starving && clan.starvationStartsAtTick != 0) {
   430	            clan.starvationStartsAtTick = 0;
   431	            emit ClanStarvationChanged(clan.clanId, false, tick);
   432	        }
   433	    }
   434	
   435	    /// @dev Check if a clan is currently starving (lazy read).
   436	    function _isStarving(Clan storage clan) internal view returns (bool) {
   437	        return clan.starvationStartsAtTick != 0 && clan.starvationStartsAtTick <= _world.currentTick;
   438	    }
   439	
   440	    /// @dev Resolve an action for a clansman that is in ACTING state.
   441	    function _resolveAction(
   442	        Clan storage clan,
   443	        Clansman storage cs,
   444	        Mission storage m,
   445	        uint32 clanId,
   446	        uint64 tick,
   447	        bytes32 tickSeed
   448	    ) internal {
   449	        bool starving = _isStarving(clan);
   450	        ActionType action = m.action;
   451	
   452	        if (action == ActionType.ChopWood) {
   453	            _gatherWood(clan, cs, m, clanId, tick, starving, tickSeed);
   454	        } else if (action == ActionType.MineIron) {
   455	            _gatherIron(clan, cs, m, clanId, tick, starving, tickSeed);
   456	        } else if (action == ActionType.FishDocks) {
   457	            _gatherFishDocks(clan, cs, m, clanId, tick, starving, tickSeed);
   458	        } else if (action == ActionType.FishDeepSea) {
   459	            _gatherFishDeepSea(clan, cs, m, clanId, tick, starving, tickSeed);
   460	        } else if (action == ActionType.HarvestWheat) {
   461	            _gatherWheat(clan, cs, m, clanId, tick, starving);
   462	        } else if (action == ActionType.DepositResources) {
   463	            // Deposit event ABI intentionally stores the current tick as uint32.
   464	            // forge-lint: disable-next-line(unsafe-typecast)
   465	            _doDeposit(clan, cs, m, clanId, uint32(tick));
   466	        } else if (action == ActionType.WithdrawResources) {
   467	            // Withdraw event ABI intentionally mirrors ResourcesDeposited's uint32 tick.
   468	            // forge-lint: disable-next-line(unsafe-typecast)
   469	            _doWithdrawResources(clan, cs, m, clanId, uint32(tick));
   470	        } else if (action == ActionType.Wait) {
   471	            // NOOP — worker stays ACTING (continuous), no transition needed
   472	            // Wait mission is effectively persistent until interrupted
   473	        } else if (action == ActionType.DefendBase) {
   474	            // Persistent mission. Registration happens atomically at order submission.
   475	        } else if (
   476	            action == ActionType.BuildWall || action == ActionType.UpgradeBase || action == ActionType.UpgradeMonument
   477	        ) {
   478	            // Phase 1 stub: check homebase, check resources; if ok, stub success
   479	            _doBuilding(clan, cs, m, clanId, tick, action);
   480	        } else if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
   481	            _completeMission(cs, m);
   482	        }
   483	    }
   484	
   485	    // -------------------------------------------------------------------------
   486	    // Gathering helpers
   487	    // -------------------------------------------------------------------------
   488	
   489	    function _gatherWood(
   490	        Clan storage, // clan (unused — no clan-level mutation in wood gather)
   491	        Clansman storage cs,
   492	        Mission storage m,
   493	        uint32 clanId,
   494	        uint64 tick,
   495	        bool starving,
   496	        bytes32 tickSeed
   497	    ) internal {
   498	        if (cs.carryWood >= ClanWorldConstants.WOOD_CARRY_CAP) {
   499	            _completeMission(cs, m);
   500	            return;
   501	        }
   502	
   503	        uint256 remaining = ClanWorldConstants.WOOD_CARRY_CAP - cs.carryWood;
   504	        uint256 yield = ClanWorldConstants.WOOD_YIELD_PER_TICK * uint256(getActionDuration(ActionType.ChopWood));
   505	        bytes32 woodRng = keccak256(abi.encode("wood_crit", tickSeed, cs.clansmanId, m.nonce, tick));

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '505,700p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
   505	        bytes32 woodRng = keccak256(abi.encode("wood_crit", tickSeed, cs.clansmanId, m.nonce, tick));
   506	        if (uint256(woodRng) % 10000 < ClanWorldConstants.WOOD_CRIT_BPS) {
   507	            yield *= 2;
   508	        }
   509	
   510	        if (starving) yield = yield / 2;
   511	        if (yield > remaining) yield = remaining;
   512	        cs.carryWood += yield;
   513	
   514	        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.ChopWood, yield, 0, 0, 0, 0, tick);
   515	
   516	        if (cs.carryWood >= ClanWorldConstants.WOOD_CARRY_CAP) {
   517	            _completeMission(cs, m);
   518	        }
   519	    }
   520	
   521	    function _gatherIron(
   522	        Clan storage clan,
   523	        Clansman storage cs,
   524	        Mission storage m,
   525	        uint32 clanId,
   526	        uint64 tick,
   527	        bool starving,
   528	        bytes32 tickSeed
   529	    ) internal {
   530	        uint256 remaining = ClanWorldConstants.IRON_CAP - cs.carryIron;
   531	        if (remaining == 0) {
   532	            _completeMission(cs, m);
   533	            return;
   534	        }
   535	        uint256 yield = ClanWorldConstants.IRON_BASE_YIELD;
   536	        if (starving) yield = yield / 2;
   537	        if (yield > remaining) yield = remaining;
   538	        cs.carryIron += yield;
   539	
   540	        // Gold bonus roll — scoped to reduce stack depth
   541	        uint256 goldBonus = _rollIronGoldBonus(clan, cs.clansmanId, m.nonce, tick, tickSeed);
   542	
   543	        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.MineIron, 0, yield, 0, 0, goldBonus, tick);
   544	
   545	        if (cs.carryIron >= ClanWorldConstants.IRON_CAP) {
   546	            _completeMission(cs, m);
   547	        }
   548	    }
   549	
   550	    function _rollIronGoldBonus(Clan storage clan, uint32 clansmanId, uint64 nonce, uint64 tick, bytes32 tickSeed)
   551	        internal
   552	        returns (uint256 goldBonus)
   553	    {
   554	        bytes32 goldRng = keccak256(abi.encode("iron_gold_bonus", tickSeed, clansmanId, nonce, tick));
   555	        if (uint256(goldRng) % 10000 < ClanWorldConstants.GOLD_FROM_IRON_BPS) {
   556	            goldBonus = ClanWorldConstants.GOLD_FROM_IRON_AMOUNT;
   557	            clan.goldBalance += goldBonus;
   558	        }
   559	    }
   560	
   561	    function _gatherFishDocks(
   562	        Clan storage,
   563	        Clansman storage cs,
   564	        Mission storage m,
   565	        uint32 clanId,
   566	        uint64 tick,
   567	        bool starving,
   568	        bytes32 tickSeed
   569	    ) internal {
   570	        uint256 remaining = ClanWorldConstants.FISH_CAP - cs.carryFish;
   571	        if (remaining == 0) {
   572	            _completeMission(cs, m);
   573	            return;
   574	        }
   575	        bytes32 fishRng = keccak256(abi.encode("fish_roll", tickSeed, cs.clansmanId, m.nonce, tick));
   576	        uint256 fishRoll = uint256(fishRng) % 10000;
   577	        uint256 yield = 0;
   578	        if (fishRoll < ClanWorldConstants.FISH_DOCKS_BPS) {
   579	            yield = 1e18;
   580	        }
   581	        if (starving) yield = yield / 2;
   582	        if (yield > remaining) yield = remaining;
   583	        if (yield > 0) {
   584	            cs.carryFish += yield;
   585	            emit ResourcesGathered(clanId, cs.clansmanId, ActionType.FishDocks, 0, 0, 0, yield, 0, tick);
   586	        }
   587	        if (cs.carryFish >= ClanWorldConstants.FISH_CAP) {
   588	            _completeMission(cs, m);
   589	        }
   590	    }
   591	
   592	    function _gatherFishDeepSea(
   593	        Clan storage,
   594	        Clansman storage cs,
   595	        Mission storage m,
   596	        uint32 clanId,
   597	        uint64 tick,
   598	        bool starving,
   599	        bytes32 tickSeed
   600	    ) internal {
   601	        uint256 remaining = ClanWorldConstants.FISH_CAP - cs.carryFish;
   602	        if (remaining == 0) {
   603	            _completeMission(cs, m);
   604	            return;
   605	        }
   606	        bytes32 fishRng = keccak256(abi.encode("fish_roll", tickSeed, cs.clansmanId, m.nonce, tick));
   607	        uint256 fishRoll = uint256(fishRng) % 10000;
   608	        uint256 yield = 0;
   609	        if (fishRoll < ClanWorldConstants.FISH_DEEP_BPS) {
   610	            yield = 1e18;
   611	        }
   612	        if (starving) yield = yield / 2;
   613	        if (yield > remaining) yield = remaining;
   614	        if (yield > 0) {
   615	            cs.carryFish += yield;
   616	            emit ResourcesGathered(clanId, cs.clansmanId, ActionType.FishDeepSea, 0, 0, 0, yield, 0, tick);
   617	        }
   618	        if (cs.carryFish >= ClanWorldConstants.FISH_CAP) {
   619	            _completeMission(cs, m);
   620	        }
   621	    }
   622	
   623	    function _gatherWheat(
   624	        Clan storage,
   625	        /* clan — unused but kept positional for callsite parity */
   626	        Clansman storage cs,
   627	        Mission storage m,
   628	        uint32 clanId,
   629	        uint64 tick,
   630	        bool starving
   631	    ) internal {
   632	        uint256 remaining = ClanWorldConstants.WHEAT_CAP - cs.carryWheat;
   633	        if (remaining == 0) {
   634	            _completeMission(cs, m);
   635	            return;
   636	        }
   637	        // Determine plot index from region
   638	        uint8 region = m.targetRegion;
   639	        uint256 plotIdx;
   640	        if (region == ClanWorldConstants.REGION_WEST_FARMS) {
   641	            plotIdx = 0;
   642	        } else if (region == ClanWorldConstants.REGION_EAST_FARMS) {
   643	            plotIdx = 1;
   644	        } else {
   645	            // Wrong region — complete (no harvest)
   646	            _completeMission(cs, m);
   647	            return;
   648	        }
   649	
   650	        WheatPlot storage plot = _wheatPlots[clanId][plotIdx];
   651	        if (plot.state != WheatPlotState.Harvestable || plot.remainingWheat == 0) {
   652	            // Plot not ready — worker waits
   653	            _completeMission(cs, m);
   654	            return;
   655	        }
   656	
   657	        uint256 yield = WHEAT_HARVEST_RATE;
   658	        if (starving) yield = yield / 2;
   659	        if (yield > remaining) yield = remaining;
   660	        if (yield > plot.remainingWheat) yield = plot.remainingWheat;
   661	
   662	        cs.carryWheat += yield;
   663	        plot.remainingWheat -= yield;
   664	
   665	        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.HarvestWheat, 0, 0, yield, 0, 0, tick);
   666	
   667	        if (plot.remainingWheat == 0) {
   668	            plot.state = WheatPlotState.Regrowing;
   669	            plot.regrowUntilTick = tick + ClanWorldConstants.WHEAT_PLOT_REGROW_TICKS;
   670	        }
   671	
   672	        if (cs.carryWheat >= ClanWorldConstants.WHEAT_CAP || plot.remainingWheat == 0) {
   673	            _completeMission(cs, m);
   674	        }
   675	        // else continuous
   676	    }
   677	
   678	    function _doDeposit(Clan storage clan, Clansman storage cs, Mission storage m, uint32 clanId, uint32 tick)
   679	        internal
   680	    {
   681	        // Must be at homebase region
   682	        if (cs.currentRegion != clan.baseRegion) {
   683	            _completeMission(cs, m);
   684	            return;
   685	        }
   686	        bool hasAnything = cs.carryWood > 0 || cs.carryIron > 0 || cs.carryWheat > 0 || cs.carryFish > 0;
   687	        if (!hasAnything) {
   688	            // Empty deposits are silent no-ops; no zero-delta event for indexers to process.
   689	            _completeMission(cs, m);
   690	            return;
   691	        }
   692	
   693	        uint256 woodDelta = cs.carryWood;
   694	        uint256 ironDelta = cs.carryIron;
   695	        uint256 wheatDelta = cs.carryWheat;
   696	        uint256 fishDelta = cs.carryFish;
   697	
   698	        clan.vaultWood += woodDelta;
   699	        clan.vaultIron += ironDelta;
   700	        clan.vaultWheat += wheatDelta;

exec
/bin/bash -lc "nl -ba packages/contracts/test/ClanWorld.t.sol | sed -n '1040,1095p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
  1040	        (, address woodAddr, uint32 clanId, uint32 csId) =
  1041	            _setupHarnessClanAt(ClansmanState.WAITING, ClanWorldConstants.REGION_UNICORN_TOWN, 0);
  1042	
  1043	        Clan memory beforeClan = world.getClan(clanId);
  1044	        Clansman memory beforeCs = world.getClansman(csId);
  1045	        uint256 expectedGoldIn = woodPool.getAmountInForExactOut(1e18);
  1046	
  1047	        vm.expectEmit(true, false, false, true);
  1048	        emit IClanWorldEvents.ImmediateMarketActionExecuted(
  1049	            clanId,
  1050	            csId,
  1051	            ActionType.MarketBuy,
  1052	            ClanWorldConstants.RESOURCE_GOLD,
  1053	            expectedGoldIn,
  1054	            uint8(ResourceType.Wood),
  1055	            1e18,
  1056	            world.getWorldState().currentTick
  1057	        );
  1058	        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 2e18);
  1059	
  1060	        Clan memory afterClan = world.getClan(clanId);
  1061	        Clansman memory afterCs = world.getClansman(csId);
  1062	        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "immediate buy should be accepted");
  1063	        assertEq(uint8(r[0].marketMode), uint8(MarketExecutionMode.Immediate), "buy should be immediate");
  1064	        assertEq(afterClan.vaultWood, beforeClan.vaultWood, "vault wood should be unchanged");
  1065	        assertGt(afterCs.carryWood, beforeCs.carryWood, "carry wood should increase immediately");
  1066	        assertLt(afterClan.goldBalance, beforeClan.goldBalance, "gold should be debited immediately");
  1067	        assertFalse(world.getActiveMission(csId).active, "immediate buy should not install a mission");
  1068	    }
  1069	
  1070	    function test_marketBuy_zeroMaxGoldInRejectsAtSubmit() public {
  1071	        (, address woodAddr, uint32 clanId, uint32 csId) =
  1072	            _setupHarnessClanAt(ClansmanState.WAITING, ClanWorldConstants.REGION_UNICORN_TOWN, 0);
  1073	
  1074	        Clan memory beforeClan = world.getClan(clanId);
  1075	        Clansman memory beforeCs = world.getClansman(csId);
  1076	
  1077	        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 0);
  1078	
  1079	        Clan memory afterClan = world.getClan(clanId);
  1080	        Clansman memory afterCs = world.getClansman(csId);
  1081	        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), "zero maxGoldIn is ambiguous");
  1082	        assertEq(uint8(r[0].marketMode), uint8(MarketExecutionMode.None), "rejected buy has no mode");
  1083	        assertEq(afterClan.goldBalance, beforeClan.goldBalance, "rejected buy should not debit gold");
  1084	        assertEq(afterCs.carryWood, beforeCs.carryWood, "rejected buy should not credit carry");
  1085	        assertEq(afterCs.cooldownEndsAtTs, beforeCs.cooldownEndsAtTs, "rejected buy should not consume cooldown");
  1086	        assertFalse(world.getActiveMission(csId).active, "rejected buy should not install a mission");
  1087	    }
  1088	
  1089	    function test_immediateMarket_insufficientLiquidityFailsAndConsumesCooldown() public {
  1090	        (, address woodAddr, uint32 clanId, uint32 csId) =
  1091	            _setupHarnessClanAtWithWoodSeed(ClansmanState.WAITING, ClanWorldConstants.REGION_UNICORN_TOWN, 0, 5e18);
  1092	
  1093	        Clan memory beforeClan = world.getClan(clanId);
  1094	
  1095	        vm.expectEmit(true, false, false, true);

exec
/bin/bash -lc "nl -ba packages/contracts/test/ClanWorld.t.sol | sed -n '1260,1465p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
  1260	        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 5e18, 0);
  1261	        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "sell order should be accepted");
  1262	
  1263	        // Find out which tick the action fires
  1264	        Mission memory m = world.getActiveMission(csId);
  1265	        uint64 executeAtTick = m.settlesAtTick;
  1266	        uint256 expectedGoldOut = woodPool.getAmountOutForExactIn(5e18);
  1267	
  1268	        // Advance ticks until the heartbeat before executeAtTick
  1269	        uint64 curTick = world.getWorldState().currentTick;
  1270	        for (uint256 i = 0; i < uint256(executeAtTick - curTick); i++) {
  1271	            _advanceTick();
  1272	        }
  1273	
  1274	        vm.expectEmit(true, false, false, true);
  1275	        emit IClanWorldEvents.ScheduledMarketActionExecuted(
  1276	            clanId,
  1277	            csId,
  1278	            ActionType.MarketSell,
  1279	            uint8(ResourceType.Wood),
  1280	            5e18,
  1281	            ClanWorldConstants.RESOURCE_GOLD,
  1282	            expectedGoldOut,
  1283	            executeAtTick
  1284	        );
  1285	        _advanceTick();
  1286	
  1287	        // Settle clan to apply any mission resolution
  1288	        world.settleClan(clanId);
  1289	
  1290	        uint256 goldAfter = world.getClan(clanId).goldBalance;
  1291	        assertGt(goldAfter, goldBefore, "gold should increase after sell");
  1292	    }
  1293	
  1294	    // -------------------------------------------------------------------------
  1295	    // Test 12: buy_debitsGold — after scheduled buy, gold decreases, vault resource increases
  1296	    // -------------------------------------------------------------------------
  1297	
  1298	    function test_buy_debitsGold() public {
  1299	        address woodAddr = _setupMarket();
  1300	        uint32 clanId = _mintClan();
  1301	
  1302	        // Give clan ample gold for the buy
  1303	        // We need a second clansman to do the buy while first does something else
  1304	        ClanFullView memory view_ = world.getClanFullView(clanId);
  1305	        uint32 csId = view_.clansmen[0].clansman.clansman.clansmanId;
  1306	
  1307	        uint256 goldBefore = world.getClan(clanId).goldBalance;
  1308	        uint256 vaultWoodBefore = world.getClan(clanId).vaultWood;
  1309	        uint256 carryWoodBefore = world.getClansman(csId).carryWood;
  1310	
  1311	        // Submit buy order for 1e18 wood, maxGoldIn = generous 500e18
  1312	        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 500e18);
  1313	        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "buy order should be accepted");
  1314	
  1315	        Mission memory m = world.getActiveMission(csId);
  1316	        uint64 executeAtTick = m.settlesAtTick;
  1317	
  1318	        uint64 curTick = world.getWorldState().currentTick;
  1319	        uint256 ticksNeeded = uint256(executeAtTick - curTick) + 1;
  1320	        for (uint256 i = 0; i < ticksNeeded; i++) {
  1321	            _advanceTick();
  1322	        }
  1323	
  1324	        world.settleClan(clanId);
  1325	
  1326	        uint256 goldAfter = world.getClan(clanId).goldBalance;
  1327	        uint256 vaultWoodAfter = world.getClan(clanId).vaultWood;
  1328	        uint256 carryWoodAfter = world.getClansman(csId).carryWood;
  1329	        assertLt(goldAfter, goldBefore, "gold should decrease after buy");
  1330	        assertEq(vaultWoodAfter, vaultWoodBefore, "vault wood should be unchanged after buy");
  1331	        assertGt(carryWoodAfter, carryWoodBefore, "carry wood should increase after buy");
  1332	    }
  1333	
  1334	    // -------------------------------------------------------------------------
  1335	    // Test 13: buy_maxGoldIn — buy fails with ERR_MAX_GOLD_IN_EXCEEDED
  1336	    // -------------------------------------------------------------------------
  1337	
  1338	    function test_buy_maxGoldIn() public {
  1339	        address woodAddr = _setupMarket();
  1340	        uint32 clanId = _mintClan();
  1341	        uint32 csId = _firstCs(clanId);
  1342	
  1343	        // maxGoldIn = 1 wei (will always be exceeded for any nonzero buy)
  1344	        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 1);
  1345	        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "order submission should succeed");
  1346	
  1347	        Mission memory m = world.getActiveMission(csId);
  1348	        uint64 executeAtTick = m.settlesAtTick;
  1349	        uint64 curTick = world.getWorldState().currentTick;
  1350	
  1351	        // Advance all ticks UP TO (but not including) the execute tick
  1352	        if (executeAtTick > curTick) {
  1353	            for (uint256 i = 0; i < uint256(executeAtTick - curTick); i++) {
  1354	                _advanceTick();
  1355	            }
  1356	        }
  1357	
  1358	        // Now the next heartbeat will close executeAtTick — that's when MarketActionFailed fires
  1359	        // Place expectEmit right before the final heartbeat
  1360	        vm.expectEmit(true, false, false, true);
  1361	        emit IClanWorldEvents.MarketActionFailed(
  1362	            clanId,
  1363	            csId,
  1364	            ActionType.MarketBuy,
  1365	            MarketExecutionMode.Scheduled,
  1366	            StatusCode.ERR_MAX_GOLD_IN_EXCEEDED,
  1367	            executeAtTick
  1368	        );
  1369	        _advanceTick();
  1370	
  1371	        Clansman memory cs = world.getClansman(csId);
  1372	
  1373	        // Verify gold balance unchanged (buy failed)
  1374	        assertEq(world.getClan(clanId).goldBalance, 3e18, "gold should be unchanged after failed buy");
  1375	        assertGt(cs.cooldownEndsAtTs, block.timestamp, "failed scheduled buy should consume cooldown");
  1376	        assertEq(uint8(cs.state), uint8(ClansmanState.WAITING), "failed scheduled worker waits");
  1377	        assertEq(world.getScheduledMarketActionsForTick(executeAtTick).length, 0, "queue should be deleted");
  1378	    }
  1379	
  1380	    function test_scheduledMarketBuy_insufficientGoldFailsAndConsumesCooldown() public {
  1381	        address woodAddr = _setupMarket();
  1382	        uint32 clanId = _mintClan();
  1383	        uint32 csId = _firstCs(clanId);
  1384	
  1385	        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 7e18, 10e18);
  1386	        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "buy order should be accepted");
  1387	
  1388	        Mission memory m = world.getActiveMission(csId);
  1389	        uint64 executeAtTick = m.settlesAtTick;
  1390	        Clan memory beforeClan = world.getClan(clanId);
  1391	
  1392	        _advanceUntilNextHeartbeatCloses(executeAtTick);
  1393	        vm.expectEmit(true, false, false, true);
  1394	        emit IClanWorldEvents.MarketActionFailed(
  1395	            clanId,
  1396	            csId,
  1397	            ActionType.MarketBuy,
  1398	            MarketExecutionMode.Scheduled,
  1399	            StatusCode.ERR_NOT_ENOUGH_GOLD,
  1400	            executeAtTick
  1401	        );
  1402	        _advanceTick();
  1403	
  1404	        Clan memory afterClan = world.getClan(clanId);
  1405	        Clansman memory cs = world.getClansman(csId);
  1406	        assertEq(afterClan.vaultWood, beforeClan.vaultWood, "failed buy should not credit resources");
  1407	        assertEq(afterClan.goldBalance, beforeClan.goldBalance, "failed buy should not debit gold");
  1408	        assertGt(cs.cooldownEndsAtTs, block.timestamp, "failed scheduled buy should consume cooldown");
  1409	        assertEq(uint8(cs.state), uint8(ClansmanState.WAITING), "failed scheduled worker waits");
  1410	        assertEq(world.getScheduledMarketActionsForTick(executeAtTick).length, 0, "queue should be deleted");
  1411	    }
  1412	
  1413	    function test_scheduledMarketBuy_overCapacityRejectsAtSubmit() public {
  1414	        ClanWorldTestHarness harness = new ClanWorldTestHarness();
  1415	        world = harness;
  1416	        address woodAddr = _setupMarket();
  1417	        uint32 clanId = _mintClan();
  1418	        uint32 csId = _firstCs(clanId);
  1419	        harness.setCarry(csId, ClanWorldConstants.WOOD_CAP - 5e17, 0, 0, 0);
  1420	
  1421	        Clan memory beforeClan = world.getClan(clanId);
  1422	        Clansman memory beforeCs = world.getClansman(csId);
  1423	        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 10e18);
  1424	
  1425	        Clan memory afterClan = world.getClan(clanId);
  1426	        Clansman memory cs = world.getClansman(csId);
  1427	
  1428	        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_CARRY_FULL), "over-capacity buy should be rejected");
  1429	        assertEq(uint8(r[0].marketMode), uint8(MarketExecutionMode.None), "rejected buy has no mode");
  1430	        assertEq(afterClan.vaultWood, beforeClan.vaultWood, "rejected buy should not credit resources");
  1431	        assertEq(afterClan.goldBalance, beforeClan.goldBalance, "rejected buy should not debit gold");
  1432	        assertEq(cs.cooldownEndsAtTs, beforeCs.cooldownEndsAtTs, "rejected buy should not consume cooldown");
  1433	        assertEq(uint8(cs.state), uint8(beforeCs.state), "rejected buy should not change worker state");
  1434	        assertFalse(world.getActiveMission(csId).active, "rejected buy should not install a mission");
  1435	    }
  1436	
  1437	    function test_scheduledMarketBuy_insufficientLiquidityFailsAndConsumesCooldown() public {
  1438	        address woodAddr = _setupMarketWithWoodSeed(5e18);
  1439	        uint32 clanId = _mintClan();
  1440	        uint32 csId = _firstCs(clanId);
  1441	
  1442	        OrderResult[] memory r =
  1443	            _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 6e18, type(uint256).max);
  1444	        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "buy order should be accepted");
  1445	
  1446	        Mission memory m = world.getActiveMission(csId);
  1447	        uint64 executeAtTick = m.settlesAtTick;
  1448	        Clan memory beforeClan = world.getClan(clanId);
  1449	
  1450	        _advanceUntilNextHeartbeatCloses(executeAtTick);
  1451	        vm.expectEmit(true, false, false, true);
  1452	        emit IClanWorldEvents.MarketActionFailed(
  1453	            clanId,
  1454	            csId,
  1455	            ActionType.MarketBuy,
  1456	            MarketExecutionMode.Scheduled,
  1457	            StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
  1458	            executeAtTick
  1459	        );
  1460	        _advanceTick();
  1461	
  1462	        Clan memory afterClan = world.getClan(clanId);
  1463	        Clansman memory cs = world.getClansman(csId);
  1464	        assertEq(afterClan.vaultWood, beforeClan.vaultWood, "failed buy should not credit resources");
  1465	        assertEq(afterClan.goldBalance, beforeClan.goldBalance, "failed buy should not debit gold");

exec
/bin/bash -lc "nl -ba packages/contracts/test/ClanWorld.t.sol | sed -n '2860,2895p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
  2860	            "market order on cooldown must be rejected, not scheduled"
  2861	        );
  2862	    }
  2863	
  2864	    function test_marketBuy_creditsCarry_notVault() public {
  2865	        (, address woodTok, uint32 clanId, uint32 csId) =
  2866	            _setupHarnessClanAt(ClansmanState.WAITING, ClanWorldConstants.REGION_UNICORN_TOWN, 0);
  2867	
  2868	        uint256 vaultWoodBefore = world.getClan(clanId).vaultWood;
  2869	        uint256 carryWoodBefore = world.getClansman(csId).carryWood;
  2870	        uint256 goldBefore = world.getClan(clanId).goldBalance;
  2871	
  2872	        uint256 buyAmt = 1e18;
  2873	        ClanOrder[] memory orders = new ClanOrder[](1);
  2874	        orders[0] = ClanOrder({
  2875	            clansmanId: csId,
  2876	            gotoRegion: ClanWorldConstants.REGION_UNICORN_TOWN,
  2877	            action: ActionType.MarketBuy,
  2878	            targetClanId: 0,
  2879	            marketToken: woodTok,
  2880	            marketAmount: buyAmt,
  2881	            maxGoldIn: type(uint256).max,
  2882	            withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
  2883	        });
  2884	        vm.prank(elder);
  2885	        OrderResult[] memory results = world.submitClanOrders(clanId, orders);
  2886	
  2887	        assertEq(uint8(results[0].status), uint8(StatusCode.OK), "buy: immediate market buy must succeed");
  2888	        assertGt(world.getClansman(csId).carryWood, carryWoodBefore, "buy: carry must increase");
  2889	        assertEq(world.getClan(clanId).vaultWood, vaultWoodBefore, "buy: vault must be unchanged");
  2890	        assertLt(world.getClan(clanId).goldBalance, goldBefore, "buy: gold must decrease");
  2891	    }
  2892	}

exec
/bin/bash -lc "nl -ba packages/contracts/test/SeedPools.t.sol | sed -n '55,140p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
    55	        assertEq(world.getPool(uint8(ResourceType.Wood)), address(woodPool), "wood pool");
    56	        assertEq(world.getPool(uint8(ResourceType.Wheat)), address(wheatPool), "wheat pool");
    57	        assertEq(world.getPool(uint8(ResourceType.Fish)), address(fishPool), "fish pool");
    58	        assertEq(world.getPool(uint8(ResourceType.Iron)), address(ironPool), "iron pool");
    59	    }
    60	
    61	    function test_treasurySeedingTransfersExpectedPoolBalances() public {
    62	        _assertPoolSeeded(
    63	            woodToken, woodPool, world.INITIAL_WOOD_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WOOD(), "wood"
    64	        );
    65	        _assertPoolSeeded(
    66	            wheatToken, wheatPool, world.INITIAL_WHEAT_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WHEAT(), "wheat"
    67	        );
    68	        _assertPoolSeeded(
    69	            fishToken, fishPool, world.INITIAL_FISH_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_FISH(), "fish"
    70	        );
    71	        _assertPoolSeeded(
    72	            ironToken, ironPool, world.INITIAL_IRON_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_IRON(), "iron"
    73	        );
    74	        assertEq(goldToken.balanceOf(address(this)), 0, "treasury gold fully seeded");
    75	    }
    76	
    77	    function test_kInvariantHoldsAfterEachSwap() public {
    78	        uint256 kBefore = _k(woodPool);
    79	
    80	        vm.prank(address(world));
    81	        woodPool.swapExactInForOut(10e18, 1);
    82	        uint256 kAfterSell = _k(woodPool);
    83	        assertGe(kAfterSell, kBefore, "k after exact-in sell");
    84	
    85	        vm.prank(address(world));
    86	        woodPool.swapExactOutForInWithMaxIn(3e18, 10e18);
    87	        uint256 kAfterBuy = _k(woodPool);
    88	        assertGe(kAfterBuy, kAfterSell, "k after exact-out buy");
    89	    }
    90	
    91	    function test_pricePreviewMatchesActualSwap() public {
    92	        uint256 amountIn = 25e18;
    93	        uint256 preview = world.getPrice(uint8(ResourceType.Wood), amountIn);
    94	
    95	        vm.prank(address(world));
    96	        uint256 actual = woodPool.swapExactInForOut(amountIn, 0);
    97	
    98	        assertEq(actual, preview, "preview should match exact-in swap");
    99	    }
   100	
   101	    function _seedTreasuryAndApprove() internal {
   102	        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
   103	        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
   104	        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
   105	        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
   106	        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
   107	        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
   108	        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
   109	        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
   110	        uint256 totalGoldSeed = goldForWood + goldForWheat + goldForFish + goldForIron;
   111	
   112	        woodToken.seedTreasury(address(this), woodSeed);
   113	        wheatToken.seedTreasury(address(this), wheatSeed);
   114	        fishToken.seedTreasury(address(this), fishSeed);
   115	        ironToken.seedTreasury(address(this), ironSeed);
   116	        goldToken.seedTreasury(address(this), totalGoldSeed);
   117	
   118	        woodToken.approve(address(world), woodSeed);
   119	        wheatToken.approve(address(world), wheatSeed);
   120	        fishToken.approve(address(world), fishSeed);
   121	        ironToken.approve(address(world), ironSeed);
   122	        goldToken.approve(address(world), totalGoldSeed);
   123	    }
   124	
   125	    function _seedConfig() internal view returns (PoolSeedConfig memory) {
   126	        return PoolSeedConfig({
   127	            woodSeed: world.INITIAL_WOOD_POOL_SEED(),
   128	            wheatSeed: world.INITIAL_WHEAT_POOL_SEED(),
   129	            fishSeed: world.INITIAL_FISH_POOL_SEED(),
   130	            ironSeed: world.INITIAL_IRON_POOL_SEED(),
   131	            goldSeedForWood: world.INITIAL_GOLD_SEED_FOR_WOOD(),
   132	            goldSeedForWheat: world.INITIAL_GOLD_SEED_FOR_WHEAT(),
   133	            goldSeedForFish: world.INITIAL_GOLD_SEED_FOR_FISH(),
   134	            goldSeedForIron: world.INITIAL_GOLD_SEED_FOR_IRON()
   135	        });
   136	    }
   137	
   138	    function _assertPoolSeeded(
   139	        MinimalERC20 resourceToken,
   140	        StubPool pool,

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '1650,1735p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
  1650	            cs.carryFish -= amount;
  1651	            return true;
  1652	        }
  1653	        return false;
  1654	    }
  1655	
  1656	    function _addToCarry(Clansman storage cs, address token, uint256 amount) internal {
  1657	        if (token == _treasury.woodToken) {
  1658	            cs.carryWood += amount;
  1659	            return;
  1660	        }
  1661	        if (token == _treasury.ironToken) {
  1662	            cs.carryIron += amount;
  1663	            return;
  1664	        }
  1665	        if (token == _treasury.wheatToken) {
  1666	            cs.carryWheat += amount;
  1667	            return;
  1668	        }
  1669	        if (token == _treasury.fishToken) {
  1670	            cs.carryFish += amount;
  1671	            return;
  1672	        }
  1673	    }
  1674	
  1675	    /// @dev Check a clan vault balance without mutating storage.
  1676	    function _hasVaultBalance(Clan storage clan, address token, uint256 amount) internal view returns (bool) {
  1677	        if (token == _treasury.woodToken) return clan.vaultWood >= amount;
  1678	        if (token == _treasury.ironToken) return clan.vaultIron >= amount;
  1679	        if (token == _treasury.wheatToken) return clan.vaultWheat >= amount;
  1680	        if (token == _treasury.fishToken) return clan.vaultFish >= amount;
  1681	        return false;
  1682	    }
  1683	
  1684	    function _hasWithdrawRequest(WithdrawResourcesData memory req) internal pure returns (bool) {
  1685	        return req.wood > 0 || req.iron > 0 || req.wheat > 0 || req.fish > 0;
  1686	    }
  1687	
  1688	    function _hasVaultResources(Clan storage clan, WithdrawResourcesData memory req) internal view returns (bool) {
  1689	        return clan.vaultWood >= req.wood && clan.vaultIron >= req.iron && clan.vaultWheat >= req.wheat
  1690	            && clan.vaultFish >= req.fish;
  1691	    }
  1692	
  1693	    function _hasCarryCapacityForWithdraw(Clansman storage cs, WithdrawResourcesData memory req)
  1694	        internal
  1695	        view
  1696	        returns (bool)
  1697	    {
  1698	        return req.wood <= _remainingCapacity(cs.carryWood, ClanWorldConstants.WOOD_CAP)
  1699	            && req.iron <= _remainingCapacity(cs.carryIron, ClanWorldConstants.IRON_CAP)
  1700	            && req.wheat <= _remainingCapacity(cs.carryWheat, ClanWorldConstants.WHEAT_CAP)
  1701	            && req.fish <= _remainingCapacity(cs.carryFish, ClanWorldConstants.FISH_CAP);
  1702	    }
  1703	
  1704	    function _remainingCapacity(uint256 carried, uint256 cap) internal pure returns (uint256) {
  1705	        if (carried >= cap) return 0;
  1706	        return cap - carried;
  1707	    }
  1708	
  1709	    function _handleMarketFailure(
  1710	        uint32 clanId,
  1711	        uint32 clansmanId,
  1712	        ActionType action,
  1713	        MarketExecutionMode mode,
  1714	        StatusCode reason,
  1715	        uint64 tick
  1716	    ) internal returns (StatusCode) {
  1717	        Clansman storage cs = _clansmen[clansmanId];
  1718	        if (cs.clansmanId != 0 && cs.state != ClansmanState.DEAD) {
  1719	            cs.state = ClansmanState.WAITING;
  1720	            cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
  1721	        }
  1722	        _emitMarketActionFailed(clanId, clansmanId, action, mode, reason, tick);
  1723	        return reason;
  1724	    }
  1725	
  1726	    function _remainingCarryForToken(Clansman storage cs, address token) internal view returns (uint256) {
  1727	        uint256 carried;
  1728	        uint256 cap;
  1729	        if (token == _treasury.woodToken) {
  1730	            carried = cs.carryWood;
  1731	            cap = ClanWorldConstants.WOOD_CAP;
  1732	        } else if (token == _treasury.ironToken) {
  1733	            carried = cs.carryIron;
  1734	            cap = ClanWorldConstants.IRON_CAP;
  1735	        } else if (token == _treasury.wheatToken) {

exec
/bin/bash -lc "nl -ba packages/contracts/src/StubPool.sol | sed -n '1,120p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
     1	// SPDX-License-Identifier: MIT
     2	pragma solidity ^0.8.34;
     3	
     4	interface IERC20Balance {
     5	    function balanceOf(address account) external view returns (uint256);
     6	}
     7	
     8	/// @notice Constant-product AMM pool for one resource/gold pair.
     9	///         TOKEN_A is the resource token and TOKEN_B is gold. ClanWorld owns
    10	///         the swap surface because clans use the engine's internal accounting,
    11	///         while the treasury seeds real ERC20 balances into the pool once.
    12	contract StubPool {
    13	    address public immutable TOKEN_A; // resource token
    14	    address public immutable TOKEN_B; // gold token
    15	    address public immutable ENGINE; // ClanWorld address
    16	
    17	    uint256 public reserveA; // resource reserve
    18	    uint256 public reserveB; // gold reserve
    19	
    20	    bool private _seeded;
    21	
    22	    modifier onlyEngine() {
    23	        require(msg.sender == ENGINE, "StubPool: only engine");
    24	        _;
    25	    }
    26	
    27	    constructor(address tokenA_, address tokenB_, address engine_) {
    28	        TOKEN_A = tokenA_;
    29	        TOKEN_B = tokenB_;
    30	        ENGINE = engine_;
    31	    }
    32	
    33	    /// @notice Called by ClanWorld at seedPools time to set initial reserves.
    34	    ///         Can only be called once.
    35	    function seed(uint256 amountA, uint256 amountB) external onlyEngine {
    36	        require(!_seeded, "StubPool: already seeded");
    37	        require(amountA > 0 && amountB > 0, "StubPool: zero seed");
    38	        require(IERC20Balance(TOKEN_A).balanceOf(address(this)) >= amountA, "StubPool: missing token A");
    39	        require(IERC20Balance(TOKEN_B).balanceOf(address(this)) >= amountB, "StubPool: missing token B");
    40	        reserveA = amountA;
    41	        reserveB = amountB;
    42	        _seeded = true;
    43	    }
    44	
    45	    function getAmountOutForExactIn(uint256 amountIn) public view returns (uint256 amountOut) {
    46	        require(amountIn > 0, "StubPool: zero amount");
    47	        require(reserveA > 0 && reserveB > 0, "StubPool: not seeded");
    48	        amountOut = (reserveB * amountIn) / (reserveA + amountIn);
    49	    }
    50	
    51	    function getAmountInForExactOut(uint256 amountOut) public view returns (uint256 amountIn) {
    52	        require(amountOut > 0, "StubPool: zero amount");
    53	        require(amountOut < reserveA, "StubPool: insufficient resource reserve");
    54	        require(reserveB > 0, "StubPool: not seeded");
    55	
    56	        uint256 numerator = reserveB * amountOut;
    57	        uint256 denominator = reserveA - amountOut;
    58	        amountIn = numerator / denominator + (numerator % denominator == 0 ? 0 : 1);
    59	    }
    60	
    61	    /// @notice Exact-input sell: resource in, gold out.
    62	    function swapExactInForOut(uint256 amountIn, uint256 minOut) external onlyEngine returns (uint256 amountOut) {
    63	        return _swapExactInForOut(amountIn, minOut);
    64	    }
    65	
    66	    function _swapExactInForOut(uint256 amountIn, uint256 minOut) internal returns (uint256 amountOut) {
    67	        uint256 priorK = reserveA * reserveB;
    68	        amountOut = getAmountOutForExactIn(amountIn);
    69	        require(amountOut >= minOut, "StubPool: insufficient output");
    70	
    71	        reserveA += amountIn;
    72	        reserveB -= amountOut;
    73	
    74	        require(reserveA * reserveB >= priorK, "StubPool: k invariant");
    75	    }
    76	
    77	    /// @notice Exact-output buy: gold in, exact resource out.
    78	    function swapExactOutForInWithMaxIn(uint256 amountOut, uint256 maxIn)
    79	        external
    80	        onlyEngine
    81	        returns (uint256 amountIn)
    82	    {
    83	        return _swapExactOutForInWithMaxIn(amountOut, maxIn);
    84	    }
    85	
    86	    function _swapExactOutForInWithMaxIn(uint256 amountOut, uint256 maxIn) internal returns (uint256 amountIn) {
    87	        uint256 priorK = reserveA * reserveB;
    88	        amountIn = getAmountInForExactOut(amountOut);
    89	        require(amountIn <= maxIn, "StubPool: max input exceeded");
    90	
    91	        reserveA -= amountOut;
    92	        reserveB += amountIn;
    93	
    94	        require(reserveA * reserveB >= priorK, "StubPool: k invariant");
    95	    }
    96	
    97	    /// @notice Exact-input sell: clan sells amountIn of resource, gets goldOut.
    98	    ///         Legacy alias for Phase 6.1 scheduled-market code.
    99	    function sellResource(uint256 amountIn) external onlyEngine returns (uint256 goldOut) {
   100	        goldOut = _swapExactInForOut(amountIn, 1);
   101	    }
   102	
   103	    /// @notice Legacy quote alias for exact-output resource buys.
   104	    function quoteBuy(uint256 amountOut) external view returns (uint256 goldIn) {
   105	        goldIn = getAmountInForExactOut(amountOut);
   106	    }
   107	
   108	    /// @notice Exact-output buy: clan buys amountOut of resource, pays goldIn.
   109	    ///         Legacy alias for Phase 6.1 scheduled-market code.
   110	    function buyResource(uint256 amountOut) external onlyEngine returns (uint256 goldIn) {
   111	        goldIn = _swapExactOutForInWithMaxIn(amountOut, type(uint256).max);
   112	    }
   113	
   114	    function getReserves() external view returns (uint256, uint256) {
   115	        return (reserveA, reserveB);
   116	    }
   117	}

exec
/bin/bash -lc "nl -ba packages/contracts/script/Deploy.s.sol | sed -n '45,85p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
    45	        console.log("ironGoldPool: ", address(ironGold));
    46	
    47	        address[6] memory tokens =
    48	            [address(wood), address(iron), address(wheat), address(fish), address(gold), address(blueprint)];
    49	        address[4] memory pools = [address(woodGold), address(wheatGold), address(fishGold), address(ironGold)];
    50	
    51	        game.initTreasury(tokens, pools);
    52	
    53	        uint256 woodSeed = game.INITIAL_WOOD_POOL_SEED();
    54	        uint256 wheatSeed = game.INITIAL_WHEAT_POOL_SEED();
    55	        uint256 fishSeed = game.INITIAL_FISH_POOL_SEED();
    56	        uint256 ironSeed = game.INITIAL_IRON_POOL_SEED();
    57	        uint256 goldForWood = game.INITIAL_GOLD_SEED_FOR_WOOD();
    58	        uint256 goldForWheat = game.INITIAL_GOLD_SEED_FOR_WHEAT();
    59	        uint256 goldForFish = game.INITIAL_GOLD_SEED_FOR_FISH();
    60	        uint256 goldForIron = game.INITIAL_GOLD_SEED_FOR_IRON();
    61	        uint256 totalGoldSeed = goldForWood + goldForWheat + goldForFish + goldForIron;
    62	
    63	        wood.seedTreasury(treasury, woodSeed);
    64	        wheat.seedTreasury(treasury, wheatSeed);
    65	        fish.seedTreasury(treasury, fishSeed);
    66	        iron.seedTreasury(treasury, ironSeed);
    67	        gold.seedTreasury(treasury, totalGoldSeed);
    68	
    69	        wood.approve(address(game), woodSeed);
    70	        wheat.approve(address(game), wheatSeed);
    71	        fish.approve(address(game), fishSeed);
    72	        iron.approve(address(game), ironSeed);
    73	        gold.approve(address(game), totalGoldSeed);
    74	
    75	        game.seedPools(
    76	            PoolSeedConfig({
    77	                woodSeed: woodSeed,
    78	                wheatSeed: wheatSeed,
    79	                fishSeed: fishSeed,
    80	                ironSeed: ironSeed,
    81	                goldSeedForWood: goldForWood,
    82	                goldSeedForWheat: goldForWheat,
    83	                goldSeedForFish: goldForFish,
    84	                goldSeedForIron: goldForIron
    85	            })

exec
/bin/bash -lc "nl -ba packages/contracts/test/StatusCodeEnumStability.t.sol | sed -n '1,45p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
     1	// SPDX-License-Identifier: MIT
     2	pragma solidity ^0.8.34;
     3	
     4	import {Test} from "forge-std/Test.sol";
     5	import {StatusCode} from "../src/IClanWorld.sol";
     6	
     7	contract StatusCodeEnumStabilityTest is Test {
     8	    function test_statusCodeNumericValuesAreStable() public pure {
     9	        assertEq(uint8(StatusCode.OK), 0, "OK");
    10	        assertEq(uint8(StatusCode.ERR_CLAN_DEAD), 1, "ERR_CLAN_DEAD");
    11	        assertEq(uint8(StatusCode.ERR_CLAN_NOT_OWNED), 2, "ERR_CLAN_NOT_OWNED");
    12	        assertEq(uint8(StatusCode.ERR_CLANSMAN_DEAD), 3, "ERR_CLANSMAN_DEAD");
    13	        assertEq(uint8(StatusCode.ERR_INVALID_CLANSMAN), 4, "ERR_INVALID_CLANSMAN");
    14	        assertEq(uint8(StatusCode.ERR_INVALID_REGION), 5, "ERR_INVALID_REGION");
    15	        assertEq(uint8(StatusCode.ERR_INVALID_ACTION), 6, "ERR_INVALID_ACTION");
    16	        assertEq(uint8(StatusCode.ERR_INVALID_TARGET), 7, "ERR_INVALID_TARGET");
    17	        assertEq(uint8(StatusCode.ERR_COOLDOWN_ACTIVE), 8, "ERR_COOLDOWN_ACTIVE");
    18	        assertEq(uint8(StatusCode.ERR_NOT_WAITING), 9, "ERR_NOT_WAITING");
    19	        assertEq(uint8(StatusCode.ERR_NOT_IN_UNICORN_TOWN), 10, "ERR_NOT_IN_UNICORN_TOWN");
    20	        assertEq(uint8(StatusCode.ERR_NOT_AT_HOMEBASE), 11, "ERR_NOT_AT_HOMEBASE");
    21	        assertEq(uint8(StatusCode.ERR_NOT_AT_TARGET_BASE), 12, "ERR_NOT_AT_TARGET_BASE");
    22	        assertEq(uint8(StatusCode.ERR_NOT_DEFENDABLE), 13, "ERR_NOT_DEFENDABLE");
    23	        assertEq(uint8(StatusCode.ERR_MISSING_RESOURCES), 14, "ERR_MISSING_RESOURCES");
    24	        assertEq(uint8(StatusCode.ERR_EMPTY_CARGO), 15, "ERR_EMPTY_CARGO");
    25	        assertEq(uint8(StatusCode.ERR_PLOT_NOT_READY), 16, "ERR_PLOT_NOT_READY");
    26	        assertEq(uint8(StatusCode.ERR_PLOT_EMPTY), 17, "ERR_PLOT_EMPTY");
    27	        assertEq(uint8(StatusCode.ERR_MARKET_ZERO_AMOUNT), 18, "ERR_MARKET_ZERO_AMOUNT");
    28	        assertEq(uint8(StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN), 19, "ERR_MARKET_UNSUPPORTED_TOKEN");
    29	        assertEq(uint8(StatusCode.ERR_IMMEDIATE_MARKET_NOT_ELIGIBLE), 20, "ERR_IMMEDIATE_MARKET_NOT_ELIGIBLE");
    30	        assertEq(uint8(StatusCode.ERR_MARKET_BUY_OVER_CAPACITY), 21, "ERR_MARKET_BUY_OVER_CAPACITY");
    31	        assertEq(uint8(StatusCode.ERR_MARKET_BUY_MAX_GOLD_EXCEEDED), 22, "ERR_MARKET_BUY_MAX_GOLD_EXCEEDED");
    32	        assertEq(uint8(StatusCode.ERR_WORLD_TICK_MISMATCH), 23, "ERR_WORLD_TICK_MISMATCH");
    33	        assertEq(uint8(StatusCode.ERR_NO_ACTIVE_BANDIT), 24, "ERR_NO_ACTIVE_BANDIT");
    34	        assertEq(uint8(StatusCode.ERR_SEASON_ENDED), 25, "ERR_SEASON_ENDED");
    35	        assertEq(uint8(StatusCode.ERR_NOT_ENOUGH_GOLD), 26, "ERR_NOT_ENOUGH_GOLD");
    36	        assertEq(uint8(StatusCode.ERR_CARRY_FULL), 27, "ERR_CARRY_FULL");
    37	        assertEq(uint8(StatusCode.ERR_MARKET_INSUFFICIENT_LIQUIDITY), 28, "ERR_MARKET_INSUFFICIENT_LIQUIDITY");
    38	        assertEq(uint8(StatusCode.ERR_LIQUIDITY_INSUFFICIENT), 29, "ERR_LIQUIDITY_INSUFFICIENT");
    39	        assertEq(uint8(StatusCode.ERR_MAX_GOLD_IN_EXCEEDED), 30, "ERR_MAX_GOLD_IN_EXCEEDED");
    40	        assertEq(uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), 31, "ERR_SLIPPAGE_REQUIRED");
    41	    }
    42	}

exec
/bin/bash -lc "rg -n \"function test_.*zeroMaxGoldIn|ERR_SLIPPAGE_REQUIRED|MarketBuy.*0\\)|maxGoldIn: 0\" packages/contracts/test" in /tmp/wt-superswarm-357
 succeeded in 0ms:
packages/contracts/test/Reentrancy.t.sol:233:            maxGoldIn: 0,
packages/contracts/test/StatusCodeEnumStability.t.sol:40:        assertEq(uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), 31, "ERR_SLIPPAGE_REQUIRED");
packages/contracts/test/Gathering.t.sol:63:            maxGoldIn: 0,
packages/contracts/test/HeartbeatOrdering.t.sol:100:            maxGoldIn: 0,
packages/contracts/test/MissionTiming.t.sol:60:            maxGoldIn: 0,
packages/contracts/test/DefendBase.t.sol:45:            maxGoldIn: 0,
packages/contracts/test/DefendBase.t.sol:60:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:215:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:240:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:400:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:411:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:460:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:814:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:905:                maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1070:    function test_marketBuy_zeroMaxGoldInRejectsAtSubmit() public {
packages/contracts/test/ClanWorld.t.sol:1077:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 0);
packages/contracts/test/ClanWorld.t.sol:1081:        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), "zero maxGoldIn is ambiguous");
packages/contracts/test/ClanWorld.t.sol:1628:                maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1697:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1791:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1832:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1855:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1865:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1899:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1972:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2005:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2128:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2251:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2439:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2511:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2616:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2628:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2640:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2652:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2783:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2821:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2852:            maxGoldIn: 0,

exec
/bin/bash -lc "rg -n \"getMarketState|spotPrice|PoolReserves|INITIAL_(WOOD|WHEAT|FISH|IRON|GOLD_SEED)|clanworld_v4_spec|5\\.11|1000:500|1000.*700|500:600|250:800\" docs packages/contracts" in /tmp/wt-superswarm-357
 succeeded in 0ms:
docs/planning/CANONICAL_SPEC.md:18:| 7 | `clanworld_v4_spec.md` | `docs/planning/` |
docs/planning/clanworld_v4_4_ui_indexer_getters.md:120:### 2.3 `getMarketState()`
docs/planning/clanworld_v4_4_ui_indexer_getters.md:128:    PoolReserves wood;
docs/planning/clanworld_v4_4_ui_indexer_getters.md:129:    PoolReserves wheat;
docs/planning/clanworld_v4_4_ui_indexer_getters.md:130:    PoolReserves fish;
docs/planning/clanworld_v4_4_ui_indexer_getters.md:131:    PoolReserves iron;
docs/planning/clanworld_v4_4_ui_indexer_getters.md:138:struct PoolReserves {
docs/planning/clanworld_v4_4_ui_indexer_getters.md:144:    uint256 spotPriceGoldPerResource;
docs/planning/clanworld_v4_4_ui_indexer_getters.md:147:function getMarketState() external view returns (MarketState memory);
docs/planning/clanworld_v4_4_ui_indexer_getters.md:152:- `spotPriceGoldPerResource` is computed inline so the indexer does not have to do AMM math.
docs/planning/clanworld_v4_4_ui_indexer_getters.md:251:| `getMarketState()`              | ~5 calls           | Medium — market panel + price charts   |
docs/planning/clanworld_v4_5_alignment_addendum.md:16:1. `clanworld_v4_spec.md` — base game mechanics
docs/planning/clanworld_v4_5_alignment_addendum.md:471:elder world market                # getMarketState
docs/planning/battleplan-v1.txt:3:Doc’s there, ready to forward. The price-tracking idea is folded into getMarketState() — spot price computed onchain in 18-decimal fixed point, indexer stores one price row per resource per tick, UI gets free sparklines. No separate getter needed.
docs/planning/clanworld_v4_spec.md:599:## 5.11 Initial pool seeding
docs/planning/clanworld_v4_spec.md:604:- Wheat / Gold: `1000 wheat : 700 gold`
docs/reviews/pr137-review-claude-opus.md:60:| 9 | `src/ClanWorld.sol` | 1655–1663 | **`spotPriceGoldPerResource` can overflow.** `rB * 1e18` overflows if `reserveB` exceeds `~1.15e59`. Pathological for typical seeds but a sharp edge for view-layer availability. Agent 2. | **SHOULD FIX** |
docs/reviews/pr137-review-claude-opus.md:68:| 17 | `test/ClanWorld.t.sol` | — | **`getMarketState()` never tested.** Pool reserves and queue state view function has no test coverage. Agent 5. | **DEFER** |
docs/reviews/pr137-review-claude-opus.md:144:- **Test coverage**: #17 (getMarketState), #18 (stale action path), #19 (double-init guards)
docs/reviews/pr357-codereview-codex-5-5.md:27:1. Default market seed ratios match v4 spec §5.11 — replaced uniform `INITIAL_RESOURCE_POOL_SEED=100_000e18` / `INITIAL_GOLD_POOL_SEED=50_000e18` with 8 asymmetric per-resource constants:
docs/reviews/pr357-codereview-codex-5-5.md:28:   - INITIAL_WOOD_POOL_SEED=1_000e18, GOLD_FOR_WOOD=500e18
docs/reviews/pr357-codereview-codex-5-5.md:29:   - INITIAL_WHEAT_POOL_SEED=1_000e18, GOLD_FOR_WHEAT=700e18
docs/reviews/pr357-codereview-codex-5-5.md:30:   - INITIAL_FISH_POOL_SEED=500e18, GOLD_FOR_FISH=600e18
docs/reviews/pr357-codereview-codex-5-5.md:31:   - INITIAL_IRON_POOL_SEED=250e18, GOLD_FOR_IRON=800e18
docs/reviews/pr357-codereview-codex-5-5.md:53:7. **Documentation** — should this PR also update `clanworld_v4_spec.md` §5.11 (or note that the v4 spec is now the canonical spec for this constant)? Does it conflict with the in-flight Phase 6 audit doc PR #350?
docs/reviews/pr357-codereview-codex-5-5.md:94:+        uint256 woodSeed = game.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:95:+        uint256 wheatSeed = game.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:96:+        uint256 fishSeed = game.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:97:+        uint256 ironSeed = game.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:98:+        uint256 goldForWood = game.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:99:+        uint256 goldForWheat = game.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:100:+        uint256 goldForFish = game.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:101:+        uint256 goldForIron = game.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:155:+    uint256 public constant INITIAL_WOOD_POOL_SEED = 1_000e18;
docs/reviews/pr357-codereview-codex-5-5.md:156:+    uint256 public constant INITIAL_WHEAT_POOL_SEED = 1_000e18;
docs/reviews/pr357-codereview-codex-5-5.md:157:+    uint256 public constant INITIAL_FISH_POOL_SEED = 500e18;
docs/reviews/pr357-codereview-codex-5-5.md:158:+    uint256 public constant INITIAL_IRON_POOL_SEED = 250e18;
docs/reviews/pr357-codereview-codex-5-5.md:159:+    uint256 public constant INITIAL_GOLD_SEED_FOR_WOOD = 500e18;
docs/reviews/pr357-codereview-codex-5-5.md:160:+    uint256 public constant INITIAL_GOLD_SEED_FOR_WHEAT = 700e18;
docs/reviews/pr357-codereview-codex-5-5.md:161:+    uint256 public constant INITIAL_GOLD_SEED_FOR_FISH = 600e18;
docs/reviews/pr357-codereview-codex-5-5.md:162:+    uint256 public constant INITIAL_GOLD_SEED_FOR_IRON = 800e18;
docs/reviews/pr357-codereview-codex-5-5.md:211:+        return _setupMarketWithWoodSeed(world.INITIAL_WOOD_POOL_SEED());
docs/reviews/pr357-codereview-codex-5-5.md:223:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:224:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:225:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:226:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:227:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:228:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:229:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:274:+        return _setupHarnessClanAtWithWoodSeed(state, region, cooldownEndsAtTs, world.INITIAL_WOOD_POOL_SEED());
docs/reviews/pr357-codereview-codex-5-5.md:367:+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:368:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:369:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:370:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:371:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:372:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:373:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:374:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:500:+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:501:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:502:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:503:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:504:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:505:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:506:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:507:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:562:+            woodToken, woodPool, world.INITIAL_WOOD_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WOOD(), "wood"
docs/reviews/pr357-codereview-codex-5-5.md:565:+            wheatToken, wheatPool, world.INITIAL_WHEAT_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WHEAT(), "wheat"
docs/reviews/pr357-codereview-codex-5-5.md:568:+            fishToken, fishPool, world.INITIAL_FISH_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_FISH(), "fish"
docs/reviews/pr357-codereview-codex-5-5.md:571:+            ironToken, ironPool, world.INITIAL_IRON_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_IRON(), "iron"
docs/reviews/pr357-codereview-codex-5-5.md:588:+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:589:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:590:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:591:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:592:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:593:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:594:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:595:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:627:+            woodSeed: world.INITIAL_WOOD_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:628:+            wheatSeed: world.INITIAL_WHEAT_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:629:+            fishSeed: world.INITIAL_FISH_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:630:+            ironSeed: world.INITIAL_IRON_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:631:+            goldSeedForWood: world.INITIAL_GOLD_SEED_FOR_WOOD(),
docs/reviews/pr357-codereview-codex-5-5.md:632:+            goldSeedForWheat: world.INITIAL_GOLD_SEED_FOR_WHEAT(),
docs/reviews/pr357-codereview-codex-5-5.md:633:+            goldSeedForFish: world.INITIAL_GOLD_SEED_FOR_FISH(),
docs/reviews/pr357-codereview-codex-5-5.md:634:+            goldSeedForIron: world.INITIAL_GOLD_SEED_FOR_IRON()
docs/reviews/pr357-codereview-codex-5-5.md:669:| `docs/planning/clanworld_v4_spec.md` | §5.1–5.13 (the canonical Unicorn Town market model: venue, pool set, scheduled vs immediate execution modes, ordering, slippage, failure semantics, seed ratios, gold faucets, depletion) |
docs/reviews/pr357-codereview-codex-5-5.md:673:| `docs/planning/clanworld_v4_4_ui_indexer_getters.md` | §2.3 `getMarketState()` shape (4 PoolReserves + spotPriceGoldPerResource + currentTick + currentTickQueue + nextTickQueue) |
docs/reviews/pr357-codereview-codex-5-5.md:689:- **5.11** Initial seed ratios: Wood/Gold 1000:500, Wheat/Gold 1000:700, Fish/Gold 500:600, Iron/Gold 250:800
docs/reviews/pr357-codereview-codex-5-5.md:701:- **v4.4 §2.3** `getMarketState()` returns 4 PoolReserves with `spotPriceGoldPerResource` + `currentTick` + currentTickQueue + nextTickQueue
docs/reviews/pr357-codereview-codex-5-5.md:736:| **Initial seed ratios** | Wood/Gold 1000:500; Wheat/Gold 1000:700; Fish/Gold 500:600; Iron/Gold 250:800 (§5.11) | `seedPools(PoolSeedConfig)` accepts arbitrary per-pool config from caller. Hardcoded constants `INITIAL_RESOURCE_POOL_SEED = 100_000e18`, `INITIAL_GOLD_POOL_SEED = 50_000e18` are uniform across pools and used by tests/deploy scripts. | `ClanWorld.sol:82-83`; `IClanWorld.sol:402-410`; `SeedPools.t.sol:114-127` | ⚠️ TRIVIAL — defaults are uniform; spec's asymmetric ratios are a deployer-config concern, not a contract-enforcement concern. PoolSeedConfig is the right surface; tests just don't test the spec's exact numbers. Deployer must pass spec ratios at seed time to comply. |
docs/reviews/pr357-codereview-codex-5-5.md:740:| **`getMarketState()` shape** | 4 PoolReserves + spot price + currentTick + currentTickQueue + nextTickQueue (v4.4 §2.3) | Returns exactly that struct shape | `ClanWorld.sol:2593-2603`; `IClanWorld.sol:474-481` | ✅ MATCHES |
docs/reviews/pr357-codereview-codex-5-5.md:741:| **`spotPriceGoldPerResource` formula** | `goldReserve * 1e18 / resourceReserve`, `0` if reserve == 0 (v4.4 §2.3) | Exactly that, with the same zero-guard | `ClanWorld.sol:2613` | ✅ MATCHES |
docs/reviews/pr357-codereview-codex-5-5.md:782:- 1 is **uniform default seed ratios** (100k:50k uniform) vs spec's asymmetric (1000:500, 1000:700, 500:600, 250:800) — only matters at deploy-time configuration.
docs/reviews/pr357-codereview-codex-5-5.md:847:| **Spec asymmetric seed ratios** | No test seeds with the exact spec values (Wood 1000:500, Wheat 1000:700, Fish 500:600, Iron 250:800) and verifies prices behave as expected; tests use uniform 100k:50k. Deployment-side risk: if a deployer follows tests as a reference rather than the spec, they'll seed wrong. | §5.11 |
docs/reviews/pr357-codereview-codex-5-5.md:851:| **`getMarketState()` shape contract** | No test calls `getMarketState()` and asserts all 4 reserves + spot prices + currentTick + both queue snapshots are populated correctly (especially `nextTickQueue` containing actions queued for currentTick+1). | v4.4 §2.3 |
docs/reviews/pr357-codereview-codex-5-5.md:852:| **`spotPriceGoldPerResource` zero-reserve guard** | Edge case where one reserve is zero (e.g., immediately after extreme depletion) — spec demands `0` return. Not asserted. | v4.4 §2.3 |
docs/reviews/pr357-codereview-codex-5-5.md:905:**Setup:** Deploy with the exact spec ratios: Wood/Gold 1000e18:500e18, Wheat/Gold 1000e18:700e18, Fish/Gold 500e18:600e18, Iron/Gold 250e18:800e18. Read `getMarketState()`.
docs/reviews/pr357-codereview-codex-5-5.md:908:**He should verify:** spot prices in `getMarketState()` match expected within 1 wei rounding.
docs/reviews/pr357-codereview-codex-5-5.md:935:Major mechanics — exact-input sell vs exact-output buy, worker-carry source/destination, maxGoldIn slippage guard, scheduled FIFO, heartbeat cleanup, immediate-vs-scheduled ordering, settlement-before-market heartbeat ordering, reentrancy guards, status-code presence, getMarketState shape, x*y=k AMM with k-invariant — **all match spec**.
docs/reviews/pr357-codereview-codex-5-5.md:966:2. **Default seed ratios match spec** (`ClanWorld.sol:82-83`) — split `INITIAL_RESOURCE_POOL_SEED` and `INITIAL_GOLD_POOL_SEED` into 4 per-pool constants matching §5.11 ratios. Or document that the spec ratios must be passed by the deployer.
docs/reviews/pr357-codereview-codex-5-5.md:987:- `docs/planning/clanworld_v4_spec.md` §5 + invariants §15
docs/reviews/pr357-codereview-codex-5-5.md:1011:  2. ClanWorld.sol:82-83  default seed constants are uniform; spec §5.11 has asymmetric per-pool ratios
docs/reviews/pr357-codereview-codex-5-5.md:1308:/bin/bash -lc 'rg -n "INITIAL_RESOURCE_POOL_SEED|INITIAL_GOLD_POOL_SEED|INITIAL_WOOD_POOL_SEED|INITIAL_WHEAT_POOL_SEED|INITIAL_FISH_POOL_SEED|INITIAL_IRON_POOL_SEED|INITIAL_GOLD_SEED_FOR_" .' in /tmp/wt-superswarm-357
docs/reviews/pr357-codereview-codex-5-5.md:1310:./packages/contracts/script/Deploy.s.sol:53:        uint256 woodSeed = game.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1311:./packages/contracts/script/Deploy.s.sol:54:        uint256 wheatSeed = game.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1312:./packages/contracts/script/Deploy.s.sol:55:        uint256 fishSeed = game.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1313:./packages/contracts/script/Deploy.s.sol:56:        uint256 ironSeed = game.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1314:./packages/contracts/script/Deploy.s.sol:57:        uint256 goldForWood = game.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:1315:./packages/contracts/script/Deploy.s.sol:58:        uint256 goldForWheat = game.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:1316:./packages/contracts/script/Deploy.s.sol:59:        uint256 goldForFish = game.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:1317:./packages/contracts/script/Deploy.s.sol:60:        uint256 goldForIron = game.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:1318:./packages/contracts/src/ClanWorld.sol:82:    uint256 public constant INITIAL_WOOD_POOL_SEED = 1_000e18;
docs/reviews/pr357-codereview-codex-5-5.md:1319:./packages/contracts/src/ClanWorld.sol:83:    uint256 public constant INITIAL_WHEAT_POOL_SEED = 1_000e18;
docs/reviews/pr357-codereview-codex-5-5.md:1320:./packages/contracts/src/ClanWorld.sol:84:    uint256 public constant INITIAL_FISH_POOL_SEED = 500e18;
docs/reviews/pr357-codereview-codex-5-5.md:1321:./packages/contracts/src/ClanWorld.sol:85:    uint256 public constant INITIAL_IRON_POOL_SEED = 250e18;
docs/reviews/pr357-codereview-codex-5-5.md:1322:./packages/contracts/src/ClanWorld.sol:86:    uint256 public constant INITIAL_GOLD_SEED_FOR_WOOD = 500e18;
docs/reviews/pr357-codereview-codex-5-5.md:1323:./packages/contracts/src/ClanWorld.sol:87:    uint256 public constant INITIAL_GOLD_SEED_FOR_WHEAT = 700e18;
docs/reviews/pr357-codereview-codex-5-5.md:1324:./packages/contracts/src/ClanWorld.sol:88:    uint256 public constant INITIAL_GOLD_SEED_FOR_FISH = 600e18;
docs/reviews/pr357-codereview-codex-5-5.md:1325:./packages/contracts/src/ClanWorld.sol:89:    uint256 public constant INITIAL_GOLD_SEED_FOR_IRON = 800e18;
docs/reviews/pr357-codereview-codex-5-5.md:1326:./packages/contracts/test/ClanWorld.t.sol:96:        return _setupMarketWithWoodSeed(world.INITIAL_WOOD_POOL_SEED());
docs/reviews/pr357-codereview-codex-5-5.md:1327:./packages/contracts/test/ClanWorld.t.sol:125:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1328:./packages/contracts/test/ClanWorld.t.sol:126:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1329:./packages/contracts/test/ClanWorld.t.sol:127:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1330:./packages/contracts/test/ClanWorld.t.sol:128:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:1331:./packages/contracts/test/ClanWorld.t.sol:129:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:1332:./packages/contracts/test/ClanWorld.t.sol:130:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:1333:./packages/contracts/test/ClanWorld.t.sol:131:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:1334:./packages/contracts/test/ClanWorld.t.sol:932:        return _setupHarnessClanAtWithWoodSeed(state, region, cooldownEndsAtTs, world.INITIAL_WOOD_POOL_SEED());
docs/reviews/pr357-codereview-codex-5-5.md:1335:./packages/contracts/test/HeartbeatOrdering.t.sol:155:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1336:./packages/contracts/test/HeartbeatOrdering.t.sol:156:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1337:./packages/contracts/test/HeartbeatOrdering.t.sol:157:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1338:./packages/contracts/test/HeartbeatOrdering.t.sol:158:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1339:./packages/contracts/test/HeartbeatOrdering.t.sol:159:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:1340:./packages/contracts/test/HeartbeatOrdering.t.sol:160:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:1341:./packages/contracts/test/HeartbeatOrdering.t.sol:161:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:1342:./packages/contracts/test/HeartbeatOrdering.t.sol:162:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:1343:./packages/contracts/test/Reentrancy.t.sol:172:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1344:./packages/contracts/test/Reentrancy.t.sol:173:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1345:./packages/contracts/test/Reentrancy.t.sol:174:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1346:./packages/contracts/test/Reentrancy.t.sol:175:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1347:./packages/contracts/test/Reentrancy.t.sol:176:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:1348:./packages/contracts/test/Reentrancy.t.sol:177:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:1349:./packages/contracts/test/Reentrancy.t.sol:178:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:1350:./packages/contracts/test/Reentrancy.t.sol:179:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:1351:./packages/contracts/test/SeedPools.t.sol:63:            woodToken, woodPool, world.INITIAL_WOOD_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WOOD(), "wood"
docs/reviews/pr357-codereview-codex-5-5.md:1352:./packages/contracts/test/SeedPools.t.sol:66:            wheatToken, wheatPool, world.INITIAL_WHEAT_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WHEAT(), "wheat"
docs/reviews/pr357-codereview-codex-5-5.md:1353:./packages/contracts/test/SeedPools.t.sol:69:            fishToken, fishPool, world.INITIAL_FISH_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_FISH(), "fish"
docs/reviews/pr357-codereview-codex-5-5.md:1354:./packages/contracts/test/SeedPools.t.sol:72:            ironToken, ironPool, world.INITIAL_IRON_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_IRON(), "iron"
docs/reviews/pr357-codereview-codex-5-5.md:1355:./packages/contracts/test/SeedPools.t.sol:102:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1356:./packages/contracts/test/SeedPools.t.sol:103:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1357:./packages/contracts/test/SeedPools.t.sol:104:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1358:./packages/contracts/test/SeedPools.t.sol:105:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1359:./packages/contracts/test/SeedPools.t.sol:106:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:1360:./packages/contracts/test/SeedPools.t.sol:107:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:1361:./packages/contracts/test/SeedPools.t.sol:108:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:1362:./packages/contracts/test/SeedPools.t.sol:109:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:1363:./packages/contracts/test/SeedPools.t.sol:127:            woodSeed: world.INITIAL_WOOD_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:1364:./packages/contracts/test/SeedPools.t.sol:128:            wheatSeed: world.INITIAL_WHEAT_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:1365:./packages/contracts/test/SeedPools.t.sol:129:            fishSeed: world.INITIAL_FISH_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:1366:./packages/contracts/test/SeedPools.t.sol:130:            ironSeed: world.INITIAL_IRON_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:1367:./packages/contracts/test/SeedPools.t.sol:131:            goldSeedForWood: world.INITIAL_GOLD_SEED_FOR_WOOD(),
docs/reviews/pr357-codereview-codex-5-5.md:1368:./packages/contracts/test/SeedPools.t.sol:132:            goldSeedForWheat: world.INITIAL_GOLD_SEED_FOR_WHEAT(),
docs/reviews/pr357-codereview-codex-5-5.md:1369:./packages/contracts/test/SeedPools.t.sol:133:            goldSeedForFish: world.INITIAL_GOLD_SEED_FOR_FISH(),
docs/reviews/pr357-codereview-codex-5-5.md:1370:./packages/contracts/test/SeedPools.t.sol:134:            goldSeedForIron: world.INITIAL_GOLD_SEED_FOR_IRON()
docs/reviews/pr357-codereview-codex-5-5.md:1371:./docs/reviews/pr357-codereview-codex-5-5.md:27:1. Default market seed ratios match v4 spec §5.11 — replaced uniform `INITIAL_RESOURCE_POOL_SEED=100_000e18` / `INITIAL_GOLD_POOL_SEED=50_000e18` with 8 asymmetric per-resource constants:
docs/reviews/pr357-codereview-codex-5-5.md:1372:./docs/reviews/pr357-codereview-codex-5-5.md:28:   - INITIAL_WOOD_POOL_SEED=1_000e18, GOLD_FOR_WOOD=500e18
docs/reviews/pr357-codereview-codex-5-5.md:1373:./docs/reviews/pr357-codereview-codex-5-5.md:29:   - INITIAL_WHEAT_POOL_SEED=1_000e18, GOLD_FOR_WHEAT=700e18
docs/reviews/pr357-codereview-codex-5-5.md:1374:./docs/reviews/pr357-codereview-codex-5-5.md:30:   - INITIAL_FISH_POOL_SEED=500e18, GOLD_FOR_FISH=600e18
docs/reviews/pr357-codereview-codex-5-5.md:1375:./docs/reviews/pr357-codereview-codex-5-5.md:31:   - INITIAL_IRON_POOL_SEED=250e18, GOLD_FOR_IRON=800e18
docs/reviews/pr357-codereview-codex-5-5.md:1379:./docs/reviews/pr357-codereview-codex-5-5.md:94:+        uint256 woodSeed = game.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1380:./docs/reviews/pr357-codereview-codex-5-5.md:95:+        uint256 wheatSeed = game.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1381:./docs/reviews/pr357-codereview-codex-5-5.md:96:+        uint256 fishSeed = game.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1382:./docs/reviews/pr357-codereview-codex-5-5.md:97:+        uint256 ironSeed = game.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1383:./docs/reviews/pr357-codereview-codex-5-5.md:98:+        uint256 goldForWood = game.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:1384:./docs/reviews/pr357-codereview-codex-5-5.md:99:+        uint256 goldForWheat = game.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:1385:./docs/reviews/pr357-codereview-codex-5-5.md:100:+        uint256 goldForFish = game.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:1386:./docs/reviews/pr357-codereview-codex-5-5.md:101:+        uint256 goldForIron = game.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:1389:./docs/reviews/pr357-codereview-codex-5-5.md:155:+    uint256 public constant INITIAL_WOOD_POOL_SEED = 1_000e18;
docs/reviews/pr357-codereview-codex-5-5.md:1390:./docs/reviews/pr357-codereview-codex-5-5.md:156:+    uint256 public constant INITIAL_WHEAT_POOL_SEED = 1_000e18;
docs/reviews/pr357-codereview-codex-5-5.md:1391:./docs/reviews/pr357-codereview-codex-5-5.md:157:+    uint256 public constant INITIAL_FISH_POOL_SEED = 500e18;
docs/reviews/pr357-codereview-codex-5-5.md:1392:./docs/reviews/pr357-codereview-codex-5-5.md:158:+    uint256 public constant INITIAL_IRON_POOL_SEED = 250e18;
docs/reviews/pr357-codereview-codex-5-5.md:1393:./docs/reviews/pr357-codereview-codex-5-5.md:159:+    uint256 public constant INITIAL_GOLD_SEED_FOR_WOOD = 500e18;
docs/reviews/pr357-codereview-codex-5-5.md:1394:./docs/reviews/pr357-codereview-codex-5-5.md:160:+    uint256 public constant INITIAL_GOLD_SEED_FOR_WHEAT = 700e18;
docs/reviews/pr357-codereview-codex-5-5.md:1395:./docs/reviews/pr357-codereview-codex-5-5.md:161:+    uint256 public constant INITIAL_GOLD_SEED_FOR_FISH = 600e18;
docs/reviews/pr357-codereview-codex-5-5.md:1396:./docs/reviews/pr357-codereview-codex-5-5.md:162:+    uint256 public constant INITIAL_GOLD_SEED_FOR_IRON = 800e18;
docs/reviews/pr357-codereview-codex-5-5.md:1398:./docs/reviews/pr357-codereview-codex-5-5.md:211:+        return _setupMarketWithWoodSeed(world.INITIAL_WOOD_POOL_SEED());
docs/reviews/pr357-codereview-codex-5-5.md:1401:./docs/reviews/pr357-codereview-codex-5-5.md:223:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1402:./docs/reviews/pr357-codereview-codex-5-5.md:224:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1403:./docs/reviews/pr357-codereview-codex-5-5.md:225:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1404:./docs/reviews/pr357-codereview-codex-5-5.md:226:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:1405:./docs/reviews/pr357-codereview-codex-5-5.md:227:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:1406:./docs/reviews/pr357-codereview-codex-5-5.md:228:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:1407:./docs/reviews/pr357-codereview-codex-5-5.md:229:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:1409:./docs/reviews/pr357-codereview-codex-5-5.md:274:+        return _setupHarnessClanAtWithWoodSeed(state, region, cooldownEndsAtTs, world.INITIAL_WOOD_POOL_SEED());
docs/reviews/pr357-codereview-codex-5-5.md:1412:./docs/reviews/pr357-codereview-codex-5-5.md:367:+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1413:./docs/reviews/pr357-codereview-codex-5-5.md:368:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1414:./docs/reviews/pr357-codereview-codex-5-5.md:369:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1415:./docs/reviews/pr357-codereview-codex-5-5.md:370:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1416:./docs/reviews/pr357-codereview-codex-5-5.md:371:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:1417:./docs/reviews/pr357-codereview-codex-5-5.md:372:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:1418:./docs/reviews/pr357-codereview-codex-5-5.md:373:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:1419:./docs/reviews/pr357-codereview-codex-5-5.md:374:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:1422:./docs/reviews/pr357-codereview-codex-5-5.md:500:+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1423:./docs/reviews/pr357-codereview-codex-5-5.md:501:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1424:./docs/reviews/pr357-codereview-codex-5-5.md:502:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1425:./docs/reviews/pr357-codereview-codex-5-5.md:503:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1426:./docs/reviews/pr357-codereview-codex-5-5.md:504:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:1427:./docs/reviews/pr357-codereview-codex-5-5.md:505:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:1428:./docs/reviews/pr357-codereview-codex-5-5.md:506:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:1429:./docs/reviews/pr357-codereview-codex-5-5.md:507:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:1432:./docs/reviews/pr357-codereview-codex-5-5.md:562:+            woodToken, woodPool, world.INITIAL_WOOD_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WOOD(), "wood"
docs/reviews/pr357-codereview-codex-5-5.md:1433:./docs/reviews/pr357-codereview-codex-5-5.md:565:+            wheatToken, wheatPool, world.INITIAL_WHEAT_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WHEAT(), "wheat"
docs/reviews/pr357-codereview-codex-5-5.md:1434:./docs/reviews/pr357-codereview-codex-5-5.md:568:+            fishToken, fishPool, world.INITIAL_FISH_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_FISH(), "fish"
docs/reviews/pr357-codereview-codex-5-5.md:1435:./docs/reviews/pr357-codereview-codex-5-5.md:571:+            ironToken, ironPool, world.INITIAL_IRON_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_IRON(), "iron"
docs/reviews/pr357-codereview-codex-5-5.md:1438:./docs/reviews/pr357-codereview-codex-5-5.md:588:+        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1439:./docs/reviews/pr357-codereview-codex-5-5.md:589:+        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1440:./docs/reviews/pr357-codereview-codex-5-5.md:590:+        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1441:./docs/reviews/pr357-codereview-codex-5-5.md:591:+        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:1442:./docs/reviews/pr357-codereview-codex-5-5.md:592:+        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:1443:./docs/reviews/pr357-codereview-codex-5-5.md:593:+        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:1444:./docs/reviews/pr357-codereview-codex-5-5.md:594:+        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:1445:./docs/reviews/pr357-codereview-codex-5-5.md:595:+        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:1448:./docs/reviews/pr357-codereview-codex-5-5.md:627:+            woodSeed: world.INITIAL_WOOD_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:1449:./docs/reviews/pr357-codereview-codex-5-5.md:628:+            wheatSeed: world.INITIAL_WHEAT_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:1450:./docs/reviews/pr357-codereview-codex-5-5.md:629:+            fishSeed: world.INITIAL_FISH_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:1451:./docs/reviews/pr357-codereview-codex-5-5.md:630:+            ironSeed: world.INITIAL_IRON_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:1452:./docs/reviews/pr357-codereview-codex-5-5.md:631:+            goldSeedForWood: world.INITIAL_GOLD_SEED_FOR_WOOD(),
docs/reviews/pr357-codereview-codex-5-5.md:1453:./docs/reviews/pr357-codereview-codex-5-5.md:632:+            goldSeedForWheat: world.INITIAL_GOLD_SEED_FOR_WHEAT(),
docs/reviews/pr357-codereview-codex-5-5.md:1454:./docs/reviews/pr357-codereview-codex-5-5.md:633:+            goldSeedForFish: world.INITIAL_GOLD_SEED_FOR_FISH(),
docs/reviews/pr357-codereview-codex-5-5.md:1455:./docs/reviews/pr357-codereview-codex-5-5.md:634:+            goldSeedForIron: world.INITIAL_GOLD_SEED_FOR_IRON()
docs/reviews/pr357-codereview-codex-5-5.md:1456:./docs/reviews/pr357-codereview-codex-5-5.md:736:| **Initial seed ratios** | Wood/Gold 1000:500; Wheat/Gold 1000:700; Fish/Gold 500:600; Iron/Gold 250:800 (§5.11) | `seedPools(PoolSeedConfig)` accepts arbitrary per-pool config from caller. Hardcoded constants `INITIAL_RESOURCE_POOL_SEED = 100_000e18`, `INITIAL_GOLD_POOL_SEED = 50_000e18` are uniform across pools and used by tests/deploy scripts. | `ClanWorld.sol:82-83`; `IClanWorld.sol:402-410`; `SeedPools.t.sol:114-127` | ⚠️ TRIVIAL — defaults are uniform; spec's asymmetric ratios are a deployer-config concern, not a contract-enforcement concern. PoolSeedConfig is the right surface; tests just don't test the spec's exact numbers. Deployer must pass spec ratios at seed time to comply. |
docs/reviews/pr357-codereview-codex-5-5.md:1458:./docs/reviews/pr357-codereview-codex-5-5.md:966:2. **Default seed ratios match spec** (`ClanWorld.sol:82-83`) — split `INITIAL_RESOURCE_POOL_SEED` and `INITIAL_GOLD_POOL_SEED` into 4 per-pool constants matching §5.11 ratios. Or document that the spec ratios must be passed by the deployer.
docs/reviews/pr357-codereview-codex-5-5.md:3117:    63	            woodToken, woodPool, world.INITIAL_WOOD_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WOOD(), "wood"
docs/reviews/pr357-codereview-codex-5-5.md:3120:    66	            wheatToken, wheatPool, world.INITIAL_WHEAT_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WHEAT(), "wheat"
docs/reviews/pr357-codereview-codex-5-5.md:3123:    69	            fishToken, fishPool, world.INITIAL_FISH_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_FISH(), "fish"
docs/reviews/pr357-codereview-codex-5-5.md:3126:    72	            ironToken, ironPool, world.INITIAL_IRON_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_IRON(), "iron"
docs/reviews/pr357-codereview-codex-5-5.md:3156:   102	        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:3157:   103	        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:3158:   104	        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:3159:   105	        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:3160:   106	        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:3161:   107	        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:3162:   108	        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:3163:   109	        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
docs/reviews/pr357-codereview-codex-5-5.md:3181:   127	            woodSeed: world.INITIAL_WOOD_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:3182:   128	            wheatSeed: world.INITIAL_WHEAT_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:3183:   129	            fishSeed: world.INITIAL_FISH_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:3184:   130	            ironSeed: world.INITIAL_IRON_POOL_SEED(),
docs/reviews/pr357-codereview-codex-5-5.md:3185:   131	            goldSeedForWood: world.INITIAL_GOLD_SEED_FOR_WOOD(),
docs/reviews/pr357-codereview-codex-5-5.md:3186:   132	            goldSeedForWheat: world.INITIAL_GOLD_SEED_FOR_WHEAT(),
docs/reviews/pr357-codereview-codex-5-5.md:3187:   133	            goldSeedForFish: world.INITIAL_GOLD_SEED_FOR_FISH(),
docs/reviews/pr357-codereview-codex-5-5.md:3188:   134	            goldSeedForIron: world.INITIAL_GOLD_SEED_FOR_IRON()
docs/reviews/pr357-codereview-codex-5-5.md:3418:    53	        uint256 woodSeed = game.INITIAL_WOOD_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:3419:    54	        uint256 wheatSeed = game.INITIAL_WHEAT_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:3420:    55	        uint256 fishSeed = game.INITIAL_FISH_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:3421:    56	        uint256 ironSeed = game.INITIAL_IRON_POOL_SEED();
docs/reviews/pr357-codereview-codex-5-5.md:3422:    57	        uint256 goldForWood = game.INITIAL_GOLD_SEED_FOR_WOOD();
docs/reviews/pr357-codereview-codex-5-5.md:3423:    58	        uint256 goldForWheat = game.INITIAL_GOLD_SEED_FOR_WHEAT();
docs/reviews/pr357-codereview-codex-5-5.md:3424:    59	        uint256 goldForFish = game.INITIAL_GOLD_SEED_FOR_FISH();
docs/reviews/pr357-codereview-codex-5-5.md:3425:    60	        uint256 goldForIron = game.INITIAL_GOLD_SEED_FOR_IRON();
packages/contracts/abi/IClanWorld.json:1462:      "name": "getMarketState",
packages/contracts/abi/IClanWorld.json:1473:              "internalType": "struct PoolReserves",
packages/contracts/abi/IClanWorld.json:1491:                  "name": "spotPriceGoldPerResource",
packages/contracts/abi/IClanWorld.json:1500:              "internalType": "struct PoolReserves",
packages/contracts/abi/IClanWorld.json:1518:                  "name": "spotPriceGoldPerResource",
packages/contracts/abi/IClanWorld.json:1527:              "internalType": "struct PoolReserves",
packages/contracts/abi/IClanWorld.json:1545:                  "name": "spotPriceGoldPerResource",
packages/contracts/abi/IClanWorld.json:1554:              "internalType": "struct PoolReserves",
packages/contracts/abi/IClanWorld.json:1572:                  "name": "spotPriceGoldPerResource",
packages/contracts/script/Deploy.s.sol:53:        uint256 woodSeed = game.INITIAL_WOOD_POOL_SEED();
packages/contracts/script/Deploy.s.sol:54:        uint256 wheatSeed = game.INITIAL_WHEAT_POOL_SEED();
packages/contracts/script/Deploy.s.sol:55:        uint256 fishSeed = game.INITIAL_FISH_POOL_SEED();
packages/contracts/script/Deploy.s.sol:56:        uint256 ironSeed = game.INITIAL_IRON_POOL_SEED();
packages/contracts/script/Deploy.s.sol:57:        uint256 goldForWood = game.INITIAL_GOLD_SEED_FOR_WOOD();
packages/contracts/script/Deploy.s.sol:58:        uint256 goldForWheat = game.INITIAL_GOLD_SEED_FOR_WHEAT();
packages/contracts/script/Deploy.s.sol:59:        uint256 goldForFish = game.INITIAL_GOLD_SEED_FOR_FISH();
packages/contracts/script/Deploy.s.sol:60:        uint256 goldForIron = game.INITIAL_GOLD_SEED_FOR_IRON();
packages/contracts/src/ClanWorld.sol:36:    PoolReserves,
packages/contracts/src/ClanWorld.sol:82:    uint256 public constant INITIAL_WOOD_POOL_SEED = 1_000e18;
packages/contracts/src/ClanWorld.sol:83:    uint256 public constant INITIAL_WHEAT_POOL_SEED = 1_000e18;
packages/contracts/src/ClanWorld.sol:84:    uint256 public constant INITIAL_FISH_POOL_SEED = 500e18;
packages/contracts/src/ClanWorld.sol:85:    uint256 public constant INITIAL_IRON_POOL_SEED = 250e18;
packages/contracts/src/ClanWorld.sol:86:    uint256 public constant INITIAL_GOLD_SEED_FOR_WOOD = 500e18;
packages/contracts/src/ClanWorld.sol:87:    uint256 public constant INITIAL_GOLD_SEED_FOR_WHEAT = 700e18;
packages/contracts/src/ClanWorld.sol:88:    uint256 public constant INITIAL_GOLD_SEED_FOR_FISH = 600e18;
packages/contracts/src/ClanWorld.sol:89:    uint256 public constant INITIAL_GOLD_SEED_FOR_IRON = 800e18;
packages/contracts/src/ClanWorld.sol:2605:    function getMarketState() external view override returns (MarketState memory) {
packages/contracts/src/ClanWorld.sol:2617:    function _poolReserves(address resourceToken, address poolAddr) internal view returns (PoolReserves memory pr) {
packages/contracts/src/ClanWorld.sol:2625:        pr.spotPriceGoldPerResource = rA > 0 ? (rB * 1e18) / rA : 0;
packages/contracts/src/ClanWorldStub.sol:36:    PoolReserves,
packages/contracts/src/ClanWorldStub.sol:341:    function getMarketState() external view override returns (MarketState memory) {
packages/contracts/src/ClanWorldStub.sol:343:            wood: PoolReserves({
packages/contracts/src/ClanWorldStub.sol:344:                resourceToken: _treasury.woodToken, resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0
packages/contracts/src/ClanWorldStub.sol:346:            wheat: PoolReserves({
packages/contracts/src/ClanWorldStub.sol:347:                resourceToken: _treasury.wheatToken, resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0
packages/contracts/src/ClanWorldStub.sol:349:            fish: PoolReserves({
packages/contracts/src/ClanWorldStub.sol:350:                resourceToken: _treasury.fishToken, resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0
packages/contracts/src/ClanWorldStub.sol:352:            iron: PoolReserves({
packages/contracts/src/ClanWorldStub.sol:353:                resourceToken: _treasury.ironToken, resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0
packages/contracts/src/IClanWorld.sol:9: *   - clanworld_v4_spec.md (mechanics)
packages/contracts/src/IClanWorld.sol:468:struct PoolReserves {
packages/contracts/src/IClanWorld.sol:472:    uint256 spotPriceGoldPerResource; // = goldReserve * 1e18 / resourceReserve, or 0
packages/contracts/src/IClanWorld.sol:476:    PoolReserves wood;
packages/contracts/src/IClanWorld.sol:477:    PoolReserves wheat;
packages/contracts/src/IClanWorld.sol:478:    PoolReserves fish;
packages/contracts/src/IClanWorld.sol:479:    PoolReserves iron;
packages/contracts/src/IClanWorld.sol:818:    function getMarketState() external view returns (MarketState memory);
packages/contracts/test/ClanWorld.t.sol:40:    PoolReserves,
packages/contracts/test/ClanWorld.t.sol:96:        return _setupMarketWithWoodSeed(world.INITIAL_WOOD_POOL_SEED());
packages/contracts/test/ClanWorld.t.sol:125:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
packages/contracts/test/ClanWorld.t.sol:126:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
packages/contracts/test/ClanWorld.t.sol:127:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
packages/contracts/test/ClanWorld.t.sol:128:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
packages/contracts/test/ClanWorld.t.sol:129:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
packages/contracts/test/ClanWorld.t.sol:130:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
packages/contracts/test/ClanWorld.t.sol:131:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
packages/contracts/test/ClanWorld.t.sol:932:        return _setupHarnessClanAtWithWoodSeed(state, region, cooldownEndsAtTs, world.INITIAL_WOOD_POOL_SEED());
packages/contracts/test/ClanWorld.t.sol:1036:        assertEq(world.getMarketState().nextTickQueue.length, 0, "future queue stays off next tick when not next tick");
packages/contracts/test/HeartbeatOrdering.t.sol:155:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
packages/contracts/test/HeartbeatOrdering.t.sol:156:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
packages/contracts/test/HeartbeatOrdering.t.sol:157:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
packages/contracts/test/HeartbeatOrdering.t.sol:158:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
packages/contracts/test/HeartbeatOrdering.t.sol:159:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
packages/contracts/test/HeartbeatOrdering.t.sol:160:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
packages/contracts/test/HeartbeatOrdering.t.sol:161:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
packages/contracts/test/HeartbeatOrdering.t.sol:162:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
packages/contracts/test/Reentrancy.t.sol:172:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
packages/contracts/test/Reentrancy.t.sol:173:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
packages/contracts/test/Reentrancy.t.sol:174:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
packages/contracts/test/Reentrancy.t.sol:175:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
packages/contracts/test/Reentrancy.t.sol:176:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
packages/contracts/test/Reentrancy.t.sol:177:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
packages/contracts/test/Reentrancy.t.sol:178:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
packages/contracts/test/Reentrancy.t.sol:179:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
packages/contracts/test/SeedPools.t.sol:63:            woodToken, woodPool, world.INITIAL_WOOD_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WOOD(), "wood"
packages/contracts/test/SeedPools.t.sol:66:            wheatToken, wheatPool, world.INITIAL_WHEAT_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WHEAT(), "wheat"
packages/contracts/test/SeedPools.t.sol:69:            fishToken, fishPool, world.INITIAL_FISH_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_FISH(), "fish"
packages/contracts/test/SeedPools.t.sol:72:            ironToken, ironPool, world.INITIAL_IRON_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_IRON(), "iron"
packages/contracts/test/SeedPools.t.sol:102:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
packages/contracts/test/SeedPools.t.sol:103:        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
packages/contracts/test/SeedPools.t.sol:104:        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
packages/contracts/test/SeedPools.t.sol:105:        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
packages/contracts/test/SeedPools.t.sol:106:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
packages/contracts/test/SeedPools.t.sol:107:        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
packages/contracts/test/SeedPools.t.sol:108:        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
packages/contracts/test/SeedPools.t.sol:109:        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
packages/contracts/test/SeedPools.t.sol:127:            woodSeed: world.INITIAL_WOOD_POOL_SEED(),
packages/contracts/test/SeedPools.t.sol:128:            wheatSeed: world.INITIAL_WHEAT_POOL_SEED(),
packages/contracts/test/SeedPools.t.sol:129:            fishSeed: world.INITIAL_FISH_POOL_SEED(),
packages/contracts/test/SeedPools.t.sol:130:            ironSeed: world.INITIAL_IRON_POOL_SEED(),
packages/contracts/test/SeedPools.t.sol:131:            goldSeedForWood: world.INITIAL_GOLD_SEED_FOR_WOOD(),
packages/contracts/test/SeedPools.t.sol:132:            goldSeedForWheat: world.INITIAL_GOLD_SEED_FOR_WHEAT(),
packages/contracts/test/SeedPools.t.sol:133:            goldSeedForFish: world.INITIAL_GOLD_SEED_FOR_FISH(),
packages/contracts/test/SeedPools.t.sol:134:            goldSeedForIron: world.INITIAL_GOLD_SEED_FOR_IRON()

codex
The validation guard is early enough to cover both modes: `_validateAction` runs before the immediate/scheduled branch, so a delayed buy with `maxGoldIn == 0` never reaches enqueue. I’m checking whether tests pin that exact delayed case, and whether generated/static artifacts drifted with the public constants.
exec
/bin/bash -lc "rg -n \"ActionType\\.MarketBuy.*0|MarketBuy[\\s\\S]{0,160}maxGoldIn: 0|_submitMarketOrder\\(["'^'"\\n]*MarketBuy["'^'"\\n]*, 0\\)\" packages/contracts/test" in /tmp/wt-superswarm-357
 succeeded in 0ms:
packages/contracts/test/ClanWorld.t.sol:1077:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 0);
packages/contracts/test/ClanWorld.t.sol:1169:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 7e18, 10e18);
packages/contracts/test/ClanWorld.t.sol:1191:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 10e18);
packages/contracts/test/ClanWorld.t.sol:1312:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 500e18);
packages/contracts/test/ClanWorld.t.sol:1385:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 7e18, 10e18);
packages/contracts/test/ClanWorld.t.sol:1423:        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 10e18);

exec
/bin/bash -lc 'rg -n "INITIAL_RESOURCE_POOL_SEED|INITIAL_GOLD_POOL_SEED|INITIAL_WOOD_POOL_SEED|INITIAL_GOLD_SEED_FOR_WOOD" packages/contracts/abi packages/contracts/broadcast packages/contracts/cache packages/contracts/out 2>/dev/null' in /tmp/wt-superswarm-357
 exited 2 in 0ms:
exec
/bin/bash -lc "rg -n \"INITIAL_RESOURCE_POOL_SEED|INITIAL_GOLD_POOL_SEED\" packages apps docs --glob '"'!docs/reviews/pr357-codereview-codex-5-5.md'"'" in /tmp/wt-superswarm-357
 exited 1 in 0ms:
exec
/bin/bash -lc "rg -n \"ERR_SLIPPAGE_REQUIRED|ERR_MAX_GOLD_IN_EXCEEDED|ERR_MARKET_BUY_MAX_GOLD_EXCEEDED\" packages apps docs --glob '"'!docs/reviews/pr357-codereview-codex-5-5.md'"'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
docs/planning/clanworld_v4_2_state_schema_interface_spec.md:919:    ERR_MARKET_BUY_MAX_GOLD_EXCEEDED,
packages/contracts/src/ClanWorld.sol:1898:                StatusCode.ERR_MAX_GOLD_IN_EXCEEDED,
packages/contracts/src/ClanWorld.sol:2060:                StatusCode.ERR_MAX_GOLD_IN_EXCEEDED,
packages/contracts/src/ClanWorld.sol:2185:                return StatusCode.ERR_SLIPPAGE_REQUIRED;
packages/contracts/src/IClanWorld.sol:181:    ERR_MARKET_BUY_MAX_GOLD_EXCEEDED, // Deprecated/reserved legacy ordinal (replaced by ERR_MAX_GOLD_IN_EXCEEDED); kept only to preserve enum ordinal stability.
packages/contracts/src/IClanWorld.sol:189:    ERR_MAX_GOLD_IN_EXCEEDED,
packages/contracts/src/IClanWorld.sol:190:    ERR_SLIPPAGE_REQUIRED
packages/contracts/test/StatusCodeEnumStability.t.sol:31:        assertEq(uint8(StatusCode.ERR_MARKET_BUY_MAX_GOLD_EXCEEDED), 22, "ERR_MARKET_BUY_MAX_GOLD_EXCEEDED");
packages/contracts/test/StatusCodeEnumStability.t.sol:39:        assertEq(uint8(StatusCode.ERR_MAX_GOLD_IN_EXCEEDED), 30, "ERR_MAX_GOLD_IN_EXCEEDED");
packages/contracts/test/StatusCodeEnumStability.t.sol:40:        assertEq(uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), 31, "ERR_SLIPPAGE_REQUIRED");
packages/contracts/test/ClanWorld.t.sol:1081:        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), "zero maxGoldIn is ambiguous");
packages/contracts/test/ClanWorld.t.sol:1135:            StatusCode.ERR_MAX_GOLD_IN_EXCEEDED,
packages/contracts/test/ClanWorld.t.sol:1144:            uint8(r[0].status), uint8(StatusCode.ERR_MAX_GOLD_IN_EXCEEDED), "failed immediate buy should propagate"
packages/contracts/test/ClanWorld.t.sol:1335:    // Test 13: buy_maxGoldIn — buy fails with ERR_MAX_GOLD_IN_EXCEEDED
packages/contracts/test/ClanWorld.t.sol:1366:            StatusCode.ERR_MAX_GOLD_IN_EXCEEDED,

exec
/bin/bash -lc "rg -n \"_executeMarketBuyExternal|_executeMarketSellExternal|submitClanOrders\\(|function .*external|function .*public\" packages/contracts/src/ClanWorld.sol | sed -n '1,140p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
916:    function heartbeat() external override nonReentrant {
1018:    function settleClan(uint32 clanId) external override nonReentrant {
1026:    function settleClansman(uint32 csId) external override nonReentrant {
1033:    function finalizeSeason() external override {
1042:    function mintClan(address to) external override nonReentrant returns (uint32 clanId, uint256 iftTokenId) {
1119:    function submitClanOrders(uint32 clanId, ClanOrder[] calldata orders)
1464:                try this._executeMarketSellExternal(
1481:                try this._executeMarketBuyExternal(
1525:    function _executeMarketSellExternal(
1537:    function _executeMarketBuyExternal(
2222:    function initTreasury(address[6] calldata tokens, address[4] calldata pools) external override nonReentrant {
2240:    function seedPools(PoolSeedConfig calldata cfg) external override nonReentrant {
2275:    function transferGold(uint32, uint32, uint256) external pure override {
2279:    function transferVaultResource(uint32, uint32, ResourceType, uint256) external pure override {
2283:    function transferBlueprint(uint32, uint32, uint256) external pure override {
2299:    function getWorldState() external view override returns (WorldState memory) {
2303:    function getTreasuryState() external view override returns (TreasuryState memory) {
2307:    function getResourceToken(uint8 resourceType) external view override returns (address) {
2315:    function getPool(uint8 resourceType) external view override returns (address) {
2319:    function getPrice(uint8 resourceType, uint256 amountIn) external view override returns (uint256 amountOut) {
2331:    function getClan(uint32 clanId) external view override returns (Clan memory) {
2335:    function getClansman(uint32 clansmanId) external view override returns (Clansman memory) {
2339:    function getActiveMission(uint32 clansmanId) external view override returns (Mission memory) {
2356:    function getActionDuration(ActionType action) public pure override returns (uint64) {
2378:    function getTravelTicks(uint8 fromRegion, uint8 toRegion) external pure override returns (uint64) {
2382:    function getBanditTroop(uint32) external pure override returns (BanditTroop memory) {
2418:    function getActiveDefenders(uint32 targetClanId) external view override returns (uint32[] memory clansmanIds) {
2446:    function getDefendingClans(uint8 region) external view override returns (uint32[] memory) {
2456:    function getDerivedClanState(uint32 clanId) external view override returns (DerivedClanState memory) {
2464:    function getDerivedClansmanState(uint32 clansmanId) external view override returns (DerivedClansmanState memory) {
2481:    function getBanditTargetPreview(uint32) external pure override returns (uint32) {
2503:    function quoteLootValueRaw(uint32 clanId) external view override returns (uint256) {
2507:    function quoteLootValueSettled(uint32 clanId) external view override returns (uint256) {
2525:    function getWorldSnapshot() external view override returns (WorldSnapshot memory) {
2561:    function getClanFullView(uint32 clanId) external view override returns (ClanFullView memory) {
2605:    function getMarketState() external view override returns (MarketState memory) {
2628:    function getActiveBanditView() external pure override returns (ActiveBanditView memory) {
2651:    function getRegionPopulation(uint8 region) external view override returns (RegionOccupant[] memory) {

exec
/bin/bash -lc "nl -ba docs/planning/clanworld_v4_spec.md | sed -n '595,610p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
   595	- no partial swap occurs
   596	- clansman retains their inventory or balances
   597	- clansman becomes or remains `WAITING` in Unicorn Town
   598	
   599	## 5.11 Initial pool seeding
   600	At deploy time, a treasury or deployer-controlled bootstrap address mints and seeds the initial resource and gold liquidity.
   601	
   602	### Working initial seed ratios
   603	- Wood / Gold: `1000 wood : 500 gold`
   604	- Wheat / Gold: `1000 wheat : 700 gold`
   605	- Fish / Gold: `500 fish : 600 gold`
   606	- Iron / Gold: `250 iron : 800 gold`
   607	
   608	These numbers are economic placeholders and may be tuned later, but v1 requires concrete initial pool anchors.
   609	
   610	## 5.12 Gold faucets

exec
/bin/bash -lc "rg --files packages/contracts | rg 'abi|out|broadcast|cache|json"'$'"'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
packages/contracts/package.json
packages/contracts/abi/IClanWorld.json
packages/contracts/deployments/base-sepolia.json
packages/contracts/deployments/worldchain-sepolia.json
packages/contracts/test/ActionTypeEnumStability.t.sol
packages/contracts/test/StatusCodeEnumStability.t.sol

exec
/bin/bash -lc 'rg -n "INITIAL_RESOURCE_POOL_SEED|INITIAL_GOLD_POOL_SEED|INITIAL_WOOD_POOL_SEED|INITIAL_GOLD_SEED_FOR_WOOD" packages/contracts/abi packages/contracts/src packages/contracts/script packages/contracts/test' in /tmp/wt-superswarm-357
 succeeded in 0ms:
packages/contracts/src/ClanWorld.sol:82:    uint256 public constant INITIAL_WOOD_POOL_SEED = 1_000e18;
packages/contracts/src/ClanWorld.sol:86:    uint256 public constant INITIAL_GOLD_SEED_FOR_WOOD = 500e18;
packages/contracts/script/Deploy.s.sol:53:        uint256 woodSeed = game.INITIAL_WOOD_POOL_SEED();
packages/contracts/script/Deploy.s.sol:57:        uint256 goldForWood = game.INITIAL_GOLD_SEED_FOR_WOOD();
packages/contracts/test/ClanWorld.t.sol:96:        return _setupMarketWithWoodSeed(world.INITIAL_WOOD_POOL_SEED());
packages/contracts/test/ClanWorld.t.sol:128:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
packages/contracts/test/ClanWorld.t.sol:932:        return _setupHarnessClanAtWithWoodSeed(state, region, cooldownEndsAtTs, world.INITIAL_WOOD_POOL_SEED());
packages/contracts/test/Reentrancy.t.sol:172:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
packages/contracts/test/Reentrancy.t.sol:176:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
packages/contracts/test/SeedPools.t.sol:63:            woodToken, woodPool, world.INITIAL_WOOD_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WOOD(), "wood"
packages/contracts/test/SeedPools.t.sol:102:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
packages/contracts/test/SeedPools.t.sol:106:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
packages/contracts/test/SeedPools.t.sol:127:            woodSeed: world.INITIAL_WOOD_POOL_SEED(),
packages/contracts/test/SeedPools.t.sol:131:            goldSeedForWood: world.INITIAL_GOLD_SEED_FOR_WOOD(),
packages/contracts/test/HeartbeatOrdering.t.sol:155:        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
packages/contracts/test/HeartbeatOrdering.t.sol:159:        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '2600,2628p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
  2600	            incomingDefenderIds: _defendingClansByRegion[clan.baseRegion],
  2601	            thisClanDefendingBaseId: thisClanDefendingBaseId
  2602	        });
  2603	    }
  2604	
  2605	    function getMarketState() external view override returns (MarketState memory) {
  2606	        return MarketState({
  2607	            wood: _poolReserves(_treasury.woodToken, _treasury.woodGoldPool),
  2608	            wheat: _poolReserves(_treasury.wheatToken, _treasury.wheatGoldPool),
  2609	            fish: _poolReserves(_treasury.fishToken, _treasury.fishGoldPool),
  2610	            iron: _poolReserves(_treasury.ironToken, _treasury.ironGoldPool),
  2611	            currentTick: _world.currentTick,
  2612	            currentTickQueue: _scheduledMarketActions[_world.currentTick],
  2613	            nextTickQueue: _scheduledMarketActions[_world.currentTick + 1]
  2614	        });
  2615	    }
  2616	
  2617	    function _poolReserves(address resourceToken, address poolAddr) internal view returns (PoolReserves memory pr) {
  2618	        pr.resourceToken = resourceToken;
  2619	        if (poolAddr == address(0) || resourceToken == address(0)) {
  2620	            return pr;
  2621	        }
  2622	        (uint256 rA, uint256 rB) = StubPool(poolAddr).getReserves();
  2623	        pr.resourceReserve = rA;
  2624	        pr.goldReserve = rB;
  2625	        pr.spotPriceGoldPerResource = rA > 0 ? (rB * 1e18) / rA : 0;
  2626	    }
  2627	
  2628	    function getActiveBanditView() external pure override returns (ActiveBanditView memory) {

exec
/bin/bash -lc "nl -ba packages/contracts/test/ClanWorld.t.sol | sed -n '1010,1040p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
  1010	    }
  1011	
  1012	    function test_immediateMarket_busyWorker_fallsBackToScheduled() public {
  1013	        (ClanWorldTestHarness harness, address woodAddr, uint32 clanId, uint32 csId) =
  1014	            _setupHarnessClanAt(ClansmanState.ACTING, ClanWorldConstants.REGION_UNICORN_TOWN, 0);
  1015	        harness.setCarry(csId, 2e18, 0, 0, 0);
  1016	
  1017	        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
  1018	        Mission memory m = world.getActiveMission(csId);
  1019	
  1020	        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "busy market worker should schedule");
  1021	        assertEq(uint8(r[0].marketMode), uint8(MarketExecutionMode.Scheduled), "busy worker should be scheduled");
  1022	        assertTrue(m.active, "scheduled fallback should install a mission");
  1023	        assertEq(world.getScheduledMarketActionsForTick(m.settlesAtTick).length, 1, "scheduled action queues at submit");
  1024	    }
  1025	
  1026	    function test_scheduledMarket_queueVisibleAtSubmit() public {
  1027	        (ClanWorldTestHarness harness, address woodAddr, uint32 clanId, uint32 csId) =
  1028	            _setupHarnessClanAt(ClansmanState.WAITING, ClanWorldConstants.REGION_FOREST, 0);
  1029	        harness.setCarry(csId, 2e18, 0, 0, 0);
  1030	
  1031	        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
  1032	        Mission memory m = world.getActiveMission(csId);
  1033	
  1034	        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "scheduled sell should be accepted");
  1035	        assertEq(world.getScheduledMarketActionsForTick(m.settlesAtTick).length, 1, "queue visible immediately");
  1036	        assertEq(world.getMarketState().nextTickQueue.length, 0, "future queue stays off next tick when not next tick");
  1037	    }
  1038	
  1039	    function test_immediateMarketBuy_executesWhenMaxGoldSatisfied() public {
  1040	        (, address woodAddr, uint32 clanId, uint32 csId) =

exec
/bin/bash -lc "nl -ba packages/contracts/test/HeartbeatOrdering.t.sol | sed -n '190,365p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
   190	    // -------------------------------------------------------------------------
   191	    // test_heartbeat_settlementBeforeMarket
   192	    //
   193	    // Proves Step 1 (settle) fires before Step 2 (market execute) within the SAME
   194	    // heartbeat closing tick T:
   195	    //   - cs0 is placed at Unicorn Town (region 3). Deposit to homebase Forest
   196	    //     (region 1) = 2 ticks travel. arrivalTick = T0+2, settlesAtTick = T0+3.
   197	    //   - cs1 at Forest submits MarketSell to UT (region 3) = 2 ticks travel.
   198	    //     settlesAtTick = T0+2, matching the market action's arrival tick.
   199	    //   - vault starts at 0; cs0 has carry wood.
   200	    //   - Heartbeat at T0+2: Step 1 deposits cs0 carry wood to vault, Step 2 sells
   201	    //     it. Gold increases only if Step 1 ran first (vault was 0 before Step 1).
   202	    //   - If ordering were reversed, sell would fail (vault still 0) and gold stays flat.
   203	    // -------------------------------------------------------------------------
   204	    function test_heartbeat_settlementBeforeMarket() public {
   205	        _setupMarket();
   206	        uint32 clanId = _mintClan();
   207	        uint32 csId0 = _firstCs(clanId);
   208	        uint32 csId1 = _secondCs(clanId);
   209	
   210	        uint64 t0 = world.getWorldState().currentTick;
   211	
   212	        // Place cs0 at Unicorn Town (region 3). Homebase = Forest (region 1).
   213	        // Deposit from Unicorn Town to Forest: travel = 2 ticks.
   214	        world.setClansmanRegion(csId0, ClanWorldConstants.REGION_UNICORN_TOWN);
   215	
   216	        // cs0: submit Deposit. arrivalTick = t0+2, settlesAtTick = t0+3.
   217	        OrderResult[] memory r0 =
   218	            _submitOrder(clanId, csId0, ClanWorldConstants.REGION_FOREST, ActionType.DepositResources);
   219	        assertEq(uint8(r0[0].status), uint8(StatusCode.OK), "deposit order must succeed");
   220	        Mission memory depositMission = world.getActiveMission(csId0);
   221	        assertEq(depositMission.settlesAtTick, t0 + 3, "deposit settlesAtTick must be t0+3");
   222	
   223	        // Give cs0 carry wood (for deposit) and cs1 carry wood (for sell).
   224	        // Sell now draws from carry, not vault — zero vault to confirm vault is not involved.
   225	        world.setCarryWood(csId0, 10e18);
   226	        world.setCarryWood(csId1, 5e18);
   227	        world.setVaultWood(clanId, 0);
   228	        assertEq(world.getClan(clanId).vaultWood, 0, "vault wood must be 0 before test tick");
   229	
   230	        // cs1: at Forest. Submit MarketSell to UT. Forest→UT = 2 ticks.
   231	        // Market actions execute at the heartbeat closing their arrival tick.
   232	        OrderResult[] memory r1 = _submitMarketOrder(clanId, csId1, ActionType.MarketSell, address(woodToken), 5e18, 0);
   233	        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "market sell order must enqueue");
   234	        Mission memory sellMission = world.getActiveMission(csId1);
   235	        assertEq(sellMission.arrivalTick, t0 + 2, "sell arrivalTick must be t0+2");
   236	        assertEq(sellMission.settlesAtTick, t0 + 2, "sell settlesAtTick must be t0+2");
   237	
   238	        uint256 goldBefore = world.getClan(clanId).goldBalance;
   239	
   240	        // Advance past both the market sale at t0+2 and the deposit completion at t0+3.
   241	        _advanceToTick(t0 + 4);
   242	
   243	        uint256 goldAfter = world.getClan(clanId).goldBalance;
   244	        assertGt(goldAfter, goldBefore, "gold must increase: settlement ran before market sell");
   245	        assertEq(world.getClansman(csId0).carryWood, 0, "cs0 carry wood cleared by deposit");
   246	        assertFalse(world.getActiveMission(csId0).active, "deposit mission must be complete");
   247	    }
   248	
   249	    // -------------------------------------------------------------------------
   250	    // test_heartbeat_atomicTickSeedPublish
   251	    //
   252	    // Proves Step 5: after heartbeat, currentTick increments by 1, currentTickSeed
   253	    // changes, and the new seed is deterministic from block.prevrandao + prior seed.
   254	    // -------------------------------------------------------------------------
   255	    function test_heartbeat_atomicTickSeedPublish() public {
   256	        WorldState memory before_ = world.getWorldState();
   257	        uint64 tickBefore = before_.currentTick;
   258	        bytes32 seedBefore = before_.currentTickSeed;
   259	
   260	        bytes32 expectedSeed = keccak256(abi.encode(block.prevrandao, seedBefore, tickBefore));
   261	        world.heartbeat();
   262	
   263	        WorldState memory after_ = world.getWorldState();
   264	        assertEq(after_.currentTick, tickBefore + 1, "tick must increment by 1");
   265	        assertNotEq(after_.currentTickSeed, seedBefore, "seed must change after heartbeat");
   266	        assertEq(after_.currentTickSeed, expectedSeed, "seed must match keccak(prevrandao, oldSeed, closedTick)");
   267	
   268	        // Second heartbeat chains from the new seed
   269	        uint64 tick2 = after_.currentTick;
   270	        bytes32 seed2 = after_.currentTickSeed;
   271	        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
   272	        bytes32 expectedSeed2 = keccak256(abi.encode(block.prevrandao, seed2, tick2));
   273	        world.heartbeat();
   274	
   275	        assertEq(world.getWorldState().currentTick, tick2 + 1, "tick must increment again");
   276	        assertEq(world.getWorldState().currentTickSeed, expectedSeed2, "seed must chain from prior seed");
   277	    }
   278	
   279	    // -------------------------------------------------------------------------
   280	    // test_heartbeat_seasonTransition
   281	    //
   282	    // Proves Step 4 (world events) fires AFTER Steps 1-3:
   283	    //   - season boundary is crossed at SEASON_DURATION_TICKS
   284	    //   - currentSeasonNumber increments on the heartbeat that closes tick
   285	    //     SEASON_DURATION_TICKS-1 (newTick = SEASON_DURATION_TICKS >= seasonEndTick)
   286	    //   - no crash or revert when there are no pending missions or market actions
   287	    // -------------------------------------------------------------------------
   288	    function test_heartbeat_seasonTransition() public {
   289	        WorldState memory ws0 = world.getWorldState();
   290	        assertEq(ws0.currentSeasonNumber, 1, "season starts at 1");
   291	        assertEq(ws0.seasonEndTick, ClanWorldConstants.SEASON_DURATION_TICKS, "seasonEndTick starts at 360");
   292	
   293	        // Advance SEASON_DURATION_TICKS heartbeats to cross the boundary
   294	        for (uint256 i = 0; i < ClanWorldConstants.SEASON_DURATION_TICKS; i++) {
   295	            vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
   296	            world.heartbeat();
   297	        }
   298	
   299	        WorldState memory ws1 = world.getWorldState();
   300	        assertEq(ws1.currentSeasonNumber, 2, "season must have incremented to 2 after Steps 1-4");
   301	        assertEq(ws1.currentTick, ClanWorldConstants.SEASON_DURATION_TICKS, "tick must be at season boundary");
   302	        assertEq(ws1.seasonStartTick, ClanWorldConstants.SEASON_DURATION_TICKS, "new seasonStartTick");
   303	        assertEq(ws1.seasonEndTick, ClanWorldConstants.SEASON_DURATION_TICKS * 2, "new seasonEndTick");
   304	    }
   305	
   306	    // -------------------------------------------------------------------------
   307	    // test_heartbeat_noopTick
   308	    //
   309	    // Heartbeat with no pending missions and no queued market actions must:
   310	    //   - not revert
   311	    //   - increment currentTick exactly by 1
   312	    //   - change currentTickSeed
   313	    // -------------------------------------------------------------------------
   314	    function test_heartbeat_noopTick() public {
   315	        uint64 tickBefore = world.getWorldState().currentTick;
   316	        bytes32 seedBefore = world.getWorldState().currentTickSeed;
   317	
   318	        world.heartbeat();
   319	
   320	        assertEq(world.getWorldState().currentTick, tickBefore + 1, "tick must increment");
   321	        assertNotEq(world.getWorldState().currentTickSeed, seedBefore, "seed must change");
   322	    }
   323	
   324	    // -------------------------------------------------------------------------
   325	    // test_heartbeat_multipleStepsInOneTick
   326	    //
   327	    // Proves that adjacent heartbeat work can process a scheduled market action
   328	    // at its arrival tick and a normal mission at its later settlement tick.
   329	    //   - cs0 placed at Unicorn Town, deposits to Forest homebase: settlesAtTick = T0+3
   330	    //   - cs1 sells wood to UT from Forest: settlesAtTick = T0+2
   331	    // -------------------------------------------------------------------------
   332	    function test_heartbeat_multipleStepsInOneTick() public {
   333	        _setupMarket();
   334	        uint32 clanId = _mintClan();
   335	        uint32 csId0 = _firstCs(clanId);
   336	        uint32 csId1 = _secondCs(clanId);
   337	
   338	        uint64 t0 = world.getWorldState().currentTick;
   339	
   340	        // cs0: placed at Unicorn Town (2 ticks from Forest homebase).
   341	        // Deposit: arrivalTick = t0+2, settlesAtTick = t0+3.
   342	        world.setClansmanRegion(csId0, ClanWorldConstants.REGION_UNICORN_TOWN);
   343	        world.setCarryWood(csId0, 10e18);
   344	        OrderResult[] memory r0 =
   345	            _submitOrder(clanId, csId0, ClanWorldConstants.REGION_FOREST, ActionType.DepositResources);
   346	        assertEq(uint8(r0[0].status), uint8(StatusCode.OK), "deposit must succeed");
   347	        assertEq(world.getActiveMission(csId0).settlesAtTick, t0 + 3, "deposit settlesAtTick must be t0+3");
   348	
   349	        // cs1: at Forest, sells wood to UT. Forest→UT = 2 ticks. settlesAtTick = t0+2.
   350	        // Give cs1 carry wood — sell draws from carry (not vault).
   351	        world.setCarryWood(csId1, 10e18);
   352	        OrderResult[] memory r1 = _submitMarketOrder(clanId, csId1, ActionType.MarketSell, address(woodToken), 5e18, 0);
   353	        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "market sell must enqueue");
   354	        assertEq(world.getActiveMission(csId1).arrivalTick, t0 + 2, "sell arrivalTick must be t0+2");
   355	        assertEq(world.getActiveMission(csId1).settlesAtTick, t0 + 2, "sell settlesAtTick must be t0+2");
   356	
   357	        uint256 goldBefore = world.getClan(clanId).goldBalance;
   358	
   359	        // Advance past the sell at t0+2 and the deposit at t0+3.
   360	        _advanceToTick(t0 + 4);
   361	
   362	        // Both cs0 deposit (settled at T0+3) and cs1 sell (settled at T0+2) must have fired.
   363	        assertEq(world.getClansman(csId0).carryWood, 0, "deposit settled: carry cleared");
   364	        assertGt(world.getClan(clanId).goldBalance, goldBefore, "sell executed: gold increased");
   365	        assertFalse(world.getActiveMission(csId0).active, "deposit mission must be complete");

exec
/bin/bash -lc "rg -n \"function _completeMission|_marketMissionCommitSequence|delete _missions|m\\.active = false\" packages/contracts/src/ClanWorld.sol" in /tmp/wt-superswarm-357
 succeeded in 0ms:
63:    mapping(uint32 => uint64) private _marketMissionCommitSequence; // clansmanId => FIFO sequence captured at submit
322:                m.active = false; // silent invalidation; dead clansman gets no MissionCompleted
895:    function _completeMission(Clansman storage cs, Mission storage m) internal {
898:        m.active = false;
1359:            _marketMissionCommitSequence[cs.clansmanId] = _world.nextCommitSequence++;
1361:            delete _marketMissionCommitSequence[cs.clansmanId];
1369:            commitSequence: _marketMissionCommitSequence[clansmanId],

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '830,870p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
   830	
   831	        clan.vaultWood -= woodCost;
   832	        clan.vaultIron -= ironCost;
   833	        clan.vaultWheat -= wheatCost;
   834	        uint8 old = clan.baseLevel;
   835	        clan.baseLevel = nextLevel;
   836	        emit BaseLevelChanged(clanId, old, nextLevel, tick);
   837	        return true;
   838	    }
   839	
   840	    function _tryUpgradeMonument(Clan storage clan, uint32 clanId, uint64 tick) internal returns (bool) {
   841	        uint8 nextLevel = clan.monumentLevel + 1;
   842	        if (nextLevel > 10) return false;
   843	
   844	        uint256 woodCost;
   845	        uint256 wheatCost;
   846	        uint256 ironCost;
   847	        uint256 blueprintCost;
   848	
   849	        if (nextLevel == 1) {
   850	            woodCost = 30e18;
   851	            wheatCost = 20e18;
   852	        } else if (nextLevel == 2) {
   853	            woodCost = 50e18;
   854	            wheatCost = 30e18;
   855	        } else if (nextLevel == 3) {
   856	            woodCost = 70e18;
   857	            wheatCost = 40e18;
   858	            ironCost = 5e18;
   859	        } else if (nextLevel == 4) {
   860	            woodCost = 90e18;
   861	            wheatCost = 50e18;
   862	            ironCost = 10e18;
   863	        } else if (nextLevel == 5) {
   864	            woodCost = 120e18;
   865	            wheatCost = 60e18;
   866	            ironCost = 15e18;
   867	        } else if (nextLevel == 6) {
   868	            woodCost = 150e18;
   869	            wheatCost = 80e18;
   870	            ironCost = 20e18;

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '1008,1032p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
  1008	                _world.winterEndsAtTick = nextWinterEnd;
  1009	            } else {
  1010	                // no more winters this season; sentinel = seasonEndTick so guard never fires
  1011	                _world.winterStartsAtTick = _world.seasonEndTick;
  1012	                _world.winterEndsAtTick = _world.seasonEndTick;
  1013	            }
  1014	        }
  1015	    }
  1016	
  1017	    /// @notice Public settlement trigger — lazily settle a clan.
  1018	    function settleClan(uint32 clanId) external override nonReentrant {
  1019	        _settleClan(clanId);
  1020	    }
  1021	
  1022	    /// @notice Lazily settle a single clansman's mission to current tick. Idempotent.
  1023	    ///         Internally settles the entire clan (including upkeep) to guarantee
  1024	    ///         correct ordering and prevent double-settlement. Callers may call this
  1025	    ///         or settleClan interchangeably; both are safe and idempotent.
  1026	    function settleClansman(uint32 csId) external override nonReentrant {
  1027	        Clansman storage cs = _clansmen[csId];
  1028	        if (cs.clansmanId == 0) return;
  1029	        _settleClan(cs.clanId);
  1030	    }
  1031	
  1032	    /// @notice Finalize season. Phase 1 stub.

exec
/bin/bash -lc "nl -ba packages/contracts/src/ClanWorld.sol | sed -n '890,905p'" in /tmp/wt-superswarm-357
 succeeded in 0ms:
   890	        emit MonumentLevelChanged(clanId, old, nextLevel, tick);
   891	        return true;
   892	    }
   893	
   894	    /// @dev Complete a mission: set worker to WAITING, set cooldown, mark mission inactive, emit event.
   895	    function _completeMission(Clansman storage cs, Mission storage m) internal {
   896	        cs.state = ClansmanState.WAITING;
   897	        cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
   898	        m.active = false;
   899	        emit MissionCompleted(_clans[cs.clanId].clanId, cs.clansmanId, m.nonce, m.action);
   900	    }
   901	
   902	    // =========================================================================
   903	    // WORLD PROGRESSION
   904	    // =========================================================================
   905	

exec
/bin/bash -lc 'rg --files docs/reviews | sort' in /tmp/wt-superswarm-357
 succeeded in 0ms:
docs/reviews/pr132-review-claude-opus.md
docs/reviews/pr133-review-claude-opus.md
docs/reviews/pr136-review-claude-opus.md
docs/reviews/pr137-review-claude-opus.md
docs/reviews/pr357-codereview-codex-5-5.md
docs/reviews/pr357-codereview-opus-4-7.md

exec
/bin/bash -lc 'git status --short && git rev-parse --short HEAD && git branch --show-current' in /tmp/wt-superswarm-357
 succeeded in 0ms:
?? docs/reviews/pr357-codereview-codex-5-5.md
?? docs/reviews/pr357-codereview-opus-4-7.md
79879ce

exec
/bin/bash -lc 'rg -n "scheduled.*MarketBuy|maxGoldIn.*0|zeroMaxGoldIn|ERR_SLIPPAGE_REQUIRED" packages/contracts/test/ClanWorld.t.sol packages/contracts/test/HeartbeatOrdering.t.sol packages/contracts/test/SeedPools.t.sol' in /tmp/wt-superswarm-357
 succeeded in 0ms:
packages/contracts/test/ClanWorld.t.sol:215:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:240:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:400:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:411:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:460:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:814:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:905:                maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1070:    function test_marketBuy_zeroMaxGoldInRejectsAtSubmit() public {
packages/contracts/test/ClanWorld.t.sol:1081:        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), "zero maxGoldIn is ambiguous");
packages/contracts/test/ClanWorld.t.sol:1311:        // Submit buy order for 1e18 wood, maxGoldIn = generous 500e18
packages/contracts/test/ClanWorld.t.sol:1380:    function test_scheduledMarketBuy_insufficientGoldFailsAndConsumesCooldown() public {
packages/contracts/test/ClanWorld.t.sol:1413:    function test_scheduledMarketBuy_overCapacityRejectsAtSubmit() public {
packages/contracts/test/ClanWorld.t.sol:1437:    function test_scheduledMarketBuy_insufficientLiquidityFailsAndConsumesCooldown() public {
packages/contracts/test/ClanWorld.t.sol:1628:                maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1697:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1703:        // Clan 2: buy 1e18 wood with maxGoldIn = 100e18
packages/contracts/test/ClanWorld.t.sol:1712:            maxGoldIn: 100e18,
packages/contracts/test/ClanWorld.t.sol:1791:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1832:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1855:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1865:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1899:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:1972:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2005:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2128:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2251:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2439:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2511:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2616:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2628:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2640:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2652:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2783:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2821:            maxGoldIn: 0,
packages/contracts/test/ClanWorld.t.sol:2852:            maxGoldIn: 0,
packages/contracts/test/HeartbeatOrdering.t.sol:100:            maxGoldIn: 0,

codex
# Super-Swarm Review — PR #357 (head 79879ce) — Phase 6B spec cleanup

## SUMMARY
CLEAN. I found no merge-blocking bugs in enum ordinals, scheduled market timing, slippage validation, reentrancy, or seed migration. Merge recommendation: proceed to Liam UAT; the only residual note is that scheduled zero-slippage-buy coverage is implicit via shared validation rather than a dedicated delayed-case test.

## HIGH severity findings
CLEAN — no findings.

## MEDIUM severity findings
CLEAN — no findings.

## LOW severity findings
CLEAN — no findings.

## Cross-cutting observations
- Enum stability is correct: `ERR_MAX_GOLD_IN_EXCEEDED` remains ordinal `30`, and `ERR_SLIPPAGE_REQUIRED` is appended at `31` in `packages/contracts/src/IClanWorld.sol:189-190`, pinned by `packages/contracts/test/StatusCodeEnumStability.t.sol:39-40`.

- `executeAtTick` cascade looks coherent. Market missions now set `executesAtTick = arrivalTick` and `settlesAtTick = arrivalTick` in `packages/contracts/src/ClanWorld.sol:1335-1341`; enqueue still keys off `m.settlesAtTick` at `:1365-1378`, so scheduled actions fire at arrival. Heartbeat settles missions first, then executes market queue at `:929-934`; `_resolveAction` completes the market mission at `:480-481`, and the scheduled action validator intentionally checks `action`/`nonce`, not `active`, at `:1447-1451`.

- Cooldown behavior is stable with the new timing. Submission still sets cooldown at `:1295-1296`; market completion also runs the generic `_completeMission` cooldown reset at `:895-898`, and failures run `_handleMarketFailure` at `:1709-1723`. That is existing contract behavior, and the PR shifts it to the arrival heartbeat consistently with the new market execution tick.

- Slippage guard placement is correct for both immediate and scheduled buys. `_validateAction` runs before the immediate/scheduled split, and the guard is before carry-cap validation at `:2183-2189`, so `MarketBuy(maxGoldIn=0)` cannot enqueue or execute through the normal public path. The external execution wrappers are protected by `require(msg.sender == address(this))` at `:1525-1546`, so direct calls cannot bypass proposal validation.

- MarketSell asymmetry is intentional. Sell is exact-input with no `maxGoldOut`/`minGoldOut` field, while buy is exact-output and bounded by `maxGoldIn`; no analogous sell guard is required by the current interface/spec.

- Pool seed migration is complete in source, tests, and deploy script. The old `INITIAL_RESOURCE_POOL_SEED` / `INITIAL_GOLD_POOL_SEED` names do not remain in active code; the deploy path now sums per-resource gold seeds in `packages/contracts/script/Deploy.s.sol:53-85`, and seed tests assert all four asymmetric pool balances in `packages/contracts/test/SeedPools.t.sol:61-74`.

- Test coverage is adequate for merge. There is a direct zero-`maxGoldIn` submit rejection test at `packages/contracts/test/ClanWorld.t.sol:1070-1087`, timing assertions for arrival-tick market settlement in `HeartbeatOrdering.t.sol:230-236` and `:349-355`, and asymmetric seed balance assertions in `SeedPools.t.sol`. A dedicated delayed `MarketBuy(maxGoldIn=0)` test would be nice, but the guard is mode-agnostic and runs before enqueue, so this is not a gate concern.

- Documentation does not need a spec update in this PR: `docs/planning/clanworld_v4_spec.md:599-608` already lists the asymmetric §5.11 ratios. The only stale mentions of the old constants are in review artifacts/audit context, not canonical docs or contract code.
2026-04-30T11:38:49.301228Z ERROR codex_core::session: failed to record rollout items: thread 019dde2c-ae6d-7411-a700-71dd982ee751 not found
tokens used
106,247
# Super-Swarm Review — PR #357 (head 79879ce) — Phase 6B spec cleanup

## SUMMARY
CLEAN. I found no merge-blocking bugs in enum ordinals, scheduled market timing, slippage validation, reentrancy, or seed migration. Merge recommendation: proceed to Liam UAT; the only residual note is that scheduled zero-slippage-buy coverage is implicit via shared validation rather than a dedicated delayed-case test.

## HIGH severity findings
CLEAN — no findings.

## MEDIUM severity findings
CLEAN — no findings.

## LOW severity findings
CLEAN — no findings.

## Cross-cutting observations
- Enum stability is correct: `ERR_MAX_GOLD_IN_EXCEEDED` remains ordinal `30`, and `ERR_SLIPPAGE_REQUIRED` is appended at `31` in `packages/contracts/src/IClanWorld.sol:189-190`, pinned by `packages/contracts/test/StatusCodeEnumStability.t.sol:39-40`.

- `executeAtTick` cascade looks coherent. Market missions now set `executesAtTick = arrivalTick` and `settlesAtTick = arrivalTick` in `packages/contracts/src/ClanWorld.sol:1335-1341`; enqueue still keys off `m.settlesAtTick` at `:1365-1378`, so scheduled actions fire at arrival. Heartbeat settles missions first, then executes market queue at `:929-934`; `_resolveAction` completes the market mission at `:480-481`, and the scheduled action validator intentionally checks `action`/`nonce`, not `active`, at `:1447-1451`.

- Cooldown behavior is stable with the new timing. Submission still sets cooldown at `:1295-1296`; market completion also runs the generic `_completeMission` cooldown reset at `:895-898`, and failures run `_handleMarketFailure` at `:1709-1723`. That is existing contract behavior, and the PR shifts it to the arrival heartbeat consistently with the new market execution tick.

- Slippage guard placement is correct for both immediate and scheduled buys. `_validateAction` runs before the immediate/scheduled split, and the guard is before carry-cap validation at `:2183-2189`, so `MarketBuy(maxGoldIn=0)` cannot enqueue or execute through the normal public path. The external execution wrappers are protected by `require(msg.sender == address(this))` at `:1525-1546`, so direct calls cannot bypass proposal validation.

- MarketSell asymmetry is intentional. Sell is exact-input with no `maxGoldOut`/`minGoldOut` field, while buy is exact-output and bounded by `maxGoldIn`; no analogous sell guard is required by the current interface/spec.

- Pool seed migration is complete in source, tests, and deploy script. The old `INITIAL_RESOURCE_POOL_SEED` / `INITIAL_GOLD_POOL_SEED` names do not remain in active code; the deploy path now sums per-resource gold seeds in `packages/contracts/script/Deploy.s.sol:53-85`, and seed tests assert all four asymmetric pool balances in `packages/contracts/test/SeedPools.t.sol:61-74`.

- Test coverage is adequate for merge. There is a direct zero-`maxGoldIn` submit rejection test at `packages/contracts/test/ClanWorld.t.sol:1070-1087`, timing assertions for arrival-tick market settlement in `HeartbeatOrdering.t.sol:230-236` and `:349-355`, and asymmetric seed balance assertions in `SeedPools.t.sol`. A dedicated delayed `MarketBuy(maxGoldIn=0)` test would be nice, but the guard is mode-agnostic and runs before enqueue, so this is not a gate concern.

- Documentation does not need a spec update in this PR: `docs/planning/clanworld_v4_spec.md:599-608` already lists the asymmetric §5.11 ratios. The only stale mentions of the old constants are in review artifacts/audit context, not canonical docs or contract code.
