import { useEffect, useRef, useState } from 'react';
import { useQuery } from 'convex/react';
import { type FunctionReference, anyApi } from 'convex/server';
import { Application, Assets, Container, Graphics, Sprite, Text } from 'pixi.js';
import { useAgentLogs, type AgentLog } from './useAgentLogs';
import worldMapBg from './assets/world-map.png';

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
  { id: 'clan-iron',  name: 'Iron Guard',   homeRegion: 'forest',     color: 0x4488cc, sigil: '/sigils/iron-guard-sigil.png',  portrait: '/portraits/aldric-portrait.png',  archetype: 'Cautious'   },
  { id: 'clan-ember', name: 'Ember Hand',   homeRegion: 'mountains',  color: 0xcc4422, sigil: '/sigils/ember-hand-sigil.png',  portrait: '/portraits/brennan-portrait.png', archetype: 'Aggressive' },
  { id: 'clan-dawn',  name: 'Dawn Watch',   homeRegion: 'west-farms', color: 0xccaa22, sigil: '/sigils/dawn-watch-sigil.png',  portrait: '/portraits/sora-portrait.png',    archetype: 'Builder'    },
  { id: 'clan-storm', name: 'Storm Riders', homeRegion: 'east-farms', color: 0x44aacc, sigil: '/sigils/storm-riders-sigil.png', portrait: '/portraits/mira-portrait.png',   archetype: 'Trader'     },
];

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

type BubbleHandle = {
  container: Container;
  bornAt: number;
  lifeMs: number;
  height: number; // backdrop + tail; used for vertical stacking
  clanId: string;
};

// Worker travel animation (PR #44) — small clan-colored dots crossing between regions.
interface WorkerTravel {
  id: string;
  fromRegionKey: string;
  toRegionKey: string;
  startedAt: number;
  durationMs: number;
  color: number;
  gfx: Graphics;
}

const TRAVEL_DOT_RADIUS = 3; // 6px diameter
const TRAVEL_FADE_OUT_MS = 400;
const TRAVEL_MIN_MS = 8000;
const TRAVEL_MAX_MS = 15000;
const CANNED_TRAVEL_INTERVAL_MS = 30_000;

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

  const [pixiReady, setPixiReady] = useState(false);
  const [, setSize] = useState({ w: 800, h: 600 });

  const logs = useAgentLogs();
  const snapshot = useQuery(getSnapshotRef) as SnapshotData | undefined;

  // ---- Pixi init ------------------------------------------------------------
  useEffect(() => {
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
        if (!mounted || !canvasWrapRef.current) return;
        canvasWrapRef.current.appendChild(app.canvas);
        // CSS: stretch to wrapper
        app.canvas.style.display = 'block';
        app.canvas.style.width = '100%';
        app.canvas.style.height = '100%';
        // Allow native pinch-zoom on iOS/Telegram WebView. Pixi v8's EventSystem
        // sets touchAction='none' on the canvas during init (see pixijs.com/8.x
        // events guide + GH#2483), which blocks the browser's native pinch
        // gesture regardless of <meta viewport user-scalable=yes>. Overriding
        // back to 'pinch-zoom' restores two-finger zoom on the canvas while
        // single-touch events still reach Pixi for hit testing.
        app.canvas.style.touchAction = 'pinch-zoom';

        // 1. Background terrain map (PR #40) — fantasy strategy art generated to match REGIONS layout.
        // Loaded async; sprite is added to app.stage BEFORE buildScene so region circles render on top.
        try {
          const tex = await Assets.load(worldMapBg);
          if (!mounted) return;
          const bg = new Sprite(tex);
          bg.width = initialW;
          bg.height = initialH;
          bg.x = 0;
          bg.y = 0;
          app.stage.addChild(bg);
          drawnRef.current.bgSprite = bg;
        } catch (err) {
          // Non-fatal — fall through to flat background color set in app.init
          console.warn('[WorldMap] failed to load terrain background', err);
        }

        // 2. Build scene (regions, sigil sprites, bandit indicator) — PR #41 + PR #42 logic
        buildScene(app);

        // 3. Speech bubble layer + ticker (PR #43) — added last so bubbles render above everything.
        const bubbleLayer = new Container();
        app.stage.addChild(bubbleLayer);
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
            const anchor = flagAnchorsRef.current.get(clanId);
            if (anchor && list.length > 0) {
              let cursorY = anchor.y - BUBBLE_FLAG_OFFSET_Y;
              for (let i = 0; i < list.length; i++) {
                const b = list[i];
                if (!b) continue;
                b.container.x = anchor.x;
                b.container.y = cursorY;
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
        app.stage.addChildAt(travelLayer, app.stage.getChildIndex(bubbleLayer));
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
              // Fade out at destination
              const fadeAge = elapsed - t.durationMs;
              if (fadeAge >= TRAVEL_FADE_OUT_MS) {
                layer.removeChild(t.gfx);
                t.gfx.destroy();
                list.splice(i, 1);
                continue;
              }
              t.gfx.x = tx;
              t.gfx.y = ty;
              t.gfx.alpha = Math.max(0, 1 - fadeAge / TRAVEL_FADE_OUT_MS);
            } else {
              t.gfx.x = fx + (tx - fx) * progress;
              t.gfx.y = fy + (ty - fy) * progress;
              // Subtle fade-in over first 200ms so dots don't pop in
              t.gfx.alpha = Math.min(1, elapsed / 200);
            }
          }
        };
        travelTickerCbRef.current = travelCb;
        app.ticker.add(travelCb);

        // 4. Initial layout (PR #41) — projects normalized coords + positions flag anchors.
        relayout(initialW, initialH);
        setSize({ w: initialW, h: initialH });
        setPixiReady(true);
      });

    return () => {
      mounted = false;
      const a = appRef.current;
      if (a && tickerCbRef.current) a.ticker.remove(tickerCbRef.current);
      if (a && travelTickerCbRef.current) a.ticker.remove(travelTickerCbRef.current);
      bubblesByClanRef.current.clear();
      seenLogIdsRef.current.clear();
      flagAnchorsRef.current.clear();
      travelsRef.current = [];
      seenTravelLogIdsRef.current.clear();
      bubbleLayerRef.current = null;
      travelLayerRef.current = null;
      tickerCbRef.current = null;
      travelTickerCbRef.current = null;
      drawnRef.current = {
        regions: [],
        regionLabels: [],
        flags: [],
        walls: [],
        monuments: [],
        banditIcon: null,
        banditSprite: null,
        banditCountdown: null,
        bgSprite: null,
      };
      appRef.current = null;
      a?.destroy(true);
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
      relayout(w, h);
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
  function buildScene(app: Application) {
    const drawn = drawnRef.current;

    for (const region of REGIONS) {
      const g = new Graphics();
      app.stage.addChild(g);
      drawn.regions.push(g);

      const label = new Text({
        text: region.name,
        style: { fill: 0xdddddd, fontSize: 11, fontFamily: 'monospace' },
      });
      label.anchor.set(0.5, 0);
      app.stage.addChild(label);
      drawn.regionLabels.push(label);
    }

    // Wall rings — drawn first so they sit above region circles but under sigils.
    for (const clan of MOCK_CLANS) {
      const wallGfx = new Graphics();
      app.stage.addChild(wallGfx);
      drawn.walls.push({ gfx: wallGfx, clan });
    }

    // Monument towers — drawn before flags so sigil layers cleanly on top.
    for (const clan of MOCK_CLANS) {
      const monGfx = new Graphics();
      app.stage.addChild(monGfx);
      drawn.monuments.push({ gfx: monGfx, clan });
    }

    for (const clan of MOCK_CLANS) {
      const flag = new Graphics();
      app.stage.addChild(flag);
      const label = new Text({
        text: clan.name,
        style: { fill: clan.color, fontSize: 10, fontFamily: 'monospace', fontWeight: 'bold' },
      });
      label.anchor.set(0, 1);
      app.stage.addChild(label);
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
          const sprite = new Sprite(texture);
          sprite.alpha = 0; // hidden until first relayout positions it
          app.stage.addChild(sprite);
          entry.sprite = sprite;
          // Trigger a relayout so sprite gets positioned and shown.
          const wrap = canvasWrapRef.current;
          if (wrap && appRef.current) {
            relayout(wrap.clientWidth || 800, wrap.clientHeight || 600);
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
    app.stage.addChild(banditIcon);
    const countdown = new Text({
      text: '',
      style: { fill: 0xffe9b8, fontSize: 11, fontFamily: 'monospace', fontWeight: 'bold' },
    });
    countdown.anchor.set(0, 0.5);
    app.stage.addChild(countdown);
    drawn.banditIcon = banditIcon;
    drawn.banditCountdown = countdown;

    // Async-load the bandit sprite — once ready, redrawBandit positions it and
    // hides the fallback ring. Catch silently so the ring stays visible on failure.
    Assets.load('/sprites/bandit.png')
      .then((texture) => {
        const sprite = new Sprite(texture);
        sprite.anchor.set(0.5, 0.5);
        sprite.alpha = 0; // hidden until first redrawBandit positions it
        app.stage.addChild(sprite);
        drawn.banditSprite = sprite;
        redrawBandit();
      })
      .catch(() => {
        // Keep fallback ring visible.
      });
  }

  // ---- Layout: scale all draw coords from REF frame to canvas dimensions ---
  // Stretches positions to fill the viewport (so 8 regions fit on tall portrait
  // phones AND wide landscape) while keeping circles circular (uniform radius).
  function relayout(w: number, h: number) {
    // Reserve space at top for scoreboard + speech bubble overlays so they
    // don't sit on top of region circles. Bottom margin only protects from clip.
    const sideMargin = 32;
    const topMargin = 140; // scoreboard ≈120px tall, +20 cushion
    const bottomMargin = 32;
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
    const regionRadius = 40 * cappedSizeScale;

    // Stretch background terrain to fill the canvas.
    if (drawn.bgSprite) {
      drawn.bgSprite.width = w;
      drawn.bgSprite.height = h;
      drawn.bgSprite.x = 0;
      drawn.bgSprite.y = 0;
    }

    // Regions
    REGIONS.forEach((region, i) => {
      const cx = projX(region.nx);
      const cy = projY(region.ny);
      const g = drawn.regions[i];
      if (g) {
        g.clear();
        g.circle(cx, cy, regionRadius);
        g.fill({ color: region.color });
        g.stroke({ color: 0xffffff, width: 1, alpha: 0.4 });
      }
      const label = drawn.regionLabels[i];
      if (label) {
        label.style.fontSize = Math.max(9, Math.round(11 * cappedSizeScale));
        label.x = cx;
        label.y = cy + regionRadius + 4;
      }
    });

    const regionMap = new Map(REGIONS.map(r => [r.id, r]));

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

    // Wall rings — opacity reflects wallLevel (0 → 0, 5 → 1.0, linear between).
    drawn.walls.forEach(({ gfx, clan }) => {
      const base = regionMap.get(clan.homeRegion);
      if (!base) return;
      const cx = projX(base.nx);
      const cy = projY(base.ny);
      const wallLevel = MOCK_WALL_LEVELS[clan.id] ?? 0;
      const alpha = Math.max(0, Math.min(1, wallLevel / WALL_LEVEL_MAX));
      gfx.clear();
      if (alpha > 0) {
        gfx.circle(cx, cy, regionRadius + 4 * cappedSizeScale);
        gfx.stroke({ width: Math.max(2, 3 * cappedSizeScale), color: clan.color, alpha });
      }
    });

    // Monument towers — stacked rectangles + top cap, height grows with level.
    // Positioned at the flag location, just below the sigil so it reads as
    // "the clan's structure at their homebase."
    drawn.monuments.forEach(({ gfx, clan }) => {
      const base = regionMap.get(clan.homeRegion);
      if (!base) return;
      const cx = projX(base.nx);
      const cy = projY(base.ny);
      const flagSize = SIGIL_SIZE * cappedSizeScale;
      const flagX = cx + 18 * cappedSizeScale;
      const flagY = cy - (SIGIL_SIZE + 8) * cappedSizeScale;

      const rawLevel = levelByClan.get(clan.id) ?? 0;
      const level = Math.max(0, Math.min(MONUMENT_LEVEL_MAX, rawLevel));
      const totalH = (MONUMENT_BASE_HEIGHT + level * MONUMENT_LEVEL_HEIGHT) * cappedSizeScale;
      const w = MONUMENT_WIDTH * cappedSizeScale;
      // Anchor: bottom-center of sigil, just below it (small gap for clarity).
      const bottomY = flagY + flagSize + 2 * cappedSizeScale + totalH;
      const topY = bottomY - totalH;
      const monX = flagX + flagSize / 2 - w / 2;

      gfx.clear();
      // Wide stone base (slightly broader for visual weight)
      const baseH = Math.max(2, 3 * cappedSizeScale);
      const baseW = w * 1.6;
      gfx.rect(monX - (baseW - w) / 2, bottomY - baseH, baseW, baseH);
      gfx.fill({ color: 0x6b6358 });
      gfx.stroke({ color: 0x000000, width: 1, alpha: 0.5 });

      // Shaft — main pillar, color tinted by clan.
      gfx.rect(monX, topY, w, totalH - baseH);
      gfx.fill({ color: 0xbdb4a2 });
      gfx.stroke({ color: clan.color, width: 1, alpha: 0.9 });

      // Top cap — small obelisk pyramid (triangle) marking the peak.
      if (level > 0) {
        const capH = Math.max(3, 5 * cappedSizeScale);
        gfx.moveTo(monX, topY);
        gfx.lineTo(monX + w / 2, topY - capH);
        gfx.lineTo(monX + w, topY);
        gfx.closePath();
        gfx.fill({ color: clan.color, alpha: 0.95 });
        gfx.stroke({ color: 0x000000, width: 1, alpha: 0.4 });
      }
    });

    // Clan flags (anchored to homebase) — sprite if loaded, else fallback rect.
    // Also recompute bubble anchors so PR #43 bubbles follow flags through resize.
    drawn.flags.forEach(({ gfx, sprite, label, clan }) => {
      const base = regionMap.get(clan.homeRegion);
      if (!base) return;
      const cx = projX(base.nx);
      const cy = projY(base.ny);
      const flagSize = SIGIL_SIZE * cappedSizeScale;
      const flagX = cx + 18 * cappedSizeScale;
      const flagY = cy - (SIGIL_SIZE + 8) * cappedSizeScale;
      // Always position the fallback rect; hide it once sprite is loaded.
      gfx.clear();
      if (!sprite) {
        gfx.rect(flagX, flagY, flagSize, flagSize);
        gfx.fill({ color: clan.color, alpha: 0.85 });
        gfx.stroke({ color: 0xffffff, width: 1 });
      }
      if (sprite) {
        sprite.width = flagSize;
        sprite.height = flagSize;
        sprite.x = flagX;
        sprite.y = flagY;
        sprite.alpha = 1;
      }
      label.style.fontSize = Math.max(8, Math.round(10 * cappedSizeScale));
      label.x = flagX + flagSize + 4;
      label.y = flagY + flagSize;

      // Bubble anchor: top-center of sigil — tail tip lands here, bubbles stack up.
      flagAnchorsRef.current.set(clan.id, { x: flagX + flagSize / 2, y: flagY });
    });

    // Bandit redraw uses live tick — recompute alongside layout
    redrawBandit();
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

  // Tick changes: refresh bandit countdown
  useEffect(() => {
    if (!pixiReady) return;
    redrawBandit();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [snapshot?.tick, pixiReady]);

  // Snapshot clan changes: re-layout so monument heights track live treasury.
  useEffect(() => {
    if (!pixiReady) return;
    const wrap = canvasWrapRef.current;
    if (!wrap) return;
    relayout(wrap.clientWidth || 800, wrap.clientHeight || 600);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [snapshot?.clans, pixiReady]);

  // Pulse the bandit icon when 1-2 ticks from attacking — urgency cue for the demo
  useEffect(() => {
    if (!pixiReady) return;
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
  useEffect(() => {
    if (!pixiReady || !bubbleLayerRef.current || logs.length === 0) return;
    const layer = bubbleLayerRef.current;

    // useAgentLogs returns desc order. Reverse so chronological add → newest stacked on top.
    const ordered: AgentLog[] = [...logs].reverse();
    for (const log of ordered) {
      if (seenLogIdsRef.current.has(log._id)) continue;
      seenLogIdsRef.current.add(log._id);

      const clanId = attributeClan(log.message);
      if (!clanId) continue; // skip unattributable logs (rather than corner-clutter)

      const msg = log.message.slice(0, 240);
      const handle = makeBubble(msg, clanId);
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
  function spawnTravel(fromRegionKey: string, toRegionKey: string, color: number) {
    const layer = travelLayerRef.current;
    if (!layer) return;
    if (fromRegionKey === toRegionKey) return;
    const from = REGIONS.find(r => r.id === fromRegionKey);
    const to = REGIONS.find(r => r.id === toRegionKey);
    if (!from || !to) return;

    const gfx = new Graphics();
    gfx.circle(0, 0, TRAVEL_DOT_RADIUS);
    gfx.fill({ color });
    gfx.stroke({ color: 0x000000, width: 1, alpha: 0.55 });
    gfx.alpha = 0;
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

  // Real travels: parse "send X to Y" out of new log messages
  useEffect(() => {
    if (!pixiReady || !travelLayerRef.current || logs.length === 0) return;
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
      spawnTravel(clan.homeRegion, dest, clan.color);
    }
  }, [logs, pixiReady]);

  // Canned demo travels: random clan → random non-home region every 30s
  // so the canvas always has visible motion even when no logs match.
  useEffect(() => {
    if (!pixiReady) return;
    const fireOne = () => {
      const clan = MOCK_CLANS[Math.floor(Math.random() * MOCK_CLANS.length)];
      if (!clan) return;
      const candidates = REGIONS.filter(r => r.id !== clan.homeRegion);
      const dest = candidates[Math.floor(Math.random() * candidates.length)];
      if (!dest) return;
      spawnTravel(clan.homeRegion, dest.id, clan.color);
    };
    // Fire one immediately so the demo isn't blank for the first 30s
    fireOne();
    const interval = window.setInterval(fireOne, CANNED_TRAVEL_INTERVAL_MS);
    return () => window.clearInterval(interval);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pixiReady]);

  // ---- Scoreboard data: live snapshot if present, else mock metadata -------
  // Portrait + archetype label come from MOCK_CLANS (they are static metadata,
  // not server state) — we look them up by clan id whether the row is sourced
  // from a live snapshot or the mock fallback.
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
    return MOCK_CLANS.map((c, i) => ({
      id: c.id,
      name: c.name,
      color: c.color,
      portrait: c.portrait,
      archetype: c.archetype,
      monumentLevel: 4 - i,
    })).sort((a, b) => b.monumentLevel - a.monumentLevel);
  })();

  return (
    <div
      ref={containerRef}
      style={{
        position: 'relative',
        width: '100%',
        // Fill remaining flex space inside <main>. min-height:0 lets flex
        // shrink past content size; dvh ensures iOS toolbar is honored.
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

      {/* Scoreboard overlay — top-right, ordered leader-first */}
      <div
        style={{
          position: 'absolute',
          top: 8,
          right: 8,
          minWidth: 150,
          maxWidth: 220,
          padding: '8px 10px',
          background: 'rgba(13, 26, 13, 0.82)',
          border: '1px solid rgba(204, 170, 34, 0.55)',
          borderRadius: 6,
          fontFamily: 'Inter, system-ui, sans-serif',
          color: '#e8e2c8',
          fontSize: 12,
          lineHeight: 1.35,
          boxShadow: '0 2px 8px rgba(0,0,0,0.4)',
          pointerEvents: 'none',
          zIndex: 2,
        }}
      >
        <div
          style={{
            fontFamily: '"Cinzel", "Times New Roman", serif',
            fontSize: 13,
            fontWeight: 600,
            letterSpacing: '0.08em',
            textTransform: 'uppercase',
            marginBottom: 6,
            color: '#e8d68f',
            borderBottom: '1px solid rgba(204, 170, 34, 0.35)',
            paddingBottom: 4,
          }}
        >
          Monuments
        </div>
        {scoreboardClans.map((c, i) => (
          <div
            key={c.id}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 6,
              padding: '3px 0 3px 6px',
              borderLeft: `3px solid ${hex(c.color)}`,
              marginBottom: i === scoreboardClans.length - 1 ? 0 : 2,
            }}
          >
            {/* Portrait avatar — pixel-art codex/PIL render keyed to clan archetype.
                image-rendering:pixelated keeps the 64px asset crisp at small sizes. */}
            {c.portrait && (
              <img
                src={c.portrait}
                alt=""
                aria-hidden
                width={22}
                height={22}
                style={{
                  width: 22,
                  height: 22,
                  borderRadius: 4,
                  border: `1px solid ${hex(c.color)}`,
                  imageRendering: 'pixelated',
                  flexShrink: 0,
                  background: 'rgba(0,0,0,0.25)',
                }}
              />
            )}
            <div style={{ flex: 1, minWidth: 0 }}>
              <div
                style={{
                  color: hex(c.color),
                  fontWeight: 600,
                  fontSize: 11,
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                }}
              >
                {c.name}
              </div>
              {c.archetype && (
                <div
                  style={{
                    color: '#a8a290',
                    fontSize: 9,
                    fontFamily: 'monospace',
                    letterSpacing: '0.04em',
                    textTransform: 'uppercase',
                    lineHeight: 1.1,
                  }}
                >
                  {c.archetype}
                </div>
              )}
            </div>
            <span
              style={{
                color: '#e8e2c8',
                fontVariantNumeric: 'tabular-nums',
                fontSize: 11,
                marginLeft: 4,
              }}
            >
              Lv {c.monumentLevel}
            </span>
          </div>
        ))}
        {snapshot?.tick !== undefined && (
          <div
            style={{
              marginTop: 6,
              paddingTop: 4,
              borderTop: '1px solid rgba(204, 170, 34, 0.25)',
              fontSize: 10,
              opacity: 0.75,
              fontFamily: 'monospace',
              textAlign: 'right',
            }}
          >
            tick {snapshot.tick}
          </div>
        )}
      </div>
    </div>
  );
}

/**
 * Build one speech bubble (PR #43).
 * Container origin = the anchor on the flag (= bottom tip of the tail).
 * Backdrop is drawn ABOVE the origin; tail points down to (0, 0).
 */
function makeBubble(message: string, clanId: string): BubbleHandle {
  const container = new Container();
  container.alpha = 0;

  const text = new Text({
    text: message,
    style: {
      fill: 0xffffff,
      fontSize: 12,
      fontFamily: 'monospace',
      wordWrap: true,
      wordWrapWidth: BUBBLE_MAX_WIDTH - BUBBLE_PAD_X * 2,
      lineHeight: 15,
    },
  });

  const textW = Math.min(text.width, BUBBLE_MAX_WIDTH - BUBBLE_PAD_X * 2);
  const textH = text.height;
  const w = textW + BUBBLE_PAD_X * 2;
  const h = textH + BUBBLE_PAD_Y * 2;

  const tailH = 8;
  const backdrop = new Graphics();
  const bx = -w / 2;
  const by = -h - tailH;
  backdrop.roundRect(bx, by, w, h, BUBBLE_CORNER);
  backdrop.fill({ color: BUBBLE_FILL, alpha: BUBBLE_FILL_ALPHA });

  // Tail triangle: from backdrop bottom edge down to the anchor (0, 0)
  backdrop.moveTo(-6, -tailH);
  backdrop.lineTo(6, -tailH);
  backdrop.lineTo(0, 0);
  backdrop.closePath();
  backdrop.fill({ color: BUBBLE_FILL, alpha: BUBBLE_FILL_ALPHA });

  container.addChild(backdrop);

  text.x = bx + BUBBLE_PAD_X;
  text.y = by + BUBBLE_PAD_Y;
  container.addChild(text);

  return {
    container,
    bornAt: performance.now(),
    lifeMs: FADE_IN_MS + HOLD_MS + FADE_OUT_MS,
    height: h + tailH,
    clanId,
  };
}
