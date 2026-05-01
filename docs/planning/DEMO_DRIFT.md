# ClanWorld — Demo Drift Register

Enumerates every demo/fake/stub component in the codebase. Each entry notes: what it is, why it exists, and which phase removes or replaces it.

---

## Contracts

| File | Description | Remove/replace phase |
|------|-------------|----------------------|
| `packages/contracts/src/ClanWorldStub.sol` | No-op stub implementing `IClanWorld`. All functions revert or return zero values. Used for test harness bootstrapping and local integration smoke tests. Do not extend; do not delete — it is the test double. | Phase 4 (swap for real contract on live network; stub stays for tests) |

---

## Server (Convex)

| File / Location | Description | Remove/replace phase |
|-----------------|-------------|----------------------|
| `apps/server/convex/heartbeat.ts` lines 33–65 (`advanceTick` mutation) | Demo-only fake tick advance. Reads the latest `worldSnapshot` row from Convex, increments `tick` by 1, and inserts a new row. Does not read chain state. Simulates world progression purely in Convex without any on-chain heartbeat call. | Phase 4 — replace with chain-reading refresh that calls `IClanWorld.getWorldSnapshot()` and writes real state |
| `apps/server/convex/crons.ts` | 5-second cron that calls `advanceTick`. Drives the fake tick loop in demo mode. Not behind a feature flag. | Phase 4 — delete entirely (do not gate; remove the cron job) |
| `apps/server/convex/mock.ts` | `seedMockState` mutation. Inserts hardcoded `MOCK_CLANS` + `MOCK_REGIONS` into Convex. Invoked manually via `pnpm convex run mock:seedMockState`. Nothing reads `MOCK_MODE` at runtime yet — the env toggle is a placeholder. | Phase 1 — remove once real chain seeding is wired |
| `apps/server/.env.template` — `MOCK_MODE=true` | Placeholder env flag. Not read at runtime; noted in `mock.ts` as a future toggle for Wave 1. | Phase 1 — wire or remove |

---

## Web frontend

| File / Location | Description | Remove/replace phase |
|-----------------|-------------|----------------------|
| `apps/web/src/WorldMap.tsx` — `MOCK_CLANS` (line 65) | Hardcoded clan definitions (id, name, homeRegion, color, archetype). Used as the primary data source for all rendering — sprites, scoreboard, travel dots, wall levels. | Phase 4 — gate behind `VITE_CLANWORLD_DEMO_MODE`; replace with live snapshot clans |
| `apps/web/src/WorldMap.tsx` — `MOCK_LEVEL_BY_CLAN` / `derivedMonumentLevel` (line ~226) | Monument level derived from treasury amount (`treasury / 250e18`). Treasury is a demo-mock value; real monument level comes from `getClanFullView().clan.monumentLevel`. | Phase 4 — replace with `snapshot.clans[n].monumentLevel` |
| `apps/web/src/WorldMap.tsx` — `DEMO_BANDIT` (line 198) | Hardcoded bandit state: region, `attacksAtTick`, attack power. Drives bandit sprite, danger pulse, countdown UI. | Phase 4 — replace with `getActiveBanditView()` result |
| `apps/web/src/WorldMap.tsx` — `MOCK_WALL_LEVELS` (line 208) | Hardcoded wall levels per clan (indexed by `MOCK_CLANS` position). | Phase 4 — replace with `getClanFullView().clan.wallLevel` |
| `apps/web/src/WorldMap.tsx` — canned travel loop (lines ~1176–1200) | Spawns continuous random travel dots between `MOCK_CLANS` home regions so the map always has motion. Not driven by real mission state. | Phase 4 — gate behind `VITE_CLANWORLD_DEMO_MODE`; real dots come from `getClanFullView().clansmen[].activeMission` |
| `apps/web/src/App.tsx` — `VITE_REQUIRE_WORLD_APP_GUARD` (line 41) | Build-time env flag. When `true`, enforces the "Open in World App to play" MiniKit gate; when false, starts in `verified=true` and bypasses the gate for dev/demo browser runs. | Phase 4 — remove flag and bypass; require real MiniKit install check |

---

## Orchestrator

| File / Location | Description | Remove/replace phase |
|-----------------|-------------|----------------------|
| `apps/orchestrator/src/main.ts` — clan-0 hardcoded order (lines 12–18) | Hardcodes a single order for clan-0 (clanId=`'0'`, clansmanId=1, action=ChopWood). Per v4.3, clanId=0 is the null sentinel — this is a smoke-test only, not a valid game action. | Phase 1 — replace with real Elder agent loop reading live snapshot |

---

## Shared packages

| File / Location | Description | Remove/replace phase |
|-----------------|-------------|----------------------|
| `packages/shared/src/types.ts` | Wave 0 placeholder type shapes (`Region`, `Clan`, `WorldSnapshot`). Intentionally minimal; do not match v4.2 contract shapes. | Phase 1 — expand to match `IClanWorld` struct layouts |
| `packages/shared/src/mocks/clanWorldFixture.ts` | Demo dataset for the 2-minute showcase. Defines `ClanDemoState`, `BanditDemoState`, four hardcoded clans (Aldric, Mira, Brennan, Sora), and a `DEMO_WORLD_SNAPSHOT`. Used by `seedMockState` and frontend fallback rendering. | Phase 1 — remove from `src/index.ts` export; keep only in test tree |
| `packages/shared/src/index.ts` — `export * from './mocks/clanWorldFixture'` | Exports demo fixture into the public package surface. Demo data leaks into prod bundle. | Phase 1 — remove this export |
| `packages/shared/src/adapters/IKeeper.ts` | Stub adapter interfaces. Real implementations throw `not implemented`. | Phase 1 (KeeperHub), Phase 2 (AXL) — replace stubs per integration plan |
| `packages/agents/src/cli.ts` | Wave 0 stub: only `elder world snapshot` is implemented; returns mock JSON. Full command surface deferred. | Phase 1 — implement real chain read |

---

## Landing / lore

| File / Location | Description | Remove/replace phase |
|-----------------|-------------|----------------------|
| `apps/landing/src/pages/LorePage.tsx` — gameplay constants | Narrative copy contains gameplay numbers (gather durations: 3 ticks, cooldown: ~3 ticks) that contradict v4 spec (cooldown = 60s / 1 tick at 60s cadence). These are lore-facing approximations, not authoritative. See `CANONICAL_SPEC.md` rank 9. | Non-authoritative; update copy when final numbers are locked for Submission 2 |
| `apps/landing/src/data/sponsors.ts` — `TODO(post-hackathon)` | Placeholder SVG sponsor logos for KeeperHub, Gensyn AXL, 0G. | Post-hackathon — replace with final assets |

---

## Notes

- Entries marked "Phase 4" correspond to the WorldMap canvas chain-wiring phase.
- Entries marked "Phase 1" correspond to the Convex + chain client wiring phase.
- `ClanWorldStub.sol` is intentionally kept indefinitely as a test double; "Phase 4" only means the stub is no longer the live deployment target.
- The `VITE_REQUIRE_WORLD_APP_GUARD` flag must be set to `true` to keep the World App gate in any Submission 2 production build.
