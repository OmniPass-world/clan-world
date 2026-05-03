# PR 468 GPT-5.5 Pro Follow-Up Review Triage

Source: GPT-5.5 Pro static/manual review of the diamond migration branch after PR 468. The review was slightly stale by the time it arrived, but it still identified one public-deploy race worth fixing before demo and several good post-demo follow-ups.

Date triaged: 2026-05-03.

## Verdict

The review did not find a new selector-table or diamond-dispatch bug. The diamond split is considered demo-close, with one contract race to fix before public testnet deployment:

- `finalizeSeason()` could be called after the facet selector was installed but before `ClanWorldDiamondInit.init()` ran.
- Before init, `currentTick == 0` and `seasonEndTick == 0`, so the season-ended check passed.
- `init()` did not explicitly reset `seasonFinalized`, so an attacker could leave a freshly initialized world already finalized.

This branch fixes that race by requiring initialized app storage before finalization and explicitly resetting the season-finalized flag during init.

## Fixed Now

| Item | Status | Notes |
|---|---|---|
| Pre-init `finalizeSeason()` race | Fixed in this PR | `FinalizeSeasonFacet.finalizeSeason()` now requires `s.initialized`; `ClanWorldDiamondInit.init()` explicitly sets `s.world.seasonFinalized = false`. |
| Pre-init finalization regression coverage | Fixed in this PR | `testDiamondFinalizeSeasonBeforeInitReverts()` installs the season facet without init and asserts the call reverts. |

## Already Covered Elsewhere

| Item | Status | Link |
|---|---|---|
| Winter start boundary parity | Covered by stacked PR | PR #472 |
| Winter end boundary parity | Covered by stacked PR | PR #473 |
| Winter crop transition cap stress | Covered by stacked PR | PR #474 |

These tests cover boundary mechanics and crop transition parity, but they do not cover the review's post-demo concern about missing cold/starvation event emission.

## Deferred Issues

The UI does not depend on chain logs for winter/cold/starvation today, so event logging can wait until after the demo. Each deferred item below should have a GitHub issue linked back to this document.

| Deferred item | Demo impact | Recommended follow-up | Issue |
|---|---|---|---|
| Emit settlement simulation events for winter/cold/starvation outcomes | Only blocker if demo/indexer depends on logs for those story beats | Extend `SettlementLog` and `commitSimulation()` to emit starvation, cold shortage, wall degradation, clansman cold death, clan eliminated, and clan died events. | [#476](https://github.com/OmniPass-world/clan-world/issues/476) |
| Wire live numeric clan IDs to visual metadata | Relevant if demo shows real-chain map without demo mode | Map numeric chain clan IDs to names, sigils, portraits, bases, walls, monuments, and bandit visuals. | [#477](https://github.com/OmniPass-world/clan-world/issues/477) |
| Remove stale real-chain default contract address fallback | Could point a real-chain client at an old deployment if env is missing | Remove the fallback default and fail loudly unless `CLAN_WORLD_CONTRACT_ADDRESS` is set. | [#478](https://github.com/OmniPass-world/clan-world/issues/478) |
| Clean up season rollover pause/order window | Only relevant if demo shows season rollover live | Either roll season inside `finalizeSeason()` or block new orders until rollover completes. | [#479](https://github.com/OmniPass-world/clan-world/issues/479) |
| Refund wall upgrade reservations after cold degradation level drift | Relevant only when wall upgrades overlap winter cold degradation | If reserved `fromLevel` no longer equals current wall level, clear/refund the reservation and fail the mission. | [#480](https://github.com/OmniPass-world/clan-world/issues/480) |
| Reconcile aggregator/lens view semantics with derived state | Can make UI stale/misleading between heartbeats | Decide whether aggregator views are raw/indexer convenience views or derived views, then update code/comments accordingly. | [#481](https://github.com/OmniPass-world/clan-world/issues/481) |
| Reject empty selector arrays in diamond cuts | Hardening, not demo-blocking | Add explicit empty-selector guards in add/replace/remove paths. | [#482](https://github.com/OmniPass-world/clan-world/issues/482) |
| Reject init calldata when init address is zero | Hardening, not demo-blocking | Require `data.length == 0` when `init == address(0)`. | [#483](https://github.com/OmniPass-world/clan-world/issues/483) |
| Reject zero diamond owner in constructor | Hardening, not demo-blocking | Require `contractOwner != address(0)` in `Diamond` constructor. | [#484](https://github.com/OmniPass-world/clan-world/issues/484) |
| Decide ERC-165 support or remove unused mapping | Hardening/review clarity | Either expose/populate `supportsInterface()` or delete `supportedInterfaces`. | [#485](https://github.com/OmniPass-world/clan-world/issues/485) |
| Add freeze/immutability path or deployment governance | Production hardening | Decide whether final deploy is frozen, multisig-owned, or timelocked. | [#486](https://github.com/OmniPass-world/clan-world/issues/486) |
| Define ETH receive policy | Production hardening | Revert native ETH sends if unused, or add an explicit sweep policy. | [#487](https://github.com/OmniPass-world/clan-world/issues/487) |
| Decide diamond owner vs treasury owner policy | Production/admin hardening | Decide whether treasury ownership should follow diamond ownership or stay separate. | [#488](https://github.com/OmniPass-world/clan-world/issues/488) |

## Demo Checklist Notes

Before public testnet demo, keep these explicit:

```bash
CLAN_WORLD_CONTRACT_ADDRESS=<CLAN_WORLD_DIAMOND_ADDRESS>
CLAN_WORLD_LENS_ADDRESS=<CLAN_WORLD_LENS_ADDRESS>
CLANWORLD_USE_REAL_INDEXER=true
CLANWORLD_USE_FAKE_HEARTBEAT=false
```

For the polished visual map demo, use:

```bash
VITE_CLANWORLD_DEMO_MODE=true
```

For a real-chain visual demo, expect less polished visuals until numeric chain clan IDs are wired to visual metadata.

## Validation For The Immediate Fix

Run:

```bash
bash scripts/forge.sh test --match-path test/diamond/DiamondSkeleton.t.sol
pnpm --dir packages/contracts check:sizes
```

Observed during triage:

- `DiamondSkeleton.t.sol`: 35 passed, 0 failed.
- `check:sizes`: passed.
- `FinalizeSeasonFacet`: 23,348 bytes.
- `ClanWorldDiamondInit`: 491 bytes.
