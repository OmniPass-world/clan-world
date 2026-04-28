import { tokens } from '../../../styles/cockpit-tokens';
import type { ElderDef } from '../../../styles/cockpit-tokens';

interface Props {
  elder: ElderDef;
  testIdPrefix: string;
}

/** Resource line in the stub vault — Phase B will source these from Convex. */
const STUB_RESOURCES = [
  { glyph: '◈', label: 'Gold',  value: 1240, delta: '+45'  },
  { glyph: '⌬', label: 'Wood',  value: 320,  delta: '-12'  },
  { glyph: '◆', label: 'Ore',   value: 88,   delta: '+0'   },
  { glyph: '◇', label: 'Stone', value: 156,  delta: '+8'   },
];

/** Asset movement event for the log strip. */
const STUB_MOVEMENTS = [
  { tick: 4, type: 'gain',  amount: '+45 gold',  source: 'raid · forest' },
  { tick: 3, type: 'spend', amount: '-12 wood',  source: 'mill upkeep'   },
  { tick: 2, type: 'gain',  amount: '+8 stone',  source: 'quarry'        },
  { tick: 1, type: 'gain',  amount: '+24 gold',  source: 'tribute'       },
];

export function VaultTab({ elder, testIdPrefix }: Props) {
  return (
    <div
      data-testid={`${testIdPrefix}-content-vault`}
      style={{
        flex: 1,
        background: tokens.bg.parchment,
        color: tokens.text.onParchment,
        padding: tokens.space.md,
        overflowY: 'auto',
        display: 'flex',
        flexDirection: 'column',
        gap: tokens.space.md,
        fontFamily: tokens.font.body,
      }}
    >
      {/* Resource grid */}
      <section>
        <SectionHeader>Vault — Clan {elder.clanId}</SectionHeader>
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: '1fr 1fr',
            gap: tokens.space.sm,
            marginTop: tokens.space.sm,
          }}
        >
          {STUB_RESOURCES.map((r) => (
            <div
              key={r.label}
              style={{
                background: 'rgba(255,255,255,0.35)',
                border: `1px solid ${tokens.border.parchmentEdge}`,
                borderRadius: tokens.radius.sm,
                padding: tokens.space.sm,
                display: 'flex',
                alignItems: 'center',
                gap: tokens.space.sm,
              }}
            >
              <span style={{ fontSize: '20px', color: elder.accent }}>{r.glyph}</span>
              <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minWidth: 0 }}>
                <span
                  style={{
                    fontSize: '9px',
                    letterSpacing: '0.14em',
                    textTransform: 'uppercase',
                    color: tokens.text.onParchmentDim,
                  }}
                >
                  {r.label}
                </span>
                <span
                  style={{
                    fontFamily: tokens.font.mono,
                    fontSize: '16px',
                    fontWeight: 600,
                    color: tokens.text.onParchment,
                  }}
                >
                  {r.value.toLocaleString()}
                </span>
              </div>
              <span
                style={{
                  fontFamily: tokens.font.mono,
                  fontSize: '10px',
                  color: r.delta.startsWith('-') ? tokens.text.danger : '#3a7a3a',
                }}
              >
                {r.delta}
              </span>
            </div>
          ))}
        </div>
      </section>

      {/* Movement log */}
      <section style={{ flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
        <SectionHeader>Asset movements</SectionHeader>
        <ul
          style={{
            listStyle: 'none',
            margin: `${tokens.space.sm} 0 0`,
            padding: 0,
            overflowY: 'auto',
            display: 'flex',
            flexDirection: 'column',
            gap: '4px',
          }}
        >
          {STUB_MOVEMENTS.map((m, i) => (
            <li
              key={i}
              style={{
                display: 'flex',
                alignItems: 'baseline',
                gap: tokens.space.sm,
                fontSize: '11px',
                fontFamily: tokens.font.mono,
                padding: '4px 6px',
                borderLeft: `2px solid ${
                  m.type === 'gain' ? '#3a7a3a' : tokens.text.danger
                }`,
                background: 'rgba(255,255,255,0.18)',
              }}
            >
              <span style={{ color: tokens.text.muted, width: '32px' }}>T{m.tick}</span>
              <span
                style={{
                  fontWeight: 600,
                  color:
                    m.type === 'gain' ? '#3a7a3a' : tokens.text.danger,
                  width: '76px',
                }}
              >
                {m.amount}
              </span>
              <span style={{ color: tokens.text.onParchmentDim, flex: 1 }}>
                {m.source}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}

function SectionHeader({ children }: { children: React.ReactNode }) {
  return (
    <h3
      style={{
        margin: 0,
        fontFamily: tokens.font.display,
        fontSize: '11px',
        letterSpacing: '0.18em',
        textTransform: 'uppercase',
        color: tokens.text.onParchmentDim,
        borderBottom: `1px solid ${tokens.border.parchmentEdge}`,
        paddingBottom: '4px',
      }}
    >
      {children}
    </h3>
  );
}
