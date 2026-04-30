I've verified the actual code. The first agent's "critical ordering bug" claim was incorrect — the code at line 1448-1449 explicitly handles this: `_completeMission` only sets `m.active = false` (preserving `m.action` and `m.nonce`), and `_executeScheduledMarketActions` validates via `m.action`/`m.nonce` instead of `m.active`. The 226 tests passing confirms this works.

Now writing the final review.

# Super-Swarm Review — PR #357 (head 79879ce) — Phase 6B spec cleanup

## SUMMARY

**CLEAN — RECOMMEND MERGE.** The PR cleanly executes three orthogonal spec-alignment fixes audited by PR #350. Verified directly against `ClanWorld.sol`: enum ordinal stability holds (ERR_SLIPPAGE_REQUIRED at 31, asserted at `StatusCodeEnumStability.t.sol:40`), the `_completeMission`/scheduled-execution interaction is intentional and explicitly documented at `ClanWorld.sol:1447-1449` (queue uses `m.action`/`m.nonce` not `m.active`), all 8 new pool-seed constants are wired through every call site, and the `maxGoldIn==0` guard sits in a `view` function with no state mutation before its early return. Two LOW nits below — none block merge.

## HIGH severity findings

CLEAN — no findings.

(Verified the most suspicious cross-cutting concern: setting `settlesAtTick = arrivalTick` for markets means `_settleCompletingMissions(closedTick)` runs `_resolveAction` → `_completeMission` BEFORE `_executeScheduledMarketActions(closedTick)` runs the swap. This is *intentional* — `_completeMission` (`ClanWorld.sol:895-900`) only clears `m.active`, leaving `m.action` and `m.nonce` intact, and the queue's stale-retask check at `ClanWorld.sol:1450-1461` reads exactly those two fields with an explicit comment acknowledging the design. Cooldown is wall-clock (`block.timestamp + COOLDOWN_SECONDS`), not tick-derived, so the 1-tick reduction has zero cooldown impact. `_executeMarketBuy`/`_executeMarketSell` (1940-1992, 1996+) operate purely on `cs.carryXXX` and `clan.goldBalance` — they don't read mission state. `_handleMarketFailure` re-setting state=WAITING + cooldown is idempotent within the same block. 226 tests pass and `HeartbeatOrdering.t.sol` was updated coherently — `test_heartbeat_settlementBeforeMarket` and `test_heartbeat_multipleStepsInOneTick` now assert market `settlesAtTick == arrivalTick == t0+2` and pass.)

## MEDIUM severity findings

CLEAN — no findings.

Specifically verified and confirmed safe:
- **Slippage guard placement** (`ClanWorld.sol:2183-2186`): runs inside `_validateAction` (a `view` function), after token-allowlist + zero-amount checks, before carry-cap. Returns `ERR_SLIPPAGE_REQUIRED` with no storage mutation possible — no reentrancy or atomicity hole. Single external entry (`submitClanOrders` → `_processOrder` → `_validateAction`) covers BOTH immediate and scheduled paths uniformly, so it is not bypass-able via the propose path.
- **MarketSell asymmetry**: confirmed intentional. `ClanOrder` has only `maxGoldIn` (no `maxGoldOut`); `ScheduledMarketAction.maxGoldIn` comment says "buy only, 0 otherwise". Sell is exact-input, so no analogous slippage var exists in the order ABI — adding one is a future spec change, not a Phase 6B concern.
- **Pool seed migration**: zero leftover references to `INITIAL_RESOURCE_POOL_SEED` / `INITIAL_GOLD_POOL_SEED` anywhere in the repo (contracts, tests, deploy script, ts/tsx workspaces, docs). Spec §5.11 (`docs/planning/clanworld_v4_spec.md:602-606`) matches the new constants exactly.
- **Enum stability**: `ERR_SLIPPAGE_REQUIRED` appended at index 31 in both `IClanWorld.sol:190` and `StatusCodeEnumStability.t.sol:40`. `ERR_MAX_GOLD_IN_EXCEEDED` remains at 30. ABI ordinal-stable.

## LOW severity findings

1. **Test coverage gap — scheduled (traveling) MarketBuy with `maxGoldIn==0`**: `test_marketBuy_zeroMaxGoldInRejectsAtSubmit` (`ClanWorld.t.sol:1070`) covers the case where the clansman is already WAITING in Unicorn Town. The guard sits in `_validateAction` which runs before the immediate-vs-scheduled fork, so the behavior is provably the same for a traveling clansman — but an explicit `test_scheduledMarketBuy_zeroMaxGoldInRejectsAtSubmit` would be cheap to add and would close a small audit-coverage gap. Defer-OK.

2. **Test coverage gap — asymmetric pool spot prices**: existing tests read the new constants but never assert `getMarketState()` returns the spec's distinct spot-price ratios (wood=0.5, wheat=0.7, fish=1.2, iron=3.2 gold/resource). A 1-shot post-seed assertion would lock in §5.11 conformance against future drift. Defer-OK.

3. **Pre-existing `swapExactInForOut(amount, 1)` literal-`0` drift** (out of scope for #357): the audit that drove this PR also flagged `ClanWorld.sol:~1810` passing `1` instead of literal `0` for `minOut` on immediate sells (spec §5.9 says `minAmountOut = 0`). Trivial wording-only divergence; explicitly listed as cleanup item #3 in the audit's Path A. Mention here so it's not lost; not part of this PR by design.

## Cross-cutting observations

- The 1-tick `settlesAtTick` reduction for markets is the most architecturally risky change in the PR, and it lands cleanly because the codebase already designed for it: the comment at `ClanWorld.sol:1447-1449` ("_completeMission sets m.active=false during settlement (by design), so we cannot use m.active as a validity signal here — check action type and nonce") shows the queue/mission decoupling pre-dates this PR. The change just exercises the existing invariant at one tick earlier.
- No fresh-deploy migration concerns: per `CLAUDE.md` "this codebase has no production users yet, break things freely" — pre-PR queued actions with `maxGoldIn=0` cannot exist in any environment that matters. On a clean redeploy of testnet pools, no orphan-queue risk.
- Documentation: PR #350 audit branch (`docs/spec-audit-phase-6`) exists separately and describes the *pre-fix* state; no conflict with this PR. Spec §5.11 already matches the new constants verbatim, so no spec doc update is needed in this PR. `docs/reviews/pr357-codereview-codex-5-5.md` carries empty HIGH/MEDIUM sections; `docs/reviews/pr357-codereview-opus-4-7.md` is a 0-byte placeholder (worth either populating or `git rm` before merge — cosmetic).

**Verdict: ship it.**
