import { tokens } from '../../../styles/cockpit-tokens';
import type { ElderDef } from '../../../styles/cockpit-tokens';
import { useMemo } from 'react';

interface Props {
  elder: ElderDef;
  testIdPrefix: string;
}

const STUB_KV = [
  { key: 'last_grudge',     value: 'clan-3'             },
  { key: 'wood_threshold',  value: '80'                 },
  { key: 'pref_target',     value: 'forest'             },
  { key: 'mood',            value: 'cautious'           },
];

const STUB_CRUD = [
  { tick: 4, op: 'WRITE', key: 'mood',         note: 'cautious → wary'   },
  { tick: 3, op: 'READ',  key: 'last_grudge',  note: 'planning retort'   },
  { tick: 2, op: 'WRITE', key: 'wood_threshold', note: 'raise to 80'     },
  { tick: 1, op: 'READ',  key: 'pref_target',  note: 'mission seeding'   },
];

const STUB_BULLETINS = [
  { age: '2t', body: '"Wood scarce — millers prioritize."' },
  { age: '5t', body: '"Crimson moves — watch the river."'  },
];

interface DemoInftState {
  tokenId: string;
  owner: string;
  dataHash: string;
  notes?: string;
  data?: Array<{ label: string; dataHash: string; uri: string }>;
}

export function ZeroGTab({ elder, testIdPrefix }: Props) {
  const demoState = useMemo<DemoInftState | null>(() => {
    if (typeof window === 'undefined') return null;
    const raw = window.localStorage.getItem(`clanworld:inft-demo:${elder.clanId}`);
    if (!raw) return null;
    try {
      return JSON.parse(raw) as DemoInftState;
    } catch {
      return null;
    }
  }, [elder.clanId]);
  const kvRows = demoState?.data?.map((entry) => ({
    key: entry.label,
    value: entry.uri,
  })) ?? STUB_KV;

  return (
    <div
      data-testid={`${testIdPrefix}-content-0g`}
      style={{
        flex: 1,
        background: tokens.bg.parchment,
        color: tokens.text.onParchment,
        padding: tokens.space.md,
        overflowY: 'auto',
        fontFamily: tokens.font.body,
        display: 'flex',
        flexDirection: 'column',
        gap: tokens.space.md,
      }}
    >
      {/* iNFT metadata */}
      <section>
        <SectionHeader>iNFT — Elder #{elder.clanId}</SectionHeader>
        <div
          style={{
            marginTop: tokens.space.sm,
            display: 'grid',
            gridTemplateColumns: 'auto 1fr',
            gap: '4px 12px',
            fontFamily: tokens.font.mono,
            fontSize: '10px',
          }}
        >
          <Field k="token_id"     v={demoState?.tokenId ?? `0x${(0xe1de7000 + elder.clanId).toString(16)}`} />
          <Field k="owner"        v={demoState?.owner ?? 'demo-owner'} />
          <Field k="archetype"    v={elder.archetype} />
          <Field k="state_root"   v={demoState?.dataHash ?? '0xa1b2…f7e9'} />
          <Field k="encrypted"    v="◉ tee-attested" />
          <Field k="version"      v="v0.4.6" />
        </div>
      </section>

      {/* KV state + memory CRUD side-by-side on wide, stacked on narrow */}
      <section style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
        <div>
          <SectionHeader>kv state</SectionHeader>
          <div
            style={{
              marginTop: tokens.space.sm,
              fontFamily: tokens.font.mono,
              fontSize: '10px',
              display: 'flex',
              flexDirection: 'column',
              gap: '2px',
            }}
          >
            {kvRows.map((kv) => (
              <div
                key={kv.key}
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  padding: '3px 6px',
                  background: 'rgba(255,255,255,0.18)',
                }}
              >
                <span style={{ color: tokens.text.onParchmentDim }}>{kv.key}</span>
                <span style={{ color: elder.accent, fontWeight: 600 }}>{kv.value}</span>
              </div>
            ))}
          </div>
        </div>

        {demoState?.notes && (
          <div>
            <SectionHeader>owner notes</SectionHeader>
            <p style={{ margin: `${tokens.space.sm} 0 0`, fontSize: '11px', lineHeight: 1.4 }}>
              {demoState.notes}
            </p>
          </div>
        )}

        <div>
          <SectionHeader>memory CRUD</SectionHeader>
          <ul
            style={{
              listStyle: 'none',
              margin: `${tokens.space.sm} 0 0`,
              padding: 0,
              fontFamily: tokens.font.mono,
              fontSize: '10px',
              display: 'flex',
              flexDirection: 'column',
              gap: '2px',
            }}
          >
            {STUB_CRUD.map((c, i) => (
              <li
                key={i}
                style={{
                  display: 'grid',
                  gridTemplateColumns: '28px 52px 1fr',
                  gap: '6px',
                  padding: '3px 6px',
                  background: 'rgba(255,255,255,0.18)',
                  alignItems: 'center',
                }}
              >
                <span style={{ color: tokens.text.muted }}>T{c.tick}</span>
                <span
                  style={{
                    fontWeight: 700,
                    color: c.op === 'WRITE' ? '#7a3a1a' : tokens.text.muted,
                  }}
                >
                  {c.op}
                </span>
                <span>
                  <span style={{ color: tokens.text.onParchmentDim }}>{c.key}</span>
                  <span style={{ color: tokens.text.onParchment, marginLeft: '6px' }}>
                    — {c.note}
                  </span>
                </span>
              </li>
            ))}
          </ul>
        </div>

        <div>
          <SectionHeader>bulletins</SectionHeader>
          <ul
            style={{
              listStyle: 'none',
              margin: `${tokens.space.sm} 0 0`,
              padding: 0,
              fontFamily: tokens.font.body,
              fontSize: '11px',
              fontStyle: 'italic',
              display: 'flex',
              flexDirection: 'column',
              gap: '4px',
            }}
          >
            {STUB_BULLETINS.map((b, i) => (
              <li
                key={i}
                style={{
                  padding: '6px 8px',
                  background: 'rgba(212,165,68,0.1)',
                  borderLeft: `2px solid ${tokens.text.accent}`,
                  display: 'flex',
                  justifyContent: 'space-between',
                  gap: tokens.space.sm,
                }}
              >
                <span>{b.body}</span>
                <span
                  style={{
                    color: tokens.text.muted,
                    fontFamily: tokens.font.mono,
                    fontStyle: 'normal',
                    fontSize: '9px',
                    flexShrink: 0,
                  }}
                >
                  {b.age}
                </span>
              </li>
            ))}
          </ul>
        </div>
      </section>
    </div>
  );
}

function Field({ k, v }: { k: string; v: string }) {
  return (
    <>
      <span style={{ color: tokens.text.onParchmentDim }}>{k}</span>
      <span style={{ color: tokens.text.onParchment, fontWeight: 600 }}>{v}</span>
    </>
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
