# Phase Super-Swarm Synthesis — PR #357 (head 79879ce)

**Models run:** Codex 5.5 ✓ | Opus 4.7 ✓ (duo — Gemini 3.1 Pro skipped; local 3-tier had Gemini CLEAN already, save daily quota)
**Phase:** dev-phase-6b-spec-cleanup
**Diff size:** 566 lines / 8 files (Solidity contracts + tests)
**Audit source:** `docs/reviews/pr198-spec-compliance-uat.md` (PR #350, on `docs/spec-audit-phase-6`)
**Local 3-tier (orch dispatch):** Gemini ✓ CLEAN | Codex ✓ CLEAN | Claude (via codex's inner swarm) ✓ CLEAN

## Summary

**Overall: CLEAN — RECOMMEND MERGE.** Both super-swarm reviewers (codex 5.5 + opus 4.7) returned CLEAN with 0 HIGH / 0 MED across all the security and correctness audit areas. The single architecturally-risky change (`settlesAtTick = arrivalTick` for markets) lands cleanly because the codebase already designed for queue/mission decoupling at `ClanWorld.sol:1447-1449`. Enum ordinal stability holds, slippage guard is correctly placed in a no-side-effect view function before carry-cap validation, MarketSell asymmetry is intentional (exact-input vs exact-output), pool seed migration is complete with zero leftover references.

**Recommended action:** merge to `dev-phase-6b-spec-cleanup`. Ready for Liam UAT.

## MUST FIX

None.

## SHOULD FIX

None.

## DEFER (optional follow-ups, not blockers)

- **L1 (Opus 4.7):** add `test_scheduledMarketBuy_zeroMaxGoldInRejectsAtSubmit` for explicit coverage of the traveling-clansman case. Guard runs at `_validateAction` which runs before the immediate-vs-scheduled fork, so behavior is provably the same — but a 1-line test would close a small audit-coverage gap. File as backlog issue.
- **L2 (Opus 4.7):** add post-seed assertion in `SeedPools.t.sol` that `getMarketState()` returns the spec's distinct spot-price ratios (wood=0.5, wheat=0.7, fish=1.2, iron=3.2 gold/resource). Locks in §5.11 conformance against future drift. File as backlog.
- **L3 (Opus 4.7):** pre-existing `swapExactInForOut(amount, 1)` literal-`0` drift on immediate sells (`ClanWorld.sol:~1810`). Spec §5.9 says `minAmountOut = 0`. Already in audit's Path A as cleanup item #3. Out of scope for #357 by design — file or skip.
- **Cosmetic:** review files committed with empty/placeholder content (`pr357-codereview-codex-5-5.md` empty HIGH/MED, `pr357-codereview-opus-4-7.md` will populate when this synthesis lands). Either populate from worktree or `git rm` before merge.

## Cross-model overlap stats

- Cross-model HIGH: 0
- Cross-model MED: 0
- Cross-model LOW: 0 (each LOW only flagged by one reviewer; opus deeper coverage)
- Single-model HIGH: 0
- Single-model MED: 0
- Single-model LOW: 3 (all from Opus 4.7 — defer-OK)

## Per-model verdicts

- **Codex 5.5:** CLEAN — 0 findings. Verified enum stability, executeAtTick cascade, cooldown stability, slippage guard placement, MarketSell asymmetry intentionality, pool seed migration completeness, test coverage adequacy. Notes documentation already aligns with v4 spec §5.11 (no doc update needed).
- **Opus 4.7:** CLEAN — 0 HIGH/MED + 3 LOW (test coverage gaps, defer-OK). Independently verified the architectural concern (`_completeMission` clearing only `m.active` + queue using `m.action`/`m.nonce`) and confirmed it's intentional design pre-dating this PR.

## Key observations

1. **Merge-ready.** Two independent reviewers (different model families) both CLEAN with detailed verification of the most suspicious cross-cutting concern (settlesAtTick reduction). High confidence.

2. **Architecturally risky change lands safely.** Both reviewers independently arrived at the same insight: `_completeMission` sets `m.active = false` but keeps `m.action`/`m.nonce`, and the scheduled queue uses those fields not `m.active`. The 1-tick reduction exercises an existing decoupling invariant rather than introducing a new one. The codebase comment at `ClanWorld.sol:1447-1449` documents this explicitly.

3. **3 LOW items deferable.** All are test-coverage-add or pre-existing-drift items; none alter contract behavior. File as backlog for post-hackathon if desired.

**Verdict: ship it. Ready for Liam UAT.**
