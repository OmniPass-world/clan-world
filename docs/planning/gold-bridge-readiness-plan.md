# GOLD Bridge Readiness Plan

Living plan for getting Solana-canonical GOLD bridged to Base with Wormhole NTT, then replacing ClanWorld's current deployed/native GOLD ERC20 with the Base-side bridged GOLD token.

Last updated: 2026-04-30 05:38 EDT

## Goal

Solana GOLD remains the canonical asset. Wormhole NTT locks GOLD on Solana, mints/releases the Base-side GOLD representation, and ClanWorld uses that Base GOLD token as its game GOLD boundary token.

## Current Readiness Snapshot

- Standalone bridge scaffold: about 70% ready.
- Bridge token readiness: Base GOLD is now fixed at 9 decimals with the NTT mint/burn/minter surface and ordinary ERC-20 allowance pulls for later ClanWorld compatibility.
- ClanWorld integration: intentionally deferred. Do not modify existing ClanWorld contracts/scripts/tests until the bridge and token deployment flow are proven.
- Current phase: testnet deployment prep. Tooling is installed and a local ignored `.env` exists, but real deployment is blocked until the Solana devnet deployer has SOL and the Base Sepolia deployer has ETH.

## Phase 1 Execution Plan: Bridge Repo Correctness and Tooling

Status: Completed

Objective: get the standalone bridge repo to a clean web typecheck/build state, with all known Wormhole Connect integration gotchas recorded before moving to deployment.

Scope:

- Fix TypeScript errors in the Wormhole Connect NTT config.
- Keep changes narrowly focused on bridge UI/tooling.
- Do not deploy contracts or initialize a real NTT project in this phase.
- Do not change ClanWorld contract deployment in bridge phases.

Entry criteria:

- Bridge repo is extracted in isolated worktree.
- Dependencies have been installed.
- Current failing command is understood: `pnpm --filter @gold-bridge/web typecheck`.

Exit criteria:

- [x] `pnpm --filter @gold-bridge/web typecheck` passes.
- [x] `pnpm --filter @gold-bridge/web build` passes.
- [x] `Component 1` checklist is updated with completed items.
- [x] Verification log records exact commands and outcomes.

Task order:

1. Patch `apps/web/src/config/wormholeConnect.ts` to match installed `@wormhole-foundation/wormhole-connect@5.1.1` types.
2. Re-run `pnpm --filter @gold-bridge/web typecheck`.
3. If typecheck exposes secondary errors, fix only bridge UI/type issues.
4. Re-run `pnpm --filter @gold-bridge/web build`.
5. Record warnings, gotchas, and any remaining non-blocking risk.

Known risks:

- Wormhole docs and installed package types are close but not identical; prefer installed package types for this repo.
- React 19 may still be runtime-risky even if TypeScript/build passes, because some Wormhole dependency peers still advertise React 16/17/18 ranges.
- The bridge widget can compile before it is functionally useful; it still needs real NTT addresses from Phase 2.
- Vite config still declares `server.port = 5173`; when running in this worktree, use `port-for clan-world-frontend-dev` and pass the allocated port through `pnpm --filter @gold-bridge/web exec vite --host 0.0.0.0 --port "$PORT"`.

## Phase 2 Execution Plan: ClanWorld External GOLD Deploy Mode

Status: Superseded and reverted

Objective: make ClanWorld deploy with either local mock GOLD or an existing Base-side bridged GOLD token address.

Scope:

- Update `packages/contracts/script/Deploy.s.sol`.
- Add minimal contract test coverage proving pool seeding works with an externally supplied ERC20-compatible GOLD.
- Do not change `IClanWorld`.
- Do not solve the final decimals strategy in this phase; add a temporary deploy-time guard to avoid accidental unit mismatch.

Entry criteria:

- Phase 1 web gates are green.
- Existing `Deploy.s.sol` behavior is understood.
- ClanWorld treasury accepts arbitrary token addresses through `initTreasury`.

Exit criteria:

- [x] `Deploy.s.sol` supports `BRIDGED_GOLD_TOKEN_ADDRESS`.
- [x] Default behavior still deploys local mock GOLD when the env var is unset.
- [x] External GOLD mode skips local GOLD minting and requires treasury-held bridged GOLD.
- [x] External GOLD mode approves and seeds pools through the normal `seedPools` path.
- [x] Minimal test/simulation covers externally supplied GOLD pool seeding.
- [x] Available checks are run and outcomes recorded.

Task order:

1. Add `BRIDGED_GOLD_TOKEN_ADDRESS` handling to the deploy script.
2. Keep local mock GOLD as the default unset-env path.
3. Add balance and decimals checks for external GOLD.
4. Add a focused `SeedPools` test with an ERC20-like external GOLD token.
5. Run available checks; document if Foundry remains unavailable.

Known risks:

- ClanWorld currently assumes 18-decimal GOLD units. External GOLD mode should reject non-18-decimal GOLD until Component 4 resolves the permanent unit strategy.
- Existing deployed ClanWorld instances cannot swap token addresses because `initTreasury` is one-time.
- This phase makes the deploy path bridge-ready, but it does not create player deposit/withdraw mechanics.

Findings:

- This phase was useful as a feasibility spike, but it crossed the desired boundary too early.
- The ClanWorld deploy script and `SeedPools` test edits from this phase were reverted on 2026-04-30 EDT.
- Integration belongs at the end, after the bridge token, NTT deployment, transfer proof, and dev tooling are solid.
- The learning still stands: ClanWorld can likely use any ERC-20-compatible GOLD later if it supports `decimals()`, `balanceOf(address)`, `approve(address,uint256)`, and `transferFrom(address,address,uint256)`.

## Phase 3 Execution Plan: 9-Decimal Base GOLD Token

Status: Completed

Objective: make the bridge repo own the Base-side GOLD representation token as a 9-decimal ERC-20 suitable for Wormhole NTT and later ClanWorld integration, without touching ClanWorld contracts.

Scope:

- Update only `gold-bridge-monorepo` and this planning doc.
- Fix the Base GOLD token at 9 decimals.
- Keep NTT-required functions: `mint(address,uint256)`, `burn(uint256)`, and `setMinter(address)`.
- Keep ordinary ERC-20 behavior needed by future ClanWorld liquidity/deposit flows: `balanceOf`, `allowance`, `approve`, `transfer`, and `transferFrom`.
- Remove duplicate Base decimals env configuration from deploy/web export paths.
- Do not wire the token into ClanWorld deployment, tests, liquidity, or game accounting.

Exit criteria:

- [x] Base `GoldBridgeToken` exposes `decimals() == 9`.
- [x] Deploy script no longer accepts a separate Base decimals env var.
- [x] Frontend generated config derives Base decimals from the Solana token decimals/default 9 instead of a duplicate Base decimals setting.
- [x] Contract tests cover NTT mint/burn behavior.
- [x] Contract tests cover ERC-20 allowance pull behavior for future ClanWorld compatibility.
- [x] Run contract tests and static review after edits.

Findings:

- Wormhole's EVM NTT docs require burn-and-mint tokens to implement `burn(uint256)` and `mint(address,uint256)`, with minter authority handed to the NTT manager after deployment.
- The token does not need ClanWorld-specific code. A plain 9-decimal ERC-20 surface is the right bridge-layer boundary.
- If ClanWorld wants internal e18 accounting later, conversion should happen in the ClanWorld integration layer, not inside the bridge token.

## Phase 4 Execution Plan: Testnet Bridge Deployment Proof

Status: Blocked on testnet funds

Objective: deploy the 9-decimal Base GOLD token, configure Wormhole NTT with Solana locking mode and Base burning mode, then prove tiny transfers in both directions.

Scope:

- Work only in `gold-bridge-monorepo`.
- Use Solana devnet and Base Sepolia.
- Create or use a 9-decimal Solana devnet GOLD mint.
- Deploy the Base 9-decimal `GoldBridgeToken`.
- Initialize and push NTT deployment config.
- Export the bridge UI config after real addresses exist.
- Do not touch ClanWorld integration yet.

Progress:

- [x] Installed NTT CLI: `ntt v1.7.0`.
- [x] Installed Solana/Agave CLI: `solana-cli 3.1.14`.
- [x] Confirmed `spl-token-cli 5.5.0` is available.
- [x] Created ignored local `.env` in `gold-bridge-monorepo`.
- [x] Created ignored throwaway Solana devnet deployer keypair.
- [x] Created ignored throwaway Base Sepolia deployer wallet.
- [x] Ran `pnpm doctor` with Foundry/Solana/NTT on PATH; passed.
- [ ] Fund Solana devnet deployer with SOL.
- [ ] Create 9-decimal Solana devnet GOLD mint or set `SOLANA_TOKEN_MINT` to an existing mint.
- [ ] Fund Base Sepolia deployer with ETH.
- [ ] Run `pnpm deploy:base-token`.
- [ ] Run `pnpm ntt:init`.
- [ ] Run `pnpm ntt:overrides`.
- [ ] Run `pnpm ntt:add-solana`.
- [ ] Run `pnpm ntt:add-base`.
- [ ] Configure conservative rate limits in `ntt/deployment.json`.
- [ ] Run `pnpm ntt:push`.
- [ ] Run `pnpm ntt:addresses`.
- [ ] Run `pnpm base:set-minter`.
- [ ] Run `pnpm web:export-config`.
- [ ] Execute tiny Solana -> Base transfer.
- [ ] Execute tiny Base -> Solana transfer.
- [ ] Record tx hashes and final deployed addresses.

Current generated test addresses:

- Solana devnet deployer: `BJmjhXs5h6d8o15kK1YppkiJExu6FWBDJyJFUyfp9L2p`
- Base Sepolia deployer: `0x96E3054A6Bd6b6d8710dE3029D3bA2EbCb930B5D`

Blockers:

- Solana devnet faucet returned rate-limit errors for `2 SOL` and `0.5 SOL` requests from this host. Current Solana deployer balance is `0 SOL`.
- Base Sepolia deployer balance is `0`.
- Without those funds, token mint creation, Base token deployment, NTT deployment, and transfer proofs cannot proceed.

## Component 1: Bridge Repo Correctness and Tooling

Status: In progress

Purpose: make `gold-bridge-monorepo` install, typecheck, build, and expose a working Wormhole Connect NTT UI.

Checklist:

- [x] Extract bridge repo into isolated worktree at `/home/claude/code/omnipass-world/clan-world-gold-bridge/gold-bridge-monorepo`.
- [x] Inspect bridge repo structure, docs, scripts, contract, and frontend.
- [x] Run static repo review with `pnpm review`.
- [x] Install pnpm dependencies in the isolated worktree.
- [x] Fix Wormhole Connect TypeScript config errors.
- [x] Re-run `pnpm --filter @gold-bridge/web typecheck`.
- [x] Re-run `pnpm --filter @gold-bridge/web build`.
- [x] Run contract build/tests after Foundry is available.
- [x] Decide whether to keep React 19 or pin React 18 for Wormhole Connect compatibility.

Findings:

- `pnpm review` passes.
- `pnpm install` completes, but Wormhole Connect brings a noisy peer dependency graph.
- `pnpm typecheck` originally failed in `apps/web/src/config/wormholeConnect.ts`.
- `pnpm --filter @gold-bridge/web typecheck` now passes after aligning config with installed Wormhole Connect types.
- `pnpm --filter @gold-bridge/web build` now passes. Build emits large chunk warnings because Wormhole Connect pulls a large wallet/chain dependency graph.
- Contract `forge build` and `forge test` now pass in `gold-bridge-monorepo/packages/contracts` with `/home/claude/.foundry/bin` on PATH.
- React decision: keep React 19. Installed React is `19.2.5`, current npm latest is `19.2.5`, and `@wormhole-foundation/wormhole-connect@5.1.1` declares peer support for `react: ^18.0.0 || >=19.2.3`.

Gotchas:

- Installed `@wormhole-foundation/wormhole-connect@5.1.1` types expect `ui.defaultInputs.source` / `destination`, not `fromChain` / `toChain`.
- The package README recommends `nttRoutes(nttConfig)` for Connect. Using `nttRoutes` avoids manually mixing executor/manual route config shapes.
- `tokensConfig` entries in the installed type do not allow a `key` field.
- Generated chain names are plain strings, but Wormhole Connect types expect typed Wormhole chain names.
- Installed `WormholeConnectConfig` type does not accept top-level `walletConnectProjectId`; it accepts it under `ui.walletConnectProjectId`.
- Some deeper wallet adapter dependencies still emit React peer warnings. Treat this as runtime wallet-modal test risk, not a reason to downgrade preemptively.

## Component 2: Wormhole NTT Deployment and Transfer Proof

Status: Not started

Purpose: prove the bridge itself works before touching ClanWorld economics.

Checklist:

- [ ] Fill `.env` for Solana devnet and Base Sepolia.
- [ ] Confirm exact Solana GOLD test mint or create a devnet test mint that mirrors production decimals.
- [ ] Deploy Base GOLD representation token.
- [ ] Run `pnpm ntt:init`.
- [ ] Run `pnpm ntt:overrides`.
- [ ] Add Solana in locking mode.
- [ ] Add Base in burning mode.
- [ ] Configure conservative rate limits in `ntt/deployment.json`.
- [ ] Run `pnpm ntt:push`.
- [ ] Set Base token minter to Base NTT manager.
- [ ] Export frontend config with `pnpm web:export-config`.
- [ ] Execute tiny Solana -> Base transfer.
- [ ] Execute tiny Base -> Solana transfer.
- [ ] Record tx hashes, NTT manager addresses, transceiver addresses, token addresses, and Wormholescan links.

Findings:

- The scaffold's NTT direction is correct for an existing immutable Solana token: Solana locking mode, Base burning mode.
- Public Wormhole docs align with the planned CLI commands for SVM locking and EVM burning.

Gotchas:

- Solana official testnet is not the target for NTT testing; use Solana devnet with `WORMHOLE_NETWORK=Testnet`.
- Solana mainnet deployment should use a paid/private RPC, not the public endpoint.
- Rate-limit precision must be confirmed against the current NTT CLI/docs and not guessed from token decimals alone.
- This repo has no real `ntt/deployment.json` yet, so all NTT addresses are unknown placeholders until deployment.

## Component 3: ClanWorld Base GOLD Replacement

Status: Deferred until final integration

Purpose: make ClanWorld register and use the Base-side bridged GOLD token instead of deploying its own `MinimalERC20("Gold", "GOLD")`.

Checklist:

- [ ] Add deploy configuration for an existing GOLD token address on Base/Base Sepolia.
- [ ] Update `packages/contracts/script/Deploy.s.sol` so GOLD can be external while resource tokens remain locally deployed.
- [ ] Skip `gold.seedTreasury(...)` when using external bridged GOLD.
- [ ] Require deployer/treasury to already hold enough bridged GOLD for pool seeding.
- [ ] Approve bridged GOLD to `ClanWorld` before `seedPools`.
- [ ] Deploy pools with `TOKEN_B = bridgedGoldAddress`.
- [ ] Update deployment artifact writing so `tokens.gold` records the bridged GOLD address.
- [ ] Add minimal tests or deployment simulation for external GOLD mode.

Findings:

- Current ClanWorld deployment script remains unchanged and still deploys `MinimalERC20("Gold", "GOLD")`.
- `ClanWorld.initTreasury` already accepts token addresses, so the engine can register an external GOLD token without changing the core interface.
- `seedPools` only needs ERC20-compatible `transferFrom`, so bridged GOLD can work if the treasury has balance and allowance.
- The bridge token now covers the ERC-20 allowance/transfer surface needed for this later work.
- Current deploy script does not write deployment JSON itself; deployment artifact updates will be a separate ops/script concern.

Gotchas:

- Existing deployments already point at old GOLD token addresses. Replacing GOLD means redeploying or adding a migration path; existing `initTreasury` is one-time.
- ClanWorld tests create `MinimalERC20` GOLD everywhere, so test fixtures will need a small external-GOLD path rather than broad rewrites.
- External GOLD must expose `decimals()`, `balanceOf(address)`, `approve(address,uint256)`, and `transferFrom(address,address,uint256)`.

## Component 4: Decimals, Accounting, and Liquidity

Status: Not started

Purpose: prevent 9-decimal Solana GOLD and 18-decimal ClanWorld assumptions from corrupting prices, starter balances, and pool reserves.

Checklist:

- [ ] Confirm production Solana GOLD decimals.
- [x] Decide canonical Base GOLD decimals for the bridge token: 9.
- [ ] If Base GOLD decimals are 9, update ClanWorld constants/accounting or introduce a conversion boundary during final integration.
- [ ] If Base GOLD decimals are 18, confirm Wormhole NTT can safely represent the Solana supply/amounts with expected normalization.
- [ ] Recalculate starter gold, pool seeds, market quotes, and UI formatting.
- [ ] Document the chosen unit convention in contracts, deployment docs, and bridge docs.
- [ ] Add at least one happy-path market test proving seeded bridged-GOLD units produce expected prices.

Findings:

- ClanWorld currently hardcodes e18-style amounts: `INITIAL_GOLD_POOL_SEED = 50_000e18`, starter `clan.goldBalance = 3e18`, and many tests use e18 values.
- The bridge token is now fixed at 9 decimals. This keeps Solana/Base bridge accounting direct and defers any e18 game-accounting conversion to ClanWorld integration.

Gotchas:

- This is the highest-risk integration detail. A token address swap alone is not enough if decimals differ.
- ClanWorld's in-game `goldBalance` is internal accounting, while ERC20 GOLD only backs pool liquidity today. That split must be intentional.

## Component 5: End-to-End Game Flow and Operational Readiness

Status: Not started

Purpose: make the bridged token useful in the actual game and produce deploy/test evidence.

Checklist:

- [ ] Decide whether players only bridge GOLD for treasury/pool liquidity or whether clans can deposit/withdraw bridged GOLD.
- [ ] If clans need real GOLD balances, design deposit and withdrawal flows.
- [ ] Update frontend/backend config to surface the bridged GOLD token address and bridge link/UI.
- [ ] Update Convex/indexer expectations if they display or track token addresses.
- [ ] Run local/anvil deployment with external GOLD mode.
- [ ] Run Base Sepolia deployment using bridged GOLD.
- [ ] Run smoke test: bridge GOLD to Base Sepolia, seed ClanWorld pools, perform market sell/buy, verify pool reserves and clan gold changes.
- [ ] Add a liquidity recovery script/runbook to pull recoverable GOLD back to the treasury before redeploying or retiring a ClanWorld contract/pool setup.
- [ ] Record final deployment addresses and verification steps.
- [ ] Produce go/no-go checklist before mainnet.

Findings:

- ClanWorld currently treats `clan.goldBalance` as internal game accounting. There is no player-facing bridged-GOLD deposit/withdraw path yet.
- Market pools are seeded with real ERC20 balances once, then ClanWorld updates internal pool reserves during market actions.

Gotchas:

- "Replace the GOLD ERC20" and "make bridged GOLD the live player economy" are different milestones.
- Liquidity recovery needs to be designed before meaningful pool funding. If we seed bridged GOLD into ClanWorld/pools and later decide to redeploy, we need a scripted, tested way to recover every withdrawable/recoverable GOLD unit rather than relying on manual contract poking.
- Mainnet readiness needs operational controls: multisig ownership, conservative rate limits, pausing plan, monitoring, tx hash logs, and recovery runbook.

## Verification Log

- 2026-04-30 EDT: Created isolated worktree `clan-world-gold-bridge` on branch `codex/gold-bridge-unzip`.
- 2026-04-30 EDT: Unzipped `docs/planning/gold-bridge-monorepo.zip` into `gold-bridge-monorepo/`.
- 2026-04-30 EDT: Ran `pnpm review` in `gold-bridge-monorepo`; passed.
- 2026-04-30 EDT: Ran `pnpm install` in `gold-bridge-monorepo`; completed with dependency warnings and generated `pnpm-lock.yaml`.
- 2026-04-30 EDT: Ran `pnpm typecheck`; failed in Wormhole Connect config typing.
- 2026-04-30 EDT: Tried `forge test`; blocked because `forge` is not installed in this environment.
- 2026-04-30 EDT: Patched `apps/web/src/config/wormholeConnect.ts` to use `nttRoutes`, typed chain names, current `defaultInputs` shape, token configs without `key`, and `ui.walletConnectProjectId`.
- 2026-04-30 EDT: Ran `pnpm --filter @gold-bridge/web typecheck`; passed.
- 2026-04-30 EDT: Ran `pnpm --filter @gold-bridge/web build`; passed with large chunk warnings.
- 2026-04-30 EDT: Ran `pnpm review`; passed.
- 2026-04-30 EDT: Initialized worktree frontend dev port manually from `port-for --list` after `port-for --init` exhausted unrelated ttyd scratch ports.
- 2026-04-30 EDT: Started bridge UI dev server with `pnpm --filter @gold-bridge/web exec vite --host 0.0.0.0 --port 58443`; `curl -I http://localhost:58443/` returned HTTP 200.
- 2026-04-30 EDT: Checked installed/npm React and Wormhole Connect peer ranges; decided to keep React 19.
- 2026-04-30 EDT: Added `BRIDGED_GOLD_TOKEN_ADDRESS` mode to `packages/contracts/script/Deploy.s.sol`.
- 2026-04-30 EDT: Added `ExternalGoldERC20` and `test_seedPools_acceptsExternallySuppliedGoldToken` to `packages/contracts/test/SeedPools.t.sol`.
- 2026-04-30 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" forge build`; passed with existing warnings/lint notes.
- 2026-04-30 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" forge test --match-contract SeedPoolsTest`; passed, 5 tests.
- 2026-04-30 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" pnpm --filter @clan-world/contracts test`; passed, 130 tests.
- 2026-04-30 EDT: Reverted the ClanWorld deploy/test edits from the external-GOLD feasibility spike; ClanWorld contracts are no longer modified in this worktree.
- 2026-04-30 EDT: Changed bridge `GoldBridgeToken` to fixed 9 decimals and removed duplicate Base decimals env/config paths.
- 2026-04-30 EDT: Added bridge-token tests for future ClanWorld-compatible allowance pulls and unlimited allowance behavior.
- 2026-04-30 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" forge build` in `gold-bridge-monorepo/packages/contracts`; passed with only modifier-size lint notes.
- 2026-04-30 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" forge test` in `gold-bridge-monorepo/packages/contracts`; passed, 6 tests.
- 2026-04-30 EDT: Ran `pnpm review` in `gold-bridge-monorepo`; passed, including the 9-decimal token static check.
- 2026-04-30 EDT: Ran `pnpm --filter @gold-bridge/web typecheck`; passed.
- 2026-04-30 EDT: Ran `pnpm --filter @gold-bridge/web build`; passed with large Wormhole dependency chunk warnings.
- 2026-04-30 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" pnpm test:contracts` in `gold-bridge-monorepo`; passed, 6 tests.
- 2026-04-30 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" pnpm build` in `gold-bridge-monorepo`; passed with Foundry modifier-size lint notes and large Wormhole dependency chunk warnings.
- 2026-04-30 EDT: Installed NTT CLI via `scripts/01-install-ntt-cli.sh`; `ntt v1.7.0`.
- 2026-04-30 EDT: Installed Solana/Agave CLI via Anza stable installer; `solana-cli 3.1.14`, `spl-token-cli 5.5.0`.
- 2026-04-30 EDT: Created ignored local deployment files in `gold-bridge-monorepo`: `.env`, `keys/solana-devnet-deployer.json`, `keys/evm-base-sepolia-deployer.json`, and `artifacts/local-addresses.txt`.
- 2026-04-30 EDT: Ran `PATH="/home/claude/.local/share/solana/install/active_release/bin:/home/claude/.foundry/bin:$PATH" bash scripts/00-doctor.sh`; passed with `.env` present.
- 2026-04-30 EDT: Tried Solana devnet airdrops of `2 SOL` and `0.5 SOL`; both failed due faucet rate limits.
- 2026-04-30 EDT: Checked generated deployer balances; Solana deployer has `0 SOL`, Base Sepolia deployer has `0`.

## Open Questions

- What is the real Solana GOLD mint address?
- What are the real Solana GOLD decimals?
- Confirm production Solana GOLD uses 9 decimals before mainnet deployment; bridge token is currently fixed at 9 decimals.
- Is bridged GOLD only the treasury/pool backing asset for now, or should clan balances become externally depositable/withdrawable?
- Do we redeploy ClanWorld for the bridged GOLD switch, or design a migration path for an existing deployment?
- Who controls Base token owner/minter, NTT manager owners, and pauser roles during testnet and production?

## Next Actions

1. Prepare Solana devnet + Base Sepolia `.env` values.
2. Deploy the 9-decimal Base GOLD token with `pnpm deploy:base-token`.
3. Initialize and configure Wormhole NTT in Solana locking mode and Base burning mode.
4. Run tiny two-way transfer proofs and record addresses/tx hashes before returning to ClanWorld integration.
