# PR #137 Review — merge: bundle E — Phase 2 economy (#91 post-rebase)

| Field | Value |
|-------|-------|
| **PR** | [#137](https://github.com/OmniPass-world/clan-world/pull/137) |
| **Branch** | `merge/bundle-e` → `dev` |
| **Author** | claude-do |
| **Review date** | 2026-04-28 |
| **Review model** | Claude Opus 4.6 |
| **Method** | 10-agent swarm (7 parallel Wave 1 + 3 parallel Wave 2) |

## PR Summary

Implements Phase 2 economy: constant-product AMM pool (`StubPool`), market sell/buy execution, FIFO scheduled queue with commit-sequence ordering, treasury initialization, and pool seeding. Touches 6 files in `packages/contracts/`, +804/−31 lines. Self-assessed as **medium risk** — substantial Solidity additions (AMM math, scheduled queue, `via_ir = true`).

Previously reviewed in R1 and R2 rounds (fixes preserved in rebase): heartbeat try/catch, stale queued action invalidation, ceiling division overflow safety, market events with realized amounts, test naming.

### Files changed

| File | +/- | Change |
|------|-----|--------|
| `packages/contracts/foundry.toml` | +1/−0 | `via_ir = true` for stack-depth relief |
| `packages/contracts/script/Deploy.s.sol` | +9/−9 | Deploy ordering: ClanWorld before pools |
| `packages/contracts/src/ClanWorld.sol` | +325/−15 | initTreasury, seedPools, scheduled market actions, FIFO queue, heartbeat execution |
| `packages/contracts/src/StubPool.sol` | +70/−4 | Upgraded from address-only stub to real constant-product AMM |
| `packages/contracts/test/ClanWorld.t.sol` | +397/−1 | 7 new Phase 2 tests (23 total green) |
| `packages/contracts/test/ClanWorldStub.t.sol` | +2/−2 | Minor test fixture updates |

---

## Review Agents

| Wave | Agent | Role | Key result |
|------|-------|------|------------|
| 1 | Correctness & Logic | Line-by-line bug hunting, state transitions | 3 confirmed issues + 2 false positives (resolved in Wave 2) |
| 1 | Security & Access Control | Reentrancy, access control, overflow, MEV, DOS | 3 actionable, 2 deferred, reentrancy confirmed safe |
| 1 | AMM Math & Economics | Constant-product formulas, rounding, K-invariant | All formulas correct; 2 economic concerns flagged |
| 1 | Architecture & Integration | Deploy script, interface compliance, cross-file | PoolsSeeded event mismatch, deploy script incomplete |
| 1 | Test Coverage & Quality | Feature-to-test mapping, gap analysis | Coverage adequate for hackathon; 6 gaps noted |
| 1 | Gas & Performance | Storage patterns, unbounded loops, via_ir | Unbounded queue is the main functional risk |
| 1 | Style, Conventions & Docs | NatSpec, naming, commits, PR body | Stale Phase 2 "stubbed" comments, initTreasury not on interface |
| 2 | Cross-cutting Conflict Resolution | Resolved vault-deduction-before-call dispute | Agent 1 false positive: external self-call rolls back state |
| 2 | FIFO Queue & Stale Guard Deep Dive | Same-type mission replacement scenarios | CONFIRMED: stale guard incomplete for same-type replacement |
| 2 | Economic Invariant Verification | Gold/resource conservation, K-invariant, pool freeze | All conservation invariants hold; sell-side freeze is theoretical |

---

## Triage Table

| # | File | Line | Finding | Category |
|---|------|------|---------|----------|
| 1 | `src/ClanWorld.sol` | 991–1057 | **Stale queue guard incomplete for same-type mission replacement.** `ScheduledMarketAction` has no `missionNonce` field; the guard only checks `m.action != sma.action`. Replacing MarketSell→MarketSell (different token/amount) leaves the old queue entry valid with stale parameters. Old entries execute with wrong token/amount, causing incorrect vault debits. Confirmed by Agents 1, 9. | **MUST FIX** |
| 2 | `src/ClanWorld.sol` | 1366–1371 | **`PoolsSeeded` event emission order mismatched vs `IClanWorld`.** Interface declares `(wood, wheat, fish, iron)` but implementation emits `(wood, iron, wheat, fish)`. Args 2–4 are swapped. Off-chain indexers decoding by position assign wrong pool addresses. Confirmed by Agents 1, 4, 8. | **SHOULD FIX** |
| 3 | `src/ClanWorld.sol` | 991–1075 | **Unbounded per-tick market queue.** No cap on `_scheduledMarketActions[tick].length`. `mintClan` is permissionless (no fee), so an attacker can create many clans and schedule many actions for the same tick. `heartbeat` iterates the full array — risk of OOG revert stalling progression. Confirmed by Agents 2, 6. | **SHOULD FIX** |
| 4 | `src/ClanWorld.sol`, `src/IClanWorld.sol` | 1331–1350 | **`initTreasury` not declared on `IClanWorld`.** Required lifecycle step missing from canonical interface. Typed clients that code against the interface miss this mandatory call before `seedPools`. Confirmed by Agents 2, 4, 7. | **SHOULD FIX** |
| 5 | `src/ClanWorld.sol` | 7–13 | **Contract-level NatSpec still says "Phase 2 … are stubbed."** Phase 2 scheduling and AMM execution are now implemented. Misleading for readers and NatSpec-consuming tools. Confirmed by Agents 4, 7. | **SHOULD FIX** |
| 6 | `src/ClanWorld.sol` | 1378–1394 | **OTC transfer functions still `revert("... Phase 2")`.** The string "Phase 2" is misleading now that Phase 2 market economy is implemented. Should clarify these are OTC-specific stubs. Agent 7. | **SHOULD FIX** |
| 7 | `script/Deploy.s.sol` | 30–46 | **Deploy script never calls `initTreasury` / `seedPools`.** Deployments using only this script leave the market offline (`poolsSeeded = false`). Operator must run separate transactions. Agent 4. | **SHOULD FIX** |
| 8 | `src/ClanWorld.sol` | 1060–1072 | **Catch-all `ERR_INVALID_ACTION` masks real failure modes.** All pool reverts, math errors, slippage failures, and missing-resource errors collapse to the same status code. Undermines debugging, monitoring, and UX. Confirmed by Agents 1, 2, 7. | **SHOULD FIX** |
| 9 | `src/ClanWorld.sol` | 1655–1663 | **`spotPriceGoldPerResource` can overflow.** `rB * 1e18` overflows if `reserveB` exceeds `~1.15e59`. Pathological for typical seeds but a sharp edge for view-layer availability. Agent 2. | **SHOULD FIX** |
| 10 | `src/ClanWorld.sol` | 1296–1320 | **Market token validation skipped before `initTreasury`.** If treasury is uninitialized, `marketToken` checks are bypassed. Orders enqueue with bogus tokens; execution fails later but queue state is wasted. Agent 2. | **SHOULD FIX** |
| 11 | `src/IClanWorld.sol` | 362–367 | **No sell-side slippage protection.** Only buys carry `maxGoldIn`. Sellers have no on-chain worst-case proceeds guarantee. Agents 3, 10. | **DEFER** |
| 12 | `src/StubPool.sol` | 43–49 | **Pool can become one-sided unusable.** Repeated sells can drain gold reserves to dust, causing `require(goldOut > 0)` to revert on all subsequent sells. Buys can recapitalize but require clan gold. Agents 3, 10. | **DEFER** |
| 13 | `script/Deploy.s.sol` | 15–35 | **Deploy script comment numbering inconsistent.** Steps labeled 1, 3, 2 instead of 1, 2, 3. Agents 4, 7. | **DEFER** |
| 14 | `foundry.toml` | 8 | **`via_ir = true` applies to all contracts.** Should be scoped to a profile or documented. Slows compilation. Agents 4, 6. | **DEFER** |
| 15 | `src/ClanWorld.sol` | 1078–1103 | **Leading underscore on `external` functions.** `_executeMarketSellExternal` / `_executeMarketBuyExternal` use internal naming convention on external visibility. Justified by try/catch pattern but unconventional. Agent 7. | **DEFER** |
| 16 | `src/IClanWorld.sol` | 692–693 | **Interface NatSpec wording drift.** `seedPools` says "deploy time" but requires `initTreasury` first. Agent 7. | **DEFER** |
| 17 | `test/ClanWorld.t.sol` | — | **`getMarketState()` never tested.** Pool reserves and queue state view function has no test coverage. Agent 5. | **DEFER** |
| 18 | `test/ClanWorld.t.sol` | — | **Stale action invalidation path untested.** The `m.action != sma.action` continue branch has no dedicated test. Agent 5. | **DEFER** |
| 19 | `test/ClanWorld.t.sol` | — | **Double-init and access control guards untested.** `initTreasury` and `seedPools` revert-on-repeat and owner-only restrictions lack explicit tests. Agent 5. | **DEFER** |
| 20 | — | — | **MEV / front-running against scheduled ticks.** Scheduled actions are public; attackers can reorder transactions. Standard AMM/game expectation, not a single-contract bug. Agent 2. | **DEFER** |
| 21 | `src/ClanWorld.sol` | 1655–1663 | **Spot price oracle is manipulable.** Instantaneous midpoint, not TWAP. Acceptable if clients don't treat it as an ungameable price feed. Agents 3, 10. | **DEFER** |
| 22 | `src/StubPool.sol` | 46, 57–58 | **`reserveB * amountIn` overflow on extreme values.** Checked math reverts on overflow — DOS for unrealistic magnitudes, not fund loss. Agent 3. | **DEFER** |
| 23 | `src/ClanWorld.sol` | 1207–1224 | **Buy path double-reads pool reserves.** `quoteBuy` then `buyResource` both read reserves. Minor gas overhead. Agent 6. | **DEFER** |
| 24 | `src/ClanWorld.sol` | 1156–1199 | **Treasury SLOAD caching opportunity.** Multiple `_treasury.*` reads per execution. Could cache storage pointer. Agent 6. | **DEFER** |
| 25 | `test/ClanWorld.t.sol` | 538–539 | **Stale comment about "second clansman".** Test only uses one clansman for buy; comment misleads. Agent 5. | **DEFER** |
| 26 | `src/ClanWorld.sol` | 1147–1185 | **Vault deduction before pool call loses resources on revert.** Agent 1 flagged as MUST FIX. **FALSE POSITIVE** — Agent 8 verified: `try this._executeMarketSellExternal(...)` is an external self-call; if `sellResource` reverts, the entire external frame (including `_deductFromVault`) is rolled back. The catch runs in the caller's frame with pre-try state. | **SKIP** |
| 27 | `src/StubPool.sol` | 43–49 | **`require(goldOut > 0)` revert on small sells causes resource loss.** Same root cause as #26. The external self-call pattern rolls back all state including vault deductions. **FALSE POSITIVE.** | **SKIP** |
| 28 | `src/StubPool.sol` | 43–74 | **Constant-product formula correctness.** Verified: `sellResource` implements `dy = floor(y·dx/(x+dx))`, `buyResource` implements `goldIn = ceil(y·amountOut/(x−amountOut))`. Both correct. Agent 3. | **SKIP** |
| 29 | `src/StubPool.sol` | 54–73 | **`quoteBuy` / `buyResource` math consistency.** Verified: identical formula, view matches charging path. Agent 3. | **SKIP** |
| 30 | `src/StubPool.sol` | 43–74 | **K-invariant preservation.** Verified: floor on output (sell) and ceil on input (buy) both preserve or increase K. Rounding favors the pool/protocol. Agents 3, 10. | **SKIP** |
| 31 | `src/ClanWorld.sol` | 1059–1103 | **Reentrancy via external self-call.** Verified safe: `StubPool` has no callbacks into `ClanWorld`; `onlyEngine` restricts all mutating pool functions. Replacing `StubPool` with malicious code is an owner trust issue. Agent 2. | **SKIP** |
| 32 | `src/ClanWorld.sol` | 991–1006 | **FIFO queue ordering / cross-clan manipulation.** Verified correct: `commitSequence` is globally monotonic; clans cannot submit orders for other clans; push order matches FIFO. Agents 2, 9. | **SKIP** |
| 33 | `test/ClanWorld.t.sol` | 27–29 | **Test isolation.** Verified sound: fresh `ClanWorld` per test in `setUp`; `_setupMarket` redeploys tokens/pools. Agent 5. | **SKIP** |
| 34 | — | — | **Gold conservation.** Verified: gold is created only via `mintClan` starter gold and iron mining RNG. Market swaps transfer gold between clan balance and pool reserves with no leak. Agent 10. | **SKIP** |
| 35 | — | — | **Resource conservation.** Verified: sell deducts exact `amount` from vault, pool receives same; buy receives exact `amountOut` from pool, vault credits same. Agent 10. | **SKIP** |

---

## Summary Stats

| Category | Count |
|----------|-------|
| **MUST FIX** | 1 |
| **SHOULD FIX** | 9 |
| **DEFER** | 15 |
| **SKIP / FALSE POSITIVE** | 10 |
| **Total** | 35 |

---

## Key Wave 2 Resolutions

### False Positive: Vault deduction before pool call (Findings #26, #27)

Agent 1 (Correctness) flagged `_executeMarketSell` deducting vault resources before calling `StubPool.sellResource` as a MUST FIX — claiming that if the pool reverts, resources are permanently lost.

**Agent 8 definitively resolved this as a false positive.** The execution path uses `try this._executeMarketSellExternal(...)`, which is an **external self-call** (`CALL` opcode to `address(this)`). Both `_deductFromVault` and `StubPool.sellResource` run inside this external call frame. If `sellResource` reverts, **all state changes in that frame — including the vault deduction — are rolled back**. The `catch` block executes in the original caller's frame with pre-try state intact.

### Confirmed: Stale queue guard incomplete (Finding #1)

Agent 9 traced five scenarios and confirmed Agent 1's concern: replacing a MarketSell mission with a different MarketSell (different token or amount) does **not** invalidate the old queue entry. The guard checks only `m.action != sma.action`, which passes `true` (both are `MarketSell`). The old entry executes with stale parameters. Cross-type replacement (MarketSell → Gather) is correctly handled.

### Verified: Economic invariants hold (Findings #34, #35)

Agent 10 confirmed gold and resource conservation, K-invariant preservation, and that `reserveB == 0` is effectively unreachable (though the sell side can freeze at dust levels).

---

## Recommended Next Steps

### 1. Address MUST FIX (blocking merge)

**Finding #1: Stale queue guard.** Add a `missionNonce` field to `ScheduledMarketAction` and check it against `_missions[clansmanId].nonce` during execution. Alternatively, remove superseded queue entries when installing a replacement market mission (more gas but simpler invariant). This is the only merge-blocking issue.

### 2. Address SHOULD FIX (before merge)

Priority order:

1. **#2 PoolsSeeded event order** — Swap emit args to match `IClanWorld` declaration: `(wood, wheat, fish, iron)`
2. **#3 Unbounded queue** — Add a per-tick cap or total clan cap. Even a generous limit (e.g., 100 actions/tick) prevents OOG grief
3. **#4 initTreasury on IClanWorld** — Add to interface for typed client discoverability
4. **#8 Catch-all error code** — Add 2–3 specific status codes (ERR_MISSING_RESOURCES, ERR_NOT_ENOUGH_GOLD, ERR_SLIPPAGE_EXCEEDED)
5. **#5, #6 Stale comments** — Quick fix: update NatSpec and OTC revert strings
6. **#7 Deploy script** — Add `initTreasury` + `seedPools` calls (or document as intentionally separate)
7. **#9 Spot price overflow** — Use `mulDiv`-style arithmetic or saturate
8. **#10 Market validation pre-init** — Reject market orders when `_treasury.woodToken == address(0)`

### 3. DEFER items (new GitHub issues)

Group by theme for follow-up issues:
- **Economic UX**: #11 (sell-side slippage), #12 (pool freeze), #20 (MEV), #21 (oracle manipulation)
- **Gas optimization**: #14 (via_ir scoping), #22 (overflow DOS), #23 (double reads), #24 (SLOAD caching)
- **Test coverage**: #17 (getMarketState), #18 (stale action path), #19 (double-init guards)
- **Code hygiene**: #13 (deploy comments), #15 (naming convention), #16 (NatSpec drift), #25 (stale test comment)

---

## Overall PR Health Assessment

**Verdict: NEEDS WORK — one MUST FIX, nine SHOULD FIX**

The core AMM math is **correct and economically sound** — constant-product formulas, rounding, K-invariant all verified. The try/catch external self-call pattern for atomic market execution is **well-designed**. Test coverage is **adequate for hackathon standards**. Gold and resource conservation **hold**.

The single blocking issue is the **incomplete stale queue guard** (Finding #1): same-type mission replacement can cause stale market actions to execute with wrong parameters. This is a correctness bug that affects fairness and economic integrity.

The nine SHOULD FIX items are individually minor but collectively represent rough edges that could cause integration issues (event order mismatch, missing interface method), operational risk (unbounded queue, deploy script gaps), and developer confusion (stale comments, generic error codes).

After fixing Finding #1 and addressing the SHOULD FIX items, this PR should be merge-ready.
