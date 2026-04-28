import { tokens } from '../../../styles/cockpit-tokens';

export type TabId = 'terminal' | 'vault' | 'clansman' | '0g' | 'comms';

export interface TabDef {
  id: TabId;
  /** Single-glyph icon — kept tiny so the tab strip stays narrow. */
  icon: string;
  /** Tiny label rendered under the icon (Liam: "icons stacked on tiny text tabs"). */
  label: string;
}

export const TABS: ReadonlyArray<TabDef> = [
  { id: 'terminal', icon: '▣', label: 'TERM' },
  { id: 'vault',    icon: '◈', label: 'VAULT' },
  { id: 'clansman', icon: '☗', label: 'CLAN' },
  { id: '0g',       icon: '◉', label: '0G' },
  { id: 'comms',    icon: '✉', label: 'COMMS' },
];

interface Props {
  active: TabId;
  onSelect: (id: TabId) => void;
  /** Clan name / accent — colors the active-tab underline. */
  clanName: string;
  clanAccent: string;
  clanGlyph: string;
  /** data-testid prefix to scope test selectors to this mini-cockpit. */
  testIdPrefix: string;
}

/**
 * Compact tab bar — icon-stacked-on-text on the left, clan badge on the right.
 *
 * Phase A.5b: tick counter removed from per-tab bar; it now lives on the
 * single app-level CockpitHeader so we render it once per page instead of
 * four times.
 *
 * Layout chosen so the bar stays dense at small panel widths. Each tab is
 * fixed ~44px wide.
 */
export function CockpitTabBar({
  active,
  onSelect,
  clanName,
  clanAccent,
  clanGlyph,
  testIdPrefix,
}: Props) {
  return (
    <div
      data-testid={`${testIdPrefix}-tabbar`}
      style={{
        display: 'flex',
        alignItems: 'stretch',
        background: tokens.bg.ironDeep,
        borderBottom: `1px solid ${tokens.border.iron}`,
        height: '46px',
        flexShrink: 0,
      }}
    >
      {/* Left: icon-stacked tabs */}
      <div style={{ display: 'flex' }}>
        {TABS.map((t) => {
          const isActive = t.id === active;
          return (
            <button
              key={t.id}
              data-testid={`${testIdPrefix}-tab-${t.id}`}
              data-active={isActive}
              onClick={() => onSelect(t.id)}
              style={{
                width: '44px',
                background: isActive ? tokens.bg.ink : 'transparent',
                color: isActive ? tokens.text.accent : tokens.text.onIronDim,
                border: 'none',
                borderRight: `1px solid ${tokens.border.iron}`,
                cursor: 'pointer',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                padding: '2px 0',
                fontFamily: tokens.font.body,
                boxShadow: isActive ? tokens.shadow.tabActive : 'none',
                transition: 'background 120ms ease, color 120ms ease',
              }}
              aria-pressed={isActive}
              aria-label={t.label}
              type="button"
            >
              <span
                style={{
                  fontSize: '18px',
                  lineHeight: 1,
                  marginBottom: '2px',
                }}
                aria-hidden
              >
                {t.icon}
              </span>
              <span
                style={{
                  fontSize: '8px',
                  letterSpacing: '0.12em',
                  fontWeight: 600,
                }}
              >
                {t.label}
              </span>
            </button>
          );
        })}
      </div>

      {/* Right: clan badge */}
      <div
        style={{
          flex: 1,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: `0 ${tokens.space.sm}`,
          color: tokens.text.onIron,
          fontFamily: tokens.font.display,
          fontSize: '12px',
          letterSpacing: '0.16em',
          textTransform: 'uppercase',
          minWidth: 0,
        }}
        title={clanName}
      >
        <span style={{ color: clanAccent, marginRight: '6px', fontSize: '14px' }}>
          {clanGlyph}
        </span>
        <span
          style={{
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
          }}
        >
          {clanName}
        </span>
      </div>
    </div>
  );
}
