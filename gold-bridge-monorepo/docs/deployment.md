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
4. Copy the Base token address into `.env`.
5. Run `pnpm ntt:init`.
6. Run `pnpm ntt:overrides`.
7. Run `pnpm ntt:add-solana`.
8. Run `pnpm ntt:add-base`.
9. Edit `ntt/deployment.json` to set rate limits.
10. Run `pnpm ntt:push`.
11. Run `pnpm ntt:addresses`.
12. Run `pnpm base:set-minter`.
13. Run `pnpm web:export-config`.
14. Run `pnpm web`.

## Rate limits

Start with low test limits. Raise them only after repeated successful transfers and monitoring.

For production, think of the outbound limit as your maximum daily blast radius.

## Verification

After deployment, verify:

- Solana mode is locking.
- Base mode is burning.
- Base token minter is the Base NTT manager.
- Peer addresses match both ways.
- Transceiver addresses match both ways.
- Rate limits are not zero unless intentionally disabled.
- Pauser and owner roles are controlled by the intended accounts.

## Rate-limit precision warning

Do not infer rate-limit string precision only from token decimals. Follow the NTT CLI and Wormhole docs for the chain you are editing. Current Wormhole docs describe EVM rate-limit values as 18-decimal strings and SVM rate-limit values as 9-decimal strings.
