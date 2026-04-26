# Stream: Ops

Operational conventions for ClanWorld.

## Makefile

(Wave 1+) A root `Makefile` collects the high-frequency commands. Modeled on `docs/planning/V1/02 Frontend Spec/Makefile`.

Likely targets:

```make
make install          # pnpm install
make dev              # turbo run dev (all workspaces)
make build            # turbo run build
make typecheck        # turbo run typecheck

make deploy-s1        # forge script Deploy → World Chain Sepolia
make deploy-s2        # forge script Deploy → Base Sepolia

make heartbeat-loop   # ./scripts/start-heartbeat-loop.sh
make demo-reset       # nuke local state, redeploy, reseed regions
make agent-fund       # send 0.1 ETH from faucet to each agent wallet
```

Wave 0 has no Makefile yet — every command is `pnpm …` direct.

## demo-reset workflow

For repeatable demo recordings:

1. Stop orchestrator and heartbeat loop.
2. Redeploy contracts (fresh address — clean state).
3. Update `ENGINE_ADDRESS` in `.env.local`.
4. Wipe local Convex deployment data (or use a separate clean deployment).
5. Re-fund agent wallets from faucet.
6. Restart orchestrator and heartbeat loop.

`make demo-reset` automates this in Wave 2+.

## Agent funding

Each Elder needs gas to submit orders. For testnet:

- World Chain Sepolia faucet: TBD (PM action item)
- Base Sepolia faucet: standard Base Sepolia faucet, 0.1 ETH per request

Agent wallets are hot-keys. Cap each at 0.5 ETH testnet. Refund as needed.

## Per-environment Convex deployments

| Env | Convex deployment | Chain | Notes |
|---|---|---|---|
| Local dev | per-dev preview | local anvil or testnet | use `MOCK_MODE` flags first |
| S1 demo | `clanworld-s1-prod` | World Chain Sepolia | shared credentials, see runbook |
| S2 demo | `clanworld-s2-prod` (or reconfigured S1) | Base Sepolia | shared credentials |

## Logging

(Wave 1+) Three log streams:

1. **Orchestrator stdout** — tick pump, Elder spawn/restart events.
2. **Per-Elder transcripts** — Claude Code persists these per `~/.claude-clan-{n}/`.
3. **Convex logs** — `convex logs` in the apps/server dir.

Aggregate to a single OTEL collector in S2+.

## Demo recording

For Submission 1:
- Record on a real phone via World App (canonical demo).
- Backup: screen-record from a Mac with World App in iOS simulator (if simulator works) or a desktop browser pretending to be the World App user-agent.

## Wallet management

Two-wallet model for S2:
- **Treasury wallet:** offline-signed, holds the multisig that owns the engine contract.
- **Agent wallets:** hot, capped, replenished from faucet.

Never mix the two. Treasury wallet keys never exist on disk on the demo machine.

## Secrets

`.env.local` is the only place secrets live. Never commit. Never log. The `WEBHOOK_SHARED_SECRET` in particular: keepers and Convex share it, but operators should rotate it after each major demo.
