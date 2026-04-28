import { tokens, ELDERS } from '../styles/cockpit-tokens';
import { MiniCockpit } from '../components/cockpit/MiniCockpit';
import { CockpitHeader } from '../components/cockpit/CockpitHeader';
import { WorldMap } from '../WorldMap';
import { WorldMapBoundary } from '../components/cockpit/shared/WorldMapBoundary';

/**
 * Cockpit Phase A — 3-column 2-row layout shell.
 *
 *   1  |    | 2
 *   -- | 5  | --
 *   3  |    | 4
 *
 * Panels 1-4 are mini-cockpits (one per Elder, hardcoded clans 1-4).
 * Panel 5 is the existing WorldMap pixi canvas, spanning both rows.
 *
 * Phase A.5b: terminal tabs render a live ttyd iframe; tick counter +
 * connection indicator hoisted to a single app-level CockpitHeader.
 *
 * Desktop-first; corners stack vertically below md (≤960px) so phones still
 * see the world map + each agent panel.
 *
 * Phase B (separate PR) wires real Convex data + tick subscription.
 */
export function Cockpit() {
  // Elder slot mapping — physical grid position → clanId.
  // Row 1: clan 1 left, clan 2 right.
  // Row 2: clan 3 left, clan 4 right.
  // Lookup by clanId so TS keeps strict-mode happy without non-null assertions
  // on a tuple-from-array destructure.
  const findElder = (clanId: number) => {
    const e = ELDERS.find((x) => x.clanId === clanId);
    if (!e) {
      throw new Error(`ELDERS roster missing clanId ${clanId} — check cockpit-tokens.ts`);
    }
    return e;
  };
  const el1 = findElder(1);
  const el2 = findElder(2);
  const el3 = findElder(3);
  const el4 = findElder(4);

  return (
    <main
      data-testid="cockpit-root"
      style={{
        background: tokens.bg.void,
        width: '100vw',
        height: '100vh',
        overflow: 'hidden',
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      <CockpitHeader />

      {/* Responsive grid:
          - desktop (≥960px): 3 cols × 2 rows, center spans both rows
          - mobile  (<960px): single column, world map first then 4 panels
          Implemented via inline media-query CSS in <style> below since
          React inline styles can't express @media. */}
      <style>{`
        .cockpit-grid {
          flex: 1;
          display: grid;
          gap: 8px;
          padding: 8px;
          min-height: 0;
          grid-template-columns: 1.3fr 1fr 1.3fr;
          grid-template-rows: minmax(560px, 1fr) minmax(560px, 1fr);
          grid-template-areas:
            "p1 p5 p2"
            "p3 p5 p4";
        }
        .cockpit-cell-1 { grid-area: p1; min-width: 0; min-height: 0; }
        .cockpit-cell-2 { grid-area: p2; min-width: 0; min-height: 0; }
        .cockpit-cell-3 { grid-area: p3; min-width: 0; min-height: 0; }
        .cockpit-cell-4 { grid-area: p4; min-width: 0; min-height: 0; }
        .cockpit-cell-5 { grid-area: p5; min-width: 0; min-height: 0; position: relative; }

        @media (max-width: 960px) {
          .cockpit-grid {
            grid-template-columns: 1fr;
            grid-template-rows: 320px repeat(4, 1fr);
            grid-template-areas:
              "p5"
              "p1"
              "p2"
              "p3"
              "p4";
          }
        }
      `}</style>

      {/* Themed scrollbars scoped to the cockpit subtree.
          Matches the iron palette so default light-grey browser bars don't
          clash with the dark cockpit chrome. Standard (Firefox) +
          ::-webkit-scrollbar (Chromium/Safari) covered.
          NOTE: does NOT affect the ttyd terminal scrollbar — that lives
          inside an iframe document we can't style from this parent. */}
      <style>{`
        [data-testid="cockpit-root"] {
          scrollbar-width: thin;
          scrollbar-color: ${tokens.border.iron} transparent;
        }
        [data-testid="cockpit-root"] ::-webkit-scrollbar {
          width: 8px;
          height: 8px;
        }
        [data-testid="cockpit-root"] ::-webkit-scrollbar-track {
          background: transparent;
        }
        [data-testid="cockpit-root"] ::-webkit-scrollbar-thumb {
          background: ${tokens.border.iron};
          border-radius: 4px;
        }
        [data-testid="cockpit-root"] ::-webkit-scrollbar-thumb:hover {
          background: ${tokens.text.onIronDim};
        }
        [data-testid="cockpit-root"] ::-webkit-scrollbar-corner {
          background: transparent;
        }
      `}</style>

      <div className="cockpit-grid" data-testid="cockpit-grid">
        <div className="cockpit-cell-1">
          <MiniCockpit elder={el1} />
        </div>
        <div className="cockpit-cell-2">
          <MiniCockpit elder={el2} />
        </div>
        <div className="cockpit-cell-3">
          <MiniCockpit elder={el3} />
        </div>
        <div className="cockpit-cell-4">
          <MiniCockpit elder={el4} />
        </div>
        <div
          className="cockpit-cell-5"
          data-testid="cockpit-worldmap"
          style={{
            border: `1px solid ${tokens.border.iron}`,
            borderRadius: tokens.radius.md,
            overflow: 'hidden',
            background: '#000',
          }}
        >
          {/* WorldMap is full-bleed; sits inside the center cell.
              The component handles its own pixi canvas sizing via ResizeObserver.
              Wrapped in a boundary so a backend-less load (judge route in plain
              browser) renders a degraded placeholder instead of unmounting the
              whole cockpit tree. */}
          <WorldMapBoundary>
            <WorldMap />
          </WorldMapBoundary>
        </div>
      </div>
    </main>
  );
}
