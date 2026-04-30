I've verified file:line refs against `9b67414` and cross-checked the doc against the source audit. Writing the review now.

# Phase Super-Swarm Review — PR #356 (head 732120b) — Phase 5B v4.6 economy alignment addendum

## SUMMARY

**NEEDS_FIXES (LOW/MEDIUM only — recommend merge after a small line-ref + downstream-impact pass).** The doc is high-quality, well-grounded in the PR #193 audit, and the canonical claims spot-check accurately against the contract source at `9b67414` (≥10 file:line refs sampled — wood/iron/fish/wheat helpers, deposit lifecycle, upkeep ordering, starvation accessor, starting-vault constants — all verified). Path A rationale is sound and structurally mirrors the existing v4.6 bandit-redesign template (PR #340). Top concerns: (1) two off-by-one line refs (`WheatPlotState.WinterLocked` at :125→actually :126; `IRON_YIELD_PER_TICK` at :57→actually :58), (2) Path A canonization should explicitly call out the order-of-magnitude aggregate-throughput implication for P6 market calibration, and (3) the cross-reference to the bandit redesign doc is a forward link to PR #340 which is not yet on `dev` — fine if they land together, broken if this merges first.

## HIGH severity findings

CLEAN — no findings. Audit fidelity is solid; canonical claims match HEAD on every spot-check.

## MEDIUM severity findings

### M1. Path A rationale omits aggregate-throughput drop and downstream P6 calibration impact
§0 Path A bullets correctly argue that per-batch values can be "rebalanced post-hackathon under restoration without touching architecture." But canonizing per-batch-equals-spec-per-tick combined with the 60s wall-clock cooldown locks in **aggregate throughput an order of magnitude below what the v4 spec implied** (the audit's UAT scenario 2 calculates ~1/10× wood/minute vs spec). The doc does not flag this for downstream Phase 6 market price calibration, which directly consumes resource velocity. Suggest one sentence in §0 or §12: *"Note: aggregate per-clansman/min throughput is ~¼–⅛ of spec-implied because the 60s cooldown gates re-submission. Phase 6 market price calibration should target the as-built throughput, not the spec's per-tick rates."*

### M2. Cross-reference to bandit redesign doc is a forward dep
§1 ("Bandit interactions with vault state — see `clanworld_v4_6_bandit_phase9_redesign.md`") and §13 references doc that lives on branch `docs/spec-v4-6-bandit-redesign` (PR #340) but is **not in `dev` and not in this PR's parent branch** (`dev-phase-5b-spec-alignment`). I verified `git ls-tree -r origin/dev -- docs/planning/` and the bandit doc is absent. If this PR merges before #340, both relative links 404. Either: (a) add a "(in flight, PR #340)" annotation, or (b) sequence the merges so #340 lands first.

### M3. Wood crit shape rationale is thin
§3.1 ratifies "×2 multiplicative" because "as-built is simpler, internally consistent, and already tested." But ×2 at 10% chance has materially different EV (4e18 → 4.4e18 expected, +10%) than spec's "+1e18 additive at 20%" — the latter, if interpreted per-tick over a 4-tick continuous batch, yields up to 12e18 (per audit Scenario 5). The doc should engage briefly with the spec ambiguity ("+1e18 per tick vs +1e18 per session") rather than punting it to §10 row 4 — otherwise the Phase 6 market designer reading this can't reason about wood-supply variance.

### M4. §11 constants table omits `WHEAT_PLOT_REGROW_TICKS` (4) and `WHEAT_PLOT_STARTING_WHEAT` (100e18)
Both are economy-relevant constants referenced in §6 of this same doc. They live at `IClanWorld.sol:75-76` and have no spec disagreement, but a doc that claims to "supersede the economy-related constants in `clanworld_v4_2_state_schema_interface_spec.md` §5" should enumerate them for completeness so that future implementers don't go hunting.

### M5. "Same-tick starvation" decision-box rationale needs the cross-phase consumer audit
§5.2 ratifies same-tick onset because "defenders contributing 0 takes effect immediately." But the bandit defense path consumes `_isStarving(clan)` (verified in `_resolveBanditAttack` per the bandit redesign). Same-tick onset means a clan that fails upkeep at tick T and is bandit-attacked at tick T (post-upkeep, pre-mission resolution) defends with 0. Spec next-tick onset would let them defend at full strength on tick T. Whichever is right, the doc should explicitly flag this as a behavioral consequence (currently only the gather-halving consequence is mentioned).

## LOW severity findings

### L1. Off-by-one: `WheatPlotState.WinterLocked` line ref
§9 row 1 says "`WheatPlotState.WinterLocked` in `IClanWorld.sol:125`" — `WinterLocked` is on line **126** (line 125 is `Regrowing`). Trivial fix.

### L2. Off-by-one: `IRON_YIELD_PER_TICK` constants-table line ref
§11 row "`IRON_YIELD_PER_TICK` … `IClanWorld.sol:57`" — `IRON_YIELD_PER_TICK` is on line **58** (line 57 is `IRON_BASE_YIELD`). The §3.2 source cite ("57-58") is correct, so this is just the §11 single-line cite to update.

### L3. Confusing line cite in §3.1 wood base yield
§3.1 wood base yield source: "`IClanWorld.sol:50, 54`". Line 50 is `WOOD_YIELD_PER_TICK = 1e18` ✓ but line 54 is `WOOD_CRIT_BONUS` (a vestigial constant unused by the impl), not relevant to the base yield. Should be `50, 51` (line 51 is the alias `WOOD_BASE_YIELD = WOOD_YIELD_PER_TICK`).

### L4. Missing line number for `WINTER_UPKEEP_MULTIPLIER_BPS`
§9 row 2 and §11 row both cite "`IClanWorld.sol`" without a line. It's at line **72**. Inconsistent with neighboring rows that do cite lines.

### L5. Cooldown duty-cycle is wall-clock, not ticks
§2.4 says "4 ticks ON + cooldown-period OFF per batch" without translating. `CLANSMAN_COOLDOWN_SECONDS = 60` (verified at `IClanWorld.sol:40`). For S1's 20s ticks that's 3 ticks of cooldown; for S2's 60s ticks it's 1 tick. UAT runners need this concrete to time their scenarios. Suggest: *"effective duty cycle = 4 ticks gathering + ⌈60s ÷ tick_seconds⌉ ticks waiting (= 7 ticks at 20s cadence, 5 ticks at 60s cadence)."*

### L6. §10 row 4 implies a settled spec interpretation that is actually ambiguous
"Wood crit shape additive +1e18 — total 3e18/tick" treats +1e18 as per-tick additive. But v4 §4.7 doesn't unambiguously specify whether crit rolls per-tick or per-mission; the audit acknowledges this. Soften with "(spec text is ambiguous on per-tick vs per-mission roll cadence)".

### L7. Vestigial `WOOD_CRIT_BONUS` constant should be flagged
The doc canonizes `*= 2` multiplicative crit, which makes `WOOD_CRIT_BONUS = WOOD_YIELD_PER_TICK` (line 54) a dead constant — never read by the gather helper. The doc flags `WINTER_WOOD_BURN_PER_BASE` and `WINTER_UPKEEP_MULTIPLIER_BPS` as "declared, unused" in §9; consistent treatment for `WOOD_CRIT_BONUS` would tighten the doc and reduce confusion.

### L8. §13 reference list is missing the v4.6 bandit redesign cross-link explicitly as the structural template
§13 lists it as "Path A precedent" but doesn't note that this doc's section structure was copied from it. Minor — but useful for future Path-A-style addenda.

## Cross-cutting observations

**Path A coherence is strong.** The doc draws a clean line between (a) what's canonized for the hackathon, (b) what's deferred to milestone #25, and (c) what's still in upstream phase scope (winter mechanics → 5.6/7). The §10 deferred table with restoration-cost annotations is genuinely useful for post-hackathon planning — it tells future-Liam not just "what's wrong" but "what's cheap to fix" (most are "Tiny constant changes" once item #1 is done).

**Audit fidelity is high but not exhaustive.** The 14-item drift count matches the audit's bottom-line ❌ count after collapsing winter sub-mechanics into single rows. The doc deliberately drops the audit's "cold damage path" entry (Phase 7 winter scope, properly out of Phase 5 economy scope per §1). Doc claim-by-claim spot-checks all matched: starvation tick-onset code, wheat-plot regrow logic, deposit atomic-transfer block, starting vault constants, all 5 gather helpers, RNG domain keys.

**Decision boxing is honest about its motivation.** Three of the four ratified decisions (same-tick starvation, ×2 wood crit, per-batch yields) are rationalized primarily as "lift to revert is too high." That's tactically correct for hackathon-timeline canonization but the doc could be one tick more candid: this is *tactical* canonization to ship S1, not an *endorsement* that batched-action is the better game-design model. Future restoration evaluation under #25 should not be biased by reading this doc as "we like it this way."

**Downstream phase impact is mostly handled.** P9 vault interface is stable (no Clan-struct field changes; vault fields still uint256). P10 winter is consistently deferred (matches bandit doc's posture of treating winter as out-of-scope). P6 market is the one place the doc could be louder — the per-batch values are spec-equivalent on paper but the cooldown gating produces an order-of-magnitude lower aggregate throughput, and that's a price-calibration input the market designer needs.

**Structural mirror with bandit doc is faithful.** Both share the Status / Read-order / Purpose / Audience header block, §0 Why-this-doc, §1 Scope, §2 As-built lifecycle, Constants section, Deferred-to-milestone section, UAT-runners-what-to-expect section, References. This doc is more granular (14 sections vs 9) which is appropriate given Phase 5's broader surface (5 gather helpers + deposit + upkeep + plots + winter constants vs bandit's narrower combat surface).
