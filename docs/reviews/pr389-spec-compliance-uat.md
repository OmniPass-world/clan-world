# PR 389 Phase 7 Spec Compliance + UAT

## Scope

Phase 7 implements the v4 direct OTC transfer surface and clan ownership handoff:

- `transferGold`
- `transferVaultResource`
- `transferBlueprint`
- `transferBundle`
- `transferClanOwnership`

Deprecated proposal/accept escrow mechanics are intentionally not present. OTC negotiation remains social/off-chain or agent-mediated; settlement is a direct owner-authorized transfer.

## Spec Alignment

| Area | Expected behavior | Implementation status |
| --- | --- | --- |
| Direct OTC transfers | Sender clan owner can transfer gold, vault resources, blueprints, or bundles directly to another clan. | Matches. |
| Dead clan restriction | Dead sender cannot transfer; dead recipient can receive. | Matches v4.3 outbound-only restriction. |
| Settlement freshness | Transfers cannot execute against partially settled clans after the lazy-settlement cap. | Matches via `ClanWorld: must settle first`. |
| Invalid resource enum | Invalid resource values must not fall through to fish. | Matches via explicit invalid-resource revert. |
| Atomic bundle | Bundle component debits/credits are atomic after settlement. | Matches. |
| Clan ownership transfer | Current owner can transfer ownership and increments `ownerNonce`. | Matches. |
| Self ownership transfer | Same-owner transfer is rejected; no nonce-only rotation feature. | Accepted implementation choice. |

## UAT Checklist

- Run direct-transfer Forge tests and verify all pass.
- Verify generated ABI contains the direct transfer functions and `ClanOwnershipTransferred`.
- Verify generated ABI does not contain OTC proposal/accept functions or events.
- Verify chainclient ABI generation/check passes.
- In local smoke testing, mint two clans and confirm an owner can transfer gold/resources from one clan to the other.

## Notes

`ownerNonce` exists for ownership handoff tracking only in this phase. If a later phase introduces off-chain signatures that require nonce-only invalidation, add an explicit ADR before changing same-owner transfer behavior.
