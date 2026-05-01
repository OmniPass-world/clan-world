# ClanWorld v4.6 Addendum: Buildings Alignment

Status: Authoritative addendum, scoped to building validation and progression semantics.
Read order: This supersedes `clanworld_v4_spec.md` section 8.6 where it describes worker `WAITING` behavior for missing build resources.

## Decision

Phase 8 canonizes the implemented building model:

- Missing resources reject at submit with `ERR_MISSING_RESOURCES`; no speculative building mission is queued.
- Building resources are checked at submit and held in per-clan reservations until settlement, invalidation, or retry.
- Reserved wheat is not spendable by upkeep while an upgrade is pending; this keeps reservation semantics consistent between real settlement and read-only simulation.
- Future-level reservations are retained and retried. If a worker reserved level N+1 before level N settles, the mission remains pending until the prerequisite level lands or the mission is invalidated.
- `UpgradeWall` is the only wall upgrade action. `BuildWall` is intentionally removed from the ABI.
- Monument L7-L10 costs are flat per level: `200 wood + 25 iron + 100 wheat + 1e18 Blueprint Fragment`.
- Upgrade events standardize on `WallLevelChanged`, `BaseLevelChanged`, and `MonumentLevelChanged`.

## Rationale

Reject-at-submit avoids speculative `WAITING` queues, gives Elders immediate feasibility feedback, prevents double-spending the same vault resources across concurrent workers, and keeps retry logic in the Elder layer instead of the contract.

Retrying retained future-level reservations allows multi-worker upgrade batches without repricing or silently discarding a worker's reserved resources. Reserved resources stay non-spendable until the mission settles or is invalidated, including during upkeep and market sells.

Removing `BuildWall` avoids bytecode bloat and prevents future agents from treating deprecated behavior as supported. The repo has no production users yet, so compatibility aliases are not justified.

The L7-L10 monument plateau keeps the blueprint gate locked while making late-game UAT practical.

## UAT Expectations

- Wall L0 to L1 uses `UpgradeWall` and costs `20 wood`.
- Base L1 to L2 costs `40 wood + 20 wheat`.
- Monument L6 to L7 requires `1e18` Blueprint Fragment plus the flat L7-L10 resources.
- Submitting an upgrade without enough reserved spendable resources returns `ERR_MISSING_RESOURCES`.
- Concurrent building upgrades reserve separate costs and cannot spend the same vault balance twice.
- Upkeep cannot consume wheat reserved for pending base or monument upgrades.
- Queued future-level base and monument upgrades settle after prerequisite levels complete, even if worker settlement order is reversed.
