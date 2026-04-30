# Testing checklist

## Local static checks

Run:

- `pnpm review`
- `forge build` inside `packages/contracts`
- `forge test` inside `packages/contracts`
- `pnpm typecheck`
- `pnpm build`

## Testnet bridge checks

1. Deploy Base Sepolia token.
2. Confirm `decimals()` returns `9`.
3. Deploy Solana devnet NTT in locking mode.
4. Deploy Base Sepolia NTT in burning mode.
5. Set Base token minter to Base NTT manager.
6. Transfer a tiny amount Solana to Base.
7. Transfer a tiny amount Base to Solana.
8. Try a transfer above the rate limit and confirm it is blocked or queued as expected.
9. Confirm the UI shows addresses and supplies.
10. Confirm explorer links open the correct pages.
11. Confirm Wormholescan activity appears after indexing.

## Mainnet smoke checks

1. Use tiny amounts.
2. Transfer Solana to Base.
3. Transfer Base to Solana.
4. Confirm no unexpected supply drift.
5. Confirm admin roles.
6. Keep rate limits low for the first production day.
