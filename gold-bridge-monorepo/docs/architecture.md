# Architecture

The bridge uses Wormhole Native Token Transfers.

## Canonical chain

Solana is canonical because your real GOLD token already exists there and cannot be modified.

The Solana NTT manager is deployed in locking mode. That means users deposit GOLD into the manager-controlled custody account. The original SPL token supply does not change.

## Spoke chain

Base is the spoke chain.

The Base GOLD ERC-20 representation is deployed by this repo behind an OpenZeppelin transparent upgradeable proxy. It is fixed at 9 decimals, matching the expected Solana GOLD precision. The Base NTT manager is deployed in burning mode. It mints Base GOLD when Solana GOLD is locked, and burns Base GOLD when users bridge back to Solana.

The proxy admin and token owner should both be controlled by a public timelock. V1 includes an allowlist-scoped recovery hook for contract-held migration liquidity. The hook is intentionally narrow, timelocked, and permanently disableable; V2 removes the recovery ABI while preserving token state.

ClanWorld integration is intentionally outside the bridge layer for now. The bridge token exposes ordinary ERC-20 allowance and transfer functions so the game can later seed liquidity or implement deposit flows, but any e18 game-accounting conversion should happen in ClanWorld integration code rather than in the token.

## Transfer flow: Solana to Base

1. User starts a transfer from Solana.
2. Solana NTT locks GOLD in custody.
3. Wormhole emits and verifies a cross-chain message.
4. Base NTT receives the message.
5. Base NTT mints Base GOLD to the recipient.

## Transfer flow: Base to Solana

1. User starts a transfer from Base.
2. Base NTT transfers and burns Base GOLD.
3. Wormhole emits and verifies a cross-chain message.
4. Solana NTT receives the message.
5. Solana NTT unlocks real GOLD to the recipient token account.

## Why not lock and lock

A lock-and-lock model needs liquidity pre-funded on every destination chain. That does not fit a clean canonical-Solana design. The intended NTT shape is locking on the canonical chain and burning on the spoke chain.

## Admin roles

Production should use multisig-controlled timelocks and pauser roles.

Minimum recommended controls:

- Base token owner timelock.
- Base token ProxyAdmin owner timelock.
- Timelock proposer multisig.
- NTT manager owner on Solana.
- NTT manager owner on Base.
- Pauser role.
- Transceiver pauser role.

## Supply accounting

Base total supply should be less than or equal to the amount of GOLD locked in Solana custody, subject to pending in-flight messages and dust normalization.
