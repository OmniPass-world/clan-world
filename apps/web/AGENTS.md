# apps/web — AGENTS.md

Vite + React frontend. The user-facing surface for both Submissions: in S1 it's wrapped as a World mini app via MiniKit; in S2 it runs in a regular browser pointed at Base Sepolia.

## What this package does

- Renders the world map (8 regions), clan panels, mission queue, whisper feed.
- Subscribes to Convex queries via `IConvexClient` for live snapshot + whispers.
- Calls `IChainClient` for any direct chain reads (rare — most reads go through Convex).
- For S1, mounts the MiniKit + World ID flow at clan mint.

## Wave 0 status

A `Hello ClanWorld` page renders a mock `WorldSnapshot` from `@clan-world/shared`. No real Convex wiring, no Pixi, no region polygons. The MiniKit + idkit deps are installed but **not initialized** — placeholder comment in `src/main.tsx`. This is intentional: Submission 1 is a thin wrapper, real World integration UX is researched in a later wave.

## Key files

- `src/main.tsx` — entry point, will wrap `<App>` in `<MiniKitProvider>` once integrated.
- `src/App.tsx` — Wave 0 page, will become the world map shell.
- `vite.config.ts` — port read from `PORT` env (per `~/claudes-world` ADR 0003).
- `index.html` — viewport meta tag set for mobile (World App is phone-first).

## Local conventions

- **No state management library** until the world map needs it. React state + Convex live queries are enough through M5.
- **Pixi for the canvas only.** UI chrome (panels, modals) stays in plain React.
- **Region polygons are SVG-authored** in `assets/regions/` (not Pixi sprites); they're the "if behind, cut to" fallback in `BUILD_PLAN.md`.
- **No CSS framework** for Wave 0–1; inline styles are fine. Add Tailwind only if a designer joins the team.

## How it interacts with adapters

- **`IConvexClient`** — primary data source. Frontend imports `createConvexClient()` from `@clan-world/shared/adapters` and subscribes via the returned interface. Stub mode returns mock data so the frontend can render before Convex is wired.
- **`IChainClient`** — used only for direct reads where Convex hasn't indexed yet (e.g., the very first tick before the indexer cron runs). Stub returns hardcoded `tick=0`.
- **`ILLMClient`** — never used by the frontend. Whisper text comes from the chain via Convex.
- **`IKeeper`** — never used by the frontend.

## Running

```bash
pnpm --filter @clan-world/web dev   # Vite dev, port from $PORT
pnpm --filter @clan-world/web build
```

For S1 demo, the deployed URL is loaded inside the World App as a mini app — see `docs/guides/stream-frontend.md`.
