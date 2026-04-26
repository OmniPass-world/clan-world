# Stream: Frontend (Vite + React)

How to work on `apps/web/`.

## Setup

```bash
pnpm install
pnpm --filter @clan-world/web dev
```

The dev server reads `PORT` from env (per `~/claudes-world` ADR 0003 port allocation). Default 5173 if unset.

## MOCK_MODE

Run with stubs end-to-end:

```bash
CLAN_WORLD_USE_STUB_CONVEX=true \
CLAN_WORLD_USE_STUB_CHAIN=true \
  pnpm --filter @clan-world/web dev
```

This is the default for early Wave 0–1 work — the frontend renders mock snapshots without needing Convex or chain wired.

## Region polygons

Regions are SVG-authored, not Pixi sprites:

```
apps/web/src/assets/regions/
  region-1.svg
  region-2.svg
  ...
  region-8.svg
```

(Wave 1+) An `RegionSvg` component imports the SVG inline and overlays clan-color fills based on `WorldSnapshot.regions[].ownerClanId`. SVG keeps the cut-list shallow — if Pixi work is behind, we can ship region polygons as plain SVG without a canvas at all.

## Pixi (Wave 2+)

Pixi is for the canvas only — animated elements, sprite-based units, particle effects. The UI chrome (panels, modals, whisper feed) stays in plain React. The Pixi canvas is a sibling element in the `<App>` tree, not the root.

```tsx
// apps/web/src/canvas/WorldCanvas.tsx (Wave 2)
import { Application } from 'pixi.js';
// ...
```

Don't reach for `pixi-react` until you've prototyped the canvas in vanilla Pixi. Wrappers add weight without much benefit at our scale.

## State management

- React state + Convex live queries are enough through M5.
- If you find yourself reaching for Zustand or Redux, reconsider — the Convex subscription IS the state store.
- For derived values (e.g., "list of clans owned by current user"), use `useMemo` with the live snapshot.

## MiniKit + World ID

Wave 0 stance: deps installed, **no integration code**. See `docs/reference/sponsor-tech.md` for the open questions that block Wave 4 integration.

When integration lands:

```tsx
// apps/web/src/main.tsx (Wave 4)
import { MiniKitProvider } from '@worldcoin/minikit-js';
// wrap <App /> in <MiniKitProvider appId={import.meta.env.VITE_WORLD_APP_ID}>
```

## Build & deploy

```bash
pnpm --filter @clan-world/web build   # → apps/web/dist/
```

Static output. Deploy to Vercel or Cloudflare Pages, register the URL with the World App as a mini app.

## Mobile testing

The World App is a phone-first surface. Test on a real device or use Chrome devtools mobile emulation with the World App user-agent.
