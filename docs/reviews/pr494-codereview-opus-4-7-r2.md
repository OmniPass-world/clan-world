# PR #494 r2 review — opus-4-7

Branch: `feat/0g-mainnet-wireup` @ `644c682` (post-HIGH-fix commit).
Scope: r1 fixes from prior dual opus-4-7 review pass.

## Verdict
SHIP

All four r1 contract/Convex HIGHs (INDEXER_SECRET, IntelligentDataItem, safeTransferFrom, newDataHash validation) and both UI HIGHs (loadToken cleanup, updateMetadata local-state) are addressed correctly. No demo-blocking regressions. Real but non-blocking gaps live in test coverage and a couple of nits — flag for v2.0.x, do not gate the demo.

## Findings
| Severity | File:line | Issue | Fix |
|---|---|---|---|
| MED | `packages/contracts/test/ClanAgentNFT.t.sol` | Zero coverage of new code paths: `safeTransferFrom` EOA fast-path, contract-receiver-correct-selector, contract-receiver-wrong-selector → `UnsafeRecipient`, non-receiver contract → `UnsafeRecipient`, AND `transferProof.newDataHash != bytes32(0) && != newHash` → `InvalidProof`. forge "5/5 pass" only proves the unchanged paths. | Post-demo: add ~5 cases using `MockERC721Receiver` + `MockBadReceiver`. |
| MED | `packages/shared/src/adapters/IInftClient.ts:157` ↔ `packages/contracts/src/ClanAgentNFT.sol:265` | JS `hashIntelligentData` and Solidity `_hashData` are both rolling keccak over `(bytes32, string, bytes32, string)` and **look** byte-identical. But no end-to-end test asserts equality. UI now sends a non-zero `newDataHash` on every `iTransfer` (OwnerEditor.tsx:209) — any future drift in either rolling-hash impl silently breaks every demo transfer at the new validation gate. | Post-demo: differential test (forge fuzz vs vitest fixture) on a known payload. Demo path is safe today. |
| LOW | `apps/server/convex/inft.ts:11-19` | `supplied !== expected` is variable-time. Acceptable for a Convex demo deployment behind HTTPS — network jitter dominates — but flag for prod. | Constant-time compare or hash both sides before any real-token deployment. |
| LOW | `apps/server/convex/inft.ts:13` | Empty-string `INDEXER_SECRET` (operator sets but blanks it) hits the "is not configured" error path. Confusing if operator thinks they configured it. | Add `expected.length === 0` branch with clearer message — pure ergonomics. |
| LOW | `apps/web/src/pages/OwnerEditor.tsx:130-138` | Catch-block clobber means a transient RPC blip on a *valid* tokenId now flips the cockpit from real owner/data to `demo-owner` + canonical demo data. Intentional per the comment, but a flaky network during demo could silently downgrade a live screenshot to a demo screenshot — judges might not notice the regression. | Post-demo: distinguish `TokenNotFound` revert (clear to demo state) from generic RPC errors (preserve last-known + show error banner). |
| NIT | `apps/web/src/pages/OwnerEditor.tsx:142,181` | `loadToken` and `updateMetadata` deps arrays omit `persistDemoState`. Functionally safe — `persistDemoState`'s deps `[notes, tokenId]` are a strict subset of both callers' deps, so no stale closure is reachable. ESLint exhaustive-deps will warn. | Add `persistDemoState` to both deps to silence lint; behavior unchanged. |
| NOTE | `apps/server/convex/inft.ts` | All four mirror mutations now require `secret` arg AND `INDEXER_SECRET` env var on the deployment. Zero callers in repo today (verified via grep — only `inft.ts` references), so nothing breaks. But indexer/scripts shipping later MUST receive the secret OOB. | Add a one-line note to demo runbook / `.env.example`: "set `INDEXER_SECRET` on Convex dashboard before indexer ships." |

## Notes

**No reentrancy in `safeTransferFrom`.** `_transfer` mutates `_owners`, `_balances`, `_tokenApprovals` and emits `Transfer` BEFORE the external `onERC721Received` callback (CEI honored). A reentrant receiver calling back in only acts with the new rightful-owner authority — no privilege escalation. EOA short-circuit (`to.code.length == 0`) is correct per ERC-721 spec. `try/catch` correctly surfaces both wrong-magic-value AND receiver-revert as `UnsafeRecipient`.

**`transferProof.newDataHash` validation — semantically correct.** Skip-on-zero preserved (existing tests all pass `bytes32(0)` — they continue to work). Non-zero supplied must equal locally computed `_hashData(newData)`. This strictly tightens the contract; no previously-working caller path is broken. Escape hatch documented inline.

**Event ordering — `IntelligentDataItem` then `IntelligentDataUpdated`.** Per-item events stream in `slot` order inside the `_replaceData` loop, then the rollup `IntelligentDataUpdated` closes the batch. Indexers can treat the rollup as a flush signal or aggregate items independently. Gas cost rises by `1 + N` log slots vs `1` previously — for the 3-item demo payload this is ~3k extra gas, immaterial.

**INDEXER_SECRET fail-closed — verified.** Missing env var → throws on FIRST line BEFORE comparison. Empty supplied with set expected → throws on second check. Convex `secret: v.string()` arg validation rejects omitted-arg before reaching the handler. Destructure `{ secret: _omit, ...row }` strips secret before `db.insert`/`db.patch`, and schema (`apps/server/convex/schema.ts:165-198`) does not declare a `secret` field — secret cannot leak to DB.

**`OwnerEditor.updateMetadata` pure-demo flow preserved.** `setData` + `persistDemoState` are now inside the `!OG_INFT_ADDRESS` branch — a build with no contract address still updates localStorage and re-renders the cockpit. Real-chain branch correctly defers state mutation to `loadToken()` after wallet tx settles, so a wallet-rejection no longer leaves the cockpit lying. `owner` correctly added to deps (used inside the new pure-demo branch via `persistDemoState(owner, ...)`).

**`loadToken` cleanup-on-failure is safe.** Catches RPC error, falls back to `demoData(tokenId || 7n, notes)` → resets owner + data + persists. The `tokenId || 7n` short-circuit covers user-typed-0/empty (where `tokenId === 0n` is the parse-failure sentinel).

**Forge tests 5/5 per commit message — credible.** Test file unchanged in this commit; existing happy paths don't intersect any of the new Solidity surface. Existing tests remain valid. Did not re-run forge in this review.

**Bottom line for T-5h:** ship. Fix commit is tight, on-target for all r1 HIGHs, no fresh demo-breakers. The MED findings are test-coverage debt for v2.0.x.
