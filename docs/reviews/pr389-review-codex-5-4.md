# PR #389 Phase 7 OTC Strip-out Review — Codex 5.4

## Sub-agent plan

Wave 1 parallel (done serially here): logic/cross-phase audit, spec+ABI audit, coverage audit. Wave 2 sequential: run `forge test`, validate any HIGH findings against surrounding reservation/death code, then classify MUST/SHOULD/DEFER/SKIP.

Validation run summary:
- `~/.foundry/bin/forge test` passed: 291/291 tests green.
- `~/.foundry/bin/forge test --match-contract DirectTransfersTest -vv` passed: 38/38 tests green.
- Checked-in `packages/contracts/abi/IClanWorld.json` matches a fresh `forge inspect src/IClanWorld.sol:IClanWorld abi`.

## Findings by category

### MUST FIX

1. Direct transfers bypass upgrade reservations for wood/iron/wheat/blueprints.

Why it matters:
- Phase 6/Phase 10 already established a spendable-vs-reserved invariant for upgrade resources. Queue-time validation intentionally treats reserved wood/iron/wheat/blueprints as unavailable to later actions.
- Phase 7 direct transfers ignore that invariant and debit raw balances instead. That lets a clan queue a wall/base/monument upgrade successfully, then OTC away the reserved assets before settlement. The later upgrade can fail or stall even though reservation-aware queue validation had already accepted it.

Code evidence:
- Reservation-aware validation uses `_spendableAfterReleasing(...)` in `_validateUpgradeWallOrder`, `_validateUpgradeBaseOrder`, and `_validateUpgradeMonumentOrder` at `packages/contracts/src/ClanWorld.sol:4170-4327`.
- Reservations are tracked in `_reservedWoodByClan`, `_reservedIronByClan`, `_reservedWheatByClan`, and `_reservedBlueprintByClan`, and incremented in `_reserveWallUpgrade/_reserveBaseUpgrade/_reserveMonumentUpgrade` at `packages/contracts/src/ClanWorld.sol:4193-4209`, `4257-4275`, `4330-4353`.
- Existing spendable-resource deduction logic already respects reservations in `_deductFromVault(...)` at `packages/contracts/src/ClanWorld.sol:3605-3624`.
- The new OTC paths do not use that pattern:
  - `transferVaultResource` checks raw `vaultWood/vaultIron/vaultWheat` and debits them directly at `packages/contracts/src/ClanWorld.sol:4558-4578`.
  - `transferBlueprint` checks raw `blueprintBalance` and debits it directly at `packages/contracts/src/ClanWorld.sol:4598-4603`.
  - `transferBundle` checks and debits raw `blueprint/vaultWood/vaultIron/vaultWheat` at `packages/contracts/src/ClanWorld.sol:4633-4649`.

Impact:
- This is the same class of invariant break as the confirmed Phase 6 withdraw-reservation bug, just through OTC instead of `WithdrawResources`.
- Gold and fish are unaffected because there is no reservation ledger for them, but wood/iron/wheat/blueprints are materially exposed.

Coverage gap:
- `packages/contracts/test/DirectTransfers.t.sol:143-470` covers happy path, dead-sender, dead-during-settle, ownership, invalid enum, and atomic bundle rollback, but it does not cover any reserved-resource or queued-upgrade scenario.

### SHOULD FIX

1. `ClanWorldStub` does not preserve the real Phase 7 transfer invariants.

Why it matters:
- The production contract rejects zero amount, same-clan, dead sender, empty bundle, and stale-settlement cases.
- The stub transfer entrypoints only check owner/recipient/balance and therefore allow flows that production rejects.
- Because `CLAN_WORLD_USE_STUB_CHAIN=true` is still an active integration mode, this can teach callers the wrong semantics in demos/smoke tests.

Code evidence:
- Real contract guards: `packages/contracts/src/ClanWorld.sol:4515-4649`.
- Stub contract weaker guards: `packages/contracts/src/ClanWorldStub.sol:166-246`.
- Stub tests currently have no OTC coverage: `packages/contracts/test/ClanWorldStub.t.sol:1-59`.

Suggested scope:
- Mirror at least `fromClan` existence, zero-amount, same-clan, empty-bundle, and dead-sender checks in the stub.
- It is fine if the stub keeps settlement/backlog behavior simplified.

### DEFER

1. `docs/planning/DEMO_DRIFT.md` is stale about `ClanWorldStub`.

Why it matters:
- The doc still says the stub is a no-op where “all functions revert or return zero values,” which is no longer true after Phase 7 added real ownership/transfer state mutations.

Code evidence:
- Stale doc text: `docs/planning/DEMO_DRIFT.md:11,72`.
- Current stub behavior: `packages/contracts/src/ClanWorldStub.sol:149-246`.

This is not blocking, but it will confuse future reviewers and integration work if left as-is.

### SKIP / false positive

1. Dead-recipient transfers look odd, but I do not see a concrete invariant break from them.

Why I am skipping it:
- The relevant spec language I found forbids dead clans from sending OTC, not from receiving it.
- Production tests intentionally allow dead recipients in the new surface.
- Rankings only include active clans, and loot-value scoring only uses vault resources, so this does not appear to create a scoring or ranking regression by itself.

Code/spec evidence:
- Spec note: `docs/planning/clanworld_v1_implementation_profile.md:128-129`.
- Tests intentionally allow dead recipients: `packages/contracts/test/DirectTransfers.t.sol:203-209`, `317-323`.
- Rankings/loot calculations ignore dead clans and/or only look at vault loot: `packages/contracts/src/ClanWorld.sol:4980-5028`.

2. ABI/event drift is clean.

Why I am skipping it:
- `IClanWorld.sol`, emitted Phase 7 events, and the checked-in ABI are aligned.
- `ClanOwnershipTransferred` is declared in the interface and emitted by both real/stub implementations.
- Fresh `forge inspect` matched `packages/contracts/abi/IClanWorld.json`.

3. I did not find a concrete missed cherry-pick from `#200` / `#358` beyond what was explicitly salvaged.

Why I am skipping it:
- The end-state includes the four direct-transfer entrypoints, `ownerNonce`, `transferClanOwnership`, and `ClanOwnershipTransferred`.
- I did not see a local codepath that obviously expected additional nonce invalidation or escrow-era machinery.
- Without the earlier PR heads in this worktree, I can only judge the merged end-state, and I do not have a concrete omitted item to call out as actionable.

## Recommended next steps

1. Fix the reservation bypass first. Reuse the existing spendable-resource pattern so OTC debits for wood/iron/wheat/blueprints respect reserved balances before transfer.
2. Add cross-phase regression tests:
   - Queue wall/base/monument upgrades, then attempt `transferVaultResource`, `transferBlueprint`, and `transferBundle` against the reserved amounts and assert revert.
   - Include a positive control where only unreserved amounts move successfully.
   - Verify the originally queued upgrade still settles successfully after allowed transfers.
3. Bring `ClanWorldStub` transfer guards into closer semantic alignment with the real contract and add focused stub OTC tests.
4. Update `docs/planning/DEMO_DRIFT.md` so the stub description matches reality.

## What you didn't get to

- I did not diff the historical contents of PRs `#200` / `#358` directly because those heads are not present in this local worktree.
- I did not produce a minimal executable repro test for the reservation-bypass bug inside the repo because this pass was constrained to review-only output, but the codepath is concrete and the full surrounding reservation machinery was traced locally.
