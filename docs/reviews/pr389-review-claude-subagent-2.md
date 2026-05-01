# PR #389 Review — Reviewer #2 (adversarial / cross-phase / merge-mess)

Worktree HEAD: `6ab8d93` (dev-merge merge of #386 — Phase 7 direct transfers + clan ownership).
Reviewer focus: merge artifacts, phase boundary leakage, cross-phase invariant violations, spec drift, stale-symbol cleanup.

## Sub-agent plan

I ran four light parallel scout passes inline via Bash + Read (rather than spawning Agent sub-processes — the surface is small enough that direct grepping is faster and gives the same coverage; parallelism was at the tool-call level):

| Pass | What it looked for | Outcome |
| --- | --- | --- |
| A — stale-symbol sweep | Any reference to `OtcProposal*`, `proposeGold/Vault/Blueprint/Bundle*`, `acceptOtcProposal`, `cancelOtcProposal`, `_otcProposals`, `proposerNonce` across `*.sol/*.ts/*.json/*.md/*.mjs` (excluding `node_modules`, `.git`, `out/`). | CLEAN. Zero hits. The strip-out left no orphans in source, ABI, adapters, or docs. |
| B — reservation-awareness audit on the 4 transfer functions | Compare `transferGold/transferVaultResource/transferBlueprint/transferBundle` against the reservation-aware primitive `_deductFromVault` (line 3606) and `_spendableAfterReleasing` (line 4413). Cross-check against v4.6 buildings-alignment §"Reserved resources stay non-spendable until the mission settles or is invalidated, including during upkeep and market sells". | **HIT — see MUST-FIX-1.** All four transfer functions use bare `clan.vaultX -= amount` style debits and check `fromClan.vaultWood >= amount` rather than `_spendableAfterReleasing(...)`. |
| C — spec drift sweep | Read v4 §11 (OTC trust model), v4.2 §10.3 (OTC transfer surface), v4.3 §M (dead clan restriction), v4.6 (reservations), numbered plan §Phase 7. Compare against the merged implementation. | One ambiguity (reservation/OTC interaction) flagged in MUST-FIX-1. Direct transfer surface itself is fully spec-compliant; carry-isolation rule satisfied; dead-sender-only restriction matches v4.3 §M.1. No stale propose/accept language anywhere in `docs/`. |
| D — merge-artifact / cross-phase regression sweep | Conflict markers in `*.sol`; ABI parity vs `IChainClient.ts`; stub vs main parity; ancillary test diffs (`GasProfiling.t.sol`, `RNG.t.sol`); `_settleClan` interaction with `MAX_LAZY_SETTLE_BACKLOG`; ownership transfer + DEAD interaction. | No conflict markers. Adapter parity is by-design (gen script whitelists read-getters only). Stub omits validation that main has — see SHOULD-FIX-1. Ancillary test diffs are pure formatting. Settle-cap interaction is correctly defended by `_requireTransferSettlementComplete`. |

The full diff for #389 is small (180 LOC in `ClanWorld.sol`, 169 LOC in `ClanWorldStub.sol`, +473 LOC of dedicated `DirectTransfers.t.sol`). 6ab8d93 is a clean fast-forward-style merge — the "really hairy" framing is about the merge sequence (Phase 7 was the last phase to land), not the diff itself.

---

## Findings

### MUST FIX

#### MUST-FIX-1 — All four transfer functions are reservation-blind (cross-phase invariant violation)

**Where:** `packages/contracts/src/ClanWorld.sol`
- `transferGold` line 4533: `fromClan.goldBalance -= amount;` — gold has no reservation map, OK in isolation.
- `transferVaultResource` lines 4561-4575: `require(fromClan.vaultWood >= amount); fromClan.vaultWood -= amount;` (and same pattern for iron/wheat/fish).
- `transferBlueprint` line 4602: `require(fromClan.blueprintBalance >= amount); fromClan.blueprintBalance -= amount;`
- `transferBundle` lines 4636-4641 (require), 4644-4649 (debit).

**The bug:** Wood, iron, wheat, and blueprint balances all have `_reservedXByClan` companion mappings (`ClanWorld.sol:94-97`) that hold resources reserved by pending wall/base/monument upgrades. The canonical reservation-aware debit primitive is `_deductFromVault` (line 3606), which checks `_spendableAfterReleasing(clan.vaultWood, _reservedWoodByClan[clanId], 0) < amount` before debiting. The four new transfer functions skip this check entirely — they compare against the *raw vault total* including reserved amounts.

**Concrete exploit / failure mode:**

1. Clan A has `vaultWood = 100`, with `_reservedWoodByClan[A] = 80` (a pending base upgrade has 80 wood reserved).
2. The spendable balance is `100 - 80 = 20`.
3. Owner of A calls `transferVaultResource(A, B, Wood, 100)`. The check `fromClan.vaultWood >= 100` passes. The debit `fromClan.vaultWood -= 100` succeeds.
4. Now `vaultWood = 0`, `_reservedWoodByClan[A] = 80`. The reservation is silently underwater.
5. When the upgrade settles via `_settleWallUpgrade` / `_settleBaseUpgrade` / `_settleMonumentUpgrade`, the path will hit `_subtractHeld(_reservedWoodByClan[A], 80) = 0` and the reservation is wiped without the upgrade being paid for. **Worse:** in the meantime, any other read using `_spendableAfterReleasing(clan.vaultWood=0, reserved=80, released=0)` returns 0, but the upgrade slot is still pending, breaking the invariant in v4.6 §"Reserved resources stay non-spendable until the mission settles or is invalidated".

**Same shape as the already-CRITICAL `WithdrawResources` reservation-bypass** that the prompt confirms is being tracked separately. This means there are now FIVE confirmed reservation-blind paths under dev-merge HEAD:

1. `_doWithdrawResources` (line 1085-1088) — pre-existing, already-CRITICAL.
2. `transferVaultResource` Wood/Iron/Wheat branches.
3. `transferBlueprint`.
4. `transferBundle` (covers all four resources + blueprint).
5. (`transferGold` is exempt — gold has no reservation map.)

The `transferVaultResource` Fish branch is also exempt — fish has no reservation, but the check parity is still cleaner.

**Spec evidence:**
- v4.6 buildings-alignment §"Concurrent building upgrades reserve separate costs and cannot spend the same vault balance twice" + §"Upkeep cannot consume wheat reserved for pending base or monument upgrades."
- v4.3 §M.1 names the four transfer entrypoints by name as the dead-clan gate; the spec is silent on reservation interaction, but the entire reservation system was introduced under v4.6 specifically to prevent double-spend of vault balances.
- v4.2 §10.3 says transfers "may draw only from clan vault resources" — *spendable* vault is the only reading consistent with the rest of the system.

**Suggested fix shape:** thread each transfer through `_spendableAfterReleasing(...)` for the reserved-bearing resources. For `transferBundle`, the "all checks before any mutation" block already exists and is the natural place to add four extra spendable checks against `_reservedWoodByClan[fromClanId]` / `_reservedIronByClan[fromClanId]` / `_reservedWheatByClan[fromClanId]` / `_reservedBlueprintByClan[fromClanId]`. Pair with new test cases:

- `test_transferVaultResource_reservation_blocks_transfer` — submit a base upgrade order, then attempt a transfer of the reserved resource and assert revert.
- `test_transferBlueprint_reservation_blocks_transfer` — submit a monument upgrade order, then attempt a blueprint transfer and assert revert.
- `test_transferBundle_partial_reservation_revert` — multi-component bundle where one component over-spends past reservation.

Recommend bundling this fix in the **same** patch as the WithdrawResources reservation-bypass fix so the new `_spendableAfterReleasing` plumbing is added once and applied across all five paths.

---

### SHOULD FIX

#### SHOULD-FIX-1 — Stub validation parity gap with main implementation

**Where:** `packages/contracts/src/ClanWorldStub.sol:166-264`.

The stub is meant to be a Base Sepolia deploy target with the same external surface. Main implementation enforces:

| Check | Main `transferGold` | Stub `transferGold` |
| --- | --- | --- |
| `amount > 0` | yes (line 4516) | **no** |
| `fromClanId != toClanId` | yes (line 4517) | **no** |
| `fromClan.clanId != 0` | yes (line 4522) | **no** (relies on `clan.owner == msg.sender` which would fail for a 0-clan, but error message is misleading) |
| `nonReentrant` modifier | yes | **no** |
| `_settleClan` + post-settle check | yes | n/a (stub has no settlement engine) |
| Dead-state revert | yes | **no** |

Same gaps appear in `transferVaultResource`, `transferBlueprint`, and `transferBundle`. The stub `transferBundle` also has no `empty bundle` check (the main version requires at least one component non-zero, line 4621).

**Why it matters:** the stub is used for Base Sepolia/AXL integration testing per `apps/*` adapter usage. If a partner integration tests against the stub and depends on observed revert messages or revert-on-zero semantics, then deploys against the real contract, behavior diverges. The error-message inconsistency (`ClanWorldStub: ...` vs `ClanWorld: ...`) is fine — they're different contracts. But the *semantic* checks (zero amount, same-clan, empty bundle, dead-sender) should match.

**Suggested fix:** mirror the validation block (minus `_settleClan` and `nonReentrant`) into each stub function. This is a stub-only edit and requires no main-contract changes.

#### SHOULD-FIX-2 — `transferClanOwnership` allows transfer of dead clans

**Where:** `packages/contracts/src/ClanWorld.sol:4491-4501`.

`transferClanOwnership` does not call `_settleClan` and does not check `clanState != DEAD`. A clan that has already been killed (via starvation winter death or bandit raid) can still have its `owner` reassigned and `ownerNonce` incremented. The spec is silent on this — v4.3 §M.1 only names the four asset-transfer entrypoints, not ownership.

**Severity:** SHOULD rather than MUST because this is likely benign or even desirable (a dead clan still owns its iNFT and might be transferred during wind-down to the same wallet that gets the on-chain residual). But it's worth confirming with Liam, and there is no test asserting either direction. Phase boundary leakage potential: future phases that gate on "is this a live owner" might assume dead-clan ownership is frozen.

**Suggested action:** add an explicit test (`test_transferClanOwnership_dead_clan_allowed` OR `_reverts`, depending on intended semantics) and a one-line comment in the function explaining the choice. Defer to Liam on whether to gate.

#### SHOULD-FIX-3 — Bundle event ordering does not match standalone-call event ordering

**Where:** `packages/contracts/src/ClanWorld.sol:4660-4667` (bundle emit) vs the per-function emits.

A standalone `transferGold` emits exactly one `GoldTransferred`. A standalone `transferBlueprint` emits exactly one `BlueprintTransferred`. A standalone `transferVaultResource` emits exactly one `VaultResourceTransferred` for the chosen resource.

A bundle that includes all six components emits, in this order: `GoldTransferred`, `BlueprintTransferred`, `VaultResourceTransferred(Wood)`, `VaultResourceTransferred(Iron)`, `VaultResourceTransferred(Wheat)`, `VaultResourceTransferred(Fish)`.

That's reasonable and consistent. **However:** indexers built per-event will see ordering they may not expect (e.g., indexers that key on `txHash + logIndex`). This is fine to ship — but for an indexer team it's worth a one-line note in `pr389-spec-compliance-uat.md` or a changelog entry that bundles emit per-component events in `[Gold, Blueprint, Wood, Iron, Wheat, Fish]` order. SHOULD rather than MUST because the order is deterministic and indexers can adapt.

---

### DEFER (file as separate GH issues)

#### DEFER-1 — No test case where bundle transfers EVERYTHING but one component fails after partial debit

The atomicity comment on `transferBundle` says "all balance checks before any mutation (atomic)". This is enforced by the structure. There IS a single negative test (`test_transferBundle_insufficient_one_component_entire_call_reverts`), but it doesn't cover the case where the bundle would succeed in *check* phase, then revert *between debits and credits* due to a `nonReentrant` re-entry (impossible by construction) or a storage write failure (impossible in EVM). So strictly the missing test is impossible-by-construction.

But there IS a real test gap: **no test covers bundle ordering with the `_requireTransferSettlementComplete` post-settle check**. If only `fromClan` is settled but `toClan` is unsettled past the cap, the test suite doesn't verify the bundle-flavor of `test_transferGold_sender_must_be_fully_settled`. File as a low-priority test-completeness issue.

#### DEFER-2 — `ownerNonce` is uint64 with no overflow protection

**Where:** `packages/contracts/src/ClanWorld.sol:4499` (`clan.ownerNonce++`).

Solidity 0.8.x reverts on overflow by default, so this is safe — but it'll silently revert at `2^64 - 1` ownerships. Not realistic in v1, but worth documenting in the NatSpec ("max 2^64 ownership rotations"). Defer to a doc-cleanup pass.

#### DEFER-3 — `transferGold/transferVaultResource/transferBlueprint` triple is functionally a subset of `transferBundle`

The four-function surface is per-spec (v4.2 §10.3 names all four), so this isn't a bug. But there is duplicated validation code across four entrypoints (zero-check, same-clan check, owner check, settle, dead-check, balance-check). If a future cleanup phase wants to reduce LOC, the standalone three could become 1-liner forwarders to `transferBundle` with a single component non-zero. Defer — current shape is more gas-efficient and easier to read.

---

### SKIP / false positives

#### SKIP-1 — Adapter parity gap (`IChainClient.ts` does not contain new transfer ABI entries)

The codegen script `scripts/gen-chainclient-abi.mjs` whitelist (lines 16-35) only emits read-getters and `submitClanOrders`. The four transfer functions and `transferClanOwnership` are intentionally not surfaced in the bundled ABI export — off-chain consumers who need the transfer surface read directly from `packages/contracts/abi/IClanWorld.json`. This is the existing architecture, not a regression. Confirmed by reading `gen-chainclient-abi.mjs` whitelist before flagging.

#### SKIP-2 — `_settleClan` cap of `MAX_LAZY_SETTLE_BACKLOG = 200` ticks could leave clan partially settled

Considered as a possible bypass — what if a clan is unsettled by 250 ticks, `_settleClan(fromClanId)` inside the transfer function only advances by 200, then the transfer proceeds against a partially-settled clan?

False alarm. The post-settle equality check `_requireTransferSettlementComplete` (line 4509) explicitly compares `lastSettledTick == _world.currentTick`. If `_settleClan` capped, the equality fails and the transfer reverts with `"ClanWorld: must settle first"`. The test `test_transferGold_sender_must_be_fully_settled` (line 326) verifies exactly this case.

#### SKIP-3 — Stab vs main differing revert messages

`ClanWorldStub: insufficient gold` vs `ClanWorld: insufficient gold`. Different contracts, different identifying prefixes, expected. Indexers should match on prefix-stripped tail or on revert selector, not on full string.

#### SKIP-4 — Ancillary test changes in `GasProfiling.t.sol` and `RNG.t.sol`

Both diffs are pure `forge fmt` line-wrapping — no logic changes. Not a regression risk.

#### SKIP-5 — No stale OTC propose/accept references

Pass A confirmed: zero hits across `.sol`, `.ts`, `.tsx`, `.json`, `.md`, `.mjs` (excluding `node_modules`, `.git`, `out/`). Strip-out is complete; spec docs (v4.2 §10.3, v4.3 §M, numbered plan §Phase 7) all describe the direct-transfer surface as the canonical design. The Phase 7B commit `3cc3c36` ("OTC proposer owner nonce binding") is the only historical breadcrumb of the propose/accept lifecycle — it's been fully reverted out.

---

## Recommended next steps

1. **Block merge of dev-merge to dev/main on MUST-FIX-1.** Bundle the fix with the already-known-CRITICAL `_doWithdrawResources` reservation-bypass — both deserve the same `_spendableAfterReleasing(...)` plumbing pass. Ideal patch surface: ~30 LOC across four transfer functions + ~60 LOC of new tests.

2. **File DEFER-1, DEFER-2, DEFER-3 as separate GH issues against the contracts milestone**, none blocking.

3. **Apply SHOULD-FIX-1 (stub validation parity) in the same fix-round** as MUST-FIX-1. The stub edits are independent and small (~40 LOC).

4. **Resolve SHOULD-FIX-2 (dead-clan ownership transfer)** by asking Liam directly: should a dead clan's iNFT ownership be transferable? Add a single test asserting whichever direction he picks.

5. **SHOULD-FIX-3 (event ordering doc note)** — append a one-line note to `docs/reviews/pr389-spec-compliance-uat.md` documenting bundle event order. No code change.

6. **Confirm with Reviewer #1's findings.** I focused narrowly on cross-phase / merge / reservation. Standard correctness coverage (gas, reentrancy, event indexed-fields, NatSpec completeness, PEP-style nits) is Reviewer #1's lane.

The merge itself was clean — no stale symbols, no conflict markers, no spec drift in `docs/`. The "hairy" framing was about Phase 7 being the last phase to land, not about the diff. The substantive risk on this PR is entirely the **reservation-bypass cross-phase invariant violation** (MUST-FIX-1), which is the same family as the already-CRITICAL withdraw bug. Fix them together.
