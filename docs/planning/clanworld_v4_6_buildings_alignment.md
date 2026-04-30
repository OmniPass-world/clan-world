# ClanWorld v4.6 Addendum — Buildings Alignment (Path A: as-built canonization)

**Status:** Authoritative addendum, scoped to building-validation semantics only
**Read order:** This doc supersedes `clanworld_v4_spec.md` §8.6 paragraph on order-`WAITING` semantics. The rest of v4 §8 remains canonical unless explicitly called out below.
**Purpose:** Canonize the as-built Phase 8 buildings implementation in `packages/contracts/src/ClanWorld.sol` as the authoritative hackathon ruleset.
**Audience:** Reviewers, UAT runners, future restoration work.

---

## 0. Why this doc exists — Path A decision

The PR #199 spec-compliance UAT report at `docs/reviews/pr199-spec-compliance-uat.md` found **1 substantial drift / 4 minor / 32 matches** for Phase 8 buildings. The substantial item is the `clanworld_v4_spec.md §8.6` `WAITING` queue behavior (`clanworld_v4_spec.md:940`) versus submit-time resource rejection in the implementation (`ClanWorld.sol:2292`, `ClanWorld.sol:2358`, `ClanWorld.sol:2434`).

Path A is chosen: this is a deliberate implementation improvement, **not a regression**. This addendum canonizes the as-built behavior and closes umbrella issue #348, filed under milestone #25, plus issue #354 for this doc.

## 1. Reject-at-submit semantics (§8.6 redesign)

| Surface | v4 spec value | As-built canonical value |
|---|---|---|
| Missing resources | Accept order, worker becomes `WAITING`, build later when vault fills (`clanworld_v4_spec.md:941-943`) | Reject submit with `ERR_MISSING_RESOURCES`; no speculative building mission enters the queue (`IClanWorld.sol:169`, `ClanWorld.sol:2274-2438`) |
| Resource timing | Checked when worker reaches homebase/action tick | Checked at submit, then held by per-clan reservation until settlement (`ClanWorld.sol:2297-2314`, `ClanWorld.sol:2440-2463`) |
| Settlement debit | Spend if resources exist at action tick | Debit the held cost on settlement; refund/clear reservation on invalidation (`ClanWorld.sol:836-843`, `ClanWorld.sol:926-930`) |

This is preferable because it removes a speculative-`WAITING` denial-of-service surface, gives callers immediate feasibility feedback, avoids queue enumeration during settlement, and makes failure predictable. The accepted trade-off is that the caller must re-submit after gathering; queueing logic moves into the Elder layer, where it belongs for L2 cost optimization.

## 2. Action name `BuildWall` deprecated alias of `UpgradeWall`

The v4 spec still says `build_wall`, but Phase 8 renamed the canonical action to `UpgradeWall`. The ABI keeps `BuildWall` in the enum for compatibility (`IClanWorld.sol:138`, `IClanWorld.sol:145`), while new `BuildWall` submissions are rejected with `ERR_INVALID_ACTION` (`ClanWorld.sol:2191-2192`; tested at `WallUpgrades.t.sol:181-190`).

Backward compatibility is limited to already-flighted legacy `BuildWall` missions: they complete harmlessly and release the worker (`ClanWorld.sol:547-549`, `WallUpgrades.t.sol:308-317`). Canonical wall upgrades use `UpgradeWall` and emit `WallLevelChanged` / `WallUpgraded` (`IClanWorld.sol:547-548`, `ClanWorld.sol:845-850`) until the next interface version bump removes the deprecated enum member.

## 3. Monument L7-L10 cost rationale

| Monument upgrade | Spec value | As-built canonical value |
|---|---|---|
| L1-L6 | Fixed table in `clanworld_v4_spec.md` §8.5 | Matches the table (`ClanWorld.sol:2735-2740`) |
| L7-L10 | "higher resources + `1e18` Blueprint Fragment"; resources tunable (`clanworld_v4_spec.md:933-938`) | Flat per level: `200 wood + 25 iron + 100 wheat + 1e18 Blueprint Fragment` (`ClanWorld.sol:2741`) |

The L7-L10 plateau is intentional tuning: it is strictly higher than L6 (`150 wood + 20 iron + 80 wheat`), preserves the locked blueprint gate, and keeps the late-game curve smooth enough that monument progress remains the exponential-growth target without making L9/L10 impossible during hackathon UAT.

## 4. Authoritative-as-of

This addendum is authoritative as of `origin/dev-phase-8-buildings` HEAD `2b92d85644526c39aaa65b47a90c5fb5baf450dc`.
