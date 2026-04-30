# Phase 7B OTC Lifecycle Spec

## Overview

ClanWorld supports four types of clan-to-clan OTC (over-the-counter) transfers:
- **Gold** (`proposeGoldTransfer` / `acceptGoldTransfer` / `cancelGoldTransfer`)
- **Vault resources** (`proposeVaultTransfer` / `acceptVaultTransfer` / `cancelVaultTransfer`)
- **Blueprint** (`proposeBlueprintTransfer` / `acceptBlueprintTransfer` / `cancelBlueprintTransfer`)
- **Bundled** (gold + all vault resources + blueprint in one call)

---

## Propose / Accept / Cancel Lifecycle

```
Proposer (fromClan owner)         Acceptor (toClan owner)
        |                                  |
        |-- propose*() ------------------>|  proposal stored, id returned
        |                                  |
        |           (time passes, tick advances)
        |                                  |
        |                    <-- accept*() |  if valid: balances move, proposal deleted
        |                                  |
        | <-- cancel*() (optional) ------->|  proposal deleted, cap slot freed
```

### Who calls what

| Function | Caller | Auth check |
|---|---|---|
| `propose*` | `fromClan.owner` | `msg.sender == fromClan.owner` |
| `accept*` | `toClan.owner` | `msg.sender == toClan.owner` |
| `cancel*` | `fromClan.owner` | `msg.sender == fromClan.owner` |

### State transitions

- **Proposed**: proposal stored in `_otcGoldProposals[proposalId]` (etc.), `_openOtcProposalsByClan[fromClanId]` incremented.
- **Accepted**: balances transferred atomically, proposal deleted (`delete` zeroes storage), open-count decremented via `_closeOtcProposal`.
- **Cancelled**: proposal deleted, open-count decremented. No balance movement.
- **Expired** (reap): proposals past `expiryTick` are reaped during the next propose call via `_reapExpiredOtcProposals`. Stale proposals consume no permanent cap slot once reaped.

---

## `expiryTick` Semantics

- **Inclusive**: a proposal with `expiryTick = T` is valid at world tick `T`. It expires at tick `T+1`.
- Acceptance guard: `require(currentTick <= expiryTick, "ClanWorld: proposal expired")`.
- Propose does NOT validate expiry — a proposer may create a proposal that expires immediately (use case: instantaneous atomic agree-then-accept in a single block).

---

## Replay Protection

- **Monotonic proposal IDs**: `_nextOtcProposalId` is incremented each time a proposal is created. IDs are unique and never reused.
- **Single-use proposals**: `delete _otcGoldProposals[proposalId]` on accept or cancel. Attempting to accept or cancel a deleted proposal reverts with `"ClanWorld: proposal not found"` (because `proposal.from == 0`).
- **No replay across cancels**: once cancelled, the proposalId slot is zeroed and cannot be reused.

---

## `proposerOwnerNonceAtPropose` — Ownership Nonce Binding

**Problem**: Alice owns clan A, proposes a gold transfer to Bob's clan B, then sells clan A to Carol. Without a guard, Bob could accept and drain Carol's gold.

**Solution**: every propose function captures `fromClan.ownerNonce` into the proposal struct. Every accept function re-checks the current `fromClan.ownerNonce` against the stored value.

```solidity
require(
    fromClan.ownerNonce == proposal.proposerOwnerNonceAtPropose,
    "ERR_PROPOSER_NO_LONGER_OWNER"
);
```

`transferClanOwnership(uint32 clanId, address newOwner)`:
- Only callable by current `clan.owner`.
- Sets `clan.owner = newOwner`.
- Increments `clan.ownerNonce`.
- Emits `ClanOwnershipTransferred(clanId, oldOwner, newOwner, newOwnerNonce)`.

**Effect on outstanding proposals**: all open proposals from that clan become unacceptable (nonce mismatch). The new owner must cancel or let them expire; they cannot be accepted against the new owner's assets.

---

## Self-Transfer Guard

Enforced at propose time for all four proposal types:

```
require(fromClanId != toClanId, "ERR_SELF_TRANSFER");
```

A clan cannot send resources to itself.

---

## Zero / Empty Transfer Guard

Enforced at propose time. Error string: `"ERR_EMPTY_TRANSFER"`.

| Proposal type | Guard |
|---|---|
| Gold | `require(amount > 0, "ERR_EMPTY_TRANSFER")` |
| Blueprint | `require(amount > 0, "ERR_EMPTY_TRANSFER")` |
| Vault | `require(wood + wheat + fish + iron > 0, "ERR_EMPTY_TRANSFER")` (any one nonzero is OK) |
| Bundled | same as vault but includes gold + blueprint |

Partial vault or bundle transfers (e.g., wood only, iron only) are valid as long as at least one component is nonzero.

---

## Open Proposal Cap

Each clan is limited to `MAX_OPEN_OTC_PROPOSALS_PER_CLAN` live proposals at once across all four proposal types. The counter is decremented on accept or cancel. Expired proposals are reaped lazily on the next propose call and do not permanently consume cap slots.

Error: `"ERR_OTC_CAP"` when cap is hit.
