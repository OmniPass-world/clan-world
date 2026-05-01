## Sub-agent plan

Wave 1 parallel, if I were dispatching: (1) Solidity logic/security, (2) spec/ABI drift, (3) cross-phase reservation/market/winter interactions, (4) test/docs coverage. Wave 2 sequential: run `forge test`, deep-dive any HIGH/MUST candidates, then write this synthesis.

I did the same serially in this worktree: inspected `IClanWorld.sol`, `ClanWorld.sol`, `ClanWorldStub.sol`, `DirectTransfers.t.sol`, shared adapter ABI generation, relevant v4/v4.2/v4.3 docs, and attempted the requested test run.

## Findings by category

### MUST FIX

1. Direct vault/blueprint transfers can spend resources already reserved for in-flight upgrades.

`submitClanOrders` reserves building resources before the mission settles (`packages/contracts/src/ClanWorld.sol:3271-3278`; reservation writes at `4197-4199`, `4261-4264`, `4337-4341`). Existing resource spend paths know about this: `_deductFromVault` uses `_spendableAfterReleasing(..., _reserved*ByClan, 0)` for wood/iron/wheat (`3606-3624`), and upgrade validation does the same (`4179-4313`, helper at `4413-4421`).

The new direct transfer paths do not. `transferVaultResource` checks and debits raw `vaultWood/vaultIron/vaultWheat` (`4561-4575`), `transferBlueprint` checks raw `blueprintBalance` (`4600-4603`), and `transferBundle` checks/debits raw vault and blueprint fields (`4636-4657`). That lets an owner reserve resources for a wall/base/monument upgrade, transfer those same resources to another clan before the upgrade settles, and leave the original upgrade unable to settle. The settlement functions then return `false` without clearing the reservation if the raw balance is now insufficient (`1149`, `1184`, `1225-1228`), so the mission/reservation can become stuck while value has already left the clan.

This is the same class of bug as the confirmed Phase 6 WithdrawResources reservation bypass, but now exposed through all OTC vault resources and blueprint transfers. Fix by making `transferVaultResource`, `transferBlueprint`, and the non-gold/non-fish parts of `transferBundle` use reservation-aware spendable balances before debiting. Add focused tests that create an upgrade reservation, attempt OTC of the reserved component, and confirm only unreserved surplus can move.

### SHOULD FIX

1. The shared chain adapter and Elder CLI cannot actually submit the new OTC/ownership calls.

The Solidity interface and canonical ABI contain `transferGold`, `transferVaultResource`, `transferBlueprint`, `transferBundle`, and `transferClanOwnership`, but `IChainClient` exposes only reads plus `submitOrders` (`packages/shared/src/adapters/IChainClient.ts:53-61`). The generated shared ABI allowlist also excludes the new functions (`scripts/gen-chainclient-abi.mjs:15-34`). `RealChainClient.submitOrders` explicitly skips every non-`mission` order (`IChainClient.ts:2334-2338`), and the Elder CLI only routes through `submitOrders` (`packages/agents/src/cli.ts:109-123`).

Contract-level OTC works in principle, but the repo's stated integration boundary is `IChainClient`, and the minimal Elder write surface was expected to include OTC calls. Add adapter methods and CLI/toolbelt commands, or explicitly mark Phase 7 as contract-only and create a follow-up issue before agents need mercenary/alliance payments.

2. `ClanWorldStub` does not preserve the real transfer invariants.

The real engine rejects zero amount, same-clan, missing clans, and dead sender after settlement. The stub transfer functions only check owner/recipient/balance (`packages/contracts/src/ClanWorldStub.sol:166-241`), so stub-mode tests or demos can pass invalid flows that the real contract rejects. At minimum, mirror zero-amount, same-clan, from-clan-exists, and dead-sender checks for the four OTC entrypoints. Settlement/backlog behavior can stay simplified.

3. Direct transfer tests miss the cross-phase reservation matrix.

`DirectTransfers.t.sol` covers ownership, dead sender after settlement, insufficient balance, same clan, zero amount, atomic bundle rollback, and dead recipient behavior. It does not cover active wall/base/monument reservations, reserved blueprint, scheduled market interactions, or adapter-level ability to call the new functions. Given the MUST above, add minimal happy/error cases for reservation-aware spendability across vault resources and blueprint. No exhaustive matrix needed.

### DEFER

1. Clan ownership transfer is contract-only and does not yet model the Submission 2 iNFT/agent handoff.

`transferClanOwnership` correctly changes `Clan.owner`, increments `ownerNonce`, and emits `ClanOwnershipTransferred` (`ClanWorld.sol:4491-4500`). It does not settle the clan, block dead clans, update an iNFT contract, or expose an adapter/CLI call. That is acceptable for this phase if it is only a placeholder for the later Track 2 handoff, but the Submission 2 flow will need a dedicated issue tying `ownerNonce`, agent restart, memory/key handoff, and UI/CLI together.

2. Dead recipients are allowed to receive transfers.

The tests intentionally assert this for gold, vault resource, and bundle transfers. The v4.3 patch only says dead senders are blocked, so I am not calling this a bug. It may still be worth deciding whether sending value into an eliminated clan should be treated as a burn, a revert, or a permanently locked donation.

### SKIP / false positive

1. Deprecated propose/accept escrow was not found in the live ABI or contract surface.

Static ABI inspection showed the expected transfer functions/events and no `propose`/`accept`/`escrow` fragments. The stale-looking "propose" hits are planning/mock UI language, not live contract API.

2. Dead-state check ordering looks correct in the real engine.

All four direct transfer functions settle sender and recipient before checking `fromClan.clanState != DEAD` (`ClanWorld.sol:4526-4531`, `4555-4559`, `4595-4599`, `4630-4634`). The PM swarm's HIGH appears fixed in the real implementation.

3. Bundle atomicity looks correct for ordinary balance insufficiency.

`transferBundle` performs all component balance checks before any mutation (`4635-4641`), then debits and credits (`4643-4657`). The existing test covers insufficient iron preserving gold balances. This does not cover the reservation bug above.

4. Event/ABI declaration vs emission is consistent for the real contract surface I could inspect.

`GoldTransferred`, `VaultResourceTransferred`, `BlueprintTransferred`, and `ClanOwnershipTransferred` are declared in `IClanWorld.sol` and emitted by the corresponding real engine functions. `packages/contracts/abi/IClanWorld.json` contains those fragments. The generated shared adapter ABI is intentionally allowlisted, but that allowlist now needs updating if the adapter is expected to call OTC.

## Recommended next steps

1. Patch the direct transfer functions to respect reserved wood/iron/wheat/blueprint balances. Use the existing `_spendableAfterReleasing` pattern so behavior matches building, market, and the Phase 6 reservation fix direction.
2. Add narrow tests for reserved-resource OTC rejection/surplus transfer across `transferVaultResource`, `transferBlueprint`, and `transferBundle`.
3. Decide whether Phase 7 includes end-to-end agent usability. If yes, add transfer/ownership methods to `IChainClient`, include them in `scripts/gen-chainclient-abi.mjs`, implement `RealChainClient`/`StubChainClient`, and add Elder CLI commands.
4. Bring `ClanWorldStub` transfer guards in line with the real contract so stub mode does not teach callers the wrong semantics.
5. Re-run the full Foundry suite in an environment with Foundry installed before merging any follow-up.

## What I didn't get to

- `forge test` could not run here: `forge` is not installed or on PATH in this worktree environment (`/bin/bash: forge: command not found`). I also tried package-level shared checks, but `node_modules` is missing, so `vitest` and `tsc` were unavailable.
- I did not use `gh` or inspect PR threads, per the read-only/no-`gh` constraint.
- I did not generate a new Foundry artifact or run `forge inspect`; static ABI checks were limited to the checked-in `packages/contracts/abi/IClanWorld.json` and the shared adapter ABI generator.
