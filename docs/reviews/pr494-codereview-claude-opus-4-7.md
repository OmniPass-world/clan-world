# PR #494 Review — claude-opus-4-7

**Scope:** `feat(0g): add iNFT demo flow` — full ERC-7857-style iNFT contract + deploy/mint/transfer scripts + Convex mirror + UI. 1716 added lines, 26 files. ~6h to demo.

## Verdict

**SHIP-WITH-FIXES** — no demo-breaker found, but 4 issues worth a 15-minute fix pass before recording, and 2 production-grade follow-ups for v2.0.x patches.

The mock verifier explicitly admits it isn't production crypto; the iNFT contract is functionally complete enough for demo; the deploy/mint/transfer scripts work end-to-end; the Convex indexer mirrors events. Demo path is fine.

## HIGH

| # | File:line | Issue | Fix |
|---|---|---|---|
| 1 | `apps/server/convex/inft.ts` (all `mirror*` mutations) | Convex `mirror*` mutations have **no caller validation**. Any client with the Convex deployment URL can spoof `inftTokens`/`inftTransfers`/`memoryEntries`/`bulletins` rows. For demo on-stage that's exposure if URL leaks; for prod it's a real vector. | Add a shared secret or signed-payload check, OR move the mirror calls behind an internal-only Convex function callable from the indexer service only. For demo: scope the Convex deploy URL to private. |
| 2 | `packages/contracts/src/ClanAgentNFT.sol:224` | `_replaceData` emits `IntelligentDataUpdated(tokenId, newHash, data[0].uri)` — only the **first item's URI** is in the event, but `newHash` covers all N items. Indexers/UI tracking "current iNFT URI" will silently drift when `data.length > 1` (which the mint script always uses — `persona`/`memory`/`owner_notes` = 3 items). | Either: emit one event per data item (loop), OR change the third arg to a stable representation (e.g. `data[0].uri` is fine if the contract documents "URI is item-0 by convention"), OR move the URI list off-chain entirely. For demo: pick a canonical "primary" item and document it. |
| 3 | `packages/contracts/src/ClanAgentNFT.sol:160-163` (`transferFrom`) and entire contract | **No `safeTransferFrom`.** Tokens transferred to a contract that isn't an `IERC721Receiver` can become permanently locked. Mainnet OZ has both. Demo path is EOA-to-EOA so unaffected, but ANY contract destination during demo recording = stuck. | Add `safeTransferFrom` overloads with `IERC721Receiver` callback before mainnet. For demo recording: confirm both `INFT_OWNER` and `INFT_NEW_OWNER` are EOAs. |
| 4 | `packages/contracts/script/TransferClanAgent.s.sol:38` + contract `iTransfer` | `TransferProof.newDataHash` is set to `bytes32(0)` in the script. The contract never reads `transferProof.newDataHash` (it computes `newHash` locally on line 173 and passes that to the verifier). Field is **dead**. Either the contract should require `transferProof.newDataHash == newHash` (intent: prevent UI/contract drift), or the field should be removed from the struct. Risk: future readers assume it's authoritative. | Either drop the field, or add `if (transferProof.newDataHash != bytes32(0) && transferProof.newDataHash != newHash) revert InvalidProof();` |

## MEDIUM

| # | File:line | Issue | Fix |
|---|---|---|---|
| 5 | `packages/contracts/src/ClanAgentNFT.sol:204-214` (`_transfer`) | `usageAuthorizations[tokenId][...]` and `delegatedAccess[tokenId]` mappings persist across transfers. New owner inherits the previous owner's authorizations — surprising for a "transfer = clean slate" model. | Clear `delegatedAccess[tokenId]` and any tracked auth users in `_transfer`. Tracking the auth list requires an `EnumerableSet` or per-tokenId enumerable mapping. For v2.0.x. |
| 6 | `packages/contracts/script/MintClanAgent.s.sol:18-29` & `TransferClanAgent.s.sol:18-29` | `dataHash = keccak256(abi.encodePacked(tokenId, label, uri))` — fully deterministic per (token, label, uri). No nonce, no timestamp, no chain id. Re-running the script produces an identical hash, which is fine for demo but trivially replayable in any "prove the data changed since N" model. | For demo: leave it. For prod: mix in `block.timestamp` or a counter, OR derive from actual encrypted blob bytes. |
| 7 | `packages/contracts/src/ClanAgentNFT.sol:109` (`setApprovalForAll`) | Reverts when `operator == msg.sender`. ERC-721 spec allows self-approval as a no-op or true. OpenZeppelin's reference implementation accepts it. Tooling that does `setApprovalForAll(myself, true)` to mark "I approve everything I own" will revert. | Either remove the check or replace `revert InvalidAddress()` with a no-op return. |

## LOW (skim, optional)

- `_balances[from] -= 1` (line 209) — not actually a bug because `_transfer` checks ownerOf == from on line 205, but worth a one-line comment so a future reader doesn't think the underflow is unguarded.
- `IntelligentTransfer` event emits `transferProof.newUri` but the contract just stored `data[*].uri` per item — the event-side URI is operator-supplied and unverified. Not a security bug; readers may be confused.
- `Mock7857Verifier.verifyTransfer` returns `true` on a single happy-path check that all fields are non-zero. As long as the demo passes non-zero field values (which the script does), it always passes. That's the documented intent.

## Notes

- **Smoke test blocker is unrelated to this PR's iNFT scope** — `infra/0g/smoke-test.ts` fails on FLOW_CONTRACT submit even with correct mainnet address (verified by direct chain probe: `flow.market()` returns valid market contract, `pricePerSector()` returns expected value). Looks like an SDK 0.3.3 estimateGas issue or a Market contract permission gate. Recommend testnet path or file fallback for demo. **This is a separate issue from the iNFT work.**
- The contracts/ABI/event design is **internally consistent** with the Convex schema additions and the UI tabs — no signature drift between layers found.
- The Convex schema changes (`inftTokens`/`inftTransfers`/`memoryEntries`/`bulletins`) all have appropriate indexes for the read patterns in `getInftDemoState`. ✓
- `Mock7857Verifier` is explicitly documented as not production crypto. Fair for demo.

## Pre-record checklist (15 min)

- [ ] HIGH 1 — gate Convex mirror mutations OR confirm Convex deploy URL is private
- [ ] HIGH 2 — pick a canonical "primary" data item for `IntelligentDataUpdated.uri` (or accept multi-emit)
- [ ] HIGH 4 — drop `TransferProof.newDataHash` field OR validate it
- [ ] Confirm `INFT_OWNER` and `INFT_NEW_OWNER` env vars in your demo deployment are EOAs (no contract addresses) so HIGH 3 doesn't bite

Defer MEDIUM 5/6/7 to v2.0.x patch.
