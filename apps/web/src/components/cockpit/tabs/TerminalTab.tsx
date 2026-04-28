import { tokens } from '../../../styles/cockpit-tokens';
import type { ElderDef } from '../../../styles/cockpit-tokens';

interface Props {
  elder: ElderDef;
  testIdPrefix: string;
}

/**
 * Terminal tab — placeholder for the future tmux read-only mirror.
 *
 * Phase A: renders a faux terminal with a few lines of stubbed output so the
 * panel "looks alive". Phase B will wire a real tmux capture-pane → WebSocket
 * stream (similar to CPC's terminal pane).
 */
export function TerminalTab({ elder, testIdPrefix }: Props) {
  // Hardcoded sample lines — make them feel like Elder LLM thinking-out-loud.
  const lines = [
    `$ elder-${elder.clanId} stream --tail`,
    `[T03] situation-block ingested (12.4kb)`,
    `[T03] thinking — wood low; mill before raid`,
    `[T03] directive: queue clansman-2 → forest`,
    `[T04] tick boundary; awaiting orchestrator`,
  ];

  return (
    <div
      data-testid={`${testIdPrefix}-content-terminal`}
      style={{
        flex: 1,
        background: '#0d0d0d',
        color: '#9ec792',
        fontFamily: tokens.font.mono,
        fontSize: '11px',
        lineHeight: 1.6,
        padding: tokens.space.md,
        overflowY: 'auto',
        position: 'relative',
        boxShadow: 'inset 0 0 24px rgba(0,0,0,0.6)',
      }}
    >
      {/* CRT scanline effect — subtle, parchment aesthetic still dominant */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          pointerEvents: 'none',
          background:
            'repeating-linear-gradient(0deg, rgba(0,0,0,0.06) 0 1px, transparent 1px 3px)',
        }}
      />
      <div
        style={{
          color: tokens.text.onIronDim,
          fontSize: '9px',
          letterSpacing: '0.15em',
          marginBottom: '8px',
          textTransform: 'uppercase',
        }}
      >
        ── Elder-{elder.clanId} tmux mirror (read-only) ──
      </div>
      {lines.map((l, i) => (
        <div key={i} style={{ position: 'relative', zIndex: 1 }}>
          {l}
        </div>
      ))}
      <div
        style={{
          position: 'relative',
          zIndex: 1,
          marginTop: '4px',
          color: '#d4a544',
        }}
      >
        ▊
      </div>
      <div
        style={{
          position: 'absolute',
          bottom: tokens.space.sm,
          right: tokens.space.sm,
          fontSize: '9px',
          color: tokens.text.muted,
          fontFamily: tokens.font.mono,
        }}
      >
        Phase B: live tmux stream
      </div>
    </div>
  );
}
