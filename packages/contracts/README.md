# @clan-world/contracts

Solidity contracts for ClanWorld. The canonical interface is `src/IClanWorld.sol` — every other component (frontend, backend, orchestrator, agents) talks to the chain through this seam. See `docs/adr/ADR001-IClanWorld-as-web2-web3-integration-seam.md`.

For Submission 1 (World mini app) the contracts deploy to **World Chain Sepolia**. Submission 2 redeploys the same code to **Base Sepolia** with KeeperHub-driven heartbeat.

## Workflow

```bash
forge build
forge test
forge script script/Deploy.s.sol --rpc-url $RPC_URL_PRIMARY --broadcast
```

`script/Deploy.s.sol` is a Wave 1 deliverable; the directory is empty in Wave 0.

## Layout

- `src/IClanWorld.sol` — canonical seam interface (24KB, do not modify without ADR)
- `foundry.toml` — Foundry config; reads `RPC_URL_PRIMARY` from env

See `../../docs/guides/stream-contracts.md` for the full deploy workflow.
