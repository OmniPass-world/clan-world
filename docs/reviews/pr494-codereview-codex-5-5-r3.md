I reviewed HEAD `644c682` with `git show` and read the three requested files. The write was blocked by the read-only sandbox, so I could not create `docs/reviews/pr494-codereview-codex-5-5-r3.md`.

Here is the exact terse review content:

```md
# PR #494 Codex 5.5 R3 Review

## Findings

| Severity | Location | Issue | Recommendation |
|---|---|---|---|
| HIGH | `apps/web/src/pages/OwnerEditor.tsx:164-175` | Real-chain metadata refresh still happens before confirmation. `writeContract()` returns the tx hash after submission, not after mining, so the immediate `await loadToken()` can re-read old chain state and leave the UI stale after a successful tx. This contradicts the new comment and can make the demo look like Update Metadata did nothing. | After `writeContract`, call `await publicClient.waitForTransactionReceipt({ hash: tx })` before `loadToken()`. Same pattern should be applied to `transferToken` at `OwnerEditor.tsx:199-217`, though that bug predates this commit. |

## Targeted Checks

- `safeTransferFrom`: OK. It transfers first, then checks `onERC721Received`; revert restores state, EOA fast path is correct, wrong selector/revert fail as `UnsafeRecipient`.
- `INDEXER_SECRET`: OK. Required by all four mirror mutations, missing Convex env fails closed, omitted arg fails validation, and `secret` is stripped before DB writes.
- `OwnerEditor` stale-state cleanup: load failure now clears prior token state, but the real-chain success path still needs receipt waiting before refresh.
- `IntelligentDataItem` order: OK. Items emit in slot order inside `_replaceData`, then `IntelligentDataUpdated` emits as the rollup/flush event.

## Verdict

Not GREEN yet: one demo-visible HIGH remains in `OwnerEditor`.
```
