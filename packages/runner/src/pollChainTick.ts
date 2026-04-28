import type { IConvexClient } from '@clan-world/shared/adapters';

/**
 * Read the current tick from Convex.
 *
 * S2 stub behaviour: if Convex is unreachable / not deployed yet, the
 * `IConvexClient` factory hands us a `StubConvexClient` that returns
 * `{ tick: 0, ... }`. The tick loop interprets `0` as "no real chain state
 * yet — keep polling". We log a one-shot warning at boot in `main.ts` when
 * `CONVEX_URL` is missing so this state is observable.
 *
 * TODO(stream-B-step-3): once Convex is deployed and exposing
 * `getCurrentTick`, wire this to a dedicated query rather than reading the
 * full snapshot — cheaper on the public Convex tier.
 */
export async function pollChainTick(convex: IConvexClient): Promise<number> {
  const snap = await convex.getSnapshot();
  return snap.tick;
}
