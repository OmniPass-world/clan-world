import { tokens } from '../../../styles/cockpit-tokens';
import type { ElderDef } from '../../../styles/cockpit-tokens';

interface Props {
  elder: ElderDef;
  testIdPrefix: string;
}

interface ClansmanRow {
  id: string;
  mission: string;
  location: string;
  /** Ticks until mission completes — null = idle. */
  eta: number | null;
  /** Ticks of cooldown remaining after mission ends — 0 = ready. */
  cooldown: number;
  /** Hunger fraction 0-1; >0.7 = visual starvation warning. */
  hunger: number;
}

const STUB_CLANSMEN: ClansmanRow[] = [
  { id: 'C1', mission: 'Raid',   location: 'Forest',     eta: 2, cooldown: 0, hunger: 0.4 },
  { id: 'C2', mission: 'Mill',   location: 'East Farms', eta: 1, cooldown: 0, hunger: 0.2 },
  { id: 'C3', mission: 'Idle',   location: 'Home',       eta: null, cooldown: 3, hunger: 0.78 },
  { id: 'C4', mission: 'Quarry', location: 'Mountains',  eta: 4, cooldown: 0, hunger: 0.55 },
];

export function ClansmanTab({ elder, testIdPrefix }: Props) {
  return (
    <div
      data-testid={`${testIdPrefix}-content-clansman`}
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
        Clansmen — Clan {elder.clanId}
      </h3>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
        {STUB_CLANSMEN.map((c) => {
          const starving = c.hunger > 0.7;
          return (
            <div
              key={c.id}
              data-testid={`${testIdPrefix}-clansman-${c.id}`}
              style={{
                display: 'grid',
                gridTemplateColumns: '28px 1fr 60px 36px',
                gap: tokens.space.sm,
                alignItems: 'center',
                padding: '6px 8px',
                background: 'rgba(255,255,255,0.22)',
                border: `1px solid ${
                  starving ? tokens.text.danger : tokens.border.parchmentEdge
                }`,
                borderRadius: tokens.radius.sm,
                fontFamily: tokens.font.mono,
                fontSize: '11px',
              }}
            >
              <span
                style={{
                  fontWeight: 700,
                  color: elder.accent,
                  fontSize: '12px',
                }}
              >
                {c.id}
              </span>
              <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                <span
                  style={{
                    fontWeight: 600,
                    color: tokens.text.onParchment,
                  }}
                >
                  {c.mission}
                </span>
                <span
                  style={{
                    color: tokens.text.onParchmentDim,
                    fontSize: '10px',
                  }}
                >
                  {c.location}
                </span>
              </div>
              <div
                style={{
                  fontSize: '10px',
                  color: tokens.text.onParchmentDim,
                  textAlign: 'right',
                }}
              >
                {c.eta !== null ? (
                  <span>ETA {c.eta}t</span>
                ) : c.cooldown > 0 ? (
                  <span>CD {c.cooldown}t</span>
                ) : (
                  <span style={{ color: '#3a7a3a' }}>ready</span>
                )}
              </div>
              <HungerBar hunger={c.hunger} starving={starving} />
            </div>
          );
        })}
      </div>
    </div>
  );
}

function HungerBar({ hunger, starving }: { hunger: number; starving: boolean }) {
  const pct = Math.round(hunger * 100);
  const fill = starving ? tokens.text.danger : '#b8862e';
  return (
    <div
      title={`Hunger ${pct}%`}
      style={{
        position: 'relative',
        height: '8px',
        background: 'rgba(0,0,0,0.18)',
        borderRadius: '1px',
        overflow: 'hidden',
        border: `1px solid ${tokens.border.parchmentEdge}`,
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 0,
          width: `${pct}%`,
          background: fill,
          transition: 'width 240ms ease',
        }}
      />
    </div>
  );
}
