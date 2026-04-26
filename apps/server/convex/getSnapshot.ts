import type { WorldSnapshot } from '@clan-world/shared';

// Stub Convex query — Wave 0 placeholder. Real impl reads from snapshot tables
// hydrated by the indexer (see docs/planning/V1/02 Frontend Spec/clanworld_convex_backend_spec.md).
//
// We deliberately do NOT import { query } from 'convex/server' yet — that requires
// the convex codegen step. This file compiles as plain TS for typecheck.

export async function getSnapshot(): Promise<WorldSnapshot> {
  return {
    tick: 0,
    tickEpoch: { startedAt: 0, durationMs: 20_000 },
    regions: [],
    clans: [],
  };
}
