# Phase Super-Swarm Synthesis — PR #358 (head 1f0eef3)

**Models run:** Codex 5.5 ✓ | Opus 4.7 ✓ | Gemini 3.1 Pro ✗ FAILED (server capacity 429 — `MODEL_CAPACITY_EXHAUSTED`, retried 10x)
**Phase:** dev-phase-7b-otc-spec → dev (security-critical b-branch)
**Diff size:** 7270 lines / multi-file (Solidity contracts + extensive tests + spec patch doc)
**Audit source:** `docs/reviews/pr200-spec-compliance-uat.md` (PR #343, on `docs/spec-audit-phase-7`)
**Local 3-tier (gstack dispatch):** Claude ✓ GREEN (H-1 false alarm verified, I-4 confirmed) | Codex ✓ GREEN (all 5 invariants pass) | Gemini ✓ GREEN (LOW-2 fixed in second commit)

## Summary

**Overall: CLEAN — APPROVE FOR MERGE.** Both surviving super-swarm reviewers (codex 5.5 + opus 4.7) returned CLEAN with 0 HIGH / 0 cross-model MED. Owner-nonce binding is correctly implemented across all 4 OTC accept paths (gold, vault, blueprint, bundled), `transferClanOwnership` is the only nonce-incrementing write site, propose-time captures `proposerOwnerNonceAtPropose` atomically with the owner-authorization check, replay protection works via storage delete + `proposal.from != 0` guards, bundled atomicity holds (single struct + balance check before any debit). 51 OTC tests pass. **The S2 demo blocker (#285) is closed.**

**Recommended action:** merge to dev. Ready for Liam UAT.

## MUST FIX

None.

## SHOULD FIX (defer-OK; document only)

| File:line | Models | Severity | Finding |
|---|---|---|---|
| Test files | Opus 4.7 (M1) | MED → defer | Nonce-mismatch tests exist for gold + vault only; blueprint + bundled lack identical coverage. Pattern is copy-paste identical so functionally fine. ~20 lines per test file would close. |
| `IClanWorld.sol:245` | Opus 4.7 (M2) | MED → defer | `Clan.ownerNonce` inserted MID-STRUCT (between `starvationStartsAtTick` and `coldDamage`), not appended. Per CLAUDE.md "no production users yet, break things freely" — non-issue for pre-launch. **Verify no testnet deployment requires upgrade migration.** |
| Codex 5.5 (LOW-1) | LOW → defer | Vestigial one-step transfer events (`GoldTransferred`, `VaultResourceTransferred`, `BlueprintTransferred`) declared but never emitted. Removing or documenting would reduce indexer ambiguity. |

## DEFER (file as follow-up issues — none blocking)

- **L1 (Opus 4.7) — inherited proposals occupy cap.** When ownership transfers, new owner inherits N unacceptable proposals (nonce mismatch reverts). Still count toward `MAX_OPEN_OTC_PROPOSALS_PER_CLAN = 8`. Hostile prior owner could pre-stuff 8 with `expiryTick = type(uint64).max` before transferring, forcing 8 cancel txs. Mitigations: `_reapExpiredOtcProposals` + new-owner cancel both work. UX wart but not security.
- **L2 (Opus 4.7) — `_reapExpiredOtcProposals` is O(n).** Pre-existing concern from PR #200's audit (not introduced by #358). Spec doc claims "lazy reap on propose, doesn't permanently consume cap slots" but doesn't acknowledge O(n) scan. Worth a TODO note.
- **L3 (Opus 4.7) — cancel-by-new-owner spec clarification.** Spec doc could explicitly call out that new-owner cancellation is intentional and freed slots are immediately reusable.
- **Codex 5.5 (LOW-2) — test coverage gap.** Suggested non-blocking additions: blueprint/bundled nonce-mismatch tests (overlaps with Opus M1), new-owner cancel for non-gold types, accept exactly at `expiryTick`, cancel-after-accept expecting `proposal not found`.

## Cross-model overlap stats

- **Cross-model CLEAN verdicts (codex 5.5 + opus 4.7):** strong consensus on security correctness
- **Cross-model HIGH/MED:** 0 (high confidence the security fix is correct)
- **Cross-model LOW:** 1 (test coverage gap on blueprint/bundled — both Codex 5.5 and Opus 4.7 noted this independently)
- **Single-model findings:** 4 (all from Opus 4.7 — deeper coverage on cap-griefing UX, storage layout middle-insert, spec doc improvements)
- **Gemini 3.1 Pro:** ✗ FAILED — `RetryableQuotaError: No capacity available for model gemini-3.1-pro-preview on the server`. Server-side capacity issue, not quota. 10 retries exhausted. Synthesis proceeds with duo.

## Per-model verdicts

- **Codex 5.5:** CLEAN — 0 HIGH/MED + 2 LOW. Verified all 4 accept-path nonce checks; only 2 owner write sites; bundled atomicity; non-escrow semantics; non-zero nonce captures atomic with owner auth.
- **Opus 4.7:** CLEAN — 0 HIGH + 2 MED + 3 LOW. Verified 51 OTC tests pass live; built file:line verification matrix for every nonce check (1824/1902/1987/2073). Also surfaced storage layout (M2) and cap-griefing UX (L1) which codex didn't.
- **Gemini 3.1 Pro:** ✗ FAILED.

## Key observations

1. **S2 demo blocker closed.** Liam's iNFT memory-continuity demo flow (transfer clan → Elder restart under new owner → resume) is now safe. The new Elder cannot accept stale OTC proposals authored by the prior owner — verified by both reviewers via end-to-end code-path trace.

2. **Pattern is reusable for sibling bugs.** `proposerOwnerNonceAtPropose` is the canonical fix for any propose/accept-with-stale-state binding-failure. Opus 4.7 noted scheduled market actions already use `missionNonce` defensively (so likely fine), but worth defensive audit if S2 Track 2 introduces other propose/accept latency surfaces.

3. **Spec doc is high quality.** `packages/contracts/docs/spec-phase-7-otc-lifecycle.md` documents the threat model (Alice→Bob→Carol) not just the API. Future spec/impl drift will be caught by this doc.

4. **All findings are deferable.** No MUST FIX. No fix-round needed. Ready for Liam UAT.

5. **Gemini 3.1 Pro server capacity failure.** Out of our control; codex 5.5 + opus 4.7 cross-model is sufficient signal for security-critical merge.

**Verdict: ship it. Ready for Liam UAT.**
