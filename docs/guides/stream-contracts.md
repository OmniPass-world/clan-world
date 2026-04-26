# Stream: Contracts

How to work on `packages/contracts/`.

## Setup

```bash
# install Foundry if missing
curl -L https://foundry.paradigm.xyz | bash
foundryup

# init lib/ submodules (Wave 1+)
cd packages/contracts
forge install
```

## Workflow

```bash
forge build    # compile to packages/contracts/out/
forge test     # run tests (Wave 1+)
forge fmt      # format
```

## Deploy

The deploy script (Wave 1+) lives at `script/Deploy.s.sol`. Targets are parameterized by `RPC_URL_PRIMARY`.

```bash
# Submission 1 — World Chain Sepolia
RPC_URL_PRIMARY=$WORLDCHAIN_SEPOLIA_RPC \
  forge script script/Deploy.s.sol --rpc-url $RPC_URL_PRIMARY --broadcast --verify

# Submission 2 — Base Sepolia
RPC_URL_PRIMARY=$BASE_SEPOLIA_RPC \
  forge script script/Deploy.s.sol --rpc-url $RPC_URL_PRIMARY --broadcast --verify
```

After deploy, write the engine address to `.env.local` as `ENGINE_ADDRESS=0x…` so the orchestrator and indexer pick it up.

## ABI extraction

The `IClanWorld` ABI is needed by:
- `RealChainClient` (in `@clan-world/shared`) — uses viem/ethers.
- The Convex indexer event handlers.
- Optionally a generated TS client.

Wave 1 plan: post-build, copy `out/IClanWorld.sol/IClanWorld.json` to `packages/shared/src/abi/IClanWorld.json` and load via JSON import.

## Testing

- Local anvil first: `anvil` in one terminal, `forge test --rpc-url http://127.0.0.1:8545` in another.
- Don't burn testnet faucet funds debugging trivial bugs.
- Snapshots: `forge snapshot` for gas regression tracking (Wave 2+).

## ABI stability

`src/IClanWorld.sol` is treated as sacred. Changes require an ADR. See `docs/adr/ADR001-IClanWorld-as-web2-web3-integration-seam.md` for the rationale.
