# GOLD Solana to Base bridge monorepo

This repo is a complete starting point for bridging an existing immutable Solana SPL token named GOLD to Base using Wormhole Native Token Transfers, also called NTT.

The architecture is simple:

1. The original GOLD SPL token remains canonical on Solana.
2. Wormhole NTT runs on Solana in locking mode.
3. A matching ERC-20 GOLD token is deployed on Base.
4. Wormhole NTT runs on Base in burning mode.
5. Solana to Base locks real GOLD on Solana and mints Base GOLD.
6. Base to Solana burns Base GOLD and unlocks real GOLD on Solana.

This repo includes:

- A Solidity 0.8.34 Base ERC-20 representation token.
- Shell scripts for the Wormhole NTT CLI flow.
- A React TypeScript SPA using Wormhole Connect's NTT route.
- Metrics panels for token addresses, explorer links, chain supplies, and recent bridge activity.
- A `.env.template` for the values you need to plug in.
- A review document with the initial code review and second polish pass.

Important: this is not an audit. Treat this as a production-oriented scaffold that still needs testnet runs, security review, and operational hardening before handling meaningful value.

## Why Wormhole NTT

Wormhole NTT is a framework for native token transfers without liquidity pools. The NTT manager handles the token transfer flow, rate limits, peer registration, and mint, burn, lock, or unlock behavior. Existing token deployments can use locking mode, which is the key reason it fits an immutable Solana SPL token.

## Repository layout

- `apps/web`: React TypeScript bridge UI.
- `packages/contracts`: Base ERC-20 token contract compiled with Solidity 0.8.34.
- `scripts`: deployment, configuration, metrics, and review scripts.
- `ntt`: placeholder directory; the init script replaces it with a real Wormhole NTT project.
- `docs`: deeper deployment, operations, architecture, testing, and security notes.

For the shortest tested deployment path, see `docs/testnet-runbook.md`.

## Prerequisites

Install these locally:

- Node.js 20 or newer.
- pnpm 9 or newer.
- Foundry, which provides `forge` and `cast`.
- Solana CLI.
- SPL Token CLI.
- Wormhole NTT CLI.

The NTT install helper is included at `scripts/01-install-ntt-cli.sh`.

## Step by step deployment

### 1. Create your environment file

Copy `.env.template` to `.env` and fill in the values.

The minimum values you need are:

- Your Solana GOLD mint address.
- Your Solana token decimals.
- Your Solana deployer keypair path.
- Your Base RPC URL.
- Your EVM private key.
- Your Base token name and symbol.
- Your Wormhole network, normally `Testnet` first and `Mainnet` later.

For Base Sepolia testing, use `WORMHOLE_NETWORK=Testnet` and `NTT_BASE_CHAIN=BaseSepolia`.

For production, use `WORMHOLE_NETWORK=Mainnet` and `NTT_BASE_CHAIN=Base`.

### 2. Install dependencies

Run `pnpm install` from the repo root.

### 3. Check local tools

Run `pnpm doctor`.

This checks for Node, pnpm, forge, cast, Solana CLI, SPL Token CLI, and the NTT CLI.

### 4. Deploy the Base GOLD ERC-20

Run `pnpm deploy:base-token`.

This deploys an upgradeable `GoldBridgeToken` on Base using Solidity 0.8.34, OpenZeppelin's transparent proxy, and a timelock-owned ProxyAdmin. The token is fixed at 9 decimals to mirror Solana GOLD. The temporary minter should usually be your deployer. After the NTT manager exists, you will replace the minter with the Base NTT manager through the timelock.

Copy the printed proxy token, implementation, timelock, and proxy admin addresses into `.env`. The proxy token address is `BASE_TOKEN_ADDRESS`.

### 5. Create or initialize the NTT project

Run `pnpm ntt:init`.

This creates the NTT project directory and initializes `deployment.json` for your selected Wormhole network.

### 6. Write custom RPC overrides

Run `pnpm ntt:overrides`.

This writes an `overrides.json` file in the NTT project directory using your Solana and Base RPC URLs. A custom Solana mainnet RPC is strongly recommended for NTT deployment.

### 7. Add Solana in locking mode

Run `pnpm ntt:add-solana`.

This uses your existing SPL token mint and deploys/configures NTT for Solana in locking mode.

This is the critical setting for an immutable Solana token. Do not use burning mode on Solana unless you actually control the SPL token mint authority and intend to give NTT mint authority.

### 8. Add Base in burning mode

Run `pnpm ntt:add-base`.

This deploys/configures NTT on Base for your deployed Base GOLD token in burning mode.

### 9. Configure rate limits

Open `ntt/deployment.json` and set sensible limits.

Start with conservative values on testnet. For example, set low daily limits until you have confidence in the transfer flow, frontend, monitoring, and recovery process. Follow the precision expected by the NTT CLI for each chain. Wormhole docs currently describe EVM rate-limit values as 18-decimal strings and SVM rate-limit values as 9-decimal strings, so do not guess here.

Then run `pnpm ntt:push`.

### 10. Set the Base token minter to the Base NTT manager

Run `pnpm ntt:addresses` to print manager and transceiver addresses.

Then run `pnpm base:set-minter`.

This schedules `setMinter` through the Base token timelock so the NTT manager can mint inbound Base GOLD and burn outbound Base GOLD. On testnet, set `TIMELOCK_EXECUTE_IMMEDIATELY=true` only when the timelock delay is zero.

### 11. Export the web config

Run `pnpm web:export-config`.

This reads `ntt/deployment.json` and writes `apps/web/src/generated/goldDeployment.ts`.

### 12. Run the bridge UI

Run `pnpm web`.

The web app is configured to read the root `.env` file, and the export script writes concrete deployment values into `apps/web/src/generated/goldDeployment.ts`.

The app shows:

- The Wormhole Connect bridge widget configured for GOLD.
- Solana and Base token addresses.
- NTT manager and transceiver addresses.
- Explorer links.
- Solana supply and Base supply.
- Recent NTT activity from Wormholescan where available.
- Local bridge history notes from the browser.

## Testnet first

Use Solana devnet plus Base Sepolia before touching mainnet value.

A safe order is:

1. Test token and NTT deployment on Solana devnet and Base Sepolia.
2. Tiny mainnet transfer from Solana to Base.
3. Tiny mainnet transfer from Base back to Solana.
4. Rate-limit tests.
5. Pausing and unpausing tests.
6. Monitoring and alerting setup.
7. Only then increase limits.

## Important design choices

### Token decimals

The Base GOLD token in this repo is fixed at 9 decimals. That matches the expected Solana GOLD precision, keeps bridge supply accounting direct, and avoids deploying an accidental 18-decimal representation before ClanWorld integration is ready.

ClanWorld can still keep any internal e18 accounting it needs later, but that conversion should happen at the game boundary rather than inside the bridge token.

### Minter handoff

The Base token starts with a temporary minter because the NTT manager address does not exist before NTT deployment. After NTT is deployed on Base, call `setMinter` through the timelock to move minter authority to the Base NTT manager.

### Upgrade and recovery model

Base GOLD uses a transparent upgradeable proxy. The proxy admin and token owner should both be controlled by a timelock. V1 includes `recoverFromAllowedSource`, a timelocked recovery hook that can move tokens only from allowlisted sources such as ClanWorld pool or treasury contracts. User wallets should not be allowlisted.

Recovery can be permanently disabled with `disableRecoveryForever`. A later V2 implementation removes the recovery ABI while preserving token balances, allowances, owner, minter, and total supply.

### Admin custody

Keep ownership and pauser roles controlled by a multisig for production. A single laptop key is acceptable for testnet, but not for mainnet liquidity.

## Useful commands

- `pnpm doctor`: check local tools.
- `pnpm review`: run static repo checks.
- `pnpm test:contracts`: run the Foundry contract tests.
- `pnpm deploy:base-token`: deploy the upgradeable Base ERC-20 token, timelock, and proxy admin stack.
- `pnpm ntt:init`: initialize the NTT project.
- `pnpm ntt:overrides`: write NTT custom RPC overrides.
- `pnpm ntt:add-solana`: add Solana in locking mode.
- `pnpm ntt:add-base`: add Base in burning mode.
- `pnpm ntt:status`: check NTT status.
- `pnpm ntt:push`: push local deployment config to chain.
- `pnpm ntt:addresses`: print deployed NTT addresses.
- `pnpm base:set-minter`: set Base token minter to the Base NTT manager.
- `pnpm web:export-config`: write generated frontend config.
- `pnpm artifacts:export`: write a public deployment summary without secrets.
- `pnpm preflight`: check token decimals, Base minter handoff, and NTT status.
- `pnpm liquidity:recover-base`: dry-run or execute a Base to Solana GOLD recovery transfer.
- `pnpm base:proxy-info`: print proxy, implementation, ProxyAdmin, owner, minter, and timelock details.
- `pnpm timelock:schedule`: schedule a generic timelock operation from `TIMELOCK_TARGET_ADDRESS` and `TIMELOCK_CALLDATA`.
- `pnpm timelock:execute`: execute a ready generic timelock operation.
- `pnpm web`: run the SPA locally.
- `pnpm metrics`: fetch basic supply metrics from Solana and Base RPCs.

## Security warning

Bridges are high-risk systems. The most dangerous parts are not the UI or ordinary token transfers. The dangerous parts are admin keys, minter authority, NTT manager configuration, rate limits, peer registration, transceiver configuration, and emergency operations.

Use testnet first and do not increase mainnet limits until you can complete both directions repeatedly with small amounts.
