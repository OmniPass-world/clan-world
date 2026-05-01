# Deployment guide

Use this guide together with the root README.

## Testnet deployment

Use:

- `WORMHOLE_NETWORK=Testnet`
- `NTT_BASE_CHAIN=BaseSepolia`
- `SOLANA_RPC_URL=https://api.devnet.solana.com`
- `BASE_RPC_URL=https://sepolia.base.org`

Solana's official NTT test flow uses devnet rather than Solana's separate testnet cluster.

## Mainnet deployment

Use:

- `WORMHOLE_NETWORK=Mainnet`
- `NTT_BASE_CHAIN=Base`
- A private or paid Solana RPC.
- A reliable Base RPC.
- A funded Solana deployer wallet.
- A funded Base deployer wallet.

## Deployment order

1. Fill `.env`.
2. Run `pnpm doctor`.
3. Run `pnpm deploy:base-token`.
4. Copy the printed proxy token, implementation, timelock, and proxy admin addresses into `.env`.
5. Run `pnpm ntt:init`.
6. Run `pnpm ntt:overrides`.
7. Run `pnpm ntt:add-solana`.
8. Run `pnpm ntt:add-base`.
9. Edit `ntt/deployment.json` to set rate limits.
10. Run `pnpm ntt:push`.
11. Run `pnpm ntt:addresses`.
12. Run `pnpm base:set-minter`, then execute the scheduled operation after the timelock delay.
13. Run `pnpm preflight`.
14. Run `pnpm artifacts:export`.
15. Run `pnpm web:export-config`.
16. Run `pnpm web`.

## Rate limits

Start with low test limits. Raise them only after repeated successful transfers and monitoring.

For production, think of the outbound limit as your maximum daily blast radius.

## Verification

After deployment, verify:

- Solana mode is locking.
- Base mode is burning.
- Base token minter is the Base NTT manager.
- Base token is an ERC-1967 transparent proxy.
- ProxyAdmin owner is the timelock.
- Base token owner is the timelock.
- Peer addresses match both ways.
- Transceiver addresses match both ways.
- Rate limits are not zero unless intentionally disabled.
- Pauser and owner roles are controlled by the intended accounts.

`pnpm preflight` automates the checks that are easiest to miss: Solana mint decimals, Base token decimals, Base token minter, transparent proxy metadata, timelock ownership, and NTT deployment status.

## Timelock calls

Use `pnpm timelock:schedule` and `pnpm timelock:execute` for owner-only token operations. Set:

- `BASE_TIMELOCK_ADDRESS`
- `TIMELOCK_TARGET_ADDRESS`
- `TIMELOCK_CALLDATA`
- optional `TIMELOCK_SALT`, `TIMELOCK_VALUE`, and `TIMELOCK_DELAY_SECONDS`

Example calldata:

```bash
cast calldata "setRecoveryAllowed(address,bool)" "$CLANWORLD_POOL_ADDRESS" true
```

## Production checklist

Before a mainnet deployment:

1. Generate fresh production Solana and EVM deployer wallets.
2. Back up key material offline before funding either wallet.
3. Fund deployers only with the amount needed for deployment and tiny proof transfers.
4. Set `WORMHOLE_NETWORK=Mainnet`, `NTT_BASE_CHAIN=Base`, production RPC URLs, and the real Solana GOLD mint.
5. Deploy Base GOLD as a transparent proxy, add both NTT chains, set conservative rate limits, push config, and hand minter authority to the Base NTT manager through the timelock.
6. Run `pnpm preflight` and archive the output.
7. Run `pnpm artifacts:export` and archive the JSON with `deployment.json`, tx hashes, and owner/pauser role notes.
8. Prove one tiny Solana -> Base transfer and one tiny Base -> Solana transfer before raising limits.
9. Confirm allowlist-scoped recovery works on a tiny contract-held amount before seeding meaningful ClanWorld liquidity.

## Rate-limit precision warning

Do not infer rate-limit string precision only from token decimals. Follow the NTT CLI and Wormhole docs for the chain you are editing. Current Wormhole docs describe EVM rate-limit values as 18-decimal strings and SVM rate-limit values as 9-decimal strings.
