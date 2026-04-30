# Contracts

`GoldBridgeToken.sol` is the Base ERC-20 representation token.

It is intentionally dependency-free so it can compile with only Foundry and Solidity 0.8.34.

It is fixed at 9 decimals to mirror Solana GOLD. The token keeps a normal ERC-20 `approve` / `transferFrom` surface so ClanWorld can later pull approved GOLD for liquidity or deposit flows without changing the bridge token.

The token implements the functions Wormhole NTT burning mode expects on EVM representation tokens:

- `mint(address,uint256)`
- `burn(uint256)`
- `setMinter(address)`

Deployment uses `scripts/03-deploy-base-token.sh` from the repo root.

A minimal Foundry test suite lives in `test/GoldBridgeToken.t.sol`. Run it with `pnpm test:contracts` from the repo root or `forge test` in this package.
