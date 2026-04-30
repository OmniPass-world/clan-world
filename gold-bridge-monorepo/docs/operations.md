# Operations

## Routine checks

Run `pnpm metrics` to fetch basic supply metrics from Solana and Base.

Watch these values:

- Solana GOLD total supply.
- Base GOLD total supply.
- NTT transfer activity.
- NTT manager paused status.
- Rate-limit utilization.

## Bridge history

The UI shows two types of history:

1. Wormholescan activity where the public API can find transfers.
2. Browser-local notes from the operator or tester.

Browser-local notes are not authoritative. Use Wormholescan and on-chain transaction hashes for authoritative tracking.

## Incident response

If anything looks wrong:

1. Pause NTT managers if needed.
2. Stop increasing rate limits.
3. Save transaction hashes and screenshots.
4. Check both manager configs with `ntt status`.
5. Check Base token minter.
6. Check Solana custody balances.
7. Do not rotate keys or change ownership until you understand the incident.

## Mainnet hardening

Use multisig admin roles. Avoid single-key deployer ownership. Store key material offline. Document who can pause, who can unpause, and who can change rate limits.
