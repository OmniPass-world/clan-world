# Code review and polish record

## First review pass

Scope reviewed:

- Solidity ERC-20 representation token.
- Wormhole NTT deployment scripts.
- Frontend config generation.
- React SPA structure.
- Metrics and history helpers.
- Documentation and environment template.

Findings and actions:

1. The Base token must expose `mint(address,uint256)`, `burn(uint256)`, and `setMinter(address)` for NTT burning mode. Confirmed and implemented.
2. The Solana side must use locking mode for an immutable SPL token. Confirmed in scripts and README.
3. The Base side must use burning mode. Confirmed in scripts and README.
4. The Base token minter must be handed off after NTT deployment. Added `scripts/08-set-base-minter.sh`.
5. Custom RPC overrides are important for Solana mainnet NTT deployment. Added `scripts/04-write-ntt-overrides.sh`.
6. The frontend cannot know NTT manager and transceiver addresses before deployment. Added `scripts/09-export-web-config.mjs` to generate config from `deployment.json`.
7. Rate limits should not default to high production values. Documentation instructs conservative limits.
8. Local bridge history cannot guarantee protocol-level history. UI labels browser-local notes separately from Wormholescan activity.

## Second review and polish pass

Improvements made:

1. Added `pnpm doctor` to check tools before deployment.
2. Added static review script to catch missing core files and config mistakes.
3. Added explicit Solidity 0.8.34 pragma and Foundry compiler setting.
4. Added typed frontend config with placeholder mode before deployment.
5. Added docs for architecture, deployment, operations, testing, and security.
6. Added direct JSON-RPC metrics script that does not require extra packages.
7. Added `overrides.example.json` and generator script.
8. Added warnings around single-key custody and production rate limits.

## Remaining production work

- Run `forge build` after installing Foundry.
- Run `pnpm install`, `pnpm typecheck`, and `pnpm build` after installing dependencies.
- Deploy on Solana devnet and Base Sepolia first.
- Do an external security review before mainnet liquidity.
- Confirm exact NTT CLI output format in your installed CLI version.
- Register token metadata and wallet/explorer labels after mainnet deployment.


## Second polish additions after review

- Fixed the NTT initialization script so the checked-in placeholder `ntt/` directory is safely replaced by a real `ntt new` project.
- Rewrote the test-transfer script to use a Bash argument array, avoiding fragile optional-argument quoting.
- Added a minimal Foundry test suite for `GoldBridgeToken`.
- Configured Vite to read the monorepo root `.env` file.
- Added frontend VITE placeholders for token, manager, and transceiver addresses.
- Hardened decimal formatting for zero-decimal tokens.
- Added an explicit warning about NTT rate-limit precision across EVM and SVM chains.
