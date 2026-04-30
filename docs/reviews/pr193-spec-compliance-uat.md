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
