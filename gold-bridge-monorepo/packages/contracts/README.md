# Contracts

`GoldBridgeToken.sol` is the upgradeable Base ERC-20 representation token.

It uses OpenZeppelin ERC20 upgradeable contracts and is deployed behind a transparent proxy whose ProxyAdmin should be owned by a timelock.

It is fixed at 9 decimals to mirror Solana GOLD. The token keeps a normal ERC-20 `approve` / `transferFrom` surface so ClanWorld can later pull approved GOLD for liquidity or deposit flows without changing the bridge token.

The token implements the functions Wormhole NTT burning mode expects on EVM representation tokens:

- `mint(address,uint256)`
- `burn(uint256)`
- `setMinter(address)`

V1 also includes timelocked, allowlist-scoped recovery:

- `setRecoveryAllowed(address,bool)`
- `recoverFromAllowedSource(address,address,uint256)`
- `disableRecoveryForever()`

`GoldBridgeTokenV2.sol` preserves storage and removes the recovery ABI for the later hardening upgrade.

Deployment uses `scripts/03-deploy-base-token.sh` from the repo root and prints the proxy token, implementation, timelock, and ProxyAdmin addresses.

A minimal Foundry test suite lives in `test/GoldBridgeToken.t.sol`. Run it with `pnpm test:contracts` from the repo root or `forge test` in this package.
