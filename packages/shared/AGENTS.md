# packages/shared — AGENTS.md

Shared TypeScript surface for the monorepo. Two responsibilities: data types and adapter interfaces. Every other workspace depends on this one.

## What this package does

- Exports core game types: `WorldSnapshot`, `ClanFullView`, `Tick`, `Region`, `Clan`, `ClanOrder`, `Whisper`, `TickEpoch`.
- Exports four adapter interfaces (`IChainClient`, `IConvexClient`, `IKeeper`, `ILLMClient`) plus stub + real implementations and a factory function per interface.
- The factory reads an env var (`CLAN_WORLD_USE_STUB_*` or `KEEPER_MODE`) and returns the chosen impl. Browser-safe via `_env.ts` helper.

## Wave 0 status

All types exist as **minimal placeholders** matching the frontend spec — expand as streams need them. All adapter interfaces are wired with stub implementations that return mock data; real implementations throw `not implemented` and land in Wave 1+.

## Key files

- `src/index.ts` — public entry, re-exports types and adapters.
- `src/types.ts` — game data types.
- `src/adapters/index.ts` — adapter barrel.
- `src/adapters/IChainClient.ts` — chain seam.
- `src/adapters/IConvexClient.ts` — backend seam.
- `src/adapters/IKeeper.ts` — heartbeat driver seam (3 impls: Foundry loop / KeeperHub / Convex cron).
- `src/adapters/ILLMClient.ts` — non-Elder LLM uses (narrator etc.); Anthropic + ZeroG impls.
- `src/adapters/_env.ts` — `readEnv(name)` helper that works in Node and Vite.

## Local conventions

- **Types are the source of truth.** If the contract spec or frontend spec disagrees, fix the disagreement here first, then update consumers.
- **Adapters are interfaces first, factories second.** Stubs are reference impls — they always return something sensible so consumers can run end-to-end with `CLAN_WORLD_USE_STUB_*=true` set.
- **`process.env` is forbidden in this package** — use `readEnv()` from `_env.ts`. The frontend bundles this code via Vite, which doesn't define `process`.
- **No runtime deps** beyond `@clan-world/*` — keep this package zero-dep so it bundles cleanly into both Node and browser consumers.
- **`bigint` for chain values** (treasury, gas, amounts). Number-to-bigint conversions happen at the adapter boundary.

## How it interacts with adapters

This package DEFINES the adapters; everyone else consumes them. Updates to an adapter interface ripple to every workspace — coordinate via `docs/conventions/adapter-interfaces.md`.

## Running

```bash
pnpm --filter @clan-world/shared typecheck
pnpm --filter @clan-world/shared build
```

See `../../docs/conventions/adapter-interfaces.md` for the worked example of how to add a new adapter or a new method to an existing one.
