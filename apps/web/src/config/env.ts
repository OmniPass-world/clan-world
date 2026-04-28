/**
 * Shared environment-flag exports for `apps/web`.
 *
 * Why this file exists: previously `WorldMap.tsx` imported `DEMO_MODE` from
 * `./App`, while `App.tsx` (transitively, via `MainApp`) imported `WorldMap`.
 * That created a module cycle — bundlers can return undefined bindings during
 * initialization, and tests can't isolate either module without dragging the
 * other in. PR #133 review MUST FIX #3.
 *
 * Rule: env flags read at module-init time live here. Components import from
 * `./config/env` (a leaf module) — never from another component file.
 */

/**
 * DEMO_MODE — gates all mock/fake data in WorldMap.
 *
 * - true  (env unset OR VITE_CLANWORLD_DEMO_MODE=true): render mock clans,
 *   bandits, walls, monuments, agentLogs. Default-on for UAT visibility so the
 *   worldmap renders without manual env setup. Also used for hackathon Loom
 *   recordings + judges-without-World-App preview.
 * - false (VITE_CLANWORLD_DEMO_MODE=false): canvas + scoreboard ONLY render
 *   real Convex/chain state. Empty world = empty UI. Set explicitly in
 *   `.env.production` (or Vercel project env at build time) when Phase B
 *   Convex data lands.
 *
 * Default policy: missing/unset env var → DEMO_MODE on (true). Only an
 * explicit `'false'` string disables it.
 */
export const DEMO_MODE = import.meta.env.VITE_CLANWORLD_DEMO_MODE !== 'false';

/**
 * DEMO_BYPASS_WORLD_GUARD — bypass the "Open in World App" gate.
 *
 * When true, App.tsx skips the MiniKit.isInstalled() check and renders the
 * canvas directly. Set to 'true' permanently by `pnpm dev` script (see
 * `apps/web/package.json`); production builds default to false.
 */
export const DEMO_BYPASS_WORLD_GUARD =
  import.meta.env.VITE_DEMO_BYPASS_WORLD_GUARD === 'true';
