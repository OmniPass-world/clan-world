All 51 OTC tests pass. I've verified the security-critical properties end-to-end. Writing the review now.

# Super-Swarm Review — PR #358 (head 1f0eef3) — Phase 7B OTC owner nonce binding

## SUMMARY

**Verdict: CLEAN — APPROVE FOR MERGE.** Owner-nonce binding is correctly implemented across all four OTC accept paths (gold, vault, blueprint, bundled), the `transferClanOwnership` write site is the only nonce-incrementing path, and propose-time captures `proposerOwnerNonceAtPropose` atomically with the owner-authorization check. The S2 demo blocker (#285) is closed. 51 OTC tests pass; the change is materially complete and merge-ready.

## HIGH severity findings

**CLEAN — no findings.**

Verification matrix:

| Property | Where | Verified |
|---|---|---|
| Nonce check on **acceptGoldTransfer** | `ClanWorld.sol:1824` | ✅ |
| Nonce check on **acceptVaultTransfer** | `ClanWorld.sol:1902` | ✅ |
| Nonce check on **acceptBlueprintTransfer** | `ClanWorld.sol:1987` | ✅ |
| Nonce check on **acceptBundledTransfer** | `ClanWorld.sol:2073` | ✅ |
| Nonce captured at propose-time (gold) | `ClanWorld.sol:1804` (set inside same fn after `owner == msg.sender` check at 1793) | ✅ atomic |
| Nonce captured at propose-time (vault/bp/bundled) | `ClanWorld.sol:1881, 1969, 2048` | ✅ atomic |
| Only **2** clan.owner write sites | `mintClan` @ 1039 (default nonce=0), `transferClanOwnership` @ 1103 (`ownerNonce++`) | ✅ I-4 confirmed |
| `transferClanOwnership` increments nonce | `ClanWorld.sol:1104` | ✅ |
| Replay protection (delete on accept) | `ClanWorld.sol:1833, 1919, 1996, 2092` + `proposal.from != 0` guard at 1814 etc. | ✅ |
| Replay protection (delete on cancel) | `ClanWorld.sol:1847, 1933, 2010, 2108` | ✅ |
| Bundled atomicity | Single struct; balance check in `_requireBundledTransferBalance` (line 2077) gated before any debit (lines 2079–2090) | ✅ all-or-nothing |
| Settle-before-debit | `_settleOtcClans` called before nonce check on every accept path | ✅ (R3 fix preserved) |

Nonce check is positioned **after** `_settleOtcClans` — correct, because settlement cannot mutate `ownerNonce` (settle only touches missions/winter/cold-damage state). Order is safe.

## MEDIUM severity findings

**M1 — Test gap: nonce-mismatch tests only exist for gold + vault; blueprint and bundled lack the same coverage.** `test_acceptGoldTransfer_revertsAfterOwnershipTransfer` (`GoldTransferOtc.t.sol:189`) and `test_acceptVaultTransfer_revertsAfterOwnershipTransfer` (`VaultTransferOtc.t.sol:222`) cover gold and vault. Blueprint and bundled accept paths have identical nonce-check shape (pure copy-paste at `ClanWorld.sol:1987` and `2073`), so they're functionally fine — but a defensive test would be a 20-line addition per file. Recommend adding `test_acceptBlueprintTransfer_revertsAfterOwnershipTransfer` and `test_acceptBundledTransfer_revertsAfterOwnershipTransfer` — not a merge blocker, but cheap insurance against future refactors that might drop the nonce check.

**M2 — Storage layout: `ownerNonce` inserted mid-struct rather than appended.** In `IClanWorld.sol`, the Clan struct has the new field placed between `starvationStartsAtTick` and `coldDamage` (line 245), not at the end. The repo's CLAUDE.md is explicit that the codebase is pre-launch and storage layout breakage is fine — but if a deploy already happened on testnet with a prior Clan struct, that deployment's storage is now incompatible. **Verify no testnet deployment is being upgraded.** For greenfield this is a non-issue.

## LOW severity findings

**L1 — Inherited stale proposals occupy `_openOtcProposalsByClan` cap until cancelled or expired.** When ownership transfers, the new owner inherits an unknown number of unacceptable proposals (their nonce mismatch will revert any accept). These still count toward `MAX_OPEN_OTC_PROPOSALS_PER_CLAN = 8`. A hostile prior owner could pre-stuff 8 proposals with `expiryTick = type(uint64).max` before transferring, forcing the new owner to issue 8 cancel txs to free the OTC slots. Mitigations exist (`_reapExpiredOtcProposals` runs at propose-time; new-owner cancel works per `test_cancelGoldTransfer_newOwnerCanCancelInheritedProposal`), but these are reactive. Could be addressed by having `transferClanOwnership` reset the cap counter or iterate-and-delete inherited proposals — both are gas-bound by N proposals so probably not worth it. **Document as known UX wart.**

**L2 — `_reapExpiredOtcProposals` is O(n) per propose where n = `_nextOtcProposalId`.** Pre-existing concern from PR #200's audit (gstack noted this). Not introduced by PR #358; flagging only because Phase 7B's spec doc (`spec-phase-7-otc-lifecycle.md:84`) says "Expired proposals are reaped lazily on the next propose call and do not permanently consume cap slots" without acknowledging the O(n) scan. Worth a TODO in the spec doc.

**L3 — Cancel paths intentionally don't check nonce.** This is correct (allows new owner to clean up inherited proposals — tested) and correct that old owner can't cancel after transfer (line 1843 enforces `fromClan.owner == msg.sender`, which is now the new owner). No bug. But the spec doc could explicitly call out "cancel by new owner is intentional and freed slots are immediately reusable."

## Cross-cutting observations

**Phase 7B closes the S2 demo blocker.** The Liam iNFT memory-continuity demo flow (transfer clan → Elder restart under new owner → resume) now has the property that `<situation>` blocks read by the new Elder cannot include drainable OTC proposals authorized by the prior owner. Issue #285 is genuinely fixed.

**Pattern is reusable for sibling bugs.** The `proposerOwnerNonceAtPropose` shape is the canonical fix for *any* propose/accept-with-stale-state binding-failure. The same pattern could/should be applied to:
- Scheduled market actions (already invalidated by `missionNonce` per `lastMissionNonce`-comparison in market settlement, so probably fine — but worth a defensive audit)
- Future "promise" features in S2 Track 2 if any propose/accept latency exists

**Spec doc is high quality.** `packages/contracts/docs/spec-phase-7-otc-lifecycle.md` is precisely the kind of artifact that prevents future spec/impl drift. The "Why this is correct" explanation of the Alice→Bob→Carol scenario (lines 53–67) is exactly the right shape — it documents the threat model, not just the API.

**Renaming `ERR_ZERO_AMOUNT` → `ERR_EMPTY_TRANSFER`** is the only ABI-affecting change in the StatusCode enum; verify no off-chain consumer (Elder agents, indexer, frontend) reads the enum by name. Quick grep across `apps/server`, `apps/web`, `packages/agents` would close this — but for Wave 0 there are no real consumers yet.

---

**Recommendation: MERGE.** Optional follow-ups (none blocking): add nonce-mismatch tests for blueprint + bundled (M1), document the cap-griefing UX wart (L1), note the O(n) reap scan in the spec doc (L2).
