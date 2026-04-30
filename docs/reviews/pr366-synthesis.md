# Phase Super-Swarm Synthesis — PR #366 (head c3edc37)

**Models run:** Codex 5.5 ✓ | Opus 4.7 ✓ (duo — Gemini 3.1 Pro skipped to save quota; local 3-tier had Gemini)
**Phase:** dev-phase-9b-followups
**Diff size:** 172 lines / 4 files
**Local 3-tier (PM dispatch):** complete, 1 finding (75/100) addressed, no findings ≥80, forge 92/92 green (133/133 expanded per Opus verification)

## Summary

**Overall: NEEDS_FIXES — small fix-round in flight.** Codex 5.5 flagged 1 MED on `getClanFullView` parser permissiveness (accepts `"-1"`, `"4294967296"`); Opus 4.7 acknowledged the same finding as LOW-informational ("not blocking, but tighten to regex would match PR #295 pattern exactly"). The other Solidity changes (storage refactor, tick semantics standardization, NatSpec) are CLEAN per both reviewers.

**R1 fix-round dispatched to PM-dobot 15:48 ET** to address the MED + 2 LOW. PR #366 awaits R2 GREEN signal.

## MUST FIX (1 — flagged by Codex MED)

| File:line | Models | Severity | Finding |
|---|---|---|---|
| `IChainClient.ts:165-170` | Codex MED / Opus L3 | MED → fix | Parser still accepts `"-1"`, `"4294967296"` (uint32 overflow). Use `/^\d+$/` regex + range validation. Add tests for `"12abc"`, `"-1"`, `"4294967296"`, boundary cases. |

## LOW (defer-OK)

| File:line | Models | Finding |
|---|---|---|
| `ClanWorld.sol:2300` | Both | Heartbeat NatSpec step 3 wording is broader than what `_eagerSettleForBandits` actually does (only bandit spawn-candidate regions, not all world events). Tighten doc. |
| `IClanWorld.sol:455` | Codex LOW | `attackAttemptsMade`/`maxAttemptsRemaining`/`projectedTargetLootValue` placeholder NatSpec lives only in `ClanWorld.sol` body. Add brief comments on `ActiveBanditView` struct fields. |
| `IChainClient.ts` | Opus L2 | Style inconsistency: `submitOrders` uses `parseInt(...)`, new `getClanFullView` uses `Number.parseInt(...)`. Functionally identical; cosmetic. |

## DEFER (none)

## Cross-model overlap

- **0 HIGH** (both CLEAN on highs)
- **0 cross-model MED** (Codex flagged 1 MED, Opus saw same as L3)
- **2 cross-model LOW** (heartbeat NatSpec wording; both noted)
- **1 single-model LOW** (Opus style inconsistency)

## Per-model verdicts

- **Codex 5.5:** NEEDS_FIXES — 1 MED + 2 LOW. Strong protocol-grounding (verified `Number.parseInt` + string compare ≠ regex precheck claim).
- **Opus 4.7:** CLEAN — recommends merge. 0 HIGH/MED + 3 LOW. End-to-end verified storage refactor safety, tick-semantics standardization, full forge 133/133 green.

## Key observations

1. **Storage refactor (#330) verified safe by Opus end-to-end.** All 4 storage call sites read-only; memory callers correctly inlined.
2. **Tick semantics (#328b) uniformly closedTick (replay-deterministic) per Opus.** All death-linked emit sites verified consistent. Indexer implication: consumers that pinned to old `_world.currentTick` need review.
3. **R1 fix-round in flight** — addresses MED + 2 LOW. PM-dobot dispatched 15:48 ET.

**Verdict after R1: ship it once PM signals R2 GREEN.**
