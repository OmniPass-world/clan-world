import { useEffect, useRef, useState } from 'react';
import { Application, Assets, Graphics, Sprite, Text } from 'pixi.js';
import { useAgentLogs } from './useAgentLogs';
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
  { id: 'clan-iron',  name: 'Iron Guard',   homeRegion: 'forest',     color: 0x4488cc },
  { id: 'clan-ember', name: 'Ember Hand',   homeRegion: 'mountains',  color: 0xcc4422 },
  { id: 'clan-dawn',  name: 'Dawn Watch',   homeRegion: 'west-farms', color: 0xccaa22 },
  { id: 'clan-storm', name: 'Storm Riders', homeRegion: 'east-farms', color: 0x44aacc },
];

export function WorldMap() {
  const containerRef = useRef<HTMLDivElement>(null);
  const bubbleTextRef = useRef<Text | null>(null);
  const bubbleRef = useRef<Graphics | null>(null);
  const fadeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [pixiReady, setPixiReady] = useState(false);

  const logs = useAgentLogs();

  useEffect(() => {
    let mounted = true;
    const app = new Application();

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

      // Draw clan flags at homebase regions
      for (const clan of MOCK_CLANS) {
        const base = regionMap.get(clan.homeRegion);
        if (!base) continue;

        const flagX = base.x + 18;
        const flagY = base.y - 38;

        const flag = new Graphics();
        flag.rect(flagX, flagY, 20, 20);
        flag.fill({ color: clan.color });
        flag.stroke({ color: 0xffffff, width: 1 });
        app.stage.addChild(flag);

        const clanLabel = new Text({
          text: clan.name,
          style: { fill: clan.color, fontSize: 10, fontFamily: 'monospace', fontWeight: 'bold' },
        });
        clanLabel.anchor.set(0, 1);
        clanLabel.x = flagX + 24;
        clanLabel.y = flagY + 20;
        app.stage.addChild(clanLabel);
      }

      // Speech bubble (top-right) — hidden until a log arrives
      const bubbleX = 610;
      const bubbleY = 30;
      const bubbleW = 160;
      const bubbleH = 50;

      const bubble = new Graphics();
      bubble.roundRect(bubbleX, bubbleY, bubbleW, bubbleH, 10);
      bubble.fill({ color: 0xffffff });
      bubble.stroke({ color: 0xaaaaaa, width: 1 });
      // Tail triangle
      bubble.moveTo(bubbleX + 20, bubbleY + bubbleH);
      bubble.lineTo(bubbleX + 10, bubbleY + bubbleH + 14);
      bubble.lineTo(bubbleX + 35, bubbleY + bubbleH);
      bubble.fill({ color: 0xffffff });
      bubble.alpha = 0;
      app.stage.addChild(bubble);

      const bubbleText = new Text({
        text: '',
        style: { fill: 0x333333, fontSize: 12, fontFamily: 'monospace', wordWrap: true, wordWrapWidth: bubbleW - 12 },
      });
      bubbleText.anchor.set(0.5, 0.5);
      bubbleText.x = bubbleX + bubbleW / 2;
      bubbleText.y = bubbleY + bubbleH / 2;
      bubbleText.alpha = 0;
      app.stage.addChild(bubbleText);

      // Store refs so the log-watcher effect can update them
      bubbleRef.current = bubble;
      bubbleTextRef.current = bubbleText;
      setPixiReady(true);
    });

    return () => {
      mounted = false;
      if (fadeTimerRef.current) clearTimeout(fadeTimerRef.current);
      bubbleRef.current = null;
      bubbleTextRef.current = null;
      app.destroy(true);
    };
  }, []);

  // Reactive: update bubble whenever a new log entry arrives or Pixi finishes init
  useEffect(() => {
    if (!pixiReady || !bubbleTextRef.current || !bubbleRef.current || logs.length === 0) return;
    const latest = logs[0]; // desc order — first = newest
    if (!latest) return;
    const msg = latest.message.slice(0, 240);
    bubbleTextRef.current.text = msg;
    bubbleRef.current.alpha = 1;
    bubbleTextRef.current.alpha = 1;

    if (fadeTimerRef.current) clearTimeout(fadeTimerRef.current);
    fadeTimerRef.current = setTimeout(() => {
      if (bubbleRef.current) bubbleRef.current.alpha = 0;
      if (bubbleTextRef.current) bubbleTextRef.current.alpha = 0;
    }, 5000);
  }, [logs, pixiReady]);

  return <div ref={containerRef} />;
}
