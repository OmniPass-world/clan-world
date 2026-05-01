# GOLD Bridge Readiness Plan

Living plan for getting Solana-canonical GOLD bridged to Base with Wormhole NTT, then replacing ClanWorld's current deployed/native GOLD ERC20 with the Base-side bridged GOLD token.

Last updated: 2026-05-01 05:42 EDT

## Goal

Solana GOLD remains the canonical asset. Wormhole NTT locks GOLD on Solana, mints/releases the Base-side GOLD representation, and ClanWorld uses that Base GOLD token as its game GOLD boundary token.

## Current Readiness Snapshot

- Standalone bridge scaffold: about 70% ready.
- Bridge token readiness: Base GOLD is now fixed at 9 decimals, upgradeable through a timelocked transparent proxy, and includes a V1 allowlist-scoped recovery hook that can be disabled forever or removed through V2.
- ClanWorld integration: intentionally deferred. Do not modify existing ClanWorld contracts/scripts/tests until the bridge and token deployment flow are proven.
- Current phase: proxy-token testnet bridge proof complete. The upgradeable Base GOLD proxy, fresh NTT deployment, timelock minter handoff, preflight, and tiny two-way bridge proof all succeeded on Solana devnet and Base Sepolia.

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
- [x] Base `GoldBridgeToken` deploys as an initializer-based upgradeable implementation behind a transparent proxy.
- [x] Base token owner and ProxyAdmin owner can be controlled by a timelock.
- [x] V1 recovery is allowlist-scoped and can be permanently disabled.
- [x] V2 removes the recovery ABI while preserving balances, allowances, owner, minter, and total supply.
- [x] Deploy script no longer accepts a separate Base decimals env var.
- [x] Frontend generated config derives Base decimals from the Solana token decimals/default 9 instead of a duplicate Base decimals setting.
- [x] Contract tests cover NTT mint/burn behavior.
- [x] Contract tests cover ERC-20 allowance pull behavior for future ClanWorld compatibility.
- [x] Run contract tests and static review after edits.

Findings:

- Wormhole's EVM NTT docs require burn-and-mint tokens to implement `burn(uint256)` and `mint(address,uint256)`, with minter authority handed to the NTT manager after deployment.
- The token does not need ClanWorld-specific game logic. A 9-decimal ERC-20/NTT surface remains the bridge-layer boundary.
- Upgradeability is useful for late bridge-token bugs, but the trust model must be explicit. The current design uses OpenZeppelin transparent proxy separation: token behavior in the implementation, upgrade power in ProxyAdmin, and operational delay in TimelockController.
- The recovery function is intentionally named `recoverFromAllowedSource`, not owner transfer, and NatSpec states that user wallets should not be allowlisted.
- If ClanWorld wants internal e18 accounting later, conversion should happen in the ClanWorld integration layer, not inside the bridge token.

## Phase 4 Execution Plan: Testnet Bridge Deployment Proof

Status: Completed

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
- [x] Fund Solana devnet deployer with SOL.
- [x] Create 9-decimal Solana devnet GOLD mint or set `SOLANA_TOKEN_MINT` to an existing mint.
- [x] Fund Base Sepolia deployer with ETH.
- [x] Run `pnpm deploy:base-token`.
- [x] Run `pnpm ntt:init`.
- [x] Run `pnpm ntt:overrides`.
- [x] Run `pnpm ntt:add-solana`.
- [x] Run `pnpm ntt:add-base`.
- [x] Configure conservative rate limits in `ntt/deployment.json`.
- [x] Run `pnpm ntt:push`.
- [x] Run `pnpm ntt:addresses`.
- [x] Run `pnpm base:set-minter`.
- [x] Run `pnpm web:export-config`.
- [x] Execute tiny Solana -> Base transfer.
- [x] Execute tiny Base -> Solana transfer.
- [x] Record tx hashes and final deployed addresses.

Historical direct-token test addresses:

- Solana devnet deployer: `BJmjhXs5h6d8o15kK1YppkiJExu6FWBDJyJFUyfp9L2p`
- Base Sepolia deployer: `0x96E3054A6Bd6b6d8710dE3029D3bA2EbCb930B5D`
- Solana devnet GOLD mint: `6NLCfbAzMyykwjwifAZr8WRBTPsb8u5s1uAVvGBGGa4r`
- Solana NTT manager/program: `EQpZrkhQzc68x2qXV9imPstACEGEJJuXTQ8S2fAXpZva`
- Solana Wormhole transceiver: `Gtim3284zCdputS7dVgugx426Mce323Q7VJwhd46xR2P`
- Base Sepolia GOLD token: `0x57A893ACE218ccCf6A0958b5354Aaad58777806F`
- Base Sepolia NTT manager: `0x3df4e9Cd48B7c8290F80546547854ac8C82Dc276`
- Base Sepolia Wormhole transceiver: `0x787aA04c0F27843DC9e612887FD7C60f102E3fE6`

Current proxy-token test addresses:

- Solana devnet deployer: `BJmjhXs5h6d8o15kK1YppkiJExu6FWBDJyJFUyfp9L2p`
- Base Sepolia deployer: `0x96E3054A6Bd6b6d8710dE3029D3bA2EbCb930B5D`
- Solana devnet GOLD mint: `6NLCfbAzMyykwjwifAZr8WRBTPsb8u5s1uAVvGBGGa4r`
- Solana NTT manager/program: `DQAKHw5eimsucy37oTgwRWCEBrJhyfht6Z6YPx6ut4hH`
- Solana Wormhole transceiver: `81fVCz1fVChbZkqgmzFkudVuaAMDkTrK2gTWwNLi2k7M`
- Base Sepolia GOLD proxy token: `0xF6F49EAf9EA71e69450191aFe22EFaed8E2f7995`
- Base Sepolia GOLD implementation: `0x6A5DD88cd7dF0D6FD9478c6E451E5Ef6309DaC4c`
- Base Sepolia GOLD timelock: `0x686f671F2276127d52d294bC0E981C89FDA25C34`
- Base Sepolia GOLD ProxyAdmin: `0x9381505b073bacc179c35c91a05390c5486ff594`
- Base Sepolia NTT manager: `0x2B602BbF837Bd845Cc8b40AE70Dc6AB5b191eF3c`
- Base Sepolia Wormhole transceiver: `0x9a683a5464aCf816dc5e87F8686828f063e54104`

Transfer proof:

- Solana -> Base amount: `1.000000000` GOLD.
- Solana -> Base source tx: `5Q5kZFvU1W9yKdpG8GDqdr8sBeK5v9mmenjXZ8K9c3xj3f656QrW35XC9LkgAaUpPrRGurSu46dVbNsixc6WV8aA`.
- Solana -> Base Wormholescan: `https://wormholescan.io/#/tx/5Q5kZFvU1W9yKdpG8GDqdr8sBeK5v9mmenjXZ8K9c3xj3f656QrW35XC9LkgAaUpPrRGurSu46dVbNsixc6WV8aA?network=Testnet`.
- Base -> Solana amount: `0.500000000` GOLD.
- Base -> Solana approve tx: `0xc861fe52d3b92a38f4374729dee79e25a75aa0a10b7280347549dd3f31e7a07b`.
- Base -> Solana transfer tx: `0xe2dd6ab8003134a3a0d8a5a4ba17b331600aa50b71ef0ae6e47dd98ddcf32c22`.
- Base -> Solana Wormholescan: `https://wormholescan.io/#/tx/0xe2dd6ab8003134a3a0d8a5a4ba17b331600aa50b71ef0ae6e47dd98ddcf32c22?network=Testnet`.
- Post-proof balances: Solana deployer has `999999.5` devnet GOLD; Base deployer has `0.500000000` Base GOLD.

Proxy-token transfer proof:

- Solana -> Base amount: `1.000000000` GOLD.
- Solana -> Base source tx: `4VZjBLoxG3yrqRiG9SYevzVfgRHhGDf4beXMntpvyr79ssD2Bgh8R7L8DpUmYhxxUsLiwHsFXEUieZTSfw1hsqx1`.
- Solana -> Base Wormholescan: `https://wormholescan.io/#/tx/4VZjBLoxG3yrqRiG9SYevzVfgRHhGDf4beXMntpvyr79ssD2Bgh8R7L8DpUmYhxxUsLiwHsFXEUieZTSfw1hsqx1?network=Testnet`.
- Base -> Solana amount: `0.500000000` GOLD.
- Base -> Solana approve tx: `0xf51fd022743cfe0a7101ffcf16bcca87914999cddcfc0e8a01131ee3b8e7f7c2`.
- Base -> Solana transfer tx: `0xd62c3970e3852719bc7e0963324227a2f7bb4dc25dc932e3f88ff10dc3f7ede0`.
- Base -> Solana Wormholescan: `https://wormholescan.io/#/tx/0xd62c3970e3852719bc7e0963324227a2f7bb4dc25dc932e3f88ff10dc3f7ede0?network=Testnet`.
- Post-proof balances: Solana deployer has `999999` devnet GOLD; Base deployer has `0.500000000` proxy Base GOLD.

Findings:

- `ntt new` refuses to run inside an existing git repository. `scripts/02-init-ntt-project.sh` now resolves `NTT_PROJECT_DIR` to an absolute path and scaffolds from the target parent directory, which supports local ignored NTT project directories outside the repo.
- The local NTT project currently lives outside the worktree at `../../clan-world-gold-bridge-ntt-local` relative to `gold-bridge-monorepo`.
- NTT's Solana package required Solana CLI `1.18.26` and Anchor CLI `0.29.0`. The deployment flow switched Solana from Agave `3.1.14` to `1.18.26`; Anchor `0.29.0` was installed with AVM.
- The first Solana NTT build is slow on a fresh host because it compiles the Solana program and test/runtime dependencies before deployment.
- `pnpm ntt:add-base` needed `--skip-verify` instead of `-skip-verify`.
- Base NTT add-chain simulation reported a token `decimals()` `NotActivated` fork/simulation issue even though `cast call decimals()` succeeded on-chain. For this testnet deployment, the command had to continue without simulation.
- `pnpm ntt:push` needed `ETH_PRIVATE_KEY` exported and the Solana `--payer` supplied.
- The transfer helper now passes Solana payer, EVM private key, RPC overrides, and optional destination msg value. Base -> Solana needed `TEST_TRANSFER_DESTINATION_MSG_VALUE=10000000`.
- Executor ETAs on Wormhole testnet can be very long and noisy. The CLI still found VAAs for both test transfers and balances confirmed both directions.
- The proxy-token Solana NTT deployment initially failed with insufficient funds: it needed about `6.52 SOL` while the payer had about `3.51 SOL`. After funding the payer to `13.51 SOL`, rerunning `pnpm ntt:add-solana` continued successfully.
- The proxy token deploy helper tx succeeded, but `scripts/03-deploy-base-token.sh` queried the helper before RPC code was visible. The script now waits for helper bytecode before reading proxy/implementation/timelock addresses.
- The zero-delay timelock minter handoff scheduled successfully, but same-invocation execution hit `TimelockUnexpectedOperationState`. Executing the same operation after the next block succeeded.
- Base -> Solana VAA lookup for the proxy-token proof took 558 retry attempts before Wormholescan returned the VAA. Final balances still confirmed the transfer.

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

Status: Completed on testnet

Purpose: prove the bridge itself works before touching ClanWorld economics.

Checklist:

- [x] Fill `.env` for Solana devnet and Base Sepolia.
- [x] Confirm exact Solana GOLD test mint or create a devnet test mint that mirrors production decimals.
- [x] Deploy Base GOLD representation token.
- [x] Run `pnpm ntt:init`.
- [x] Run `pnpm ntt:overrides`.
- [x] Add Solana in locking mode.
- [x] Add Base in burning mode.
- [x] Configure conservative rate limits in `ntt/deployment.json`.
- [x] Run `pnpm ntt:push`.
- [x] Set Base token minter to Base NTT manager.
- [x] Export frontend config with `pnpm web:export-config`.
- [x] Execute tiny Solana -> Base transfer.
- [x] Execute tiny Base -> Solana transfer.
- [x] Record tx hashes, NTT manager addresses, transceiver addresses, token addresses, and Wormholescan links.

Findings:

- The scaffold's NTT direction is correct for an existing immutable Solana token: Solana locking mode, Base burning mode.
- Public Wormhole docs align with the planned CLI commands for SVM locking and EVM burning.
- Testnet proof used Solana devnet and Base Sepolia with a fresh 9-decimal devnet GOLD mint.
- The Base token minter is now the Base NTT manager, not the deployer.

Gotchas:

- Solana official testnet is not the target for NTT testing; use Solana devnet with `WORMHOLE_NETWORK=Testnet`.
- Solana mainnet deployment should use a paid/private RPC, not the public endpoint.
- Rate-limit precision must be confirmed against the current NTT CLI/docs and not guessed from token decimals alone.
- Local deployment artifacts and private keys are intentionally ignored. The live local NTT project sits outside the repo, while the frontend generated config records the public deployed addresses.

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

Status: In progress

Purpose: make the bridged token useful in the actual game and produce deploy/test evidence.

Checklist:

- [ ] Decide whether players only bridge GOLD for treasury/pool liquidity or whether clans can deposit/withdraw bridged GOLD.
- [ ] If clans need real GOLD balances, design deposit and withdrawal flows.
- [ ] Update frontend/backend config to surface the bridged GOLD token address and bridge link/UI.
- [ ] Update Convex/indexer expectations if they display or track token addresses.
- [ ] Run local/anvil deployment with external GOLD mode.
- [ ] Run Base Sepolia deployment using bridged GOLD.
- [ ] Run smoke test: bridge GOLD to Base Sepolia, seed ClanWorld pools, perform market sell/buy, verify pool reserves and clan gold changes.
- [x] Add a liquidity recovery script/runbook to pull recoverable wallet-held Base GOLD back to Solana before redeploying or retiring a setup.
- [x] Add a deployment artifact export command that writes public addresses, tx hashes, chain names, and modes without secrets.
- [x] Add preflight checks for Solana mint decimals, Base token decimals, Base token minter handoff, and NTT status.
- [x] Add a production deployment checklist covering fresh wallets, backups, funding, tiny proof transfers, artifact archival, and recovery proof.
- [x] Add token-level allowlist-scoped recovery for ClanWorld-held pool/treasury GOLD before meaningful liquidity is seeded.
- [x] Add timelock schedule/execute helpers for owner-only Base token operations.
- [x] Add proxy-info/preflight checks for proxy admin, implementation, token owner, and timelock ownership.
- [x] Redeploy Base Sepolia GOLD with the upgradeable proxy stack and rerun two-way NTT proof.
- [x] Record final deployment addresses and verification steps.
- [ ] Produce go/no-go checklist before mainnet.

Findings:

- ClanWorld currently treats `clan.goldBalance` as internal game accounting. There is no player-facing bridged-GOLD deposit/withdraw path yet.
- Market pools are seeded with real ERC20 balances once, then ClanWorld updates internal pool reserves during market actions.
- Operator-held Base GOLD can now be recovered to Solana with `pnpm liquidity:recover-base`; the command defaults to dry run and requires `RECOVERY_EXECUTE=true` to submit.
- `pnpm artifacts:export` writes `artifacts/deployment-summary.json`; the `artifacts` directory is ignored, so archive the JSON intentionally with deployment evidence.
- `pnpm preflight` is the quick confidence command after deployment changes. It does not replace transfer proofs, but it catches the easy-to-miss decimals and minter mistakes.
- Base GOLD now deploys as a transparent proxy. The old Base Sepolia direct-token proof remains useful historical evidence, while the current proof uses the proxy/timelock stack.
- `pnpm base:set-minter` now schedules `setMinter` through the timelock when `BASE_TIMELOCK_ADDRESS` is set. Execute after the delay with `pnpm timelock:execute`; testnets with zero delay may use `TIMELOCK_EXECUTE_IMMEDIATELY=true`.

Gotchas:

- "Replace the GOLD ERC20" and "make bridged GOLD the live player economy" are different milestones.
- Liquidity recovery needs to be tested before meaningful pool funding. If we seed bridged GOLD into ClanWorld/pools and later decide to redeploy, only allowlisted source addresses can be recovered by the token-level hook.
- Mainnet readiness needs operational controls: multisig ownership, conservative rate limits, pausing plan, monitoring, tx hash logs, and recovery runbook.
- The wallet recovery helper only controls the configured EVM deployer wallet. Token-level `recoverFromAllowedSource` can recover from allowlisted contracts, but it is intentionally timelocked and should be disabled forever or removed in V2 after the migration window.

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
- 2026-04-30 EDT: Confirmed user-funded Solana devnet deployer balance: `5 SOL`.
- 2026-04-30 EDT: Created Solana devnet 9-decimal GOLD mint `6NLCfbAzMyykwjwifAZr8WRBTPsb8u5s1uAVvGBGGa4r`.
- 2026-04-30 EDT: Created Solana token account `7SPBoxy9LQmFXhE53ksbiZTddrNtJHVTosERFwinTG4d` and minted `1,000,000` devnet GOLD to it.
- 2026-04-30 EDT: Patched `scripts/02-init-ntt-project.sh` so `ntt new` can scaffold from outside an existing git checkout.
- 2026-04-30 EDT: Ran `pnpm ntt:init`; created local NTT project outside the repo at `../../clan-world-gold-bridge-ntt-local`.
- 2026-04-30 EDT: Ran `pnpm ntt:overrides`; wrote RPC overrides.
- 2026-04-30 EDT: Installed Anchor with AVM and selected `anchor-cli 0.29.0` after NTT reported that exact version requirement.
- 2026-04-30 EDT: Ran `pnpm ntt:add-solana`; succeeded. Solana locking mode added with manager/program `EQpZrkhQzc68x2qXV9imPstACEGEJJuXTQ8S2fAXpZva` and Wormhole transceiver `Gtim3284zCdputS7dVgugx426Mce323Q7VJwhd46xR2P`.
- 2026-04-30 EDT: Funded bridge Base Sepolia deployer with `2 ETH` from the main repo deployer. Funding tx: `0x9e64c39228dfca8dc9c3d3d50ef8d34bc1482f2c785f4e41d25d2ef4586a1e79`.
- 2026-04-30 EDT: Ran `pnpm deploy:base-token`; deployed Base Sepolia GOLD `0x57A893ACE218ccCf6A0958b5354Aaad58777806F`. Deploy tx: `0x91a79c8bcbdb404a2cd74aff85fcdd53bcb5b82d6dacd596efdaf5fc8885fcb6`.
- 2026-04-30 EDT: Verified Base GOLD `decimals() == 9`, owner deployer, and initial minter deployer.
- 2026-04-30 EDT: Patched `scripts/06-add-base-burning.sh` to use `--skip-verify` and `--yes`.
- 2026-04-30 EDT: Ran `pnpm ntt:add-base`; deployed Base Sepolia NTT manager `0x3df4e9Cd48B7c8290F80546547854ac8C82Dc276` and transceiver `0x787aA04c0F27843DC9e612887FD7C60f102E3fE6`.
- 2026-04-30 EDT: Set conservative local NTT limits to `100.000000000` GOLD each direction.
- 2026-04-30 EDT: Patched `scripts/11-ntt-push.sh` to export `ETH_PRIVATE_KEY`, pass Solana `--payer`, and use `--yes`.
- 2026-04-30 EDT: Ran `pnpm ntt:push`; deployment config pushed successfully.
- 2026-04-30 EDT: Ran `pnpm base:set-minter`; Base GOLD minter set to Base NTT manager. Tx: `0xab29d0e5a98fa6d1c9241bdcb837cb9135220e68b9c50b712ed765ea30e5ac29`.
- 2026-04-30 EDT: Ran `pnpm web:export-config`; generated frontend config with live testnet addresses.
- 2026-04-30 EDT: Patched `scripts/12-test-transfer.sh` to pass Solana payer, EVM signer env, RPC overrides, and optional destination msg value.
- 2026-04-30 EDT: Ran Solana -> Base test transfer of `1` GOLD. Source tx: `5Q5kZFvU1W9yKdpG8GDqdr8sBeK5v9mmenjXZ8K9c3xj3f656QrW35XC9LkgAaUpPrRGurSu46dVbNsixc6WV8aA`.
- 2026-04-30 EDT: Ran Base -> Solana test transfer of `0.5` GOLD. Approve tx: `0xc861fe52d3b92a38f4374729dee79e25a75aa0a10b7280347549dd3f31e7a07b`; transfer tx: `0xe2dd6ab8003134a3a0d8a5a4ba17b331600aa50b71ef0ae6e47dd98ddcf32c22`.
- 2026-04-30 EDT: Confirmed post-proof balances: Solana deployer `999999.5` devnet GOLD; Base deployer `0.500000000` Base GOLD.
- 2026-04-30 EDT: Ran `pnpm review`; passed.
- 2026-04-30 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" pnpm test:contracts`; passed, 6 tests.
- 2026-04-30 EDT: Ran `pnpm --filter @gold-bridge/web typecheck`; passed.
- 2026-05-01 EDT: Added `pnpm artifacts:export`, `pnpm preflight`, and `pnpm liquidity:recover-base` operator hardening commands.
- 2026-05-01 EDT: Updated deployment and operations docs with preflight, artifact archival, production checklist, and dry-run-first Base GOLD recovery flow.
- 2026-05-01 EDT: Ran `bash -n scripts/15-preflight.sh scripts/16-recover-base-liquidity.sh scripts/lib/env.sh`; passed.
- 2026-05-01 EDT: Ran `node --check scripts/14-export-deployment-artifacts.mjs`; passed.
- 2026-05-01 EDT: Ran `pnpm review`; passed.
- 2026-05-01 EDT: Ran `pnpm artifacts:export -- --stdout`; printed public testnet deployment summary without secrets.
- 2026-05-01 EDT: Ran `RECOVERY_DESTINATION_SOLANA_ADDRESS=BJmjhXs5h6d8o15kK1YppkiJExu6FWBDJyJFUyfp9L2p RECOVERY_AMOUNT=0.1 pnpm liquidity:recover-base`; dry run passed and did not submit a transfer.
- 2026-05-01 EDT: Ran `pnpm preflight`; passed. Confirmed Solana mint decimals `9`, Base token decimals `9`, Base token minter `0x3df4e9Cd48B7c8290F80546547854ac8C82Dc276`, and NTT config synced on chain.
- 2026-05-01 EDT: Ran `pnpm artifacts:export`; wrote ignored local artifact `artifacts/deployment-summary.json`.
- 2026-05-01 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" pnpm test:contracts`; passed, 6 tests.
- 2026-05-01 EDT: Ran `pnpm --filter @gold-bridge/web typecheck`; passed.
- 2026-05-01 EDT: Added OpenZeppelin Contracts and Contracts Upgradeable dependencies for Base GOLD proxy/timelock support.
- 2026-05-01 EDT: Reworked `GoldBridgeToken` into an initializer-based 9-decimal ERC20 with NTT mint/burn/minter behavior, timelocked allowlist-scoped recovery, and `disableRecoveryForever`.
- 2026-05-01 EDT: Added `GoldBridgeTokenV2` upgrade target that preserves V1 storage while removing the recovery ABI.
- 2026-05-01 EDT: Added `UpgradeableGoldDeployer` helper to deploy implementation, TimelockController, and TransparentUpgradeableProxy in one transaction.
- 2026-05-01 EDT: Added Base proxy info and generic timelock schedule/execute scripts.
- 2026-05-01 EDT: Updated Base deploy, minter handoff, preflight, artifact export, and docs for proxy/timelock deployment.
- 2026-05-01 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" pnpm test:contracts`; passed, 12 tests.
- 2026-05-01 EDT: Ran `pnpm --filter @gold-bridge/web typecheck`; passed.
- 2026-05-01 EDT: Ran `pnpm review`; passed.
- 2026-05-01 EDT: Ran `bash -n scripts/03-deploy-base-token.sh scripts/08-set-base-minter.sh scripts/15-preflight.sh scripts/17-print-base-proxy-info.sh scripts/18-timelock-schedule.sh scripts/19-timelock-execute.sh`; passed.
- 2026-05-01 EDT: Ran `node --check scripts/14-export-deployment-artifacts.mjs`; passed.
- 2026-05-01 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" pnpm build`; passed with existing large Wormhole chunk warnings and Foundry lint notes.
- 2026-05-01 EDT: Ran `BASE_TOKEN_EXPECTED_PROXY=false pnpm preflight` against the old direct Base Sepolia proof token; passed. Future deployments default to `BASE_TOKEN_EXPECTED_PROXY=true`.
- 2026-05-01 EDT: Re-ran `bash -n` for the updated deploy, minter, preflight, proxy-info, and timelock scripts; passed.
- 2026-05-01 EDT: Re-ran `PATH="/home/claude/.foundry/bin:$PATH" pnpm test:contracts`; passed, 12 tests.
- 2026-05-01 EDT: Re-ran `pnpm review`; passed.
- 2026-05-01 EDT: Deployed Base Sepolia upgradeable GOLD proxy `0xF6F49EAf9EA71e69450191aFe22EFaed8E2f7995`, implementation `0x6A5DD88cd7dF0D6FD9478c6E451E5Ef6309DaC4c`, timelock `0x686f671F2276127d52d294bC0E981C89FDA25C34`, and ProxyAdmin `0x9381505b073bacc179c35c91a05390c5486ff594`. Deploy helper tx: `0xd9c5d05c40f30761546399faa8c08ce216901e3e83b69251eadba84d35a15ac2`.
- 2026-05-01 EDT: Ran `pnpm base:proxy-info`; confirmed token owner and ProxyAdmin owner are the timelock, minter initially deployer, decimals `9`, and timelock delay `0`.
- 2026-05-01 EDT: Initialized fresh NTT project at `../../clan-world-gold-bridge-ntt-proxy-testnet`.
- 2026-05-01 EDT: Ran `pnpm ntt:add-solana`; deployed Solana NTT manager/program `DQAKHw5eimsucy37oTgwRWCEBrJhyfht6Z6YPx6ut4hH` and transceiver `81fVCz1fVChbZkqgmzFkudVuaAMDkTrK2gTWwNLi2k7M`.
- 2026-05-01 EDT: Ran `pnpm ntt:add-base`; deployed Base Sepolia NTT manager `0x2B602BbF837Bd845Cc8b40AE70Dc6AB5b191eF3c` and transceiver `0x9a683a5464aCf816dc5e87F8686828f063e54104` for proxy GOLD.
- 2026-05-01 EDT: Set fresh proxy NTT local limits to `100.000000000` GOLD each direction and ran `pnpm ntt:push`; passed.
- 2026-05-01 EDT: Scheduled Base GOLD minter handoff through timelock. Schedule tx: `0xd741ebf55f6f351588e8847b322f4e3c538a5295a0e6bc44e48813d003bb1bf6`. Execute tx: `0xdc56f13fed35eee612510fcab2e62236e2659b89e44a963e9a1cc7af91141fbd`.
- 2026-05-01 EDT: Ran `pnpm preflight`; passed. Confirmed Solana mint decimals `9`, Base proxy token decimals `9`, Base token minter `0x2B602BbF837Bd845Cc8b40AE70Dc6AB5b191eF3c`, ProxyAdmin owner timelock, token owner timelock, and NTT config synced on chain.
- 2026-05-01 EDT: Ran Solana -> Base proxy-token test transfer of `1` GOLD. Source tx: `4VZjBLoxG3yrqRiG9SYevzVfgRHhGDf4beXMntpvyr79ssD2Bgh8R7L8DpUmYhxxUsLiwHsFXEUieZTSfw1hsqx1`.
- 2026-05-01 EDT: Ran Base -> Solana proxy-token test transfer of `0.5` GOLD. Approve tx: `0xf51fd022743cfe0a7101ffcf16bcca87914999cddcfc0e8a01131ee3b8e7f7c2`; transfer tx: `0xd62c3970e3852719bc7e0963324227a2f7bb4dc25dc932e3f88ff10dc3f7ede0`.
- 2026-05-01 EDT: Confirmed proxy-token post-proof balances: Solana deployer `999999` devnet GOLD; Base deployer `0.500000000` proxy Base GOLD.
- 2026-05-01 EDT: Ran `pnpm web:export-config`; generated frontend config with proxy-token NTT addresses.
- 2026-05-01 EDT: Ran `pnpm artifacts:export -- --stdout` and `pnpm artifacts:export`; wrote ignored local artifact with proxy-token deployment summary.
- 2026-05-01 EDT: Ran `PATH="/home/claude/.foundry/bin:$PATH" pnpm test:contracts`; passed, 12 tests.
- 2026-05-01 EDT: Ran `pnpm --filter @gold-bridge/web typecheck`; passed.
- 2026-05-01 EDT: Ran `pnpm review`; passed.
- 2026-05-01 EDT: Ran `pnpm ntt:status`; reported `deployment.json is up to date with the on-chain configuration.`
- 2026-05-01 EDT: Ran `pnpm base:proxy-info`; confirmed Base proxy minter is the Base NTT manager after timelock handoff.

## Open Questions

- What is the real Solana GOLD mint address?
- What are the real Solana GOLD decimals?
- Confirm production Solana GOLD uses 9 decimals before mainnet deployment; bridge token is currently fixed at 9 decimals.
- Is bridged GOLD only the treasury/pool backing asset for now, or should clan balances become externally depositable/withdrawable?
- Do we redeploy ClanWorld for the bridged GOLD switch, or design a migration path for an existing deployment?
- Who controls the production timelock proposer multisig, NTT manager owners, and pauser roles?
- What production timelock delay do we want: 24 hours, 48 hours, or longer?

## Next Actions

1. Build the local deployment cockpit around the existing bridge scripts and artifacts.
2. Plan ClanWorld external bridged-GOLD integration without modifying existing contracts until the other GOLD PR is ready to merge.

## Deployment Cockpit Plan

Status: in progress.

Goal: local operator dashboard for deployment, configuration, upgrade, recovery, proof transfers, and bridge monitoring.

MVP decisions:

- Local operator app: React frontend plus localhost Node helper.
- Hybrid signing: connected wallets for visibility and future signing, existing local scripts for current deploy steps.
- Networks: Solana devnet/Base Sepolia and Solana mainnet/Base mainnet.
- Mainnet authority: no raw mainnet private keys required by default; use wallet/multisig/timelock preparation for production.
- Safety UX: preview every mutating step and require typed confirmations for high-risk/mainnet actions.

Progress:

- [x] Add local cockpit API that reads `.env`, NTT `deployment.json`, deployment artifacts, RPC state, proxy slots, token owner/minter, and balances without returning secrets.
- [x] Add guided action previews/runs for existing deploy, NTT, preflight, proof, artifact, timelock, and recovery scripts.
- [x] Replace the bridge landing UI with an operator cockpit while keeping the Wormhole Connect bridge tab available.
- [x] Add overview, addresses, authority, deploy, upgrade, recovery, and bridge tabs.
- [x] Add first wallet connection layer for injected EVM and Solana operator identity.
- [x] Add Reown AppKit EVM wallet connection and network switching for phone/mobile signing.
- [x] Add EVM transaction-intent API for Base proxy deploy, V2 implementation deploy, timelock minter handoff, V2 upgrade, recovery allowlist, and recovery disable.
- [x] Add wallet-signed UI cards that prepare, sign, wait for receipts, and reconcile local `.env` deployment state.
- [x] Add app-visible Go/No-Go checklist backed by on-chain state, artifacts, deployment config, contract code, proof txs, and manual approval notes.
- [x] Add readiness report export for deployment evidence archival.
- [x] Add guided deployment spine with phases, dependencies, blockers, fixed/prefilled/editable fields, active wallet/CLI controls, outputs, and post-step evidence.
- [ ] Run a fresh full cockpit-assisted rehearsal with connected EVM wallet signing.
- [ ] Replace remaining NTT/Solana CLI-only deploy steps with wallet-native or safer mainnet handoff flows before production use.
