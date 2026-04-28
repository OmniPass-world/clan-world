import { tokens } from '../../../styles/cockpit-tokens';
import type { ElderDef } from '../../../styles/cockpit-tokens';

interface Props {
  elder: ElderDef;
  testIdPrefix: string;
}

type CommsKind = 'whisper' | 'human' | 'orch';

interface CommsLine {
  tick: number;
  kind: CommsKind;
  speaker: string;
  body: string;
}

/**
 * Communication log — three input classes:
 *   - whisper : AXL chain whisper between Elders
 *   - human   : human prompt routed to this Elder
 *   - orch    : orchestrator-injected directive
 *
 * Each kind gets a distinct visual treatment per Liam's bubble-taxonomy spec.
 */
const STUB_LINES: CommsLine[] = [
  { tick: 4, kind: 'orch',    speaker: 'orchestrator', body: 'Tick T04 begun. Yield <directives>.' },
  { tick: 4, kind: 'whisper', speaker: 'clan-3',       body: 'AXL: "trade ore for wood, 2:1?"' },
  { tick: 3, kind: 'human',   speaker: 'liam',         body: 'Slow your raids — diplomacy first.' },
  { tick: 3, kind: 'whisper', speaker: 'clan-2',       body: 'AXL: declined; counter offered 3:1.' },
  { tick: 2, kind: 'orch',    speaker: 'orchestrator', body: 'Bandit camp surfaced at forest.' },
];

const KIND_STYLES: Record<
  CommsKind,
  { label: string; bg: string; border: string; fg: string }
> = {
  whisper: {
    label: 'WHISPER',
    bg: 'rgba(90,138,168,0.12)',
    border: '#5a8aa8',
    fg: '#3a5a78',
  },
  human: {
    label: 'HUMAN',
    bg: 'rgba(212,165,68,0.14)',
    border: '#b8862e',
    fg: '#7a4e10',
  },
  orch: {
    label: 'ORCH',
    bg: 'rgba(106,168,136,0.12)',
    border: '#6aa888',
    fg: '#3a6a4a',
  },
};

export function CommsTab({ elder, testIdPrefix }: Props) {
  return (
    <div
      data-testid={`${testIdPrefix}-content-comms`}
      style={{
        flex: 1,
        background: tokens.bg.parchment,
        color: tokens.text.onParchment,
        padding: tokens.space.md,
        overflowY: 'auto',
        fontFamily: tokens.font.body,
        display: 'flex',
        flexDirection: 'column',
        gap: tokens.space.sm,
      }}
    >
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
        Comms — Elder {elder.clanId}
      </h3>

      <ul
        style={{
          listStyle: 'none',
          margin: 0,
          padding: 0,
          display: 'flex',
          flexDirection: 'column',
          gap: '6px',
        }}
      >
        {STUB_LINES.map((l, i) => {
          const s = KIND_STYLES[l.kind];
          return (
            <li
              key={i}
              data-testid={`${testIdPrefix}-comms-${l.kind}-${i}`}
              style={{
                background: s.bg,
                borderLeft: `3px solid ${s.border}`,
                padding: '6px 8px',
                fontSize: '11px',
                display: 'flex',
                flexDirection: 'column',
                gap: '2px',
              }}
            >
              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  fontFamily: tokens.font.mono,
                  fontSize: '9px',
                  letterSpacing: '0.12em',
                }}
              >
                <span style={{ color: s.fg, fontWeight: 700 }}>
                  [{s.label}] {l.speaker}
                </span>
                <span style={{ color: tokens.text.muted }}>T{l.tick}</span>
              </div>
              <div
                style={{
                  color: tokens.text.onParchment,
                  fontStyle: l.kind === 'human' ? 'italic' : 'normal',
                }}
              >
                {l.body}
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
