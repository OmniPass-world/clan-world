# PR #200 Spec-Compliance UAT — `dev-phase-7-otc`

**Reviewer:** Claude Opus 4.7 (1M ctx) — static spec-compliance pass
**HEAD:** `04a3e3a1afad1df65a0f36e5bbb20546652c0eb6` (post R3 fix-round)
**Date:** 2026-04-30
**Method:** read spec docs → walk impl → no test execution
**Note on source-of-truth branch:** the brief said "read impl from `dev-merge`", but `origin/dev-merge` (commit 6cf6f39) is currently pinned at the Phase 4 release and does NOT contain Phase 7 code. Phase 7 lives on `origin/dev-phase-7-otc` (the PR #200 source branch). Audit is against that branch.

> Scope: does the OTC transfer surface in `packages/contracts/src/ClanWorld.sol` (PR #200) match the documented v4 spec ruleset for clan-to-clan OTC? This is **not** a re-run of the cloud reviewers; it is an **independent spec-vs-code audit** focused on whether shipped behavior matches the canonical contract spec, accounting for the explicit Liam directive 2026-04-29 that re-shaped Phase 7.

---

## 1. Spec sources read

| Doc | Phase-7-relevant sections |
|---|---|
| `docs/planning/clanworld_v4_spec.md` | §3.13 (no courier — OTC happens at token/account level); §4.4 (gold = clan purse); §4.5 (vault model); §11.1–11.3 (OTC trust model — "non-atomic in v1, no protocol-level escrow primitive"); §12.4–12.5 (starting balances) |
| `docs/planning/clanworld_v4_1_addendum.md` | (no Phase-7 content) |
| `docs/planning/clanworld_v4_2_state_schema_interface_spec.md` | §4.3 vault/purse domains; §4.4 deposit rule (carry not transferable); §10.3 **OTC transfer surface** — canonical signatures `transferGold` / `transferVaultResource` / `transferBlueprint` / `transferBundle`; §15 invariants ("OTC transfers cannot draw from worker carry balances"); §17 ("explicit OTC transfer functions" locked) |
| `docs/planning/clanworld_v4_3_schema_patch.md` | J.2 (canonical writers include "explicit transfer functions"); **M. Dead Clan OTC Restriction** — sender clan must be `ACTIVE` for `transferGold/transferVaultResource/transferBlueprint/transferBundle`; O (locked summary) |
| `docs/planning/clanworld_v4_4_ui_indexer_getters.md` | (no Phase-7 content — UI getters only) |
| `docs/planning/clanworld_v4_5_alignment_addendum.md` | (no Phase-7 content — submission timeline + heartbeat caller only) |
| `docs/planning/clanworld_v1_implementation_profile.md` | §3.8 OTC model: "direct internal ledger transfers, no escrow in v1, no settlement guarantees beyond explicit transfer calls"; §3.10 dead clan cannot send OTC |
| `docs/planning/clanworld_numbered_implementation_plan.md` | §7.1–7.5 (5-line checklist: gold transfer, vault resource transfer, blueprint transfer, bundled convenience, dead-clan restriction) |

**Authoritative ruleset:** v4 spec + v4_1 (no Phase-7 changes) + v4_2 §10.3/§15 + v4_3 §M (controls on conflict) + v1 implementation profile §3.8.

**Liam directive 2026-04-29** (recorded in issue #223 body): *"Simple atomic swap (proposer + acceptor, NOT order book per Liam directive 2026-04-29)."* This re-shapes the §10.3 one-step `transferGold(from, to, amount)` into a two-step `proposeGoldTransfer` → `acceptGoldTransfer` lifecycle. Treating this directive as a Phase-7 spec amendment that supersedes §10.3's signature shape — but does NOT supersede §10.3's domain rules (vault/purse only, no carry), §M's dead-clan rule, or §11.1–11.3's "no escrow" principle.

Key spec assertions extracted (one-line each):
- **§10.3 surface** four entrypoints: `transferGold`, `transferVaultResource`, `transferBlueprint`, `transferBundle` — re-shaped per directive into propose/accept pairs
- **§10.3 domain** OTC may draw from clan vault, clan gold purse, clan blueprint balance — **never** from worker carry
- **§15 invariant** "OTC transfers cannot draw from worker carry balances"
- **§M sender restriction** sender clan state must be `ACTIVE` (i.e. != `DEAD`) for all OTC entrypoints
- **§3.8 v1 profile** "no escrow in v1; no settlement guarantees beyond explicit transfer calls" — i.e., the contract is a value-mover, not a custody primitive
- **§11.1–11.3** OTC trust is social; promise-keeping is not contract-enforced
- **§3.13** OTC asset transfer happens "directly at token/account level, not by worker courier simulation" — so atomic on-chain debit/credit is correct shape

The implementation plan §7.1–7.5 is a 5-line checklist with no design detail. Per super-swarm finding (R2 synthesis on PR #200): "§7.1-7.5 spec doesn't actually exist" — propose/accept lifecycle, expiry semantics, owner-side validation, replay flags, self-transfer/zero-amount handling are all implementer choices grounded only in the Liam directive and the cloud-reviewer iteration loop.

---

## 2. Mechanic-by-mechanic verification

| Mechanic | Spec says | Code does | File:line | Verdict |
|---|---|---|---|---|
| **Surface shape: one-step vs propose/accept** | §10.3: `transferGold(from, to, amount)` etc. — one-step direct transfer | `propose*Transfer` / `accept*Transfer` / `cancel*Transfer` lifecycle (12 entrypoints + getters) | `IClanWorld.sol:796-840`, `ClanWorld.sol:1768-2080` | ⚠️ DRIFT — re-shaped per Liam directive 2026-04-29 (legitimate amendment); §10.3 signatures are NOT preserved. Acceptable IF directive is canonical, otherwise needs spec patch. |
| **Surface shape: §10.3 entrypoint names absent** | `transferGold`, `transferVaultResource`, `transferBlueprint`, `transferBundle` are named in §10.3 | None of those four function names exist in impl; replaced wholesale | (no code) | ⚠️ DRIFT — impl-plan-blessed but breaks any external integration that read v4.2 §10.3 verbatim |
| **OTC domain — gold purse** | Draws from clan gold purse (§10.3) | `fromClan.goldBalance -= amount; toClan.goldBalance += amount` | `ClanWorld.sol:1810-1811, 2049/2055` | ✅ MATCHES |
| **OTC domain — clan vault resources** | Draws from clan vault wood/wheat/fish/iron (§10.3, §15) | Debits/credits `vault{Wood,Wheat,Fish,Iron}` only; never touches `carry*` fields | `ClanWorld.sol:1888-1895, 2050-2059` | ✅ MATCHES |
| **OTC domain — blueprint balance** | Draws from clan blueprint balance (§10.3) | `fromClan.blueprintBalance -= amount; toClan.blueprintBalance += amount` | `ClanWorld.sol:1965-1966, 2054/2060` | ✅ MATCHES |
| **§15 invariant — never from carry** | "OTC transfers cannot draw from worker carry balances" | No code path references `carryWood/Iron/Wheat/Fish/Gold` in any propose/accept | (no code references) | ✅ MATCHES |
| **§M dead-sender restriction at entrypoint** | All OTC entrypoints require sender clan state == ACTIVE | `require(fromClan.clanState != ClanState.DEAD, "ERR_CLAN_DEAD")` on all four `propose*` + all four `accept*` | `ClanWorld.sol:1778, 1805, 1844, 1881, 1933, 1960, 2001, 2044` | ✅ MATCHES (and exceeds — also blocks dead-target on accept, which spec doesn't require but is defensible) |
| **§M dead-sender — cancel still allowed** | (not specified) | `cancelGoldTransfer` etc. only require `owner == msg.sender`; no DEAD check on `fromClan` | `ClanWorld.sol:1818-1828, 1902-1912, 1973-1983, 2069-2079` | ⚠️ DRIFT — undefined by spec; tests `test_deadProposerCanCancelExistingProposals` codify cancel-after-death as intentional. Defensible cleanup behavior; flag as non-issue. |
| **§3.8 v1 profile — no escrow** | "no escrow in v1; no settlement guarantees beyond explicit transfer calls" | Contract holds NO value during proposal lifetime — proposal stores only metadata; debit/credit happen atomically at `accept*` | `ClanWorld.sol:1785-1788, 1810-1811` | ✅ MATCHES — propose/accept is NOT escrow (no asset locked); proposal is an authorization receipt the proposer can revoke (cancel) any time |
| **§3.8 v1 profile — no settlement guarantees** | Sender's balance at propose-time is not held; accept may revert if drained | `acceptGoldTransfer` re-checks `fromClan.goldBalance < amount` after settlement; reverts with ERR_NOT_ENOUGH_GOLD | `ClanWorld.sol:1808` | ✅ MATCHES |
| **Atomic balance check** | Implicit — debit must not underflow | `_hasVaultResources` and `_requireBundledTransferBalance` check ALL components before any debit; no partial debit possible | `ClanWorld.sol:1884-1895, 2047-2060, 2093-2105` | ✅ MATCHES |
| **Settlement before debit** | Implicit (R1 fix-round explicitly added per fix commit 2bec876) | `_settleOtcClans(fromClanId, toClanId)` called at top of every `accept*`, asserts both clans at `currentTick` | `ClanWorld.sol:1801, 1877, 1956, 2040, 2114-2122` | ✅ MATCHES |
| **Stale-by-200-ticks guard** | (not in spec; super-swarm H1) | Settlement-before-debit asserts `lastSettledTick == currentTick`; if `_settleClan` cap (200) prevents catch-up, assert reverts | `ClanWorld.sol:2117-2121` | ✅ MATCHES (R3 fix; test `test_acceptVaultTransfer_revertsWhenClanStaleByOver200Ticks`) |
| **Owner authorization at propose** | (not in spec; necessary for safety) | `require(fromClan.owner == msg.sender, "ClanWorld: not clan owner")` on all four `propose*` | `ClanWorld.sol:1779, 1845, 1934, 2002` | ✅ MATCHES |
| **Owner authorization at accept** | (not in spec) | `require(toClan.owner == msg.sender)` — accept is by **target** clan owner | `ClanWorld.sol:1807, 1883, 1962, 2046` | ✅ MATCHES (mirrors v4.2 §11 trust model — only target can pull) |
| **Owner authorization at cancel** | (not in spec) | `require(fromClan.owner == msg.sender)` on cancel | `ClanWorld.sol:1823, 1907, 1978, 2074` | ✅ MATCHES |
| **Self-transfer rejection** | (not in spec) | `require(fromClanId != toClanId, "ERR_SELF_TRANSFER")` on all propose paths | `ClanWorld.sol:1776, 1842, 1931, 1999` | ✅ MATCHES (impl-plan-bonus) |
| **Zero-amount rejection — gold** | (not in spec) | `require(amount > 0, "ERR_ZERO_AMOUNT")` | `ClanWorld.sol:1777, 1932` | ✅ MATCHES |
| **Zero-amount rejection — vault** | (not in spec) | `require(woodAmt > 0 || wheatAmt > 0 || fishAmt > 0 || ironAmt > 0)` | `ClanWorld.sol:1843` | ✅ MATCHES |
| **Zero-amount rejection — bundled** | (not in spec) | `require(!_isEmptyBundledTransfer(...), "ERR_ZERO_AMOUNT")` checks all 6 components | `ClanWorld.sol:2000, 2082-2091` | ✅ MATCHES |
| **Replay/double-accept prevention** | Implicit — once accepted, proposal must not be accept-able again | Proposal `delete`d after accept; `proposal.from == 0` check on next accept attempt reverts as "proposal not found" | `ClanWorld.sol:1813, 1897, 1968, 2062` | ✅ MATCHES (R3 simplified by removing accepted/cancelled flags in favor of delete-on-accept; test `test_acceptGoldTransfer_revertsWhenBalanceChangedAfterProposal` covers re-accept after cancel) |
| **Open-proposal cap per clan** | (not in spec) | `MAX_OPEN_OTC_PROPOSALS_PER_CLAN = 8` enforced at every propose; `_openOtcProposalsByClan[fromClanId]++` / `_closeOtcProposal` decrement on accept/cancel | `ClanWorld.sol:94, 1783, 1849, 1938, 2006, 2107-2112` | ✅ MATCHES (impl-plan-bonus DOS guard) |
| **Reap-expired-on-propose** | (not in spec; addresses cap-exhaustion) | `_reapExpiredOtcProposals(fromClanId)` runs at top of every propose; iterates 1..`_nextOtcProposalId-1`, deletes expired by-this-clan | `ClanWorld.sol:1782, 1848, 1937, 2005, 2124-2150` | ⚠️ DRIFT — works correctly but is **O(n²) over season lifetime** (every propose scans all historical IDs). Not a spec violation, but a scaling/gas concern. Test `test_goldTransfer_expiredProposalsDoNotConsumeCap` verifies behavior. |
| **expiryTick type — uint64** | (not in spec; consistency with `WorldState.currentTick: uint64`) | `expiryTick: uint64` in struct + signature (R3 fix #292) | `IClanWorld.sol:340/350/357/369/796 etc.`, `ClanWorld.sol:1768 etc.` | ✅ MATCHES (R3 fix; 6/6 super-swarm consensus MED was the prior `uint256` asymmetry) |
| **expiry semantics: `<= expiryTick`** | (not in spec) | `require(_world.currentTick <= proposal.expiryTick)` on accept | `ClanWorld.sol:1796, 1869, 1951, 2030` | ✅ MATCHES (inclusive — accept allowed exactly at expiry tick) |
| **Cancel of expired proposal** | (not in spec) | `cancel*` has no expiry check — proposer can cancel even after expiry, decrementing the cap counter cleanly | `ClanWorld.sol:1818-1828 etc.` | ✅ MATCHES (defensible) |
| **Reentrancy protection** | (not in spec; standard hardening) | `nonReentrant` on every propose/accept/cancel + uses `ReentrancyGuard` mixin | `ClanWorld.sol:1771, 1793, 1818 etc.` | ✅ MATCHES |
| **Event emission — Proposed** | (not in spec) | `GoldTransferProposed` / `VaultTransferProposed` / `BlueprintTransferProposed` / `BundledTransferProposed` with proposalId + party clans + amounts + expiryTick | `IClanWorld.sol:660-722` | ✅ MATCHES |
| **Event emission — Accepted** | (not in spec) | `*Accepted` events include `settledAtTick: _world.currentTick` | `ClanWorld.sol:1815, 1899, 1970, 2064` | ✅ MATCHES |
| **Event emission — Cancelled** | (not in spec) | `*Cancelled` events emit only the proposalId | `ClanWorld.sol:1828, 1912, 1983, 2079` | ✅ MATCHES |
| **Dead-event declarations** | n/a | `event GoldTransferred(...)`, `event VaultResourceTransferred(...)`, `event BlueprintTransferred(...)` are declared in `IClanWorld.sol` lines 736–740 but **never emitted anywhere in `ClanWorld.sol`** | `IClanWorld.sol:736-740` | ❌ TRIVIAL DRIFT — dead event declarations, vestigial from the §10.3 one-step shape that was abandoned. Should be removed (or, if kept for indexer parity, emitted alongside the `*Accepted` events). |
| **`ERR_CLAN_NOT_OWNED` enum unused** | n/a | Enum exists in `IClanWorld.sol:156`; raw require string `"ClanWorld: not clan owner"` used instead at all 13 OTC ownership checks | `IClanWorld.sol:156`, `ClanWorld.sol:1779 etc.` | ⚠️ TRIVIAL DRIFT — pre-existing pattern (line 1103 has the same string), NOT introduced by Phase 7. Cosmetic consistency issue. |
| **`ERR_OTC_CAP` and `ERR_SELF_TRANSFER` enums** | n/a | Enums declared (`IClanWorld.sol:183-184`) AND used as raw require strings consistently | `IClanWorld.sol:183-184`, `ClanWorld.sol:1776, 1783 etc.` | ✅ MATCHES (the enum-as-string convention of this codebase) |
| **Settled-state read on accept** | Should reflect post-settle balances | After `_settleOtcClans`, balance checks read from re-fetched `_clans[fromClanId]` storage; settled vault/purse/blueprint values are authoritative | `ClanWorld.sol:1803-1808, 1879-1886, 1958-1963, 2042-2047` | ✅ MATCHES |
| **No partial transfer** | Implicit | Bundled transfer balance check is all-or-nothing (`_requireBundledTransferBalance`); single revert if any of gold/vault/blueprint is short | `ClanWorld.sol:2047, 2093-2105` | ✅ MATCHES (test `test_acceptBundledTransfer_revertsAndLeavesAllComponentsWhenOneResourceInsufficient`) |
| **No clansman/mission interaction** | OTC is metadata-level (§3.13 — no courier) | Zero interaction with `_missions`, `_clansmen`, `Mission.action` etc. | (no code) | ✅ MATCHES |
| **No interaction with active orders** | Implicit | OTC paths do NOT reference scheduled market actions, defender registries, or any tick-bound queue | (no code) | ✅ MATCHES |

### Summary of mechanic verification

| Verdict | Count |
|---|---|
| ✅ MATCHES | 27 |
| ⚠️ DRIFT (close-but-different / undefined-by-spec) | 5 |
| ❌ TRIVIAL DRIFT | 1 (dead event declarations) |
| ❌ SUBSTANTIAL DRIFT | 0 |

**The implementation is materially spec-compliant for v4.2 §10.3 / §M / v1-profile §3.8 OTC semantics**, modulo the surface-shape re-design authorized by Liam directive 2026-04-29 (propose/accept instead of one-step transfer). All four §10.3 entrypoints are functionally available (gold, vault-resource, blueprint, bundle) with the spec-mandated domain rules (vault + purse + blueprint, never carry) and §M dead-sender restriction.

The drift items are all design-extension territory (open-proposal cap, expiry, cancel mechanism, owner authz at propose+accept) that exceed what §10.3 specified — not contradictions of it.

---

## 3. Test coverage gap analysis

### What IS tested (from `GoldTransferOtc.t.sol` + `VaultTransferOtc.t.sol` + `BlueprintTransferOtc.t.sol` + `BundledTransferOtc.t.sol` + `DeadClanOtc.t.sol`)

Per-OTC-type happy-path:
- `test_proposeGoldTransfer_storesProposalAndEmits` — propose-time storage + event
- `test_acceptGoldTransfer_transfersAtomicallyAndEmits` — atomic balance flip + Accepted event
- `test_proposeAndAcceptVaultTransfer_transfersAllResourcesAtomically`
- `test_proposeAndAcceptBlueprintTransfer_transfersAtomically`
- `test_proposeAndAcceptBundledTransfer_transfersAllComponentsAtomically`

Settlement-before-debit (R1 fix coverage):
- `test_acceptVaultTransfer_settlesPendingUpkeepBeforeDebit`
- `test_acceptVaultTransfer_settlesPendingDepositBeforeDebit`
- `test_acceptVaultTransfer_revertsWhenClanStaleByOver200Ticks` (R3 200-tick guard)

Atomic-revert-on-shortfall:
- `test_acceptGoldTransfer_revertsWhenBalanceChangedAfterProposal` (proposer drains via market between propose and accept)
- `test_acceptVaultTransfer_revertsAndLeavesAllResourcesWhenOneResourceInsufficient`
- `test_acceptBlueprintTransfer_revertsWhenBalanceChangedAfterProposal`
- `test_acceptBundledTransfer_revertsAndLeavesAllComponentsWhenGoldInsufficient`
- `test_acceptBundledTransfer_revertsAndLeavesAllComponentsWhenOneResourceInsufficient`

Expiry:
- `test_acceptGoldTransfer_revertsWhenExpired`
- `test_acceptVaultTransfer_revertsWhenExpired`
- `test_acceptBlueprintTransfer_revertsWhenExpired`
- `test_acceptBundledTransfer_revertsWhenExpired`
- `test_goldTransfer_expiredProposalsDoNotConsumeCap` (reap)

Cancel:
- `test_cancelGoldTransfer_byProposerBlocksAccept` (+ vault, blueprint, bundled equivalents)
- `test_cancelGoldTransfer_acceptorCannotCancel`

Authorization / wrong caller:
- `test_goldTransfer_wrongCallersRevert` (covers non-proposer-cannot-propose, non-target-cannot-accept, non-proposer-cannot-cancel)

Validation:
- `test_proposeGoldTransfer_revertsWhenZeroAmount` (+ blueprint)
- `test_proposeGoldTransfer_revertsWhenSelfTransfer` (+ vault, blueprint, bundled)
- `test_proposeVaultTransfer_revertsWhenAllZero`
- `test_proposeBundledTransfer_revertsWhenEmpty`

Cap:
- `test_goldTransfer_openProposalCapDecrementsAfterAccept`

Dead-clan §M coverage (DeadClanOtc.t.sol covers all 4 OTC types):
- `test_aliveClansCanProposeAndAcceptAllOtcTypes` — sanity baseline
- `test_deadProposerCannotProposeAnyOtcType`
- `test_deadProposerAfterProposeCannotBeAccepted` (clan dies between propose and accept)
- `test_deadTargetCannotAcceptAnyOtcType`
- `test_deadProposerCanCancelExistingProposals` (intentional cleanup affordance)
- `test_unrelatedClanDeathDoesNotBlockOtherClanOtc` (death-isolation)

Cross-pair non-interference:
- `test_goldTransfer_twoClanNoInterference` (+ vault, blueprint, bundled equivalents)

### What is NOT tested (keyed by criticality)

#### MUST-COVER (bug-class blockers)

| Scenario | Why critical |
|---|---|
| **Open-proposal cap exhaustion at exactly 8** | `test_goldTransfer_openProposalCapDecrementsAfterAccept` exercises cap incidentally but no test asserts the 9th propose reverts with `ERR_OTC_CAP`. Fence-post on the cap constant. |
| **Reap-expired correctness across mixed types** | `test_goldTransfer_expiredProposalsDoNotConsumeCap` proves reap works for gold proposals. No test mixes (e.g.) 4 expired gold + 4 expired vault + 1 fresh propose under cap. |
| **Cap doesn't double-count after cancel** | After cancel, `_closeOtcProposal` decrements cap; no test asserts that re-propose to cap-1 then cap-1+1 succeeds + reverts respectively. (Inferable from cap-decrements-after-accept test, but cancel path isn't directly covered.) |
| **Owner-transfer of clan iNFT mid-proposal** | Phase 7 0G iNFT (S2) ships clan-ownership transfer. R1 super-swarm flagged as HIGH; R3 did NOT add owner-nonce binding. Not yet a blocker (S2 only) — but no test exists for "clan ownership changes between propose and accept; old proposal consumes new owner's balance". When S2 ships, this is a HIGH right back. |

#### SHOULD-COVER (production-plausible edge cases)

| Scenario | Why |
|---|---|
| **Accept exactly at expiryTick** | Boundary on `<=` vs `<`. Currently `<=` (inclusive). One off-by-one test would freeze the semantics. |
| **Propose with `expiryTick < currentTick`** | Currently silently allowed (proposal stored, accept fails immediately). Whether that's intentional vs needs propose-time reject is unspecified. |
| **Bundle with only blueprint > 0 (gold/vault all zero)** | `_isEmptyBundledTransfer` check passes. Verify edge that a "blueprint-only" bundle is functionally equivalent to a `proposeBlueprintTransfer`. |
| **Cancel by previous owner after iNFT transfer** | (S2 only) — verify cancel reverts after ownership change. |
| **Multiple expired proposals reaping in batch** | `_reapExpiredOtcProposals` is O(n) across `_nextOtcProposalId`. No test with e.g. 50 historical proposals exercises gas behavior at scale. |
| **Reap loop with mixed-clan proposals** | The reap iterates ALL proposalIds from 1 — does it correctly skip proposals where `from != fromClanId`? Code reads correct (`if (proposal.from == fromClanId && ...)`) but no targeted test. |

#### NICE-TO-HAVE

- Fuzz: random sequences of propose/accept/cancel/expire across N clans with invariant that `sum(_openOtcProposalsByClan[i]) == count(non-empty proposals)`
- Event ordering: `*Proposed` event proposalId monotonically increasing across types (since `_nextOtcProposalId` is shared)
- Parity test: bundled transfer with all-of-(gold+vault+blueprint) produces same final state as 3 separate single-type transfers

**Headline gap count:** 4 MUST-COVER, 6 SHOULD-COVER, 3 NICE-TO-HAVE.

The MUST-COVER list is small and largely defensive (cap fence-posts + future-S2 iNFT-ownership). Test coverage of the core mechanic surface is GOOD — every documented domain rule has at least one test, every error path has at least one test, and §M dead-clan coverage is comprehensive across all 4 OTC types in `DeadClanOtc.t.sol`.

---

## 4. Potential UAT findings (if Liam runs interactive scenarios)

### Scenario 1 — Happy-path bundled transfer
**Setup:** Clan A has 5e18 gold + 10e18 wood + 2e18 blueprint. Clan B has 0 of each. Owner of A proposes a bundled transfer of 5e18 gold + 10e18 wood + 2e18 blueprint to B with expiryTick = currentTick+10.
**Expected per spec:** Owner of B accepts; A's gold/wood/blueprint zero out, B receives all three components atomically; `BundledTransferAccepted` event with `settledAtTick = currentTick`.
**Actual per impl:** Matches expected. (`test_proposeAndAcceptBundledTransfer_transfersAllComponentsAtomically`)
**He should verify:** post-accept, `getClan(A).goldBalance == 0`, `getClan(A).vaultWood == 0`, `getClan(A).blueprintBalance == 0`. Watch for `BundledTransferAccepted` in event stream.

### Scenario 2 — Accept after proposer drains balance
**Setup:** Clan A has 5e18 gold. Proposes a 5e18 gold transfer to Clan B. BEFORE B accepts, A spends all 5e18 gold on a market buy.
**Expected per §3.8 (no escrow / no settlement guarantees):** B's accept reverts because A no longer has the balance. Proposal still on chain (not auto-cleaned) but unspendable until cancelled or expired.
**Actual per impl:** Matches. `acceptGoldTransfer` re-checks `fromClan.goldBalance < amount` after settlement; reverts with `ERR_NOT_ENOUGH_GOLD`. (`test_acceptGoldTransfer_revertsWhenBalanceChangedAfterProposal`)
**He should verify:** revert string is "ERR_NOT_ENOUGH_GOLD"; proposal still exists in `getOtcGoldProposal(id)`; A can subsequently cancel.

### Scenario 3 — Accept by wrong caller (key authorization test)
**Setup:** Proposal exists from A → B for 1e18 gold. Wallet C calls `acceptGoldTransfer(id)`.
**Expected per impl:** Revert "ClanWorld: not clan owner" (toClan owner check).
**Actual:** Matches. (`test_goldTransfer_wrongCallersRevert`)
**He should verify:** also try (a) A trying to accept own proposal → reverts (A is not B's owner); (b) random EOA → reverts.

### Scenario 4 — Dead clan cannot initiate (§M)
**Setup:** Clan A has 0 living clansmen (kill via bandit attack or similar). State should be `DEAD`. Try to propose a 1e18 gold transfer A → B.
**Expected per §M:** Revert with `ERR_CLAN_DEAD`.
**Actual:** Matches. (`test_deadProposerCannotProposeAnyOtcType`)
**He should verify:** test all 4 propose entrypoints (gold/vault/blueprint/bundled) — all four should revert.

### Scenario 5 — Clan dies between propose and accept
**Setup:** A proposes A → B 1e18 gold. Before B accepts, A's clan dies (e.g. all clansmen killed by bandits).
**Expected per §M:** B's accept reverts because A is now DEAD.
**Actual:** Matches. (`test_deadProposerAfterProposeCannotBeAccepted`)
**He should verify:** revert path — `acceptGoldTransfer` calls `_settleOtcClans` first (which may flip A to DEAD via settlement), then checks `fromClan.clanState != ClanState.DEAD`. Watch the error.

### Scenario 6 — Cancel as cleanup affordance for dead clan
**Setup:** A has 5 active proposals. A's clan dies. Owner of A wants to clean up the proposal cap.
**Expected per impl design:** Cancel still works for dead clan owner (test codifies this). Cap counter decrements correctly.
**Actual:** Matches. (`test_deadProposerCanCancelExistingProposals`)
**He should verify:** if Liam disagrees with this design (i.e., he prefers "dead clans frozen entirely, cap leaks"), file a tweak issue. Current design is defensible — cancel is non-economic, just storage cleanup.

### Scenario 7 — Open-proposal cap exhaustion
**Setup:** Clan A has 100e18 gold. Proposes 8 separate 1e18 gold transfers to clan B (or distinct targets) without any being accepted. Try a 9th propose.
**Expected per impl:** 9th propose reverts with `ERR_OTC_CAP` (cap is 8).
**Actual:** Matches. (Inferred — no direct test asserts the 9th-call revert, but cap decrement test exercises the upper bound.)
**He should verify:** at cap, accepting one frees a slot; canceling one frees a slot; expiry+next-propose-cycle frees a slot via reap. All three release paths should work.

### Scenario 8 — Expiry boundary
**Setup:** Propose at currentTick=100 with expiryTick=110. Heartbeat to currentTick=110. Try accept.
**Expected per impl:** Accept succeeds (`<=` is inclusive).
**Actual:** Matches.
**He should verify:** repeat at currentTick=111 — should revert "proposal expired".

### Scenario 9 — OTC does NOT touch worker carry (§15 invariant)
**Setup:** Clan A has a worker mid-mission carrying 10e18 wood. Vault has 5e18 wood. A proposes a vault transfer of 8e18 wood.
**Expected per §15:** Cannot draw 8e18 — only 5e18 in vault, carry doesn't count. Accept reverts with `ERR_NOT_ENOUGH_RESOURCES`.
**Actual:** Matches — `_hasVaultResources` reads `clan.vaultWood >= 8e18`, fails. Carry untouched.
**He should verify:** post-revert, `getClansman(workerId).carryWood == 10e18` unchanged; vault unchanged.

### Scenario 10 — Bundled all-or-nothing semantics
**Setup:** A has 5e18 gold but 0 blueprint. Proposes bundled transfer of 5e18 gold + 1e18 blueprint to B. B accepts.
**Expected per impl:** Revert; A's gold NOT debited (atomic — full bundle or nothing).
**Actual:** Matches. (`test_acceptBundledTransfer_revertsAndLeavesAllComponentsWhenGoldInsufficient` and the one-resource variant)
**He should verify:** post-revert, A's gold balance unchanged at 5e18.

---

## 5. UAT verdict

**SAFE TO RUN INTERACTIVE UAT — implementation is materially spec-compliant.**

The Phase 7 OTC transfer surface in PR #200 is closer to a **well-tested superset** of the v4.2 §10.3 spec than a divergent design. The two structural deltas from §10.3 are:

1. **Surface shape** — propose/accept lifecycle instead of one-step `transferGold(...)` etc. This is a Liam directive 2026-04-29 (recorded in issue #223) and should be treated as a Phase-7 spec amendment.
2. **Dead event declarations** — `GoldTransferred` / `VaultResourceTransferred` / `BlueprintTransferred` events declared in `IClanWorld.sol:736–740` but never emitted. Vestigial from the §10.3 one-step shape that was abandoned. **TRIVIAL** — should be deleted (or kept and emitted alongside `*Accepted` if indexer parity is desired).

Every spec-mandated domain rule is enforced:
- ✅ §10.3 vault/purse/blueprint domain (no carry) — confirmed via no-carry-references audit + tests
- ✅ §15 invariant (OTC cannot draw from carry)
- ✅ §M dead-sender restriction at all 8 (4 propose + 4 accept) entrypoints
- ✅ §3.8 v1-profile "no escrow" — proposal stores metadata only, no value held
- ✅ §3.13 "asset transfer at token/account level, not by worker courier" — atomic ledger move

Test coverage is comprehensive across all 4 OTC types (gold/vault/blueprint/bundled) for happy path, settlement-before-debit, expiry, cancel, validation, dead-clan §M, and cross-pair non-interference. The 4 MUST-COVER gaps are all defensive fence-posts (cap edge cases, future-S2 iNFT ownership) — none block UAT.

**Note on the open architectural HIGH from R2 super-swarm** (clan-ownership transfer mid-proposal allows old owner's authorization to drain new owner's balance): this is a **Phase-7-meets-S2-iNFT** issue. In the current Submission-1 scope, clan ownership doesn't transfer, so the H1 is dormant. When the Submission 2 iNFT transfer demo lands, this HIGH re-activates and needs `proposerAddress` + `proposerOwnerNonce` binding. Recommend filing as a S2 prerequisite issue, not a Phase-7 blocker.

---

## 6. Path A vs Path B recommendation

**Path A — Implementation is canonical, spec is stale (RECOMMENDED).** The Liam directive 2026-04-29 already shifted Phase 7 from §10.3's one-step shape to propose/accept. The impl is internally consistent with that directive, has comprehensive tests, and covers all §10.3 domain/§M dead-clan/§15-invariant rules. Recommend a small follow-up:

1. **Spec amendment doc** — write `clanworld_v4_6_otc_propose_accept.md` documenting the propose/accept lifecycle as canonical Phase-7 surface, superseding §10.3's one-step signatures. This becomes the UAT oracle and unblocks any future spec readers from confusion.
2. **Trivial fix** — remove the 3 dead event declarations (`GoldTransferred`, `VaultResourceTransferred`, `BlueprintTransferred` in `IClanWorld.sol:736–740`). Either delete or emit them alongside the `*Accepted` events for indexer back-compat. Orchestrator can fix this directly (1-line-each delete).

**Path B — Spec is canonical, implementation has drifted.** Would require reverting Phase 7 to the §10.3 one-step shape, which contradicts the explicit Liam directive 2026-04-29 and discards 12 entrypoints of working tested code. **Not recommended.** The propose/accept design is strictly more capable (allows asynchronous coordination, expiry-based off-chain workflows, on-chain authorization receipts) than one-step transfer for the AXL-mediated diplomacy use cases v4 §11 envisions.

**Triage signal: ZERO substantial drift, 1 trivial drift, ship as-is after trivial cleanup + spec amendment.**

---

## Appendix A — Files inspected

- `packages/contracts/src/ClanWorld.sol` @ origin/dev-phase-7-otc (2575 lines; OTC code at 1765–2150)
- `packages/contracts/src/IClanWorld.sol` @ origin/dev-phase-7-otc (942 lines; structs at 336–370, errors at 155–185, function sigs at 793–840, events at 659–740)
- `packages/contracts/test/GoldTransferOtc.t.sol` (235 lines, 12 tests)
- `packages/contracts/test/VaultTransferOtc.t.sol` (300 lines, 10 tests)
- `packages/contracts/test/BlueprintTransferOtc.t.sol` (163 lines, 8 tests)
- `packages/contracts/test/BundledTransferOtc.t.sol` (233 lines, 9 tests)
- `packages/contracts/test/DeadClanOtc.t.sol` (210 lines, 6 tests)
- `docs/planning/clanworld_v4_spec.md` §3.13, §4.4–4.5, §11.1–11.3, §12.4–12.5
- `docs/planning/clanworld_v4_2_state_schema_interface_spec.md` §4.3–4.4, §10.3, §15, §17
- `docs/planning/clanworld_v4_3_schema_patch.md` §J.2, §M, §O
- `docs/planning/clanworld_v1_implementation_profile.md` §3.8, §3.10
- `docs/planning/clanworld_numbered_implementation_plan.md` §7.1–7.5
- PR #200 super-swarm synthesis comments (R1 + R2) on GitHub

## Appendix B — What I deliberately did NOT do

- Run `forge test` (per UAT brief: static analysis only)
- Re-litigate prior-reviewer findings already adjudicated in R1/R2 super-swarm (settle-before-debit, uint64 expiryTick, ownership-nonce HIGH, etc.) — those are PR-internal review history, not spec compliance
- File any GitHub issues
- Edit any code in `packages/contracts/src/`
- Audit Phase-6 / Phase-8 / Phase-9 / Phase-10 cross-phase dependencies (out of scope for OTC compliance pass)

## Appendix C — Severity legend

- ✅ **MATCHES** — code behavior conforms to spec assertion
- ⚠️ **DRIFT** — code differs from spec but is either (a) authorized by Liam directive, (b) undefined by spec and behavior is defensible, or (c) cosmetic/non-load-bearing
- ❌ **TRIVIAL DRIFT** — small wrinkle (dead code, unused enum, comment error) that's fixable in a 1-line change. Orchestrator can address directly.
- ❌ **SUBSTANTIAL DRIFT** — material behavior mismatch with spec; needs a spec-gap issue or reimpl. (None in this audit.)
