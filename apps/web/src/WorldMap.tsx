import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery } from 'convex/react';
import { type FunctionReference, anyApi } from 'convex/server';
import { Application, Assets, Container, Graphics, Sprite, Text } from 'pixi.js';
import { Viewport } from 'pixi-viewport';
import { useAgentLogs, type AgentLog } from './useAgentLogs';
import { WorldNoticePanel } from './WorldNoticePanel';
import worldMapBg from './assets/world-map.png';
import { DEMO_MODE } from './config/env';

// World dimensions used by pixi-viewport for pan/clamp/center math.
// Matches the actual hand-curated bg PNG (apps/web/src/assets/world-map.png)
// at native resolution. The viewport scales/pans this world inside the screen.
const MAP_WIDTH = 814;
const MAP_HEIGHT = 1448;
const WORLD_WIDTH = MAP_WIDTH;
const WORLD_HEIGHT = MAP_HEIGHT;

interface RegionDef {
  id: string;
  name: string;
  // Normalized coords (0-1) within an 800x600 reference frame, scaled at draw time
  // so the canvas fits any viewport (portrait phone → desktop landscape).
  nx: number;
  ny: number;
  color: number;
}

interface ClanDef {
  id: string;
  name: string;
  homeRegion: string;
  color: number;
  sigil: string;
  /** Portrait avatar shown in the HTML scoreboard overlay (style/bandit-archetype-sprites). */
  portrait: string;
  /** Archetype label rendered under the clan name in the scoreboard. */
  archetype: string;
  /** Base sprite (longhouse / tower / dock keep) shown at the home region. */
  basePng: string;
  /** Clansman worker sprite shown for traveling units (replaces colored dot). */
  clansmanPng: string;
}

// Reference design size — coords below were authored against this frame.
const REF_W = 800;
const REF_H = 600;

const REGIONS: RegionDef[] = [
  { id: 'forest',       name: 'Forest',      nx: 150 / REF_W, ny: 100 / REF_H, color: 0x228822 },
  { id: 'mountains',    name: 'Mountains',   nx: 500 / REF_W, ny: 100 / REF_H, color: 0x888888 },
  { id: 'unicorn-town', name: 'Unicorn Town',nx: 330 / REF_W, ny: 280 / REF_H, color: 0xcc88cc },
  { id: 'west-farms',   name: 'West Farms',  nx: 130 / REF_W, ny: 350 / REF_H, color: 0xaacc44 },
  { id: 'east-farms',   name: 'East Farms',  nx: 550 / REF_W, ny: 350 / REF_H, color: 0x88bb33 },
  { id: 'west-docks',   name: 'West Docks',  nx: 100 / REF_W, ny: 500 / REF_H, color: 0x336688 },
  { id: 'east-docks',   name: 'East Docks',  nx: 560 / REF_W, ny: 500 / REF_H, color: 0x336688 },
  { id: 'deep-sea',     name: 'Deep Sea',    nx: 330 / REF_W, ny: 520 / REF_H, color: 0x1144aa },
];

// Clan ↔ archetype mapping (style/bandit-archetype-sprites): each clan gets a portrait
// avatar in the scoreboard so the AI personalities are visually distinguishable.
//   Iron Guard ↔ Aldric  (cautious accumulator)
//   Ember Hand ↔ Brennan (aggressive defender)
//   Dawn Watch ↔ Sora    (long-game monument-builder)
//   Storm Riders ↔ Mira  (transactional trader)
const MOCK_CLANS: ClanDef[] = [
  { id: 'clan-iron',  name: 'Iron Guard',   homeRegion: 'forest',     color: 0x4488cc, sigil: '/sigils/iron-guard-sigil.png',  portrait: '/portraits/aldric-portrait.png',  archetype: 'Cautious',   basePng: '/bases/iron-guard.png',   clansmanPng: '/clansmen/clan-iron.png'  },
  { id: 'clan-ember', name: 'Ember Hand',   homeRegion: 'mountains',  color: 0xcc4422, sigil: '/sigils/ember-hand-sigil.png',  portrait: '/portraits/brennan-portrait.png', archetype: 'Aggressive', basePng: '/bases/ember-hand.png',   clansmanPng: '/clansmen/clan-ember.png' },
  { id: 'clan-dawn',  name: 'Dawn Watch',   homeRegion: 'west-farms', color: 0xccaa22, sigil: '/sigils/dawn-watch-sigil.png',  portrait: '/portraits/sora-portrait.png',    archetype: 'Builder',    basePng: '/bases/dawn-watch.png',   clansmanPng: '/clansmen/clan-dawn.png'  },
  { id: 'clan-storm', name: 'Storm Riders', homeRegion: 'east-farms', color: 0x44aacc, sigil: '/sigils/storm-riders-sigil.png', portrait: '/portraits/mira-portrait.png',   archetype: 'Trader',     basePng: '/bases/storm-riders.png', clansmanPng: '/clansmen/clan-storm.png' },
];

// Worker sprite textures, loaded once at init. Keyed by clan id.
// Falls back to colored Graphics dot if texture missing.
const clansmanTextureCache: Record<string, import('pixi.js').Texture | undefined> = {};

const SIGIL_SIZE = 36;

// Bubble visual + animation constants (PR #43)
const BUBBLE_MAX_WIDTH = 200;
const BUBBLE_PAD_X = 10;
const BUBBLE_PAD_Y = 8;
const BUBBLE_CORNER = 8;
const BUBBLE_FILL = 0x000000;
const BUBBLE_FILL_ALPHA = 0.72;
const BUBBLE_STACK_GAP = 6;
const BUBBLE_FLAG_OFFSET_Y = 6; // gap between sigil top and bubble tail tip
const FADE_IN_MS = 300;
const HOLD_MS = 4500;
const FADE_OUT_MS = 500;
const MAX_BUBBLES_PER_CLAN = 3;

// Tail visual constants — tuned for high contrast against dark/textured background.
const BUBBLE_TAIL_HEIGHT = 14;       // Tall enough to read as a pointer, not a chin.
const BUBBLE_TAIL_HALF_WIDTH = 7;    // Wide-ish base on the bubble side.
const BUBBLE_TAIL_OUTLINE = 0xffffff;
const BUBBLE_TAIL_OUTLINE_WIDTH = 2;

type BubbleHandle = {
  container: Container;
  bornAt: number;
  lifeMs: number;
  height: number; // backdrop + tail; used for vertical stacking
  clanId: string;
  tail: Graphics; // separate from backdrop so we can hide it on stacked (non-bottom) bubbles
};

// Worker travel animation (PR #44) — small clan-colored dots crossing between regions.
interface WorkerTravel {
  id: string;
  fromRegionKey: string;
  toRegionKey: string;
  startedAt: number;
  durationMs: number;
  color: number;
  /** Display node — Sprite when clansman texture loaded, Graphics dot fallback. */
  gfx: Container;
}

const TRAVEL_DOT_RADIUS = 4; // 8px diameter — slightly bigger so it reads in the demo
const TRAVEL_FADE_OUT_MS = 1200; // longer linger at destination
const TRAVEL_DEST_LINGER_MS = 2500; // hold at destination at full alpha before fading
const TRAVEL_MIN_MS = 4500;
const TRAVEL_MAX_MS = 8000;
const CANNED_TRAVEL_INTERVAL_MS = 1800; // continuous spawn — keeps map alive

/** Map a log message to a clan id by string-matching id or name. */
function attributeClan(msg: string): string | null {
  const lower = msg.toLowerCase();
  for (const clan of MOCK_CLANS) {
    if (lower.includes(clan.id) || lower.includes(clan.name.toLowerCase())) {
      return clan.id;
    }
  }
  return null;
}

/** Match a free-form region reference ("Mountains", "east farms") → region id. */
function matchRegionId(text: string): string | null {
  const lower = text.toLowerCase();
  // Prefer longest names first so "east-farms" wins over "farms"
  const sorted = [...REGIONS].sort((a, b) => b.name.length - a.name.length);
  for (const r of sorted) {
    if (lower.includes(r.id) || lower.includes(r.name.toLowerCase())) {
      return r.id;
    }
  }
  return null;
}

/**
 * Parse a "send <clansman/anyone> to <region>" pattern out of a log message.
 * Returns the destination region id, or null if no match.
 * Examples that should match:
 *   "send Borin to the Mountains"
 *   "Iron Guard sends a worker to East Farms"
 *   "dispatching scout to deep-sea"
 */
function parseTravelDestination(msg: string): string | null {
  const lower = msg.toLowerCase();
  // Look for "send|sends|sent|dispatch|dispatched|dispatching ... to <region>"
  const re = /\b(?:send(?:s|ing|t)?|dispatch(?:es|ing|ed)?|travel(?:s|ing|ed)?\s+to|head(?:s|ing|ed)?\s+to|move(?:s|d|ing)?\s+to)\b[^]*?\bto\s+(?:the\s+)?([a-z\- ]+?)(?:[.!,;]|$)/i;
  const m = lower.match(re);
  if (m && m[1]) {
    const candidate = m[1].trim();
    const id = matchRegionId(candidate);
    if (id) return id;
  }
  // Looser fallback: any " to <region>" reference if msg also mentions send/dispatch
  if (/\b(send|sent|sends|dispatch|dispatched|dispatching|travel|heading|moves)\b/.test(lower)) {
    const m2 = lower.match(/\bto\s+(?:the\s+)?([a-z\- ]+?)(?:[.!,;]|$)/);
    if (m2 && m2[1]) {
      const id = matchRegionId(m2[1].trim());
      if (id) return id;
    }
  }
  return null;
}

// Hex color → CSS string for the React scoreboard overlay
const hex = (n: number) => '#' + n.toString(16).padStart(6, '0');

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const getSnapshotRef = anyApi.getSnapshot!.getSnapshot as FunctionReference<'query'>;

interface SnapshotClan {
  id: string;
  name: string;
  treasury: string;
}
interface SnapshotData {
  tick: number;
  clans: SnapshotClan[];
}

// Demo bandit state — once the Convex schema gains banditState + monumentLevel,
// pull these from the snapshot. For now hardcoded so the canvas shows the threat.
// TODO(server-schema): replace with snapshot.banditState when wired.
const DEMO_BANDIT = {
  regionId: 'mountains',
  state: 'CAMPING' as const,
  attacksAtTick: 48,
};

// Mock wall levels, indexed by MOCK_CLANS position (0..3). Clan 2 (Dawn Watch)
// is bandit-damaged so its ring is faint. Replace with snapshot.walls[clanId]
// once schema is wired.
// TODO(server-schema): pull from snapshot.walls when wired.
const MOCK_WALL_LEVELS: Record<string, number> = {
  'clan-iron':  2,
  'clan-ember': 3,
  'clan-dawn':  1,
  'clan-storm': 4,
};
const WALL_LEVEL_MAX = 5;

// Monument visual constants
const MONUMENT_BASE_HEIGHT = 6;
const MONUMENT_LEVEL_HEIGHT = 8; // px per level
const MONUMENT_LEVEL_MAX = 10;
const MONUMENT_WIDTH = 8;

// Derive a "monument level" from treasury for demo display. Real schema will replace this.
function treasuryToMonument(treasury: string): number {
  try {
    const t = BigInt(treasury);
    // 250e18 per level — tuned so mock clans land at 4/3/2/1
    const level = Number(t / BigInt('250000000000000000000'));
    return Math.max(1, Math.min(level, 9));
  } catch {
    return 1;
  }
}

export function WorldMap() {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasWrapRef = useRef<HTMLDivElement>(null);
  const appRef = useRef<Application | null>(null);
  // pixi-viewport instance — wraps all map layers so multi-touch pinch / drag /
  // wheel are handled at the application layer (works in iOS WebKit + World App
  // WebView where browser-level pinch is unreliable).
  const viewportRef = useRef<Viewport | null>(null);
  const layoutRef = useRef<{ scale: number; scaleX: number; scaleY: number; offsetX: number; offsetY: number }>({
    scale: 1,
    scaleX: 1,
    scaleY: 1,
    offsetX: 0,
    offsetY: 0,
  });
  const drawnRef = useRef<{
    regions: Graphics[];
    regionLabels: Text[];
    /** Big translucent zone halos per CLAN at their home region (breathing, hackathon-visual). */
    clanZones: { gfx: Graphics; clan: ClanDef }[];
    /** Per-clan base sprite (96x96 PNG: tower / longhouse / dock keep). */
    bases: { sprite: Sprite | null; fallback: Graphics; clan: ClanDef }[];
    /** Floating "Lv N" badge beside each base. */
    levelBadges: { bg: Graphics; label: Text; clan: ClanDef }[];
    flags: { gfx: Graphics; sprite: Sprite | null; label: Text; clan: ClanDef }[];
    walls: { gfx: Graphics; clan: ClanDef }[];
    monuments: { gfx: Graphics; clan: ClanDef }[];
    /** Procedural fallback ring drawn until the bandit sprite finishes loading. */
    banditIcon: Graphics | null;
    /** Loaded bandit silhouette sprite (96x96 RGBA). null until Assets.load resolves. */
    banditSprite: Sprite | null;
    banditCountdown: Text | null;
    bgSprite: Sprite | null;
  }>({
    regions: [],
    regionLabels: [],
    clanZones: [],
    bases: [],
    levelBadges: [],
    flags: [],
    walls: [],
    monuments: [],
    banditIcon: null,
    banditSprite: null,
    banditCountdown: null,
    bgSprite: null,
  });

  // Per-clan speech-bubble system (PR #43).
  const bubbleLayerRef = useRef<Container | null>(null);
  const bubblesByClanRef = useRef<Map<string, BubbleHandle[]>>(new Map());
  const seenLogIdsRef = useRef<Set<string>>(new Set());
  const flagAnchorsRef = useRef<Map<string, { x: number; y: number }>>(new Map());
  const tickerCbRef = useRef<((ticker: { deltaMS: number }) => void) | null>(null);

  // Worker travel animation (PR #44).
  const travelLayerRef = useRef<Container | null>(null);
  const travelsRef = useRef<WorkerTravel[]>([]);
  const travelTickerCbRef = useRef<((ticker: { deltaMS: number }) => void) | null>(null);
  const seenTravelLogIdsRef = useRef<Set<string>>(new Set());
  const travelIdSeqRef = useRef(0);

  // Zone-pulse ticker (visual heartbeat for clan zone halos).
  const zonePulseCbRef = useRef<(() => void) | null>(null);
  const isMountedRef = useRef(true);

  const [pixiReady, setPixiReady] = useState(false);
  const [pixiInitError, setPixiInitError] = useState<Error | null>(null);
  const [, setSize] = useState({ w: 800, h: 600 });

  const logs = useAgentLogs();
  const snapshot = useQuery(getSnapshotRef) as SnapshotData | undefined;

  // Derived live tick counter — the worldSnapshot.tick field is currently
  // unwritten by the orchestrator script (it only writes to agentLogs), so
  // we surface a moving counter by deriving from log count. Floors at the
  // snapshot value so we never go BACKWARDS if the schema is wired later.
  const liveTick = useMemo(() => {
    return Math.max(snapshot?.tick ?? 0, logs.length);
  }, [logs, snapshot?.tick]);

  // ---- Pixi init ------------------------------------------------------------
  useEffect(() => {
    isMountedRef.current = true;
    let mounted = true;
    const app = new Application();
    appRef.current = app;

    const wrap = canvasWrapRef.current!;
    const initialW = wrap.clientWidth || 800;
    const initialH = wrap.clientHeight || 600;

    app
      .init({
        width: initialW,
        height: initialH,
        background: 0x1a2a1a,
        antialias: true,
        resolution: window.devicePixelRatio || 1,
        autoDensity: true,
      })
      .then(async () => {
        if (!mounted || !isMountedRef.current || !canvasWrapRef.current) return;
        canvasWrapRef.current.appendChild(app.canvas);
        // CSS: stretch to wrapper
        app.canvas.style.display = 'block';
        app.canvas.style.width = '100%';
        app.canvas.style.height = '100%';
        // Round-6 pinch fix: pixi-viewport handles multi-touch internally, so
        // canvas touch-action is 'none' (we own all gestures inside the canvas).
        // Browser-level pinch is locked via index.html viewport meta.
        app.canvas.style.touchAction = 'none';
        // Defensive — block iOS WebKit's 300ms double-tap delay + ensure no
        // stray multi-touch escapes to the page-level zoom.
        app.canvas.addEventListener('touchstart', (e) => {
          if (e.touches.length > 1) e.preventDefault();
        }, { passive: false });

        // pixi-viewport: wraps all map layers (bg, regions, sigils, bases,
        // bubbles, travel dots) so .pinch() / .drag() / .wheel() handle
        // multi-touch math at the application layer. Round 5's
        // canvas.style.touchAction='pinch-zoom' approach failed in World App
        // WebView; this is the canonical fix per Pixi docs.
        const viewport = new Viewport({
          screenWidth: initialW,
          screenHeight: initialH,
          worldWidth: WORLD_WIDTH,
          worldHeight: WORLD_HEIGHT,
          events: app.renderer.events,
        });
        app.stage.addChild(viewport); // viewport is the only direct child of stage
        // Fit-cover scale: smallest scale where the map fully covers the screen
        // (no dead background space on either axis). minScale = fitScale means
        // user CANNOT zoom out past fit; map always fills the screen.
        const initialFitScale = Math.max(
          initialW / WORLD_WIDTH,
          initialH / WORLD_HEIGHT,
        );
        viewport
          .drag()
          .pinch()
          .wheel()
          .decelerate()
          .clampZoom({ minScale: initialFitScale, maxScale: initialFitScale * 4 })
          .clamp({ direction: 'all', underflow: 'center' });
        viewport.setZoom(initialFitScale, true);
        viewport.moveCenter(WORLD_WIDTH / 2, WORLD_HEIGHT / 2);
        viewportRef.current = viewport;

        // 1. Background terrain map (PR #40) — fantasy strategy art generated to match REGIONS layout.
        // Loaded async; sprite is added to viewport BEFORE buildScene so region circles render on top.
        try {
          const tex = await Assets.load(worldMapBg);
          if (!mounted || !isMountedRef.current) return;
          const bg = new Sprite(tex);
          // Render at native world resolution; viewport handles screen-fit zoom.
          bg.width = MAP_WIDTH;
          bg.height = MAP_HEIGHT;
          bg.x = 0;
          bg.y = 0;
          viewport.addChild(bg);
          drawnRef.current.bgSprite = bg;
        } catch (err) {
          // Non-fatal — fall through to flat background color set in app.init
          console.warn('[WorldMap] failed to load terrain background', err);
        }

        // 2. Build scene (regions, sigil sprites, bandit indicator) — PR #41 + PR #42 logic
        // Layers are added to `viewport` (not app.stage) so pinch/drag affect them.
        buildScene(app, viewport);

        // 3. Speech bubble layer + ticker (PR #43) — added last so bubbles render above everything.
        const bubbleLayer = new Container();
        viewport.addChild(bubbleLayer);
        bubbleLayerRef.current = bubbleLayer;

        const cb = (ticker: { deltaMS: number }) => {
          const now = performance.now();
          const byClan = bubblesByClanRef.current;
          for (const [clanId, list] of byClan) {
            // Update alphas; remove dead bubbles.
            for (let i = list.length - 1; i >= 0; i--) {
              const b = list[i];
              if (!b) continue;
              const age = now - b.bornAt;
              let alpha: number;
              if (age < FADE_IN_MS) {
                alpha = age / FADE_IN_MS;
              } else if (age < FADE_IN_MS + HOLD_MS) {
                alpha = 1;
              } else if (age < b.lifeMs) {
                const fadeAge = age - FADE_IN_MS - HOLD_MS;
                alpha = 1 - fadeAge / FADE_OUT_MS;
              } else {
                alpha = 0;
              }
              b.container.alpha = Math.max(0, Math.min(1, alpha));
              if (age >= b.lifeMs) {
                bubbleLayer.removeChild(b.container);
                b.container.destroy({ children: true });
                list.splice(i, 1);
              }
            }
            // Restack: oldest closest to flag, newest on top.
            // Only the bottommost bubble (index 0) shows its tail — upper bubbles
            // would point to empty air, which looks broken.
            const anchor = flagAnchorsRef.current.get(clanId);
            if (anchor && list.length > 0) {
              let cursorY = anchor.y - BUBBLE_FLAG_OFFSET_Y;
              for (let i = 0; i < list.length; i++) {
                const b = list[i];
                if (!b) continue;
                b.container.x = anchor.x;
                b.container.y = cursorY;
                b.tail.visible = i === 0;
                cursorY -= b.height + BUBBLE_STACK_GAP;
              }
            }
            if (list.length === 0) byClan.delete(clanId);
          }
          void ticker.deltaMS;
        };
        tickerCbRef.current = cb;
        app.ticker.add(cb);

        // 3b. Worker travel layer + ticker (PR #44) — clan-colored dots crossing routes.
        // Added after bubble layer so dots can render under bubbles (less visual noise).
        const travelLayer = new Container();
        // Insert below bubble layer so bubbles always appear on top of moving dots.
        viewport.addChildAt(travelLayer, viewport.getChildIndex(bubbleLayer));
        travelLayerRef.current = travelLayer;

        const travelCb = (_ticker: { deltaMS: number }) => {
          const layer = travelLayerRef.current;
          if (!layer) return;
          const now = performance.now();
          const list = travelsRef.current;
          const { scaleX, scaleY, offsetX, offsetY } = layoutRef.current;
          const projX = (nx: number) => offsetX + nx * REF_W * scaleX;
          const projY = (ny: number) => offsetY + ny * REF_H * scaleY;

          for (let i = list.length - 1; i >= 0; i--) {
            const t = list[i];
            if (!t) continue;
            const from = REGIONS.find(r => r.id === t.fromRegionKey);
            const to = REGIONS.find(r => r.id === t.toRegionKey);
            if (!from || !to) {
              layer.removeChild(t.gfx);
              t.gfx.destroy();
              list.splice(i, 1);
              continue;
            }
            const elapsed = now - t.startedAt;
            const progress = elapsed / t.durationMs;

            const fx = projX(from.nx);
            const fy = projY(from.ny);
            const tx = projX(to.nx);
            const ty = projY(to.ny);

            if (progress >= 1) {
              const fadeAge = elapsed - t.durationMs;
              // Linger at destination at full alpha for TRAVEL_DEST_LINGER_MS,
              // THEN fade. Keeps arrival visible — answers "clansmen disappear" bug.
              if (fadeAge >= TRAVEL_DEST_LINGER_MS + TRAVEL_FADE_OUT_MS) {
                layer.removeChild(t.gfx);
                t.gfx.destroy();
                list.splice(i, 1);
                continue;
              }
              // Tiny jitter at destination so the cluster reads as living units, not pinned dots
              const jit = Math.sin((now + (t.id.charCodeAt(t.id.length - 1) * 137)) / 220) * 1.5;
              t.gfx.x = tx + jit;
              t.gfx.y = ty + jit * 0.6;
              if (fadeAge < TRAVEL_DEST_LINGER_MS) {
                t.gfx.alpha = 1;
              } else {
                const fOff = fadeAge - TRAVEL_DEST_LINGER_MS;
                t.gfx.alpha = Math.max(0, 1 - fOff / TRAVEL_FADE_OUT_MS);
              }
            } else {
              t.gfx.x = fx + (tx - fx) * progress;
              t.gfx.y = fy + (ty - fy) * progress;
              // Subtle fade-in over first 150ms so dots don't pop in
              t.gfx.alpha = Math.min(1, elapsed / 150);
            }
          }
        };
        travelTickerCbRef.current = travelCb;
        app.ticker.add(travelCb);

        // 3c. Zone-pulse ticker — gently breathe alpha on each clan zone halo so
        // the map feels alive even when no logs are attributable. Visual heartbeat.
        const zonePulseCb = () => {
          const drawn = drawnRef.current;
          if (drawn.clanZones.length === 0) return;
          const t = performance.now() / 1000;
          drawn.clanZones.forEach(({ gfx }, i) => {
            // Each zone breathes on a slightly different phase
            const phase = (t + i * 0.7) * 1.1;
            const a = 0.78 + 0.22 * Math.sin(phase);
            gfx.alpha = a;
          });
        };
        app.ticker.add(zonePulseCb);
        // Stash cleanup ref via the same pattern as travel ticker (re-use travelTickerCbRef).
        // Track separately:
        zonePulseCbRef.current = zonePulseCb;

        // 4. Initial layout (PR #41) — projects normalized coords + positions flag anchors.
        // relayout now operates in WORLD space (MAP_WIDTH x MAP_HEIGHT) since the
        // viewport handles screen-fit transformation. Children inside the viewport
        // are positioned in world coords and pixi-viewport scales them to screen.
        relayout(MAP_WIDTH, MAP_HEIGHT);
        if (!mounted || !isMountedRef.current) return;
        setSize({ w: initialW, h: initialH });
        setPixiReady(true);
      })
      .catch((err: unknown) => {
        console.error('[WorldMap] failed to initialize Pixi application', err);
        if (!mounted || !isMountedRef.current) return;
        setPixiInitError(err instanceof Error ? err : new Error(String(err)));
      });

    return () => {
      mounted = false;
      isMountedRef.current = false;
      const a = appRef.current;
      if (a && tickerCbRef.current) a.ticker.remove(tickerCbRef.current);
      if (a && travelTickerCbRef.current) a.ticker.remove(travelTickerCbRef.current);
      if (a && zonePulseCbRef.current) a.ticker.remove(zonePulseCbRef.current);
      bubblesByClanRef.current.clear();
      seenLogIdsRef.current.clear();
      flagAnchorsRef.current.clear();
      travelsRef.current = [];
      seenTravelLogIdsRef.current.clear();
      bubbleLayerRef.current = null;
      travelLayerRef.current = null;
      tickerCbRef.current = null;
      travelTickerCbRef.current = null;
      zonePulseCbRef.current = null;
      drawnRef.current = {
        regions: [],
        regionLabels: [],
        clanZones: [],
        bases: [],
        levelBadges: [],
        flags: [],
        walls: [],
        monuments: [],
        banditIcon: null,
        banditSprite: null,
        banditCountdown: null,
        bgSprite: null,
      };
      viewportRef.current = null;
      appRef.current = null;
      // PIXI v8 + React StrictMode double-invoke guard: the second cleanup
      // pass hits an already-destroyed Application where internal fields like
      // _cancelResize are undefined. Wrap in try/catch — first destroy is the
      // real one, second is benign noise.
      try {
        a?.destroy(true);
      } catch (err) {
        if (import.meta.env.DEV) {
          console.debug('[WorldMap] destroy noop (StrictMode double-invoke):', err);
        }
      }
    };
  }, []);

  // ---- Resize observer: recompute layout on viewport / orientation change --
  useEffect(() => {
    if (!pixiReady) return;
    const wrap = canvasWrapRef.current;
    const app = appRef.current;
    if (!wrap || !app) return;

    const handleResize = () => {
      if (!appRef.current) return;
      const w = wrap.clientWidth;
      const h = wrap.clientHeight;
      if (w <= 0 || h <= 0) return;
      app.renderer.resize(w, h);
      // Update pixi-viewport's screen dimensions so pinch/drag math tracks
      // the new canvas size. World dims stay fixed at WORLD_WIDTH/HEIGHT.
      const vp = viewportRef.current;
      if (vp) {
        vp.resize(w, h, WORLD_WIDTH, WORLD_HEIGHT);
        // Recompute fit-cover scale for the new screen size; reapply zoom/pan
        // clamps so user still can't zoom out past fit or pan into dead space.
        const fitScale = Math.max(w / WORLD_WIDTH, h / WORLD_HEIGHT);
        vp.clampZoom({ minScale: fitScale, maxScale: fitScale * 4 });
        vp.clamp({ direction: 'all', underflow: 'center' });
        // Snap back to fit if current zoom dropped below the new floor.
        if (vp.scale.x < fitScale) {
          vp.setZoom(fitScale, true);
          vp.moveCenter(WORLD_WIDTH / 2, WORLD_HEIGHT / 2);
        }
      }
      // relayout positions everything in WORLD coords now, not screen coords.
      relayout(WORLD_WIDTH, WORLD_HEIGHT);
      setSize({ w, h });
    };

    const ro = new ResizeObserver(handleResize);
    ro.observe(wrap);
    window.addEventListener('orientationchange', handleResize);
    return () => {
      ro.disconnect();
      window.removeEventListener('orientationchange', handleResize);
    };
  }, [pixiReady]);

  // ---- One-time: create Pixi display objects (refs hold them for relayout) -
  // All layers attach to `viewport` (not app.stage) so pixi-viewport's pinch /
  // drag transforms apply to the whole map atomically.
  function buildScene(app: Application, viewport: Viewport) {
    const drawn = drawnRef.current;

    // Clan zones, sigil flags, bases, walls, monuments, bandits — all mock data.
    // Skip entirely when DEMO_MODE is off; the canvas renders as an empty terrain map.
    if (DEMO_MODE) {
      // Clan zones (big translucent breathing halos) — drawn FIRST so everything else
      // sits on top. Visual sense of "this clan controls this zone."
      for (const clan of MOCK_CLANS) {
        const zoneGfx = new Graphics();
        viewport.addChild(zoneGfx);
        drawn.clanZones.push({ gfx: zoneGfx, clan });
      }
    }

    for (const region of REGIONS) {
      const g = new Graphics();
      viewport.addChild(g);
      drawn.regions.push(g);

      const label = new Text({
        text: region.name,
        style: { fill: 0xdddddd, fontSize: 11, fontFamily: 'monospace' },
      });
      label.anchor.set(0.5, 0);
      viewport.addChild(label);
      drawn.regionLabels.push(label);
    }

    if (DEMO_MODE) {
      // Wall rings — drawn first so they sit above region circles but under sigils.
      for (const clan of MOCK_CLANS) {
        const wallGfx = new Graphics();
        viewport.addChild(wallGfx);
        drawn.walls.push({ gfx: wallGfx, clan });
      }

      // Monument towers — drawn before flags so sigil layers cleanly on top.
      for (const clan of MOCK_CLANS) {
        const monGfx = new Graphics();
        viewport.addChild(monGfx);
        drawn.monuments.push({ gfx: monGfx, clan });
      }

      for (const clan of MOCK_CLANS) {
        const flag = new Graphics();
        viewport.addChild(flag);
        const label = new Text({
          text: clan.name,
          style: { fill: clan.color, fontSize: 10, fontFamily: 'monospace', fontWeight: 'bold' },
        });
        label.anchor.set(0, 1);
        viewport.addChild(label);
        const entry: { gfx: Graphics; sprite: Sprite | null; label: Text; clan: ClanDef } = {
          gfx: flag,
          sprite: null,
          label,
          clan,
        };
        drawn.flags.push(entry);

        // Async-load clan sigil sprite (PR #42). Fallback rect (gfx) shows during load and
        // remains visible if load fails. Once loaded, sprite is positioned by relayout.
        Assets.load(clan.sigil)
          .then((texture) => {
            if (!isMountedRef.current || !appRef.current) return;
            const sprite = new Sprite(texture);
            sprite.alpha = 0; // hidden until first relayout positions it
            viewport.addChild(sprite);
            entry.sprite = sprite;
            // Trigger a relayout so sprite gets positioned and shown.
            const wrap = canvasWrapRef.current;
            if (wrap && appRef.current) {
              relayout(WORLD_WIDTH, WORLD_HEIGHT);
            }
          })
          .catch(() => {
            // Keep fallback rect visible.
          });
      }

      // Bandit indicator (style/bandit-archetype-sprites): stylized hooded silhouette.
      // Pixi loads /sprites/bandit.png async; we keep a Graphics fallback (red ring + "!")
      // visible during the load and as a safety net if the asset 404s. The countdown text
      // anchors next to whichever marker is currently rendered.
      const banditIcon = new Graphics();
      viewport.addChild(banditIcon);
      const countdown = new Text({
        text: '',
        style: { fill: 0xffe9b8, fontSize: 11, fontFamily: 'monospace', fontWeight: 'bold' },
      });
      countdown.anchor.set(0, 0.5);
      viewport.addChild(countdown);
      drawn.banditIcon = banditIcon;
      drawn.banditCountdown = countdown;

      // Async-load the bandit sprite — once ready, redrawBandit positions it and
      // hides the fallback ring. Catch silently so the ring stays visible on failure.
      Assets.load('/sprites/bandit.png')
        .then((texture) => {
          if (!isMountedRef.current || !appRef.current) return;
          const sprite = new Sprite(texture);
          sprite.anchor.set(0.5, 0.5);
          sprite.alpha = 0; // hidden until first redrawBandit positions it
          viewport.addChild(sprite);
          drawn.banditSprite = sprite;
          redrawBandit();
        })
        .catch(() => {
          // Keep fallback ring visible.
        });

      // Per-clan BASE SPRITES — pixel-art structures at home regions (towers / keeps / longhouses).
      // Visible on top of region circles + sigil flags. Falls back to a simple colored rect.
      for (const clan of MOCK_CLANS) {
        const fallback = new Graphics();
        viewport.addChild(fallback);
        const entry: { sprite: Sprite | null; fallback: Graphics; clan: ClanDef } = {
          sprite: null,
          fallback,
          clan,
        };
        drawn.bases.push(entry);

        Assets.load(clan.basePng)
          .then((texture) => {
            if (!isMountedRef.current || !appRef.current) return;
            const sprite = new Sprite(texture);
            sprite.anchor.set(0.5, 1); // anchored at bottom-center so it "stands" on the region
            sprite.alpha = 0;
            viewport.addChild(sprite);
            entry.sprite = sprite;
            const wrap = canvasWrapRef.current;
            if (wrap && appRef.current) {
              relayout(WORLD_WIDTH, WORLD_HEIGHT);
            }
          })
          .catch(() => {
            // fallback rect stays visible
          });

        // Worker (clansman) sprite for traveling units. Cached per clan id.
        // If load fails we silently fall back to the colored Graphics dot.
        Assets.load(clan.clansmanPng)
          .then((texture) => {
            if (!isMountedRef.current) return;
            clansmanTextureCache[clan.id] = texture;
          })
          .catch(() => {
            // Travel dot fallback handles missing texture.
          });
      }

      // Floating "Lv N" badges — drawn last so they overlay everything.
      for (const clan of MOCK_CLANS) {
        const bg = new Graphics();
        viewport.addChild(bg);
        const label = new Text({
          text: 'Lv 1',
          style: {
            fill: 0xffe9b8,
            fontSize: 12,
            fontFamily: '"Cinzel", "Times New Roman", serif',
            fontWeight: '700',
          },
        });
        label.anchor.set(0.5, 0.5);
        viewport.addChild(label);
        drawn.levelBadges.push({ bg, label, clan });
      }
    } // end DEMO_MODE block
  }

  // ---- Layout: scale all draw coords from REF frame to canvas dimensions ---
  // Stretches positions to fill the viewport (so 8 regions fit on tall portrait
  // phones AND wide landscape) while keeping circles circular (uniform radius).
  function relayout(w: number, h: number) {
    // Top scoreboard removed — minimal top margin keeps zone halos centered.
    // Bottom margin reserves space for the compact tick/level pulse panel.
    const sideMargin = 24;
    const topMargin = 24;
    const bottomMargin = 60;
    const usableW = Math.max(80, w - 2 * sideMargin);
    const usableH = Math.max(80, h - topMargin - bottomMargin);
    const scaleX = usableW / REF_W;
    const scaleY = usableH / REF_H;
    // Uniform scale used for sizes (radii / labels) — prevents distortion.
    const sizeScale = Math.min(scaleX, scaleY);
    // Cap the size scale so labels don't get giant on big desktop monitors.
    const cappedSizeScale = Math.min(sizeScale, 1.4);
    const offsetX = sideMargin;
    const offsetY = topMargin;

    layoutRef.current = { scale: cappedSizeScale, scaleX, scaleY, offsetX, offsetY };
    // Locally compute scaled coords (positions stretch, sizes uniform)
    const projX = (nx: number) => offsetX + nx * REF_W * scaleX;
    const projY = (ny: number) => offsetY + ny * REF_H * scaleY;

    const drawn = drawnRef.current;
    // Smaller terrain dots — zones below now carry the "control area" weight
    const regionRadius = 18 * cappedSizeScale;

    // Background terrain renders at native world resolution (MAP_WIDTH x MAP_HEIGHT).
    // The viewport handles fit-cover scaling, so we never stretch the bg here.
    if (drawn.bgSprite) {
      drawn.bgSprite.width = MAP_WIDTH;
      drawn.bgSprite.height = MAP_HEIGHT;
      drawn.bgSprite.x = 0;
      drawn.bgSprite.y = 0;
    }

    const regionMap = new Map(REGIONS.map(r => [r.id, r]));

    if (DEMO_MODE) {
      // Big translucent CLAN ZONES — drawn first, breathing animation ticker pulses alpha.
      // Stored geometry only here; alpha applied per-tick.
      drawn.clanZones.forEach(({ gfx, clan }) => {
        const base = regionMap.get(clan.homeRegion);
        if (!base) return;
        const cx = projX(base.nx);
        const cy = projY(base.ny);
        // Radius targets ~150-200px range; scaled by cappedSizeScale so it stays
        // proportionate on tall portrait screens.
        const r = 95 * cappedSizeScale;
        gfx.clear();
        // Outer soft ring
        gfx.circle(cx, cy, r);
        gfx.fill({ color: clan.color, alpha: 0.18 });
        // Inner brighter core for "this is the base"
        gfx.circle(cx, cy, r * 0.55);
        gfx.fill({ color: clan.color, alpha: 0.28 });
        // Crisp edge stroke
        gfx.circle(cx, cy, r);
        gfx.stroke({ color: clan.color, width: 2, alpha: 0.55 });
      });
    }

    // Region dots — small, just to mark non-clan locations (mountains, deep sea, town).
    REGIONS.forEach((region, i) => {
      const cx = projX(region.nx);
      const cy = projY(region.ny);
      const g = drawn.regions[i];
      // Hide region dots that are home to a clan (zone halo replaces them visually)
      // Only apply the "clan home" suppression when DEMO_MODE is on.
      const isClanHome = DEMO_MODE && MOCK_CLANS.some(c => c.homeRegion === region.id);
      if (g) {
        g.clear();
        if (!isClanHome) {
          g.circle(cx, cy, regionRadius);
          g.fill({ color: region.color, alpha: 0.6 });
          g.stroke({ color: 0xffffff, width: 1, alpha: 0.4 });
        }
      }
      const label = drawn.regionLabels[i];
      if (label) {
        label.style.fontSize = Math.max(9, Math.round(10 * cappedSizeScale));
        label.x = cx;
        label.y = cy + (isClanHome ? 0 : regionRadius + 4);
        label.alpha = isClanHome ? 0 : 0.8;
      }
    });

    if (DEMO_MODE) {
      // Build per-clan monument level lookup. Prefer live snapshot via treasury;
      // fall back to mock 4-i pattern matching scoreboard demo data.
      const liveClans = snapshot?.clans;
      const levelByClan = new Map<string, number>();
      if (liveClans && liveClans.length > 0) {
        for (const c of liveClans) levelByClan.set(c.id, treasuryToMonument(c.treasury));
      }
      MOCK_CLANS.forEach((c, i) => {
        if (!levelByClan.has(c.id)) levelByClan.set(c.id, 4 - i);
      });

      // Wall rings — visually replaced by zone halos. Clear graphics; keep refs.
      drawn.walls.forEach(({ gfx }) => {
        gfx.clear();
      });

      // Monument towers — stacked rectangles + top cap, height grows with level.
      // Positioned at the flag location, just below the sigil so it reads as
      // "the clan's structure at their homebase."
      // Old monument obelisks — replaced by base sprites + floating Lv badges.
      // Keep refs alive (cleanup is done in unmount) but draw nothing.
      drawn.monuments.forEach(({ gfx }) => {
        gfx.clear();
      });

      // Clan sigil flags — REPLACED by base sprites. Hide them but keep bubble
      // anchors so the speech-bubble system still has positions to attach to.
      drawn.flags.forEach(({ gfx, sprite, label, clan }) => {
        const base = regionMap.get(clan.homeRegion);
        if (!base) return;
        const cx = projX(base.nx);
        const cy = projY(base.ny);
        const baseSize = Math.max(96, 144 * cappedSizeScale);
        // Hide everything visually
        gfx.clear();
        if (sprite) sprite.alpha = 0;
        label.alpha = 0;
        // Bubble anchor: top of base sprite
        flagAnchorsRef.current.set(clan.id, { x: cx, y: cy - baseSize * 1.05 });
      });

      // BASE SPRITES — render at clan home positions, replacing monument obelisks.
      drawn.bases.forEach(({ sprite, fallback, clan }) => {
        const base = regionMap.get(clan.homeRegion);
        if (!base) return;
        const cx = projX(base.nx);
        const cy = projY(base.ny);
        // Base size: ~128px at 1x scale, scales with viewport (2x bump for phone readability)
        const baseSize = Math.max(96, 144 * cappedSizeScale);
        fallback.clear();
        if (!sprite) {
          // Simple colored fallback rect with clan-color border
          fallback.rect(cx - baseSize / 2, cy - baseSize, baseSize, baseSize);
          fallback.fill({ color: 0x444444, alpha: 0.7 });
          fallback.stroke({ color: clan.color, width: 3 });
        }
        if (sprite) {
          sprite.width = baseSize;
          sprite.height = baseSize;
          sprite.x = cx;
          sprite.y = cy + baseSize * 0.15; // anchor=bottom-center; sit slightly below center
          sprite.alpha = 1;
        }
      });

      // FLOATING "Lv N" BADGES — beside each base sprite. Updates with monument level.
      drawn.levelBadges.forEach(({ bg, label, clan }) => {
        const base = regionMap.get(clan.homeRegion);
        if (!base) return;
        const cx = projX(base.nx);
        const cy = projY(base.ny);
        const baseSize = Math.max(96, 144 * cappedSizeScale);
        const lvl = levelByClan.get(clan.id) ?? 0;
        label.text = `Lv ${lvl}`;
        label.style.fontSize = Math.max(11, Math.round(13 * cappedSizeScale));
        // Position to the right of the base sprite, near the top
        const bx = cx + baseSize * 0.55;
        const by = cy - baseSize * 0.55;
        label.x = bx;
        label.y = by;
        // Pill background
        const pad = Math.max(4, 6 * cappedSizeScale);
        const w = label.width + pad * 2;
        const h = label.height + pad * 0.6;
        bg.clear();
        bg.roundRect(bx - w / 2, by - h / 2, w, h, h / 2);
        bg.fill({ color: 0x0d1a0d, alpha: 0.85 });
        bg.stroke({ color: clan.color, width: 1.5, alpha: 0.95 });
      });

      // Bandit redraw uses live tick — recompute alongside layout
      redrawBandit();
    } // end DEMO_MODE relayout block
  }

  // ---- Bandit: hooded silhouette over Mountains + ticks-until-attack readout
  // (style/bandit-archetype-sprites): replaces the prior red "!" disc with a
  // codex/PIL-rendered bandit sprite. A subtle red ring stays as fallback while
  // the sprite loads or if the asset fails.
  function redrawBandit() {
    const drawn = drawnRef.current;
    const icon = drawn.banditIcon;
    const sprite = drawn.banditSprite;
    const text = drawn.banditCountdown;
    if (!icon || !text) return;

    const region = REGIONS.find(r => r.id === DEMO_BANDIT.regionId);
    if (!region) return;
    const { scale, scaleX, scaleY, offsetX, offsetY } = layoutRef.current;
    const cx = offsetX + region.nx * REF_W * scaleX;
    const cy = offsetY + region.ny * REF_H * scaleY;

    // Bandit perches above-left of region circle. Sprite size ~32px at 1x scale,
    // matching the prior icon's visual weight while leaving room for the countdown.
    const iconX = cx - 28 * scale;
    const iconY = cy - 42 * scale;
    const spriteSize = Math.max(24, 32 * scale);
    const ringR = Math.max(10, 14 * scale);

    icon.clear();
    if (!sprite) {
      // Fallback ring while the sprite loads / on asset failure
      icon.circle(iconX, iconY, ringR);
      icon.fill({ color: 0xcc1122, alpha: 0.85 });
      icon.stroke({ color: 0xffffff, width: 2 });
      const barW = Math.max(2, 3 * scale);
      const barH = ringR * 0.95;
      icon.rect(iconX - barW / 2, iconY - barH / 2, barW, barH * 0.6);
      icon.fill({ color: 0xffffff });
      icon.circle(iconX, iconY + barH * 0.35, Math.max(1.5, barW * 0.7));
      icon.fill({ color: 0xffffff });
    }

    if (sprite) {
      sprite.width = spriteSize;
      sprite.height = spriteSize;
      sprite.x = iconX;
      sprite.y = iconY;
      sprite.alpha = 1;
    }

    const tick = snapshot?.tick ?? 0;
    const ticksUntil = Math.max(0, DEMO_BANDIT.attacksAtTick - tick);
    text.text = `${ticksUntil}t`;
    text.style.fontSize = Math.max(10, Math.round(12 * scale));
    // Anchor the countdown to the right edge of whichever marker is active.
    const markerHalfW = sprite ? spriteSize / 2 : ringR;
    text.x = iconX + markerHalfW + 4;
    text.y = iconY;
  }

  // Tick changes: refresh bandit countdown (demo mode only)
  useEffect(() => {
    if (!pixiReady || !DEMO_MODE) return;
    redrawBandit();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [snapshot?.tick, pixiReady]);

  // Snapshot clan changes: re-layout so monument heights track live treasury.
  useEffect(() => {
    if (!pixiReady) return;
    const wrap = canvasWrapRef.current;
    if (!wrap) return;
    relayout(WORLD_WIDTH, WORLD_HEIGHT);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [snapshot?.clans, pixiReady]);

  // Pulse the bandit icon when 1-2 ticks from attacking — urgency cue for the demo
  useEffect(() => {
    if (!pixiReady || !DEMO_MODE) return;
    const app = appRef.current;
    if (!app) return;
    const tick = snapshot?.tick ?? 0;
    const ticksUntil = DEMO_BANDIT.attacksAtTick - tick;
    const shouldPulse = ticksUntil <= 2 && ticksUntil >= 0;

    const onTick = () => {
      const icon = drawnRef.current.banditIcon;
      const sprite = drawnRef.current.banditSprite;
      if (!shouldPulse) {
        if (icon) icon.alpha = 1;
        if (sprite) sprite.alpha = 1;
        return;
      }
      const t = performance.now() / 220;
      const a = 0.55 + 0.45 * Math.abs(Math.sin(t));
      if (icon) icon.alpha = a;
      if (sprite) sprite.alpha = a;
    };
    app.ticker.add(onTick);
    return () => {
      app.ticker.remove(onTick);
      const icon = drawnRef.current.banditIcon;
      const sprite = drawnRef.current.banditSprite;
      if (icon) icon.alpha = 1;
      if (sprite) sprite.alpha = 1;
    };
  }, [snapshot?.tick, pixiReady]);

  // Speech bubbles (PR #43): spawn bubbles for new logs; attribute each to a clan via string match.
  // Only active in DEMO_MODE (MOCK_CLANS provides the attribution table).
  useEffect(() => {
    if (!pixiReady || !DEMO_MODE || !bubbleLayerRef.current || logs.length === 0) return;
    const layer = bubbleLayerRef.current;

    // useAgentLogs returns desc order. Reverse so chronological add → newest stacked on top.
    const ordered: AgentLog[] = [...logs].reverse();
    for (const log of ordered) {
      if (seenLogIdsRef.current.has(log._id)) continue;
      seenLogIdsRef.current.add(log._id);

      const clanId = attributeClan(log.message);
      if (!clanId) continue; // skip unattributable logs (rather than corner-clutter)

      const msg = log.message.slice(0, 240);
      const clanColor = MOCK_CLANS.find(c => c.id === clanId)?.color ?? 0xcccccc;
      const handle = makeBubble(msg, clanId, clanColor);
      layer.addChild(handle.container);

      const list = bubblesByClanRef.current.get(clanId) ?? [];
      list.push(handle);
      while (list.length > MAX_BUBBLES_PER_CLAN) {
        const dead = list.shift();
        if (dead) {
          layer.removeChild(dead.container);
          dead.container.destroy({ children: true });
        }
      }
      bubblesByClanRef.current.set(clanId, list);
    }
  }, [logs, pixiReady]);

  // ---- Worker travel (PR #44): spawn dots from log "send X to Y" + canned demos
  function spawnTravel(fromRegionKey: string, toRegionKey: string, color: number, clanId?: string) {
    const layer = travelLayerRef.current;
    if (!layer) return;
    if (fromRegionKey === toRegionKey) return;
    const from = REGIONS.find(r => r.id === fromRegionKey);
    const to = REGIONS.find(r => r.id === toRegionKey);
    if (!from || !to) return;

    // Prefer the clansman sprite (replaces the old colored dot). Falls back to the
    // dot if the texture hasn't loaded yet — keeps the demo robust on slow assets.
    const tex = clanId ? clansmanTextureCache[clanId] : undefined;
    let gfx: Container;
    if (tex) {
      const sprite = new Sprite(tex);
      sprite.anchor.set(0.5, 0.5);
      // Workers are smaller than bases — keep them readable but not chunky.
      const targetH = 28;
      const ratio = targetH / sprite.texture.height;
      sprite.height = targetH;
      sprite.width = sprite.texture.width * ratio;
      sprite.alpha = 0;
      gfx = sprite;
    } else {
      const dot = new Graphics();
      dot.circle(0, 0, TRAVEL_DOT_RADIUS);
      dot.fill({ color });
      dot.stroke({ color: 0x000000, width: 1, alpha: 0.55 });
      dot.alpha = 0;
      gfx = dot;
    }
    layer.addChild(gfx);

    const durationMs =
      TRAVEL_MIN_MS + Math.random() * (TRAVEL_MAX_MS - TRAVEL_MIN_MS);

    travelIdSeqRef.current += 1;
    travelsRef.current.push({
      id: `travel-${travelIdSeqRef.current}`,
      fromRegionKey,
      toRegionKey,
      startedAt: performance.now(),
      durationMs,
      color,
      gfx,
    });
  }

  // Real travels: parse "send X to Y" out of new log messages (demo mode only)
  useEffect(() => {
    if (!pixiReady || !DEMO_MODE || !travelLayerRef.current || logs.length === 0) return;
    const ordered: AgentLog[] = [...logs].reverse();
    for (const log of ordered) {
      if (seenTravelLogIdsRef.current.has(log._id)) continue;
      seenTravelLogIdsRef.current.add(log._id);

      const dest = parseTravelDestination(log.message);
      if (!dest) continue;
      const clanId = attributeClan(log.message);
      const clan = clanId ? MOCK_CLANS.find(c => c.id === clanId) : null;
      if (!clan) continue;
      if (clan.homeRegion === dest) continue;
      spawnTravel(clan.homeRegion, dest, clan.color, clan.id);
    }
  }, [logs, pixiReady]);

  // Canned demo travels: continuous spawn so 4-8 dots are always in motion.
  // Hackathon visual: the map should never feel dead. Skipped when DEMO_MODE is off.
  useEffect(() => {
    if (!pixiReady || !DEMO_MODE) return;
    const fireOne = () => {
      const clan = MOCK_CLANS[Math.floor(Math.random() * MOCK_CLANS.length)];
      if (!clan) return;
      const candidates = REGIONS.filter(r => r.id !== clan.homeRegion);
      const dest = candidates[Math.floor(Math.random() * candidates.length)];
      if (!dest) return;
      spawnTravel(clan.homeRegion, dest.id, clan.color, clan.id);
    };
    // Initial burst — one worker from EACH clan, staggered so they're visible
    // immediately when the canvas loads. Track timeout IDs so we can cancel
    // them on unmount (PR #133 review MUST FIX #2 — without this, callbacks
    // fire after Pixi teardown and call spawnTravel on destroyed objects).
    const staggerIds = MOCK_CLANS.map((clan, i) =>
      window.setTimeout(() => {
        const candidates = REGIONS.filter(r => r.id !== clan.homeRegion);
        const dest = candidates[Math.floor(Math.random() * candidates.length)];
        if (!dest) return;
        spawnTravel(clan.homeRegion, dest.id, clan.color, clan.id);
      }, i * 250),
    );
    const interval = window.setInterval(fireOne, CANNED_TRAVEL_INTERVAL_MS);
    return () => {
      staggerIds.forEach(id => window.clearTimeout(id));
      window.clearInterval(interval);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pixiReady]);

  if (pixiInitError) {
    throw pixiInitError;
  }

  // ---- Scoreboard data: live snapshot if present, else mock metadata -------
  // Portrait + archetype label come from MOCK_CLANS (they are static metadata,
  // not server state) — we look them up by clan id whether the row is sourced
  // from a live snapshot or the mock fallback.
  // When DEMO_MODE is off, scoreboardClans is empty — the scoreboard panel hides
  // and the "no chain data yet" placeholder is shown instead.
  const scoreboardClans = (() => {
    const live = snapshot?.clans;
    if (live && live.length > 0) {
      return live
        .map(c => {
          const meta = MOCK_CLANS.find(m => m.id === c.id);
          return {
            id: c.id,
            name: c.name,
            color: meta?.color ?? 0xcccccc,
            portrait: meta?.portrait ?? '',
            archetype: meta?.archetype ?? '',
            monumentLevel: treasuryToMonument(c.treasury),
          };
        })
        .sort((a, b) => b.monumentLevel - a.monumentLevel);
    }
    // Mock fallback — only used in DEMO_MODE
    if (DEMO_MODE) {
      return MOCK_CLANS.map((c, i) => ({
        id: c.id,
        name: c.name,
        color: c.color,
        portrait: c.portrait,
        archetype: c.archetype,
        monumentLevel: 4 - i,
      })).sort((a, b) => b.monumentLevel - a.monumentLevel);
    }
    return [];
  })();

  return (
    <div
      ref={containerRef}
      style={{
        position: 'relative',
        width: '100%',
        // Fill the parent. We set BOTH `height: 100%` (so grid-cell parents
        // like the cockpit's center cell give us their full row height) AND
        // `flex: 1 1 auto` + min-height:0 (legacy: the standalone
        // /worldmap-only route uses a flex column <main> wrapper). Without
        // height:100%, grid-cell children collapse to content-height (= 0
        // because the inner canvasWrap is absolutely positioned), pixi
        // ResizeObserver reports 0x0, and the canvas renders empty/black.
        height: '100%',
        flex: '1 1 auto',
        minHeight: 0,
        overflow: 'hidden',
      }}
    >
      <div
        ref={canvasWrapRef}
        style={{
          position: 'absolute',
          inset: 0,
          width: '100%',
          height: '100%',
        }}
      />

      {/* Compact world-pulse panel — bottom-left, semi-transparent.
          Floating Lv badges on the canvas show per-clan level; this panel just
          gives a glance of the world tick + a tight per-clan summary line.
          Shown whenever scoreboardClans is non-empty (demo mock data OR live snapshot). */}
      {scoreboardClans.length > 0 && (
        <div
          style={{
            position: 'absolute',
            bottom: 8,
            left: 8,
            padding: '5px 8px',
            background: 'rgba(13, 26, 13, 0.7)',
            border: '1px solid rgba(204, 170, 34, 0.35)',
            borderRadius: 5,
            fontFamily: 'monospace',
            color: '#e8e2c8',
            fontSize: 10,
            lineHeight: 1.3,
            boxShadow: '0 2px 6px rgba(0,0,0,0.35)',
            pointerEvents: 'none',
            zIndex: 2,
            maxWidth: '70%',
          }}
        >
          <div style={{ color: '#e8d68f', fontWeight: 600, letterSpacing: '0.05em' }}>
            tick {liveTick}
          </div>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', opacity: 0.85 }}>
            {scoreboardClans.map((c) => {
              const initials =
                c.name === 'Iron Guard' ? 'IG'
                  : c.name === 'Ember Hand' ? 'EH'
                  : c.name === 'Dawn Watch' ? 'DW'
                  : c.name === 'Storm Riders' ? 'SR'
                  : c.name.slice(0, 2).toUpperCase();
              return (
                <span key={c.id} style={{ color: hex(c.color), whiteSpace: 'nowrap' }}>
                  {initials} L{c.monumentLevel}
                </span>
              );
            })}
          </div>
        </div>
      )}

      {/* "No chain data yet" placeholder — shown when DEMO_MODE is off and no
          live snapshot clans are present. Centered overlay so it reads clearly
          on the bare terrain map. */}
      {!DEMO_MODE && (!snapshot?.clans || snapshot.clans.length === 0) && (
        <div
          data-testid="no-chain-data-placeholder"
          style={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            pointerEvents: 'none',
            zIndex: 3,
          }}
        >
          <div
            style={{
              padding: '16px 28px',
              background: 'rgba(13, 26, 13, 0.82)',
              border: '1px solid rgba(204, 170, 34, 0.4)',
              borderRadius: 8,
              fontFamily: '"Cinzel", "Times New Roman", serif',
              color: '#e8d68f',
              fontSize: 15,
              letterSpacing: '0.07em',
              boxShadow: '0 4px 16px rgba(0,0,0,0.5)',
              textAlign: 'center',
            }}
          >
            no chain data yet
          </div>
        </div>
      )}

      {/* World-level notice parchment — bottom-center, surfaces warn-level
          WORLD events (bandits, raids, weather). Distinct from per-clan
          speech bubbles. */}
      <WorldNoticePanel />
    </div>
  );
}

/**
 * Build one speech bubble (PR #43, tail-rework PR for hackathon).
 * Container origin = the anchor on the base sprite (= tip of the tail).
 * Backdrop is drawn ABOVE the origin; tail points down to (0, 0).
 *
 * The tail is a separate Graphics object so the ticker can hide it on
 * stacked (non-bottom) bubbles. Tail uses clan color + thick white outline
 * so it's clearly visible against dark/textured backgrounds and visually
 * attributes the bubble to its base.
 */
function makeBubble(message: string, clanId: string, clanColor: number): BubbleHandle {
  const container = new Container();
  container.alpha = 0;

  // Split on first ": " — header (e.g. "Iron Guard Elder") gets distinct styling
  // (bold, clan-colored, Cinzel) above the orders body. Fall back to single-line
  // rendering if the message has no header separator.
  const splitIdx = message.indexOf(': ');
  const hasHeader = splitIdx > 0;
  const header = hasHeader ? message.slice(0, splitIdx) : '';
  const body = hasHeader ? message.slice(splitIdx + 2) : message;

  const wrapWidth = BUBBLE_MAX_WIDTH - BUBBLE_PAD_X * 2;
  const HEADER_BODY_GAP = 2;

  const headerText = hasHeader
    ? new Text({
        text: header,
        style: {
          fill: clanColor,
          fontSize: 13,
          fontFamily: '"Cinzel", "Times New Roman", serif',
          fontWeight: 'bold',
          wordWrap: true,
          wordWrapWidth: wrapWidth,
          lineHeight: 16,
        },
      })
    : null;

  const bodyText = new Text({
    text: body,
    style: {
      fill: 0xfff5e0,
      fontSize: 12,
      fontFamily: 'monospace',
      wordWrap: true,
      wordWrapWidth: wrapWidth,
      lineHeight: 15,
    },
  });

  const headerW = headerText ? Math.min(headerText.width, wrapWidth) : 0;
  const headerH = headerText ? headerText.height : 0;
  const bodyW = Math.min(bodyText.width, wrapWidth);
  const bodyH = bodyText.height;

  const textW = Math.max(headerW, bodyW);
  const textH = headerText ? headerH + HEADER_BODY_GAP + bodyH : bodyH;
  const w = textW + BUBBLE_PAD_X * 2;
  const h = textH + BUBBLE_PAD_Y * 2;

  const tailH = BUBBLE_TAIL_HEIGHT;
  const backdrop = new Graphics();
  const bx = -w / 2;
  const by = -h - tailH;
  backdrop.roundRect(bx, by, w, h, BUBBLE_CORNER);
  backdrop.fill({ color: BUBBLE_FILL, alpha: BUBBLE_FILL_ALPHA });
  backdrop.stroke({ color: clanColor, width: 1.5, alpha: 0.85 });

  container.addChild(backdrop);

  // Tail: clan-colored fill with thick white outline. Drawn as a separate
  // Graphics so the ticker can hide it on non-bottom (stacked) bubbles —
  // upper-stack tails would point to empty air and look broken.
  const tail = new Graphics();
  // Triangle: top edge sits flush with backdrop bottom (y = -tailH),
  // tip at (0, 0) which is the anchor on the base sprite.
  tail.moveTo(-BUBBLE_TAIL_HALF_WIDTH, -tailH);
  tail.lineTo(BUBBLE_TAIL_HALF_WIDTH, -tailH);
  tail.lineTo(0, 0);
  tail.closePath();
  tail.fill({ color: clanColor, alpha: 1 });
  tail.stroke({ color: BUBBLE_TAIL_OUTLINE, width: BUBBLE_TAIL_OUTLINE_WIDTH, alpha: 1 });
  container.addChild(tail);

  if (headerText) {
    headerText.x = bx + BUBBLE_PAD_X;
    headerText.y = by + BUBBLE_PAD_Y;
    container.addChild(headerText);
    bodyText.x = bx + BUBBLE_PAD_X;
    bodyText.y = by + BUBBLE_PAD_Y + headerH + HEADER_BODY_GAP;
  } else {
    bodyText.x = bx + BUBBLE_PAD_X;
    bodyText.y = by + BUBBLE_PAD_Y;
  }
  container.addChild(bodyText);

  return {
    container,
    bornAt: performance.now(),
    lifeMs: FADE_IN_MS + HOLD_MS + FADE_OUT_MS,
    height: h + tailH,
    clanId,
    tail,
  };
}
