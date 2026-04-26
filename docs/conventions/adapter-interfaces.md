# Adapter Interfaces

The integration pattern that lets parallel streams build against stable seams without blocking each other on the real impl. All adapter interfaces live in `packages/shared/src/adapters/`.

## Pattern

For every external dependency that has both a "real" implementation and a "stub" implementation, we define:

1. **An interface** — what the consumer code calls.
2. **A stub class** — returns mock data; no external dependencies.
3. **A real class** — talks to the actual external system.
4. **A factory function** — reads an env var and returns one or the other.

Consumers always call the factory. They never instantiate stub or real directly. Switching between stub and real is one env var flip.

## Worked example: `IChainClient`

```ts
// packages/shared/src/adapters/IChainClient.ts
import type { ClanFullView, ClanOrder, Tick } from '../types';
import { readEnv } from './_env';

export interface IChainClient {
  getCurrentTick(): Promise<Tick>;
  submitOrders(clanId: string, orders: ClanOrder[]): Promise<{ txHash: string }>;
  getClanFullView(clanId: string): Promise<ClanFullView>;
}

class StubChainClient implements IChainClient {
  async getCurrentTick(): Promise<Tick> {
    return 0;
  }
  async submitOrders(/* … */): Promise<{ txHash: string }> {
    return { txHash: '0xstub' };
  }
  async getClanFullView(clanId: string): Promise<ClanFullView> {
    return {
      clan: { id: clanId, name: `clan-${clanId}`, treasury: 0n },
      controlledRegions: [],
      pendingOrders: [],
      whispers: [],
    };
  }
}

class RealChainClient implements IChainClient {
  async getCurrentTick(): Promise<Tick> {
    throw new Error('RealChainClient: not implemented (Wave 1+)');
  }
  // …
}

export function createChainClient(): IChainClient {
  return readEnv('CLAN_WORLD_USE_STUB_CHAIN') === 'true'
    ? new StubChainClient()
    : new RealChainClient();
}
```

Consumer:

```ts
// apps/orchestrator/src/tick.ts
import { createChainClient } from '@clan-world/shared/adapters';

const chain = createChainClient();
const tick = await chain.getCurrentTick();
```

Switching modes:

```bash
CLAN_WORLD_USE_STUB_CHAIN=true pnpm --filter @clan-world/orchestrator dev
```

## Why this pattern

1. **Parallel streams unblock each other.** The frontend can wire `IConvexClient` end-to-end before backend stream finishes the real Convex impl, because the stub gives it real-shape data.
2. **Architecture changes don't ripple.** If Wave 2 research kills our 0G compute plan, we change the stub-or-real picker for `ILLMClient`. Consumer code is untouched.
3. **Tests are trivial.** Pass `CLAN_WORLD_USE_STUB_*=true` and the whole stack runs without external deps.
4. **Demos are repeatable.** Demo-mode is just `MOCK_MODE=true` for any flaky external system.

## Rules

- **Always interface-first.** Define the interface before either impl. Both impls implement the interface — no "real adds extra methods."
- **Stubs must always return.** Stubs never throw `not implemented` — they return sensible mock data. Reals throw `not implemented` while they're in development.
- **Reals throw `not implemented` until they work.** Don't ship half-baked reals; consumers default to stubs in dev anyway.
- **Factories read env via `readEnv()`** from `_env.ts`, never directly from `process.env`. The frontend bundles via Vite, which doesn't define `process`.
- **One factory per interface.** No multi-arg constructors — the factory is the only way in.
- **No singletons.** Consumers call the factory once at startup and pass the instance down. Multiple calls return new instances.

## Adapters in this repo

| Interface | Purpose | Toggle var |
|---|---|---|
| `IChainClient` | onchain read/write | `CLAN_WORLD_USE_STUB_CHAIN` |
| `IConvexClient` | Convex backend read/sub | `CLAN_WORLD_USE_STUB_CONVEX` |
| `IKeeper` | heartbeat driver | `KEEPER_MODE` (`foundry-loop` \| `keeperhub` \| `convex`) |
| `ILLMClient` | non-Elder LLM uses | `CLAN_WORLD_USE_STUB_LLM` |

(Note: `IKeeper` doesn't have a stub/real split — it has 3 mode-selected impls. Same factory pattern, different selection logic.)

## When to add a new adapter

Add a new adapter interface when:
- A new external system is introduced (e.g., 0G Storage in S2).
- A choice of provider is anticipated (e.g., Claude vs ZeroG for LLM).
- Tests want to mock something that's currently hard-coded.

Don't add an adapter for:
- Internal utility code (e.g., a date formatter).
- One-call-at-startup dependencies (e.g., reading a config file).

If in doubt: write the consumer code first with the dependency inline. If you find yourself reaching for `process.env.NODE_ENV === 'test'` or copying that file across packages, the time has come for an adapter.

## Updating an existing adapter

If you need a new method on an existing interface:

1. Add the method signature to the interface in `packages/shared/src/adapters/`.
2. Add a stub impl that returns mock data.
3. Add a real impl that throws `not implemented` if not yet ready.
4. Update consumers — typecheck will tell you who broke.
5. Bump nothing; we're a private monorepo, this is just a git commit.

Coordinate adapter changes via PR review — they touch every consumer and warrant a closer look than a typical change.
