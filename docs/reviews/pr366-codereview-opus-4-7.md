# Super-Swarm Review — PR #366 (head c3edc37) — Phase 9B follow-up bundle

## SUMMARY
**CLEAN — recommend MERGE.** All five bundle items verified end-to-end: storage overload of `_lootValueRaw` is safe (all call sites pass storage refs in read-only contexts; memory callers correctly inlined), tick-semantics standardization is consistent across every death-linked event emission site (closedTick in heartbeat, caller-provided historical tick in lazy-settlement, with the IClanWorld NatSpec documenting both), and the strict `Number.parseInt` precheck mirrors the established PR #295 `submitOrders` pattern. Full forge suite: 133/133 green (more than the 92 quoted; suite expanded). One LOW finding on heartbeat NatSpec wording for step 3 — non-blocking but a clean follow-up.

## HIGH severity findings
CLEAN — no findings

## MEDIUM severity findings
CLEAN — no findings

## LOW severity findings

### L1 — Heartbeat NatSpec step 3 wording is slightly inaccurate
**File:** `packages/contracts/src/ClanWorld.sol:2300`
**Issue:** The new doc block says step 3 is "Eager-settle clans touched by world events this tick", but the function actually called is `_eagerSettleForBandits(closedTick)` (line 2323), which exclusively eager-settles bases and active defenders in bandit spawn-candidate regions before bandit timer/attack/spawn resolution. The function does *not* settle for season/winter or market-driven world events. The inline comment at line 2322 is accurate; only the NatSpec block at line 2300 misdescribes.
**Suggested:** Replace step 3 line with something like "Eager-settle bases and active defenders in bandit spawn-candidate regions." Doc-only — defer or fix in a follow-up.

### L2 — Style inconsistency in `IChainClient.ts` parseInt usage
**File:** `packages/shared/src/adapters/IChainClient.ts`
**Issue:** `submitOrders` (line 79) uses `parseInt(clanId, 10)`; `getClanFullView` (line 167) uses `Number.parseInt(clanId, 10)`. Functionally identical (the global `parseInt` *is* `Number.parseInt`), but the file now reads inconsistently. PR description claimed the change "mirrors PR #295 `uintValue` pattern" — fine, but the pattern is the regex precheck, not the `Number.` prefix. Either align both to `Number.parseInt` or both to `parseInt`. Cosmetic.

### L3 — Strict regex precheck accepts negative integers
**File:** `packages/shared/src/adapters/IChainClient.ts:167-170`
**Issue:** `String(parsedClanId) !== clanId.trim()` accepts strings like `'-1'` (since `String(-1) === '-1'`). Viem will reject the negative on uint32 encode, so this is caught downstream — informational only. If the spec intent was "positive decimal integer," tighten the check to a regex (e.g. `/^[1-9]\d*$/`). Not blocking; matches PR #295 pattern exactly.

## Cross-cutting observations

- **Storage overload (#330) — verified safe.** The four storage call sites of `_lootValueRaw` (`ClanWorld.sol:1713`, `:2248`, `:3402`, `:3466`) all pass `Clan storage` references inside read-only contexts (loop scans / external `view` getters). No caller mutates the struct between reads, so storage aliasing is irrelevant. The two memory callsites (`quoteLootValueSettled` and `_derivedClanStateFromSimulation`) were correctly inlined per commit `e0024bd` to resolve the overload ambiguity that arose when only the storage version remained. The `pure` → `view` mutability shift on the helper is correct because storage reads are not pure.
- **Tick semantics (#328b) — uniformly closedTick (replay-deterministic).** `_abortBanditAttacksForDeadTarget(deadClanId, excludedBanditId, tick)` now takes a tick parameter and emits `BanditEscaped`/`BanditTargetDied` with it. All call paths (`_markClanDead` from starvation at `:500` passes settlement tick; from bandit kill at `:2026` passes `_world.currentTick` which equals closedTick by the `require` at `_resolveBanditAttack:1761`). All other death-linked emit sites in the file (`:1682`, `:1775`, `:1785`, `:1830`, `:1837`) emit `closedTick` directly within `_resolveAttackingBandits`. No mixed-tick contamination remains. Test `test_deadTargetCleanupReleasesDefendersAndEscapesBandit` correctly asserts `winterStart + 3` (the tick the last clansman dies during 4-tick replay), proving the lazy-settlement path emits the historical tick rather than `_world.currentTick`. Indexer implication: any consumer that previously assumed `BanditEscaped.atTick == _world.currentTick` will now see closedTick — this is the desired behavior per the `IClanWorld.sol:599-601` doc, but indexers should be reviewed if they pinned timestamps to the old assumption.
- **NatSpec accuracy (#329) — header accurate; heartbeat doc accurate except for step 3 (see L1).** The Phase-9 declaration at `:44-48` correctly drops the "Phase 3 stubbed" sentence. The 8-step heartbeat block enumerates every action in the actual function body in the right order; the inline per-step comments inside `heartbeat()` are precise. Only the step-3 paraphrase in the doc block drifts from what the code does.
- **Placeholder annotations (#328a) — sufficient.** `getActiveBanditView` at `:3571-3589` has a block comment plus per-field inline comments for `attackAttemptsMade`, `maxAttemptsRemaining`, `projectedTargetLootValue`. A future implementer scanning the function would have to actively ignore three independent comments to ship them as truthy. Adequate.
- **Test coverage.** Forge suite: 133/133 green (BanditAttackResolution 19/19, full repo all suites pass). Doc-only items (#329, #328a) appropriately have no tests. The TS `getClanFullView` precheck has no unit test — consistent with hackathon coding rules ("minimal tests only") and matches the no-test treatment of the identical pattern in `submitOrders`.
- **No regressions surfaced.** Pre-existing forge-lint notes (asm-keccak256, one unsafe-typecast at `:2076`) are unrelated to this bundle.

Recommend merging this bundle. L1 is worth a one-line fix in a follow-up; L2/L3 are informational.
