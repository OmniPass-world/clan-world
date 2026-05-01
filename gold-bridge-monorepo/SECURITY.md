# Security notes

This repository is not an audit. It is a scaffold for a Wormhole NTT deployment.

Before mainnet value:

1. Use testnet end to end.
2. Verify Solana locking mode and Base burning mode.
3. Verify the Base token minter is exactly the Base NTT manager.
4. Verify the Base token owner and ProxyAdmin owner are the public timelock.
5. Use conservative rate limits.
6. Verify the timelock proposer is the intended multisig and the delay is public.
7. Test pausing, unpausing, and allowlist-scoped recovery.
8. Monitor supply on both chains.
9. Have a written incident response plan.

Never commit private keys, keypair JSON files, `.env`, or deployed NTT config containing sensitive local paths.
