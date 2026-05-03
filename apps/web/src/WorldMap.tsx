import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery } from 'convex/react';
import { Application, Assets, ColorMatrixFilter, Container, Graphics, Sprite, Text } from 'pixi.js';
import { Viewport } from 'pixi-viewport';
import { useAgentLogs, type AgentLog } from './useAgentLogs';
import { WorldNoticePanel } from './WorldNoticePanel';
import { api } from '../../server/convex/_generated/api';
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
// Base sprite themes (one of 8 hand-painted clan keep sets shipped under /bases/):
//   cobalt-keep      — blue/grey castle w/ banners (knight)
//   bone-standard    — red barbarian camp w/ horns (warlord)
//   gilded-hold      — gold merchant stronghold
//   tide-wardens     — blue dock-on-water (fishers)
//   pale-cathedral   — cream stone cathedral (religious order)
//   amethyst-spire   — purple gothic w/ crystals (mystic)
//   black-forge      — dark stone forge w/ orange flames (smith)
//   verdant-grove    — green tree/treehouse castle (druid)
// The 4 active clans are mapped to themes whose colour palette matches their sigil.
const MOCK_CLANS: ClanDef[] = [
  { id: 'clan-iron',  name: 'Iron Guard',   homeRegion: 'forest',     color: 0x4488cc, sigil: '/sigils/iron-guard-sigil.png',  portrait: '/portraits/aldric-portrait.png',  archetype: 'Cautious',   basePng: '/bases/cobalt-keep.png',   clansmanPng: '/clansmen/clan-iron.png'  },
  { id: 'clan-ember', name: 'Ember Hand',   homeRegion: 'mountains',  color: 0xcc4422, sigil: '/sigils/ember-hand-sigil.png',  portrait: '/portraits/brennan-portrait.png', archetype: 'Aggressive', basePng: '/bases/bone-standard.png', clansmanPng: '/clansmen/clan-ember.png' },
  { id: 'clan-dawn',  name: 'Dawn Watch',   homeRegion: 'west-farms', color: 0xccaa22, sigil: '/sigils/dawn-watch-sigil.png',  portrait: '/portraits/sora-portrait.png',    archetype: 'Builder',    basePng: '/bases/gilded-hold.png',   clansmanPng: '/clansmen/clan-dawn.png'  },
  { id: 'clan-storm', name: 'Storm Riders', homeRegion: 'east-farms', color: 0x44aacc, sigil: '/sigils/storm-riders-sigil.png', portrait: '/portraits/mira-portrait.png',   archetype: 'Trader',     basePng: '/bases/tide-wardens.png',  clansmanPng: '/clansmen/clan-storm.png' },
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

type WorldLayers = {
  worldContainer: Container;
  terrainBackground: Container;
  terrainAccents: Container;
  worldDynamic: Container;
  inWorldEffects: Container;
  selectionRings: Container;
  bubbleLayer: Container;
  screenEffects: Container;
  combatDim: Graphics;
  combatHighlight: Container;
  combatFlash: Graphics;
};

type CarryIndicator = {
  container: Container;
  fill: Graphics;
  displayedFill: number;
  targetFill: number;
};

type DayNightKeyframe = {
  r: number;
  g: number;
  b: number;
  brightness: number;
  sat: number;
};

type SelectableTarget = Container & {
  width: number;
  height: number;
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
  carry: CarryIndicator;
}

type CombatOutcome = 'success' | 'failure';

type ReparentedCombatant = {
  node: Container;
  parent: Container;
  zIndex: number;
  wasTemporary?: boolean;
};

type CombatVignette = {
  startedAt: number;
  outcome: CombatOutcome;
  bandit: Container | null;
  targetBase: Container;
  defenders: Container[];
  reparented: ReparentedCombatant[];
  baseStart: { x: number; y: number; scaleX: number; scaleY: number };
  banditStart: { x: number; y: number; scaleX: number; scaleY: number; alpha: number };
  defenderStarts: { x: number; y: number }[];
  center: { x: number; y: number };
};

const TRAVEL_DOT_RADIUS = 4; // 8px diameter — slightly bigger so it reads in the demo
const TRAVEL_FADE_OUT_MS = 1200; // longer linger at destination
const TRAVEL_DEST_LINGER_MS = 2500; // hold at destination at full alpha before fading
const TRAVEL_MIN_MS = 4500;
const TRAVEL_MAX_MS = 8000;
const CANNED_TRAVEL_INTERVAL_MS = 1800; // continuous spawn — keeps map alive

const COMBAT_VIGNETTE_LEAD_MS = 4000;
const COMBAT_ADVANCE_MS = 1500;
const COMBAT_FLASH_START_MS = 2000;
const COMBAT_FLASH_IN_MS = 80;
const COMBAT_FLASH_HOLD_MS = 100;
const COMBAT_FLASH_FADE_MS = 800;
const COMBAT_RESOLUTION_START_MS = 2200;
const COMBAT_RESOLUTION_CAP_MS = 1500;
const COMBAT_TOTAL_MS = COMBAT_RESOLUTION_START_MS + COMBAT_RESOLUTION_CAP_MS + 600;
const COMBAT_DIM_ALPHA = 0.55;
const COMBAT_DIM_TINT = 0x1a1a3a;
const COMBAT_TARGET_CLAN_ID = 'clan-ember';
/** Demo combat outcome — overrideable via URL param `?combat=success|failure`
 * for stage flexibility. Defaults to failure since wall-drop reads more
 * dramatic. Replace with `snapshot.combatOutcome` when schema lands. */
function readDemoCombatOutcome(): CombatOutcome {
  if (typeof window === 'undefined') return 'failure';
  const param = new URLSearchParams(window.location.search).get('combat');
  return param === 'success' ? 'success' : 'failure';
}

// TODO(contract-bindings): replace these demo defaults when carry caps are exposed.
const WOOD_CAP = 10;
const IRON_CAP = 5;
const WHEAT_CAP = 10;
const FISH_CAP = 10;
const CARRY_BAR_W = 16;
const CARRY_BAR_H = 3;

const TICKS_PER_DAY_CYCLE = 30;
const FALLBACK_DAY_TICK_MS = 60_000;
const DAYNIGHT_KEYFRAMES: Record<'dawn' | 'day' | 'dusk' | 'night', DayNightKeyframe> = {
  dawn: { r: 1.10, g: 0.90, b: 0.80, brightness: 0.95, sat: 0.85 },
  day: { r: 1.00, g: 1.00, b: 1.00, brightness: 1.00, sat: 1.00 },
  dusk: { r: 1.15, g: 0.85, b: 0.70, brightness: 0.85, sat: 0.95 },
  night: { r: 0.65, g: 0.70, b: 0.95, brightness: 0.55, sat: 0.70 },
};
const DAYNIGHT_PHASES = [
  { at: 0.00, key: 'dawn' as const },
  { at: 0.05, key: 'day' as const },
  { at: 0.50, key: 'dusk' as const },
  { at: 0.55, key: 'night' as const },
  { at: 1.00, key: 'dawn' as const },
];

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

function createWorldLayers(): WorldLayers {
  const worldContainer = new Container();
  const terrainBackground = new Container();
  const terrainAccents = new Container();
  const worldDynamic = new Container();
  const inWorldEffects = new Container();
  const selectionRings = new Container();
  const bubbleLayer = new Container();
  const screenEffects = new Container();
  const combatDim = new Graphics();
  const combatHighlight = new Container();
  const combatFlash = new Graphics();
  worldDynamic.sortableChildren = true;
  // §14.3: combatHighlight must use insertion-order so the success-launch
  // (bandit drawn after defenders) doesn't sort under the targeted base.
  // No sortableChildren here. (claude r3 SHOULD #1)
  screenEffects.sortableChildren = true;
  combatDim.zIndex = 0;
  combatHighlight.zIndex = 1;
  combatFlash.zIndex = 2;
  combatDim.alpha = 0;
  combatFlash.alpha = 0;
  screenEffects.addChild(combatDim, combatHighlight, combatFlash);
  worldContainer.addChild(terrainBackground, terrainAccents, worldDynamic);
  return {
    worldContainer,
    terrainBackground,
    terrainAccents,
    worldDynamic,
    inWorldEffects,
    selectionRings,
    bubbleLayer,
    screenEffects,
    combatDim,
    combatHighlight,
    combatFlash,
  };
}

function makeCarryIndicator(): CarryIndicator {
  const container = new Container();
  container.alpha = 0;
  const bg = new Graphics();
  bg.rect(-CARRY_BAR_W / 2, -CARRY_BAR_H / 2, CARRY_BAR_W, CARRY_BAR_H);
  bg.fill({ color: 0x1a1612, alpha: 0.95 });
  bg.stroke({ color: 0x000000, width: 1, alpha: 0.85 });
  const fill = new Graphics();
  container.addChild(bg);
  container.addChild(fill);
  return { container, fill, displayedFill: 0, targetFill: 0 };
}

function setCarryTargetFromCarry(
  indicator: CarryIndicator,
  carry: { wood?: number; iron?: number; wheat?: number; fish?: number },
) {
  indicator.targetFill = Math.max(
    (carry.wood ?? 0) / WOOD_CAP,
    (carry.iron ?? 0) / IRON_CAP,
    (carry.wheat ?? 0) / WHEAT_CAP,
    (carry.fish ?? 0) / FISH_CAP,
  );
}

function redrawCarryIndicator(indicator: CarryIndicator) {
  const next = Math.max(0, Math.min(1, indicator.displayedFill));
  indicator.container.alpha = next <= 0.01 ? 0 : 1;
  indicator.fill.clear();
  if (next <= 0.01) return;
  indicator.fill.rect(-CARRY_BAR_W / 2, -CARRY_BAR_H / 2, CARRY_BAR_W * next, CARRY_BAR_H);
  indicator.fill.fill({ color: 0xe8d8b5, alpha: 1 });
}

function clamp01(value: number) {
  return Math.max(0, Math.min(1, value));
}

function lerp(a: number, b: number, t: number) {
  return a + (b - a) * t;
}

function easeOutQuad(t: number) {
  return 1 - (1 - t) * (1 - t);
}

function easeInQuad(t: number) {
  return t * t;
}

function getDayNightFrame(progress01: number): DayNightKeyframe {
  const wrapped = ((progress01 % 1) + 1) % 1;
  for (let i = 0; i < DAYNIGHT_PHASES.length - 1; i++) {
    const a = DAYNIGHT_PHASES[i];
    const b = DAYNIGHT_PHASES[i + 1];
    if (!a || !b) continue;
    if (wrapped >= a.at && wrapped <= b.at) {
      const t = b.at === a.at ? 0 : (wrapped - a.at) / (b.at - a.at);
      const from = DAYNIGHT_KEYFRAMES[a.key];
      const to = DAYNIGHT_KEYFRAMES[b.key];
      return {
        r: lerp(from.r, to.r, t),
        g: lerp(from.g, to.g, t),
        b: lerp(from.b, to.b, t),
        brightness: lerp(from.brightness, to.brightness, t),
        sat: lerp(from.sat, to.sat, t),
      };
    }
  }
  return DAYNIGHT_KEYFRAMES.dawn;
}

function applyDayNightFilter(filter: ColorMatrixFilter, frame: DayNightKeyframe) {
  const r = frame.r * frame.brightness;
  const g = frame.g * frame.brightness;
  const b = frame.b * frame.brightness;
  void frame.sat;
  filter.matrix = [
    r, 0, 0, 0, 0,
    0, g, 0, 0, 0,
    0, 0, b, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

function drawSelectionRing(g: Graphics, radius: number, color: number) {
  g.clear();
  const segmentCount = 8;
  const gap = 0.18;
  const step = (Math.PI * 2) / segmentCount;
  for (let i = 0; i < segmentCount; i++) {
    const start = i * step + gap;
    const end = (i + 1) * step - gap;
    const samples = 6;
    for (let j = 0; j <= samples; j++) {
      const a = lerp(start, end, j / samples);
      const x = Math.cos(a) * radius;
      const y = Math.sin(a) * radius * 0.45;
      if (j === 0) g.moveTo(x, y);
      else g.lineTo(x, y);
    }
  }
  g.stroke({ color, width: 2, alpha: 1 });
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
    bases: {
      container: Container;
      sprite: Sprite | null;
      fallback: Graphics;
      glow: Graphics;
      clan: ClanDef;
      baseY: number;
      phaseOffset: number;
    }[];
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

  const layersRef = useRef<WorldLayers | null>(null);
  const dayNightFilterRef = useRef<ColorMatrixFilter | null>(null);
  const dayNightTickerCbRef = useRef<(() => void) | null>(null);
  const selectedRef = useRef<{
    target: SelectableTarget;
    ring: Graphics;
    color: number;
  } | null>(null);
  const tickClockRef = useRef<{ tick: number; seenAtMs: number }>({ tick: 0, seenAtMs: Date.now() });
  // Snapshot ref populated below in a useEffect — declared up here so the
  // day/night ticker (registered once at Pixi mount) reads current
  // snapshot/tickEpoch instead of the stale closure capture.
  const snapshotRef = useRef<ReturnType<typeof useQuery<typeof api.getSnapshot.getSnapshot>> | undefined>(undefined);

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
  const combatVignetteRef = useRef<CombatVignette | null>(null);
  // Set true after a `?combat=success` vignette completes, so the bandit
  // stays hidden post-fade-out instead of popping back to the home anchor.
  const banditDefeatedRef = useRef(false);
  const combatTickerCbRef = useRef<(() => void) | null>(null);
  const combatPlayedTickRef = useRef<number | null>(null);
  const liveTickClockRef = useRef<{ tick: number; seenAtMs: number }>({ tick: 0, seenAtMs: Date.now() });
  const liveTickRef = useRef(0);

  // Zone-pulse ticker (visual heartbeat for clan zone halos).
  const zonePulseCbRef = useRef<(() => void) | null>(null);
  const isMountedRef = useRef(true);

  const [pixiReady, setPixiReady] = useState(false);
  const [pixiInitError, setPixiInitError] = useState<Error | null>(null);
  const [, setSize] = useState({ w: 800, h: 600 });

  const logs = useAgentLogs();
  const snapshot = useQuery(api.getSnapshot.getSnapshot);

  // Derived live tick counter — the worldSnapshot.tick field is currently
  // unwritten by the orchestrator script (it only writes to agentLogs), so
  // we surface a moving counter by deriving from log count. Floors at the
  // snapshot value so we never go BACKWARDS if the schema is wired later.
  const liveTick = useMemo(() => {
    return Math.max(snapshot?.tick ?? 0, logs.length);
  }, [logs, snapshot?.tick]);
  const banditTicksUntil = DEMO_BANDIT.attacksAtTick - liveTick;
  const shouldPulseBandit = DEMO_MODE && banditTicksUntil <= 2 && banditTicksUntil >= 0;

  useEffect(() => {
    liveTickRef.current = liveTick;
    if (liveTickClockRef.current.tick !== liveTick) {
      liveTickClockRef.current = { tick: liveTick, seenAtMs: Date.now() };
    }
  }, [liveTick]);

  useEffect(() => {
    snapshotRef.current = snapshot;
    const rawTick = snapshot?.tick;
    if (typeof rawTick === 'number' && Number.isFinite(rawTick)) {
      tickClockRef.current = { tick: rawTick, seenAtMs: Date.now() };
    }
  }, [snapshot]);

  function getDayNightProgress() {
    const snap = snapshotRef.current;
    const tick = snap?.tick;
    const epoch = snap?.tickEpoch;
    const hasEpoch = !!epoch && typeof epoch.startedAt === 'number' && epoch.startedAt > 0;
    if (typeof tick === 'number' && Number.isFinite(tick) && (tick > 0 || hasEpoch)) {
      let subTickProgress = 0;
      if (hasEpoch && typeof epoch.durationMs === 'number' && epoch.durationMs > 0) {
        const startedAtMs = epoch.startedAt < 10_000_000_000 ? epoch.startedAt * 1000 : epoch.startedAt;
        subTickProgress = clamp01((Date.now() - startedAtMs) / epoch.durationMs);
      } else {
        const elapsed = Date.now() - tickClockRef.current.seenAtMs;
        subTickProgress = clamp01(elapsed / FALLBACK_DAY_TICK_MS);
      }
      return ((tick + subTickProgress) % TICKS_PER_DAY_CYCLE) / TICKS_PER_DAY_CYCLE;
    }
    return ((Date.now() / FALLBACK_DAY_TICK_MS) % TICKS_PER_DAY_CYCLE) / TICKS_PER_DAY_CYCLE;
  }

  function fitWorldAnimated() {
    const viewport = viewportRef.current;
    const wrap = canvasWrapRef.current;
    if (!viewport || !wrap) return;
    const fitScale = Math.max(
      (wrap.clientWidth || viewport.screenWidth) / WORLD_WIDTH,
      (wrap.clientHeight || viewport.screenHeight) / WORLD_HEIGHT,
    );
    viewport.plugins.remove('animate');
    viewport.animate({
      position: { x: WORLD_WIDTH / 2, y: WORLD_HEIGHT / 2 },
      scale: fitScale,
      time: 400,
      ease: 'easeInOutQuad',
    });
  }

  function clearSelection() {
    const selected = selectedRef.current;
    if (!selected) return;
    selected.target.removeChild(selected.ring);
    selected.ring.destroy();
    selectedRef.current = null;
    fitWorldAnimated();
  }

  function selectTarget(target: SelectableTarget, color: number) {
    const viewport = viewportRef.current;
    if (!viewport) return;
    // No-op during active combat vignette — a fresh selection ring would
    // appear inside the dimmed combat scene, undercutting the focus and
    // potentially persisting after the dim layer fades (codex 5.4 LOW).
    if (combatVignetteRef.current) return;
    let ring = selectedRef.current?.ring;
    if (!ring) {
      ring = new Graphics();
    } else if (ring.parent) {
      ring.parent.removeChild(ring);
    }
    const radius = Math.max(18, Math.max(target.width || 0, target.height || 0) * 0.7);
    drawSelectionRing(ring, radius, color);
    ring.visible = true;
    ring.alpha = 1;
    ring.rotation = 0;
    target.addChildAt(ring, 0);
    selectedRef.current = { target, ring, color };

    const global = target.getGlobalPosition();
    const world = viewport.toWorld(global);
    viewport.plugins.remove('animate');
    viewport.animate({
      position: { x: world.x, y: world.y },
      scale: 2.0,
      time: 400,
      ease: 'easeInOutQuad',
    });
  }

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

        const layers = createWorldLayers();
        viewport.addChild(
          layers.worldContainer,
          layers.inWorldEffects,
          layers.selectionRings,
          layers.bubbleLayer,
          layers.screenEffects,
        );
        const dayNightFilter = new ColorMatrixFilter();
        layers.worldContainer.filters = [dayNightFilter];
        dayNightFilterRef.current = dayNightFilter;
        layersRef.current = layers;
        bubbleLayerRef.current = layers.bubbleLayer;
        travelLayerRef.current = layers.worldDynamic;

        // 1. Background terrain map (PR #40) — fantasy strategy art generated to match REGIONS layout.
        // Loaded async; sprite is added to terrainBackground BEFORE buildScene so region circles render on top.
        try {
          const tex = await Assets.load(worldMapBg);
          if (!mounted || !isMountedRef.current) return;
          const bg = new Sprite(tex);
          // Render at native world resolution; viewport handles screen-fit zoom.
          bg.width = MAP_WIDTH;
          bg.height = MAP_HEIGHT;
          bg.x = 0;
          bg.y = 0;
          layers.terrainBackground.addChild(bg);
          drawnRef.current.bgSprite = bg;
        } catch (err) {
          // Non-fatal — fall through to flat background color set in app.init
          console.warn('[WorldMap] failed to load terrain background', err);
        }

        // 2. Build scene (regions, sigil sprites, bandit indicator) — PR #41 + PR #42 logic
        // Layers are added to `viewport` (not app.stage) so pinch/drag affect them.
        buildScene(() => !mounted || !isMountedRef.current);

        // 3. Speech bubble ticker (PR #43) — bubbleLayer sits above selection/effects.
        const bubbleLayer = layers.bubbleLayer;

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

        // 3b. Worker travel ticker (PR #44) — clansmen live in worldDynamic so
        // they Y-sort against bases and bandits.
        const travelLayer = layers.worldDynamic;

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
              if (selectedRef.current?.target === t.gfx) selectedRef.current = null;
              layer.removeChild(t.gfx);
              t.gfx.destroy({ children: true });
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
                if (selectedRef.current?.target === t.gfx) selectedRef.current = null;
                layer.removeChild(t.gfx);
                t.gfx.destroy({ children: true });
                list.splice(i, 1);
                continue;
              }
              // Tiny jitter at destination so the cluster reads as living units, not pinned dots
              const jit = Math.sin((now + (t.id.charCodeAt(t.id.length - 1) * 137)) / 220) * 1.5;
              t.gfx.x = tx + jit;
              t.gfx.y = ty + jit * 0.6;
              t.gfx.zIndex = Math.round(t.gfx.y);
              t.carry.targetFill = 0;
              if (fadeAge < TRAVEL_DEST_LINGER_MS) {
                t.gfx.alpha = 1;
              } else {
                const fOff = fadeAge - TRAVEL_DEST_LINGER_MS;
                t.gfx.alpha = Math.max(0, 1 - fOff / TRAVEL_FADE_OUT_MS);
              }
            } else {
              t.gfx.x = fx + (tx - fx) * progress;
              t.gfx.y = fy + (ty - fy) * progress;
              t.gfx.zIndex = Math.round(t.gfx.y);
              setCarryTargetFromCarry(t.carry, {
                wood: WOOD_CAP * Math.min(1, progress),
              });
              // Subtle fade-in over first 150ms so dots don't pop in
              t.gfx.alpha = Math.min(1, elapsed / 150);
            }
            const lerpFactor = t.carry.targetFill >= t.carry.displayedFill ? 0.15 : 0.28;
            t.carry.displayedFill += (t.carry.targetFill - t.carry.displayedFill) * lerpFactor;
            redrawCarryIndicator(t.carry);
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
          const now = performance.now();
          drawn.bases.forEach((base) => {
            if (base.baseY <= 0) return;
            // 0.25 Hz (4-second period). 2π/4000 = π/2000 keeps units honest:
            // sin((t + offset) * π / period_ms_half) cycles once per period.
            base.container.y = base.baseY + Math.round(Math.sin((now + base.phaseOffset) * Math.PI / 2000) * 1);
            base.container.zIndex = Math.round(base.baseY);
          });
        };
        app.ticker.add(zonePulseCb);
        // Stash cleanup ref via the same pattern as travel ticker (re-use travelTickerCbRef).
        // Track separately:
        zonePulseCbRef.current = zonePulseCb;

        const dayNightCb = () => {
          const filter = dayNightFilterRef.current;
          if (!filter) return;
          const frame = getDayNightFrame(getDayNightProgress());
          applyDayNightFilter(filter, frame);
          const glowAlpha = clamp01(1 - frame.brightness);
          drawnRef.current.bases.forEach((base) => {
            base.glow.alpha = glowAlpha;
          });

          const selected = selectedRef.current;
          if (selected) {
            const ring = selected.ring;
            const now = performance.now();
            ring.rotation += (app.ticker.deltaMS / 1000) * Math.PI * 2;
            ring.alpha = 0.6 + Math.sin((now / 1000) * Math.PI) * 0.4;
          }
        };
        dayNightTickerCbRef.current = dayNightCb;
        app.ticker.add(dayNightCb);

        const combatCb = () => {
          updateCombatVignette();
        };
        combatTickerCbRef.current = combatCb;
        app.ticker.add(combatCb);

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
      if (a && dayNightTickerCbRef.current) a.ticker.remove(dayNightTickerCbRef.current);
      if (a && combatTickerCbRef.current) a.ticker.remove(combatTickerCbRef.current);
      finishCombatVignette(true);
      selectedRef.current?.ring.destroy();
      selectedRef.current = null;
      bubblesByClanRef.current.clear();
      seenLogIdsRef.current.clear();
      flagAnchorsRef.current.clear();
      travelsRef.current = [];
      seenTravelLogIdsRef.current.clear();
      bubbleLayerRef.current = null;
      travelLayerRef.current = null;
      layersRef.current = null;
      tickerCbRef.current = null;
      travelTickerCbRef.current = null;
      zonePulseCbRef.current = null;
      dayNightTickerCbRef.current = null;
      combatTickerCbRef.current = null;
      dayNightFilterRef.current = null;
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

  useEffect(() => {
    if (!pixiReady) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        clearSelection();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pixiReady]);

  // ---- One-time: create Pixi display objects (refs hold them for relayout) -
  // All layers attach to `viewport` (not app.stage) so pixi-viewport's pinch /
  // drag transforms apply to the whole map atomically.
  function buildScene(isAssetLoadCancelled: () => boolean) {
    const drawn = drawnRef.current;
    const layers = layersRef.current;
    if (!layers) return;

    // Clan zones, sigil flags, bases, walls, monuments, bandits — all mock data.
    // Skip entirely when DEMO_MODE is off; the canvas renders as an empty terrain map.
    if (DEMO_MODE) {
      // Clan zones (big translucent breathing halos) — drawn FIRST so everything else
      // sits on top. Visual sense of "this clan controls this zone."
      for (const clan of MOCK_CLANS) {
        const zoneGfx = new Graphics();
        layers.terrainAccents.addChild(zoneGfx);
        drawn.clanZones.push({ gfx: zoneGfx, clan });
      }
    }

    for (const region of REGIONS) {
      const g = new Graphics();
      layers.terrainBackground.addChild(g);
      drawn.regions.push(g);

      const label = new Text({
        text: region.name,
        style: { fill: 0xdddddd, fontSize: 11, fontFamily: 'monospace' },
      });
      label.anchor.set(0.5, 0);
      layers.terrainBackground.addChild(label);
      drawn.regionLabels.push(label);
    }

    if (DEMO_MODE) {
      // Wall rings — drawn first so they sit above region circles but under sigils.
      for (const clan of MOCK_CLANS) {
        const wallGfx = new Graphics();
        layers.worldDynamic.addChild(wallGfx);
        drawn.walls.push({ gfx: wallGfx, clan });
      }

      // Monument towers — drawn before flags so sigil layers cleanly on top.
      for (const clan of MOCK_CLANS) {
        const monGfx = new Graphics();
        layers.worldDynamic.addChild(monGfx);
        drawn.monuments.push({ gfx: monGfx, clan });
      }

      for (const clan of MOCK_CLANS) {
        const flag = new Graphics();
        layers.worldDynamic.addChild(flag);
        const label = new Text({
          text: clan.name,
          style: { fill: clan.color, fontSize: 10, fontFamily: 'monospace', fontWeight: 'bold' },
        });
        label.anchor.set(0, 1);
        layers.worldDynamic.addChild(label);
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
            const cancelled = isAssetLoadCancelled();
            if (cancelled || !appRef.current) return;
            const sprite = new Sprite(texture);
            sprite.alpha = 0; // hidden until first relayout positions it
            layers.worldDynamic.addChild(sprite);
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
      banditIcon.eventMode = 'static';
      banditIcon.cursor = 'pointer';
      banditIcon.on('pointertap', (event) => {
        event.stopPropagation();
        selectTarget(banditIcon as SelectableTarget, 0xffe9b8);
      });
      layers.worldDynamic.addChild(banditIcon);
      const countdown = new Text({
        text: '',
        style: { fill: 0xffe9b8, fontSize: 11, fontFamily: 'monospace', fontWeight: 'bold' },
      });
      countdown.anchor.set(0, 0.5);
      layers.inWorldEffects.addChild(countdown);
      drawn.banditIcon = banditIcon;
      drawn.banditCountdown = countdown;

      // Async-load the bandit sprite — once ready, redrawBandit positions it and
      // hides the fallback ring. Catch silently so the ring stays visible on failure.
      Assets.load('/sprites/bandit.png')
        .then((texture) => {
          const cancelled = isAssetLoadCancelled();
          if (cancelled || !appRef.current) return;
          // The .then() fires once per page load. Earlier round-2 fix
          // early-returned during vignette to avoid redrawBandit() snapping
          // the reparented banditIcon back to home — but skipping creation
          // entirely meant the sprite was permanently lost if the asset
          // resolved mid-vignette (gemini r3 HIGH #1). Now: always create
          // the sprite + assign to drawn; only skip the redraw if a
          // vignette is active. finishCombatVignette() calls redrawBandit
          // afterward which positions the new sprite.
          const sprite = new Sprite(texture);
          sprite.anchor.set(0.5, 0.5);
          sprite.alpha = 0; // hidden until first redrawBandit positions it
          sprite.eventMode = 'static';
          sprite.cursor = 'pointer';
          sprite.on('pointertap', (event) => {
            event.stopPropagation();
            selectTarget(sprite as SelectableTarget, 0xffe9b8);
          });
          layers.worldDynamic.addChild(sprite);
          drawn.banditSprite = sprite;
          if (combatVignetteRef.current) return;
          redrawBandit();
        })
        .catch(() => {
          // Keep fallback ring visible.
        });

      // Per-clan BASE SPRITES — pixel-art structures at home regions (towers / keeps / longhouses).
      // Visible on top of region circles + sigil flags. Falls back to a simple colored rect.
      for (const clan of MOCK_CLANS) {
        const container = new Container();
        layers.worldDynamic.addChild(container);
        const fallback = new Graphics();
        const glow = new Graphics();
        container.addChild(fallback);
        container.addChild(glow);
        container.eventMode = 'static';
        container.cursor = 'pointer';
        container.on('pointertap', (event) => {
          event.stopPropagation();
          selectTarget(container as SelectableTarget, clan.color);
        });
        const entry: {
          container: Container;
          sprite: Sprite | null;
          fallback: Graphics;
          glow: Graphics;
          clan: ClanDef;
          baseY: number;
          phaseOffset: number;
        } = {
          container,
          sprite: null,
          fallback,
          glow,
          clan,
          baseY: 0,
          phaseOffset: 0,
        };
        drawn.bases.push(entry);

        Assets.load(clan.basePng)
          .then((texture) => {
            const cancelled = isAssetLoadCancelled();
            if (cancelled || !appRef.current) return;
            const sprite = new Sprite(texture);
            sprite.anchor.set(0.5, 1); // anchored at bottom-center so it "stands" on the region
            sprite.alpha = 0;
            container.addChildAt(sprite, Math.min(1, container.children.length));
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
            const cancelled = isAssetLoadCancelled();
            if (cancelled) return;
            clansmanTextureCache[clan.id] = texture;
          })
          .catch(() => {
            // Travel dot fallback handles missing texture.
          });
      }

      // Floating "Lv N" badges — drawn last so they overlay everything.
      for (const clan of MOCK_CLANS) {
        const bg = new Graphics();
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
        const base = drawn.bases.find((b) => b.clan.id === clan.id);
        if (base) base.container.addChild(bg, label);
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

    const layers = layersRef.current;
    if (layers) {
      layers.combatDim.clear();
      layers.combatDim.rect(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
      layers.combatDim.fill({ color: COMBAT_DIM_TINT, alpha: 1 });
      layers.combatFlash.clear();
      layers.combatFlash.rect(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
      layers.combatFlash.fill({ color: 0xffffff, alpha: 1 });
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
        const baseSize = Math.max(67, 101 * cappedSizeScale);
        // Hide everything visually
        gfx.clear();
        if (sprite) sprite.alpha = 0;
        label.alpha = 0;
        // Bubble anchor: top of base sprite
        flagAnchorsRef.current.set(clan.id, { x: cx, y: cy - baseSize * 1.05 });
      });

      // BASE SPRITES — render at clan home positions, replacing monument obelisks.
      drawn.bases.forEach((entry) => {
        const { container, sprite, fallback, glow, clan } = entry;
        const base = regionMap.get(clan.homeRegion);
        if (!base) return;
        const cx = projX(base.nx);
        const cy = projY(base.ny);
        // Base size: ~128px at 1x scale, scales with viewport (2x bump for phone readability)
        const baseSize = Math.max(67, 101 * cappedSizeScale);
        entry.baseY = cy + baseSize * 0.15;
        entry.phaseOffset = ((Math.round(cx) * 73) ^ (Math.round(entry.baseY) * 31)) % 4000;
        container.x = cx;
        container.y = entry.baseY;
        container.zIndex = Math.round(entry.baseY);
        fallback.clear();
        if (!sprite) {
          // Simple colored fallback rect with clan-color border
          fallback.rect(-baseSize / 2, -baseSize, baseSize, baseSize);
          fallback.fill({ color: 0x444444, alpha: 0.7 });
          fallback.stroke({ color: clan.color, width: 3 });
        }
        if (sprite) {
          sprite.width = baseSize;
          sprite.height = baseSize;
          sprite.x = 0;
          sprite.y = 0; // anchor=bottom-center; parent sits slightly below region center
          sprite.alpha = 1;
        }
        glow.clear();
        glow.circle(0, -baseSize * 0.8, Math.max(6, 8 * cappedSizeScale));
        glow.fill({ color: 0xffd27d, alpha: 0.6 });
      });

      // FLOATING "Lv N" BADGES — beside each base sprite. Updates with monument level.
      drawn.levelBadges.forEach(({ bg, label, clan }) => {
        const base = regionMap.get(clan.homeRegion);
        if (!base) return;
        const baseSize = Math.max(67, 101 * cappedSizeScale);
        const lvl = levelByClan.get(clan.id) ?? 0;
        label.text = `Lv ${lvl}`;
        label.style.fontSize = Math.max(11, Math.round(13 * cappedSizeScale));
        // Position to the right of the base sprite, near the top
        const bx = baseSize * 0.55;
        const by = -baseSize * 0.7;
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

      // Bandit redraw uses live tick — recompute alongside layout.
      // Skip during active vignette so a snapshot.clans-driven relayout
      // doesn't snap the reparented bandit back to home anchor mid-
      // choreography (opus 4.7 r4 LOW). The vignette ticker self-corrects
      // on the next frame anyway, but a one-frame snap is visible.
      if (!combatVignetteRef.current) redrawBandit();
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
    // After a `?combat=success` vignette completes, the bandit is defeated.
    // Skip all redraw / re-show on subsequent layouts (gemini r3 HIGH #2).
    if (banditDefeatedRef.current) {
      icon.visible = false;
      icon.alpha = 0;
      if (sprite) {
        sprite.visible = false;
        sprite.alpha = 0;
      }
      text.visible = false;
      return;
    }

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
    const banditZ = Math.round(iconY);

    icon.clear();
    icon.x = iconX;
    icon.y = iconY;
    icon.zIndex = banditZ;
    if (!sprite) {
      // Fallback ring while the sprite loads / on asset failure.
      // Draw shapes at icon-local origin so target.getGlobalPosition() in
      // selectTarget() resolves to the visible center, not the parent layer's origin.
      icon.circle(0, 0, ringR);
      icon.fill({ color: 0xcc1122, alpha: 0.85 });
      icon.stroke({ color: 0xffffff, width: 2 });
      const barW = Math.max(2, 3 * scale);
      const barH = ringR * 0.95;
      icon.rect(-barW / 2, -barH / 2, barW, barH * 0.6);
      icon.fill({ color: 0xffffff });
      icon.circle(0, barH * 0.35, Math.max(1.5, barW * 0.7));
      icon.fill({ color: 0xffffff });
    }

    if (sprite) {
      sprite.width = spriteSize;
      sprite.height = spriteSize;
      sprite.x = iconX;
      sprite.y = iconY;
      sprite.zIndex = banditZ;
      sprite.alpha = 1;
    }

    const ticksUntil = Math.max(0, DEMO_BANDIT.attacksAtTick - liveTick);
    text.text = `${ticksUntil}t`;
    text.style.fontSize = Math.max(10, Math.round(12 * scale));
    // Anchor the countdown to the right edge of whichever marker is active.
    const markerHalfW = sprite ? spriteSize / 2 : ringR;
    text.x = iconX + markerHalfW + 4;
    text.y = iconY;
  }

  function getMsUntilTickClose() {
    const snap = snapshotRef.current;
    const epoch = snap?.tickEpoch;
    const durationMs =
      epoch && typeof epoch.durationMs === 'number' && epoch.durationMs > 0
        ? epoch.durationMs
        : FALLBACK_DAY_TICK_MS;
    if (epoch && typeof epoch.startedAt === 'number' && epoch.startedAt > 0 && snap?.tick === liveTickRef.current) {
      const startedAtMs = epoch.startedAt < 10_000_000_000 ? epoch.startedAt * 1000 : epoch.startedAt;
      return Math.max(0, durationMs - (Date.now() - startedAtMs));
    }
    const elapsed = Date.now() - liveTickClockRef.current.seenAtMs;
    return Math.max(0, durationMs - elapsed);
  }

  function shouldStartCombatVignette() {
    if (!DEMO_MODE || combatVignetteRef.current) return false;
    const attackTick = DEMO_BANDIT.attacksAtTick;
    if (combatPlayedTickRef.current === attackTick) return false;
    const currentTick = liveTickRef.current;
    if (currentTick === attackTick - 1) {
      // Codex cloud P1: when tickEpoch is unavailable (Sub1 logs-driven liveTick
      // mode where ticks advance every ~20s but FALLBACK_DAY_TICK_MS is 60s),
      // `getMsUntilTickClose()` never drops to ≤4000ms before liveTick rolls
      // forward — the precise pre-close window never fires and the vignette
      // only triggers post-close (line below). Detect fallback mode and
      // trigger as soon as we enter the pre-attack tick. Vignette occupies the
      // first 4s of the pre-attack tick instead of the last 4s; visually similar.
      const snap = snapshotRef.current;
      const epoch = snap?.tickEpoch;
      const havePreciseEpoch =
        epoch && typeof epoch.startedAt === 'number' && epoch.startedAt > 0
        && typeof epoch.durationMs === 'number' && epoch.durationMs > 0;
      if (havePreciseEpoch) {
        return getMsUntilTickClose() <= COMBAT_VIGNETTE_LEAD_MS;
      }
      return true;
    }
    return currentTick >= attackTick;
  }

  function makeCombatDefender(color: number, clanId: string) {
    const tex = clansmanTextureCache[clanId];
    if (tex) {
      const sprite = new Sprite(tex);
      sprite.anchor.set(0.5, 0.5);
      const targetH = 32;
      const ratio = targetH / sprite.texture.height;
      sprite.height = targetH;
      sprite.width = sprite.texture.width * ratio;
      return sprite;
    }

    const fallback = new Graphics();
    fallback.circle(0, 0, 8);
    fallback.fill({ color, alpha: 1 });
    fallback.stroke({ color: 0xffffff, width: 1, alpha: 0.75 });
    return fallback;
  }

  function reparentForCombat(node: Container, vignette: CombatVignette, wasTemporary = false) {
    const layers = layersRef.current;
    const parent = node.parent;
    if (!layers || !(parent instanceof Container)) return;
    vignette.reparented.push({ node, parent, zIndex: node.zIndex, wasTemporary });
    parent.removeChild(node);
    layers.combatHighlight.addChild(node);
    node.zIndex = Math.round(node.y);
  }

  function startCombatVignette() {
    const layers = layersRef.current;
    if (!layers) return;
    const drawn = drawnRef.current;
    const targetClan =
      MOCK_CLANS.find(c => c.id === COMBAT_TARGET_CLAN_ID)
      ?? MOCK_CLANS.find(c => c.homeRegion === DEMO_BANDIT.regionId);
    if (!targetClan) return;
    const targetBase = drawn.bases.find(b => b.clan.id === targetClan.id);
    if (!targetBase) return;

    const targetBaseNode = targetBase.container;
    const baseSize = Math.max(67, 101 * layoutRef.current.scale);
    const center = {
      x: targetBaseNode.x,
      y: targetBaseNode.y - baseSize * 0.55,
    };
    const bandit = drawn.banditSprite ?? drawn.banditIcon;
    if (!bandit) return;

    // Mark this tick as played BEFORE any reparenting / mutation so a partial-start
    // throw can't loop the per-frame ticker into spawning new defender nodes every
    // frame (codex r3 SHOULD #1).
    combatPlayedTickRef.current = DEMO_BANDIT.attacksAtTick;

    // §14.3: combatDim sits above worldDynamic and would otherwise dim the
    // active selection ring. Clear the ring (without the camera fit-out) so
    // the dimmed world reads cleanly. Speech bubbles still dim mid-flight
    // (structural fix queued for v1.2) — claude r3 MUST #3 cheap fix.
    const selected = selectedRef.current;
    if (selected) {
      selected.target.removeChild(selected.ring);
      selected.ring.destroy();
      selectedRef.current = null;
    }

    const defenderAngles = [Math.PI * 0.75, Math.PI * 0.5, Math.PI * 0.25];
    const defenders = defenderAngles.map((angle) => {
      const defender = makeCombatDefender(targetClan.color, targetClan.id);
      defender.x = center.x + Math.cos(angle) * 58;
      defender.y = center.y + Math.sin(angle) * 34;
      defender.zIndex = Math.round(defender.y);
      layers.worldDynamic.addChild(defender);
      return defender;
    });

    const vignette: CombatVignette = {
      startedAt: performance.now(),
      outcome: readDemoCombatOutcome(),
      bandit,
      targetBase: targetBaseNode,
      defenders,
      reparented: [],
      baseStart: {
        x: targetBaseNode.x,
        y: targetBaseNode.y,
        scaleX: targetBaseNode.scale.x,
        scaleY: targetBaseNode.scale.y,
      },
      banditStart: {
        x: bandit.x,
        y: bandit.y,
        scaleX: bandit.scale.x,
        scaleY: bandit.scale.y,
        alpha: bandit.alpha,
      },
      defenderStarts: defenders.map(d => ({ x: d.x, y: d.y })),
      center,
    };

    reparentForCombat(targetBaseNode, vignette);
    reparentForCombat(bandit, vignette);
    defenders.forEach(defender => reparentForCombat(defender, vignette, true));
    combatVignetteRef.current = vignette;
  }

  function finishCombatVignette(force = false) {
    const vignette = combatVignetteRef.current;
    const layers = layersRef.current;
    if (!vignette || !layers) return;

    layers.combatDim.alpha = 0;
    layers.combatFlash.alpha = 0;
    vignette.targetBase.x = vignette.baseStart.x;
    vignette.targetBase.y = vignette.baseStart.y;
    vignette.targetBase.scale.set(vignette.baseStart.scaleX, vignette.baseStart.scaleY);
    // On success outcome the vignette fades the bandit to alpha=0 + 0.3 scale;
    // unconditionally restoring banditStart would pop the defeated bandit
    // back to full opacity (gemini r3 HIGH #2). Lock the defeated state via
    // banditDefeatedRef + skip the visual restore on success.
    if (vignette.outcome === 'success' && !force) {
      banditDefeatedRef.current = true;
      if (vignette.bandit) {
        vignette.bandit.alpha = 0;
        vignette.bandit.visible = false;
      }
    } else if (vignette.bandit) {
      vignette.bandit.x = vignette.banditStart.x;
      vignette.bandit.y = vignette.banditStart.y;
      vignette.bandit.scale.set(vignette.banditStart.scaleX, vignette.banditStart.scaleY);
      vignette.bandit.alpha = vignette.banditStart.alpha;
    }

    for (const item of vignette.reparented) {
      if (item.node.parent) item.node.parent.removeChild(item.node);
      if (item.wasTemporary) {
        item.node.destroy({ children: true });
        continue;
      }
      item.parent.addChild(item.node);
      item.node.zIndex = item.zIndex;
    }
    layers.combatHighlight.removeChildren();
    combatVignetteRef.current = null;
    if (!force) redrawBandit();
  }

  function updateCombatVignette() {
    if (shouldStartCombatVignette()) startCombatVignette();
    const vignette = combatVignetteRef.current;
    const layers = layersRef.current;
    if (!vignette || !layers) return;

    const now = performance.now();
    const age = now - vignette.startedAt;
    if (age >= COMBAT_TOTAL_MS) {
      finishCombatVignette();
      return;
    }

    // §10.8 cap rule: combat dim must not stack with day/night darkening into
    // an unreadable scene. The naive `min(0.55, 1 - brightness)` reads the
    // spec literally but inverts the intent — at full daylight (brightness=1)
    // it gives 0, killing combat dim during the brightest part of the cycle
    // (codex 5.4 SuperSwarm catch). Correct semantic: dim down by the AMOUNT
    // of existing day/night darkening so total visual darkness stays bounded.
    // Floor at 0.2 so combat still has a visible beat even at deep night.
    const dayNightBrightness = getDayNightFrame(getDayNightProgress()).brightness;
    const existingDarkness = clamp01(1 - dayNightBrightness);
    const dimTarget = Math.max(0.2, COMBAT_DIM_ALPHA - existingDarkness);
    const fadeOutStart = COMBAT_TOTAL_MS - 600;
    if (age < 600) {
      layers.combatDim.alpha = dimTarget * clamp01(age / 600);
    } else if (age >= fadeOutStart) {
      layers.combatDim.alpha = dimTarget * (1 - clamp01((age - fadeOutStart) / 600));
    } else {
      layers.combatDim.alpha = dimTarget;
    }

    const flashAge = age - COMBAT_FLASH_START_MS;
    if (flashAge < 0) {
      layers.combatFlash.alpha = 0;
    } else if (flashAge < COMBAT_FLASH_IN_MS) {
      layers.combatFlash.alpha = clamp01(flashAge / COMBAT_FLASH_IN_MS);
    } else if (flashAge < COMBAT_FLASH_IN_MS + COMBAT_FLASH_HOLD_MS) {
      layers.combatFlash.alpha = 1;
    } else {
      const fadeAge = flashAge - COMBAT_FLASH_IN_MS - COMBAT_FLASH_HOLD_MS;
      layers.combatFlash.alpha = Math.max(0, 1 - fadeAge / COMBAT_FLASH_FADE_MS);
    }

    if (age < COMBAT_ADVANCE_MS) {
      const t = easeInQuad(clamp01(age / COMBAT_ADVANCE_MS));
      if (vignette.bandit) {
        vignette.bandit.x = lerp(vignette.banditStart.x, vignette.center.x - 24, t);
        vignette.bandit.y = lerp(vignette.banditStart.y, vignette.center.y - 8, t);
      }
      vignette.defenders.forEach((defender, i) => {
        const start = vignette.defenderStarts[i];
        if (!start) return;
        defender.x = lerp(start.x, vignette.center.x + 18 + i * 8, t);
        defender.y = lerp(start.y, vignette.center.y + 10, t);
      });
    } else if (age < COMBAT_FLASH_START_MS) {
      const jitter = Math.sin(now / 55) * 1;
      if (vignette.bandit) {
        vignette.bandit.x = vignette.center.x - 24 + jitter;
        vignette.bandit.y = vignette.center.y - 8;
      }
      vignette.defenders.forEach((defender, i) => {
        defender.x = vignette.center.x + 18 + i * 8 - jitter;
        defender.y = vignette.center.y + 10 + Math.sin(now / 70 + i) * 1;
      });
    } else if (age >= COMBAT_RESOLUTION_START_MS) {
      const rAge = age - COMBAT_RESOLUTION_START_MS;
      if (vignette.outcome === 'success') {
        const launchT = easeOutQuad(clamp01(rAge / 600));
        if (vignette.bandit) {
          vignette.bandit.x = vignette.center.x - 24 - launchT * 60;
          vignette.bandit.y = vignette.center.y - 8 - launchT * 16;
          const fadeT = clamp01((rAge - 250) / 600);
          const s = lerp(1, 0.3, fadeT);
          vignette.bandit.scale.set(vignette.banditStart.scaleX * s, vignette.banditStart.scaleY * s);
          vignette.bandit.alpha = 1 - fadeT;
        }
        vignette.defenders.forEach((defender, i) => {
          defender.y = vignette.center.y + 10 + Math.sin(now / 90 + i) * 5;
        });
      } else {
        const jumpT = easeOutQuad(clamp01(rAge / 300));
        vignette.defenders.forEach((defender, i) => {
          const angle = Math.PI * (0.2 + i * 0.22);
          defender.x = vignette.center.x + 16 + i * 8 + Math.cos(angle) * 28 * jumpT;
          defender.y = vignette.center.y + 10 + Math.sin(angle) * 20 * jumpT;
        });
        const dropT = easeInQuad(clamp01(rAge / 400));
        vignette.targetBase.scale.y = lerp(vignette.baseStart.scaleY, vignette.baseStart.scaleY * 0.9, dropT);
      }
    }

    if (vignette.bandit) vignette.bandit.zIndex = Math.round(vignette.bandit.y);
    vignette.defenders.forEach(defender => {
      defender.zIndex = Math.round(defender.y);
    });
    vignette.targetBase.zIndex = Math.round(vignette.targetBase.y);
  }

  // Tick changes: refresh bandit countdown (demo mode only).
  // Skipped while a combat vignette is animating — redrawBandit overrides the
  // bandit sprite's x/y/zIndex back to the region anchor, snapping the bandit
  // out of mid-flight choreography (claude r3 MUST #1).
  useEffect(() => {
    if (!pixiReady || !DEMO_MODE) return;
    if (combatVignetteRef.current) return;
    redrawBandit();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [liveTick, pixiReady]);

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

    const resetBanditAlpha = () => {
      // Defeated bandit stays alpha=0 — don't reset to 1 (opus 4.6/4.7 r4
      // defensive). Currently masked by visible=false but enforces the
      // "stay hidden post-defeat" invariant against future writers that
      // might flip visible back to true.
      if (banditDefeatedRef.current) return;
      const icon = drawnRef.current.banditIcon;
      const sprite = drawnRef.current.banditSprite;
      if (icon) icon.alpha = 1;
      if (sprite) sprite.alpha = 1;
    };

    if (!shouldPulseBandit) {
      resetBanditAlpha();
      return;
    }

    const onTick = () => {
      // Yield bandit alpha ownership to the combat vignette while it's active.
      // Without this guard, the pulse keeps writing alpha every frame AFTER the
      // vignette ticker, silently nullifying the success-outcome fade-out
      // (opus 4.7 SuperSwarm catch). The vignette window overlaps the pulse
      // window when banditTicksUntil ∈ [0, 2].
      if (combatVignetteRef.current) return;
      // Defeated bandit stays hidden — don't pulse it back into visibility.
      if (banditDefeatedRef.current) return;
      const icon = drawnRef.current.banditIcon;
      const sprite = drawnRef.current.banditSprite;
      const t = performance.now() / 220;
      const a = 0.55 + 0.45 * Math.abs(Math.sin(t));
      if (icon) icon.alpha = a;
      if (sprite) sprite.alpha = a;
    };
    app.ticker.add(onTick);
    return () => {
      app.ticker.remove(onTick);
      resetBanditAlpha();
    };
  }, [pixiReady, shouldPulseBandit]);

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
    gfx.eventMode = 'static';
    gfx.cursor = 'pointer';
    gfx.on('pointertap', (event) => {
      event.stopPropagation();
      selectTarget(gfx as SelectableTarget, color);
    });
    const carry = makeCarryIndicator();
    carry.container.y = tex ? -18 : -TRAVEL_DOT_RADIUS - 6;
    gfx.addChild(carry.container);
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
      carry,
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
  const scoreboardClans = useMemo(() => {
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
  }, [snapshot]);

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
