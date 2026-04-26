import { useEffect, useMemo, useRef, useState } from 'react';
import { useAgentLogs, type AgentLog } from './useAgentLogs';

// World-event keyword filter. Logs at warn level whose message starts with
// "WORLD:" OR contains any of these words are surfaced as world notices.
const WORLD_KEYWORDS = ['bandit', 'raid', 'winter', 'omen', 'famine', 'storm front'];

function isWorldEvent(log: AgentLog): boolean {
  if (log.level !== 'warn') return false;
  const msg = log.message.toLowerCase();
  if (msg.startsWith('world:')) return true;
  return WORLD_KEYWORDS.some(k => msg.includes(k));
}

// Strip a leading "WORLD:" tag and the level prefix the orchestrator may emit
// so the parchment reads as in-world flavor text.
function cleanMessage(raw: string): string {
  let msg = raw;
  // strip "warn|" or "info|" prefix if present
  msg = msg.replace(/^(warn|info|error)\|\s*/i, '');
  // strip leading "WORLD:" tag
  msg = msg.replace(/^WORLD:\s*/i, '');
  return msg.trim();
}

const HOLD_MS = 8000;
const SLIDE_MS = 500;

/**
 * Bottom-of-viewport parchment panel for WORLD-level events (bandits, raids,
 * weather, omens). Distinct from per-clan speech bubbles. Mounted as an HTML
 * overlay (NOT inside Pixi) — simpler, and the parchment texture/typography
 * is easier to control with CSS than with Graphics.
 */
export function WorldNoticePanel() {
  const logs = useAgentLogs();

  // Pull all world-event logs in chronological order (logs come desc).
  const worldEvents = useMemo(() => {
    return [...logs].reverse().filter(isWorldEvent);
  }, [logs]);

  // Latest event id we've animated for. New event id → trigger slide-in.
  const [currentId, setCurrentId] = useState<string | null>(null);
  const [visible, setVisible] = useState(false);
  const hideTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (worldEvents.length === 0) return;
    const latest = worldEvents[worldEvents.length - 1];
    if (!latest) return;
    if (latest._id === currentId) return;

    // New world event — show it.
    setCurrentId(latest._id);
    setVisible(true);

    if (hideTimerRef.current) clearTimeout(hideTimerRef.current);
    hideTimerRef.current = setTimeout(() => {
      // Per spec: "Keep one persistent at all times after the first event lands."
      // So: don't hide once a notice has landed — just stay on the latest.
      // (If we wanted true slide-down: setVisible(false) here.)
      // Keep visible=true; effect re-runs only when a NEW event arrives.
    }, HOLD_MS);

    return () => {
      if (hideTimerRef.current) clearTimeout(hideTimerRef.current);
    };
  }, [worldEvents, currentId]);

  const latest = worldEvents[worldEvents.length - 1];
  if (!latest || !visible) return null;

  const text = cleanMessage(latest.message);

  return (
    <div
      style={{
        position: 'absolute',
        bottom: 12,
        left: '50%',
        transform: visible
          ? 'translate(-50%, 0)'
          : 'translate(-50%, calc(100% + 24px))',
        transition: `transform ${SLIDE_MS}ms cubic-bezier(0.22, 1, 0.36, 1)`,
        width: 'min(560px, calc(100% - 24px))',
        padding: '10px 18px',
        // Parchment gradient: warm tan → aged darker tan
        background:
          'linear-gradient(180deg, #e8d8a8 0%, #d9c89a 50%, #c0a070 100%)',
        // Subtle inner highlight + outer dark rim for "aged scroll" feel
        boxShadow:
          'inset 0 1px 0 rgba(255,240,200,0.6), inset 0 -1px 0 rgba(80,50,20,0.35), 0 4px 12px rgba(0,0,0,0.5)',
        border: '1px solid #6b4a1c',
        borderRadius: 6,
        color: '#3a2410',
        fontFamily: '"Cinzel", "Times New Roman", Georgia, serif',
        fontSize: 14,
        lineHeight: 1.35,
        letterSpacing: '0.02em',
        textAlign: 'center',
        textShadow: '0 1px 0 rgba(255,240,200,0.5)',
        pointerEvents: 'none',
        zIndex: 3,
      }}
    >
      <div
        style={{
          fontSize: 10,
          letterSpacing: '0.18em',
          textTransform: 'uppercase',
          color: '#6b4a1c',
          marginBottom: 2,
          fontWeight: 700,
        }}
      >
        World Notice
      </div>
      <div style={{ fontWeight: 600 }}>{text}</div>
    </div>
  );
}
