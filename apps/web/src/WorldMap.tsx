import { useEffect, useRef, useState } from 'react';
import { Application, Assets, Container, Graphics, Sprite, Text } from 'pixi.js';
import { useAgentLogs, type AgentLog } from './useAgentLogs';
import worldMapBg from './assets/world-map.png';

interface RegionDef {
  id: string;
  name: string;
  x: number;
  y: number;
  color: number;
}

interface ClanDef {
  id: string;
  name: string;
  homeRegion: string;
  color: number;
  sigil: string;
}

const REGIONS: RegionDef[] = [
  { id: 'forest',       name: 'Forest',      x: 150, y: 100, color: 0x228822 },
  { id: 'mountains',    name: 'Mountains',   x: 500, y: 100, color: 0x888888 },
  { id: 'unicorn-town', name: 'Unicorn Town',x: 330, y: 280, color: 0xcc88cc },
  { id: 'west-farms',   name: 'West Farms',  x: 130, y: 350, color: 0xaacc44 },
  { id: 'east-farms',   name: 'East Farms',  x: 550, y: 350, color: 0x88bb33 },
  { id: 'west-docks',   name: 'West Docks',  x: 100, y: 500, color: 0x336688 },
  { id: 'east-docks',   name: 'East Docks',  x: 560, y: 500, color: 0x336688 },
  { id: 'deep-sea',     name: 'Deep Sea',    x: 330, y: 520, color: 0x1144aa },
];

const MOCK_CLANS: ClanDef[] = [
  { id: 'clan-iron',  name: 'Iron Guard',   homeRegion: 'forest',     color: 0x4488cc, sigil: '/sigils/iron-guard-sigil.png' },
  { id: 'clan-ember', name: 'Ember Hand',   homeRegion: 'mountains',  color: 0xcc4422, sigil: '/sigils/ember-hand-sigil.png' },
  { id: 'clan-dawn',  name: 'Dawn Watch',   homeRegion: 'west-farms', color: 0xccaa22, sigil: '/sigils/dawn-watch-sigil.png' },
  { id: 'clan-storm', name: 'Storm Riders', homeRegion: 'east-farms', color: 0x44aacc, sigil: '/sigils/storm-riders-sigil.png' },
];

const SIGIL_SIZE = 36;

// Bubble visual + animation constants
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

export function WorldMap() {
  const containerRef = useRef<HTMLDivElement>(null);
  const appRef = useRef<Application | null>(null);
  const bubbleLayerRef = useRef<Container | null>(null);
  const bubblesByClanRef = useRef<Map<string, BubbleHandle[]>>(new Map());
  const seenLogIdsRef = useRef<Set<string>>(new Set());
  const flagAnchorsRef = useRef<Map<string, { x: number; y: number }>>(new Map());
  const tickerCbRef = useRef<((ticker: { deltaMS: number }) => void) | null>(null);
  const [pixiReady, setPixiReady] = useState(false);

  const logs = useAgentLogs();

  useEffect(() => {
    let mounted = true;
    const app = new Application();
    appRef.current = app;

    app.init({ width: 800, height: 600, background: 0x1a2a1a }).then(async () => {
      if (!mounted || !containerRef.current) return;
      containerRef.current.appendChild(app.canvas);

      // Background terrain map — fantasy strategy art generated to match REGIONS layout.
      // Loaded async; sprite is added before any region circles so it renders behind them.
      try {
        const tex = await Assets.load(worldMapBg);
        if (!mounted) return;
        const bg = new Sprite(tex);
        bg.width = 800;
        bg.height = 600;
        bg.x = 0;
        bg.y = 0;
        app.stage.addChild(bg);
      } catch (err) {
        // Non-fatal — fall through to flat background color set in app.init
        console.warn('[WorldMap] failed to load terrain background', err);
      }

      const regionMap = new Map(REGIONS.map(r => [r.id, r]));

      // Draw regions as circles
      for (const region of REGIONS) {
        const g = new Graphics();
        g.circle(region.x, region.y, 40);
        g.fill({ color: region.color });
        g.stroke({ color: 0xffffff, width: 1, alpha: 0.4 });
        app.stage.addChild(g);

        const label = new Text({
          text: region.name,
          style: { fill: 0xdddddd, fontSize: 11, fontFamily: 'monospace' },
        });
        label.anchor.set(0.5, 0);
        label.x = region.x;
        label.y = region.y + 44;
        app.stage.addChild(label);
      }

      // Draw clan sigils at homebase regions
      for (const clan of MOCK_CLANS) {
        const base = regionMap.get(clan.homeRegion);
        if (!base) continue;

        const sigilX = base.x + 18;
        const sigilY = base.y - 46;

        // Fallback rectangle drawn immediately while sprite loads async.
        const fallback = new Graphics();
        fallback.rect(sigilX, sigilY, SIGIL_SIZE, SIGIL_SIZE);
        fallback.fill({ color: clan.color, alpha: 0.85 });
        fallback.stroke({ color: 0xffffff, width: 1 });
        app.stage.addChild(fallback);

        // Async sprite load — replaces fallback once texture is ready.
        Assets.load(clan.sigil)
          .then((texture) => {
            if (!mounted) return;
            const sprite = new Sprite(texture);
            sprite.width = SIGIL_SIZE;
            sprite.height = SIGIL_SIZE;
            sprite.x = sigilX;
            sprite.y = sigilY;
            app.stage.addChild(sprite);
            // Remove fallback once sprite is up.
            fallback.destroy();
          })
          .catch(() => {
            // Keep fallback visible if sprite fails to load.
          });

        const clanLabel = new Text({
          text: clan.name,
          style: { fill: clan.color, fontSize: 10, fontFamily: 'monospace', fontWeight: 'bold' },
        });
        clanLabel.anchor.set(0, 1);
        clanLabel.x = sigilX + SIGIL_SIZE + 4;
        clanLabel.y = sigilY + SIGIL_SIZE;
        app.stage.addChild(clanLabel);

        // Bubble anchor: top-center of sigil — tail tip lands here, bubbles stack up.
        flagAnchorsRef.current.set(clan.id, { x: sigilX + SIGIL_SIZE / 2, y: sigilY });
      }

      // Bubble layer is added last so bubbles render above everything.
      const bubbleLayer = new Container();
      app.stage.addChild(bubbleLayer);
      bubbleLayerRef.current = bubbleLayer;

      // Per-frame fade + lifecycle ticker.
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

      setPixiReady(true);
    });

    return () => {
      mounted = false;
      const a = appRef.current;
      if (a && tickerCbRef.current) a.ticker.remove(tickerCbRef.current);
      bubblesByClanRef.current.clear();
      seenLogIdsRef.current.clear();
      flagAnchorsRef.current.clear();
      bubbleLayerRef.current = null;
      tickerCbRef.current = null;
      appRef.current = null;
      a?.destroy(true);
    };
  }, []);

  // Spawn bubbles for new logs; attribute each log to a clan via string match.
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

  return <div ref={containerRef} />;
}

/**
 * Build one speech bubble.
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
