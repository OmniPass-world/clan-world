# Security notes

This repository is not an audit. It is a scaffold for a Wormhole NTT deployment.

Before mainnet value:

1. Use testnet end to end.
2. Verify Solana locking mode and Base burning mode.
3. Verify the Base token minter is exactly the Base NTT manager.
4. Verify admin ownership and pauser roles are held by a multisig.
5. Use conservative rate limits.
6. Test pausing, unpausing, and transfer recovery.
7. Monitor supply on both chains.
8. Have a written incident response plan.

Never commit private keys, keypair JSON files, `.env`, or deployed NTT config containing sensitive local paths.
