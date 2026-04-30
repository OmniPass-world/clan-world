# Phase Super-Swarm Synthesis — PR #356 (head 732120b)

**Models run:** Codex 5.5 ✓ | Opus 4.7 ✓ | Gemini 3.1 Pro ✓ (3-model trio — doc-only PR, scaled-down from full 6-model)
**Phase:** dev-phase-5b-spec-alignment
**Diff size:** 363 lines (single-file: `docs/planning/clanworld_v4_6_phase5_economy_alignment.md`)
**Audit source:** `docs/reviews/pr193-spec-compliance-uat.md` (PR #342, on `docs/spec-audit-phase-5`)

## Summary

**Overall: NEEDS_FIXES — small-batch doc revisions only.** 0 cross-model HIGH, 1 single-model HIGH (Codex 5.5 lifecycle inaccuracy), 5 cross-model MED (1 confirmed by 2 models, 4 single-model from Opus 4.7), 5 LOW (3 cross-model line-ref fixes, 5 single-model nuances).

**Recommended action:** dispatch a single-iteration fix-round to PM-dobot (no impl changes; ~10 line-ref edits + 1 paragraph on aggregate throughput for downstream P6). PM swarm-clean again → orch-direct re-review (no need for full trio re-run on small doc edits) → ready for Liam UAT.

## MUST FIX

| File:line | Models | Severity | Finding | Fix |
|---|---|---|---|---|
| `clanworld_v4_6_phase5_economy_alignment.md:60` | Codex 5.5 | **HIGH** | Doc says gather submission validation includes "carry not already full" — actually `_validateAction` only validates target region; carry-full is checked at resolution. Misrepresents contract behavior. | Change "validation: worker reachable + carry not already full + target region correct" → "validation: target-region correct (carry-full is checked at resolution, not submit)". Verify against `ClanWorld.sol:1622-1649` (validateAction) + `487-490, 519-523, 559-563, 590-594, 621-625` (gather resolution carry-full checks). |

## SHOULD FIX

| File:line | Models | Severity | Finding |
|---|---|---|---|
| `pr356:260-262, 296` | Codex 5.5 | MED | Doc routes deferred winter work to "Phase 5.6 / Phase 7". The implementation plan + contract comments label winter as **Phase 10**. Reword to "Phase 10 winter/elimination". (Counter-evidence: `clanworld_numbered_implementation_plan.md:413-433`, `ClanWorld.sol:952` "timer only; mechanics = Phase 10".) |
| `pr356:0` (top) | Opus 4.7 | MED (M1) | Path A rationale omits aggregate-throughput callout for downstream P6 market price calibration. Per-batch ratification + 60s cooldown gates re-submission → ~¼–⅛ of spec-implied per-min throughput. P6 market designer needs this explicit. Add one sentence to §0 or §12: *"Aggregate per-clansman/min throughput is ~¼–⅛ of spec-implied because the 60s cooldown gates re-submission. Phase 6 market price calibration should target the as-built throughput, not the spec's per-tick rates."* |
| `pr356:349-350` | Codex 5.5, Opus 4.7 (M2) | MED | Doc cross-links to `docs/reviews/pr193-spec-compliance-uat.md` and `docs/planning/clanworld_v4_6_bandit_phase9_redesign.md` — neither is on this PR's branch. Audit lives on `docs/spec-audit-phase-5` (PR #342); bandit doc lives on `docs/spec-v4-6-bandit-redesign` (PR #341). Either annotate "(in flight, PR #N)" or sequence #341 + #342 to merge before #356. |
| `pr356:307` | Codex 5.5 | MED | Doc says `WOOD_CRIT_BONUS` has "no separate constant" — actually the constant exists at `IClanWorld.sol:52-54` but is unused by the impl (gather does `yield *= 2` instead). Distinguish "constant exists but is not the impl mechanism" from "no separate constant". |
| `pr356 §3.1` | Opus 4.7 (M3) | MED | Wood crit shape rationale is thin. Doc ratifies `*= 2` (10% chance, EV +10%) but spec's "+1e18 additive at 20%" — if interpreted per-tick over a 4-tick continuous batch — yields up to 12e18 (audit Scenario 5). Acknowledge spec ambiguity (per-tick vs per-mission roll cadence) explicitly rather than punting to §10. |
| `pr356 §11` | Opus 4.7 (M4) | MED | §11 constants table omits `WHEAT_PLOT_REGROW_TICKS` (=4) and `WHEAT_PLOT_STARTING_WHEAT` (=100e18) — both economy-relevant + referenced in §6. Add to table for completeness. (`IClanWorld.sol:75-76`.) |
| `pr356 §5.2` | Opus 4.7 (M5) | MED | "Same-tick starvation" decision-box rationale needs cross-phase consumer audit. Bandit defense path consumes `_isStarving(clan)` — same-tick onset means a clan failing upkeep at T defends bandit attack at T with 0. Doc only flags gather-halving consequence; should also flag bandit-defense consequence. |

## DEFER (file as follow-up issues — none triggered)

No defer items — all findings are actionable in this PR.

## SKIP (false positive / out of scope)

None.

## LOW (line-ref + clarity nits — bundle into the same fix-round)

| File:line | Models | Finding |
|---|---|---|
| `pr356:266` | **Codex 5.5, Gemini 3.1 Pro, Opus 4.7** (3/3) | `WheatPlotState.WinterLocked` cited at `IClanWorld.sol:125` — actually line **126**. Line 125 is `Regrowing`. |
| `pr356:322` | **Codex 5.5, Gemini 3.1 Pro, Opus 4.7** (3/3) | `WINTER_UPKEEP_MULTIPLIER_BPS` cited at `IClanWorld.sol` without line — should be **line 72**. |
| `pr356 §11` | Opus 4.7 (L2) | `IRON_YIELD_PER_TICK` cited at `IClanWorld.sol:57` — actually line **58**. Line 57 is `IRON_BASE_YIELD`. |
| `pr356 §3.1` | Opus 4.7 (L3) | Wood base yield source `IClanWorld.sol:50, 54` — line 54 is the vestigial `WOOD_CRIT_BONUS`, not relevant to base yield. Should be `50, 51` (51 is the `WOOD_BASE_YIELD = WOOD_YIELD_PER_TICK` alias). |
| `pr356:174` | Codex 5.5 (L) | "generic `WOOD_CAP = CLANSMAN_CARRY_CAP` constant" → "generic `CLANSMAN_CARRY_CAP` constant". |
| `pr356 §2.4` | Opus 4.7 (L5) | Cooldown duty-cycle "4 ticks ON + cooldown-period OFF" not translated. `CLANSMAN_COOLDOWN_SECONDS = 60` (`IClanWorld.sol:40`). At S1 20s ticks = 3 cooldown ticks; S2 60s ticks = 1 cooldown tick. Add: *"effective duty cycle = 4 ticks gathering + ⌈60s ÷ tick_seconds⌉ ticks waiting (= 7 ticks at 20s cadence, 5 ticks at 60s cadence)"*. |
| `pr356 §10 row 4` | Opus 4.7 (L6) | "Wood crit shape additive +1e18 — total 3e18/tick" implies a settled per-tick interpretation; spec is ambiguous on per-tick vs per-mission roll cadence. Soften with "(spec text is ambiguous on per-tick vs per-mission roll cadence)". |
| `pr356 §9` | Opus 4.7 (L7) | Vestigial `WOOD_CRIT_BONUS` should be flagged "declared, unused" alongside `WINTER_WOOD_BURN_PER_BASE` and `WINTER_UPKEEP_MULTIPLIER_BPS`. Consistent treatment. |
| `pr356 §13` | Opus 4.7 (L8) | Reference list could note the bandit redesign as the structural template explicitly (currently only cites it as "Path A precedent"). |

## Cross-model overlap stats

- **Findings flagged by 3 models:** 2 (both LOW — `WinterLocked` line + `WINTER_UPKEEP_MULTIPLIER_BPS` line). Highest confidence; cosmetic.
- **Findings flagged by 2 models:** 1 (MED — cross-link forward dep, both Codex 5.5 + Opus 4.7).
- **Single-model findings:** 13 (1 HIGH from Codex 5.5; 4 MED from Opus 4.7; 1 MED from Codex 5.5; 6 LOW from Opus 4.7; 1 LOW from Codex 5.5).

**Single-model HIGH (Codex 5.5 lifecycle inaccuracy)** — historically reliable on Solidity protocol claims; verifiable by reading `_validateAction` directly. Treat as MUST FIX.

**Opus 4.7's larger MED batch** reflects deeper cross-phase consumer audit (M5 bandit defense + M1 P6 market calibration) — these are not nit-picks; they're load-bearing for downstream phase reviewers.

## Per-model verdicts

- **Codex 5.5:** NEEDS_FIXES — 1 HIGH + 3 MED + 3 LOW. Strong protocol-grounding (verified gather lifecycle + spec-vs-impl).
- **Opus 4.7:** NEEDS_FIXES — 0 HIGH + 5 MED + 8 LOW. Strong cross-phase consumer audit + downstream-impact concerns.
- **Gemini 3.1 Pro:** CLEAN — 0 HIGH + 0 MED + 2 LOW. Strong on doc structure + Path A coherence; missed the lifecycle inaccuracy and the 4 cross-phase MEDs (Gemini Pro tier-3 weakness pattern).

## Key observations

1. **Doc is structurally excellent.** All 3 models converged on Path A coherence + faithful audit fidelity + clean structural mirror with the v4.6 bandit redesign template. The 1 HIGH and 5 MED are all in the doc's *factual claims* — not its design.

2. **Cross-phase impact handling is the consistent gap.** Opus 4.7 surfaced 2 cross-phase consumer audits (P6 market calibration, P9 bandit defense via `_isStarving`) that the doc didn't make explicit. Codex 5.5 separately caught the wrong winter-deferral target (Phase 10 not Phase 5.6/7). Combined signal: the doc is internally rigorous but underplays its downstream consumers.

3. **Recommended fix-round shape:** ~10 surgical line-ref + claim corrections (5 LOW typos + 1 HIGH wording fix + 5 MED clarity additions) + 2 paragraph additions (P6 market throughput callout + bandit defense same-tick consequence). Single PM iteration; no orch-direct super-swarm re-run needed. Orch-direct sanity check on the fix-round commit suffices before Liam UAT.
