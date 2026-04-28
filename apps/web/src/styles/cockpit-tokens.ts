/**
 * Cockpit design tokens — parchment-on-cosmic-dark aesthetic to match the
 * existing WorldMap canvas. Token-only file (no React); imported by every
 * cockpit component to keep the visual language consistent.
 *
 * Palette philosophy:
 *   - Background = void (deep cosmic black) so the world-map canvas reads as
 *     a "window" into the realm.
 *   - Panels = parchment-on-iron — warm aged paper face on a cold iron frame.
 *   - Tabs = inkwell — desaturated brown with a single warm gold accent for
 *     the active state. Avoids the "generic dashboard primary blue" look.
 *   - Tick counter = vellum gold, monospace, evokes scribe tally marks.
 */

export const tokens = {
  // Foundation
  bg: {
    void: '#0a0a0a',          // page background (matches existing main)
    parchment: '#e8dec7',     // panel face — aged paper
    parchmentDim: '#cdbfa0',  // hover / inactive parchment
    iron: '#2a2620',          // panel border / chrome
    ironDeep: '#16140f',      // tab strip background
    ink: '#1a1612',           // tab strip darker accent
  },
  // Text
  text: {
    onParchment: '#2a1f10',   // primary on parchment (rich brown ink)
    onParchmentDim: '#5a4628',// secondary on parchment
    onIron: '#c9b88a',        // primary on iron chrome (warm gold)
    onIronDim: '#7a6b4a',     // secondary on iron
    accent: '#d4a544',        // active tab / tick counter glow
    danger: '#b03a2e',        // starvation / error
    muted: '#6b5e44',
  },
  // Borders
  border: {
    iron: '#3a3528',
    ironLight: '#4a4232',
    parchmentEdge: '#a89b78',
  },
  // Typography
  font: {
    display: '"Cinzel", "Times New Roman", serif',
    body: '"Inter", system-ui, sans-serif',
    mono: '"JetBrains Mono", "SF Mono", Consolas, monospace',
  },
  // Spacing scale (4px base)
  space: {
    xs: '4px',
    sm: '8px',
    md: '12px',
    lg: '16px',
    xl: '24px',
  },
  // Radii — small, parchment edges should feel hand-cut not pillowy
  radius: {
    sm: '2px',
    md: '4px',
  },
  // Shadows — subtle, warm
  shadow: {
    panel: '0 2px 8px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,220,160,0.08)',
    tab: 'inset 0 -2px 0 rgba(0,0,0,0.4)',
    tabActive: 'inset 0 -2px 0 #d4a544, 0 0 12px rgba(212,165,68,0.25)',
  },
} as const;

/** Hardcoded clan roster for Phase A — mirrors ~/agents/elders/elder-N/. */
export interface ElderDef {
  clanId: number;        // 1-4, matches elder-N folder
  name: string;
  archetype: string;
  /** Single-character glyph used in lieu of a sprite for the panel header. */
  glyph: string;
  /** Accent hue for this clan's panel chrome (subtle — keeps parchment dominant). */
  accent: string;
}

export const ELDERS: ReadonlyArray<ElderDef> = [
  { clanId: 1, name: 'Storm Riders',     archetype: 'Aggressive Raider',     glyph: '⚡', accent: '#5a8aa8' },
  { clanId: 2, name: 'Iron Guard',       archetype: 'Cautious Accumulator',  glyph: '⛨', accent: '#7a8a6a' },
  { clanId: 3, name: 'Crimson',          archetype: 'Volatile Opportunist',  glyph: '✦', accent: '#a85a5a' },
  { clanId: 4, name: 'Verdant Wardens',  archetype: 'Patient Builder',       glyph: '❦', accent: '#6aa888' },
] as const;
