import { useEffect, useRef, useState } from 'react';
import { tokens } from '../../styles/cockpit-tokens';
import { useConnectionStatus, type ConnectionStatus } from '../../hooks/useConnectionStatus';

/**
 * Phase A.5b stub: returns hardcoded tick so the header has something to show.
 *
 * TODO(phase-b): wire to a Convex query (likely `api.engine.currentTick`)
 * so the value updates live as the engine ticks. The pulse animation in
 * <TickCounter> will then visibly fire on each increment.
 */
function useCurrentTick(): { tick: number; tickMax: number } {
  return { tick: 4, tickMax: 10 };
}

/**
 * App-level cockpit header — replaces the per-mini-cockpit chrome that used
 * to repeat the tick counter four times. Single instance now.
 *
 * Layout: title left, tick counter middle-right, connection pill far right.
 */
export function CockpitHeader() {
  const { tick, tickMax } = useCurrentTick();
  const { status, retry } = useConnectionStatus();

  return (
    <header
      data-testid="cockpit-chrome"
      style={{
        height: '40px',
        background: tokens.bg.ironDeep,
        borderBottom: `1px solid ${tokens.border.iron}`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: `0 ${tokens.space.md}`,
        flexShrink: 0,
        gap: tokens.space.md,
      }}
    >
      <div
        style={{
          fontFamily: tokens.font.display,
          fontSize: '12px',
          letterSpacing: '0.24em',
          color: tokens.text.onIron,
          textTransform: 'uppercase',
          whiteSpace: 'nowrap',
        }}
      >
        ClanWorld Cockpit
      </div>
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: tokens.space.lg,
        }}
      >
        <TickCounter tick={tick} tickMax={tickMax} />
        <ConnectionPill status={status} onRetry={retry} />
      </div>
    </header>
  );
}

interface TickProps {
  tick: number;
  tickMax: number;
}

/**
 * Mono "T n/N" counter with a 200ms border-glow flash on each increment.
 * Uses a ref-tracked previous tick so the flash fires only on actual change,
 * not on remount.
 */
function TickCounter({ tick, tickMax }: TickProps) {
  const [pulsing, setPulsing] = useState(false);
  const prevTickRef = useRef(tick);

  useEffect(() => {
    if (tick === prevTickRef.current) return;
    prevTickRef.current = tick;
    setPulsing(true);
    const t = setTimeout(() => setPulsing(false), 200);
    return () => clearTimeout(t);
  }, [tick]);

  return (
    <div
      data-testid="cockpit-header-tick"
      data-pulsing={pulsing}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '4px',
        padding: '4px 10px',
        border: `1px solid ${pulsing ? tokens.text.accent : tokens.border.iron}`,
        borderRadius: tokens.radius.sm,
        background: tokens.bg.ink,
        boxShadow: pulsing
          ? `0 0 12px ${tokens.text.accent}, inset 0 0 6px rgba(212,165,68,0.25)`
          : 'none',
        fontFamily: tokens.font.mono,
        fontSize: '12px',
        color: tokens.text.accent,
        fontWeight: 600,
        letterSpacing: '0.08em',
        transition: 'box-shadow 200ms ease, border-color 200ms ease',
      }}
      title="Engine tick"
    >
      <span style={{ opacity: 0.6 }}>T</span>
      <span>{tick}</span>
      <span style={{ opacity: 0.4 }}>/</span>
      <span style={{ opacity: 0.6 }}>{tickMax}</span>
    </div>
  );
}

interface PillProps {
  status: ConnectionStatus;
  onRetry: () => void;
}

const STATUS_COLORS: Record<ConnectionStatus, string> = {
  connected: '#7a8a6a',
  reconnecting: tokens.text.accent,
  disconnected: tokens.text.danger,
};

const STATUS_LABELS: Record<ConnectionStatus, string> = {
  connected: 'connected',
  reconnecting: 'reconnecting',
  disconnected: 'disconnected',
};

const STATUS_GLYPHS: Record<ConnectionStatus, string> = {
  connected: '●',
  reconnecting: '⟳',
  disconnected: '●',
};

/**
 * Connection state pill. Shows current heartbeat status with a glyph + label,
 * and exposes a manual "Reconnect" button when fully disconnected.
 */
function ConnectionPill({ status, onRetry }: PillProps) {
  const color = STATUS_COLORS[status];
  return (
    <div
      data-testid="cockpit-connection-pill"
      data-status={status}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '6px',
        padding: '4px 10px',
        border: `1px solid ${tokens.border.iron}`,
        borderRadius: tokens.radius.sm,
        background: tokens.bg.ink,
        fontFamily: tokens.font.mono,
        fontSize: '11px',
        color: tokens.text.onIronDim,
        letterSpacing: '0.06em',
      }}
      title={`Cockpit backend: ${STATUS_LABELS[status]}`}
    >
      <span
        aria-hidden
        style={{
          color,
          fontSize: '13px',
          lineHeight: 1,
          display: 'inline-block',
          animation: status === 'reconnecting' ? 'cockpit-pill-spin 1.2s linear infinite' : undefined,
        }}
      >
        {STATUS_GLYPHS[status]}
      </span>
      <span style={{ color: tokens.text.onIron }}>{STATUS_LABELS[status]}</span>
      {status === 'disconnected' && (
        <button
          data-testid="cockpit-connection-pill-retry"
          type="button"
          onClick={onRetry}
          style={{
            marginLeft: '4px',
            padding: '2px 8px',
            border: `1px solid ${tokens.border.ironLight}`,
            borderRadius: tokens.radius.sm,
            background: 'transparent',
            color: tokens.text.accent,
            fontFamily: tokens.font.mono,
            fontSize: '10px',
            letterSpacing: '0.08em',
            cursor: 'pointer',
            textTransform: 'uppercase',
          }}
        >
          Reconnect
        </button>
      )}
      <style>{`
        @keyframes cockpit-pill-spin {
          from { transform: rotate(0deg); }
          to   { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
}
