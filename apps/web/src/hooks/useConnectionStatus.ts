import { useCallback, useEffect, useRef, useState } from 'react';

export type ConnectionStatus = 'connected' | 'reconnecting' | 'disconnected';

const HEARTBEAT_INTERVAL_MS = 15_000;
const MAX_RETRIES = 3;
/** 2s, 4s, 8s exponential backoff. */
const BACKOFF_MS = [2_000, 4_000, 8_000];
/**
 * Heartbeat target — ttyd is the canonical "is the cockpit backend reachable"
 * probe. We hit elder-1 specifically because that's the always-on Elder; the
 * other ttyd services start lazily at demo time.
 *
 * Tests stub this URL via Playwright `page.route()`.
 *
 * Known limitation: this is a *reachability* probe, not a *health* probe.
 * `mode: 'no-cors'` resolves for any HTTP response (including 502/503 from
 * Caddy when the upstream ttyd is down). We accept this trade-off for now —
 * a same-origin /healthz endpoint on app.clan-world.com would be more
 * accurate but requires a server-side proxy that's out of scope here.
 * Phase B may revisit by adding a Convex query that the server polls.
 */
export const HEARTBEAT_URL =
  'https://cockpit.clan-world.com/elder-1-tty/';

interface Options {
  /** Override the heartbeat URL (for tests). */
  url?: string;
  /** Override the heartbeat poll interval (for tests). */
  intervalMs?: number;
}

/**
 * Heartbeat-driven connection state machine.
 *
 *   connected ──fail──▶ reconnecting ──MAX_RETRIES fails──▶ disconnected
 *       ▲                    │                                  │
 *       └─────────success─────┘──manual retry()──────────────────┘
 *
 * The fetch uses `mode: 'no-cors'` because the cockpit page lives on a
 * different subdomain than ttyd — the response is opaque, but `fetch`
 * resolving (vs rejecting) is enough signal that the host is reachable.
 *
 * On `visibilitychange` → visible, we fire an immediate heartbeat ONLY if
 * the state is `connected` or `reconnecting`. We never auto-leave the
 * `disconnected` state — that state is sticky until the user clicks
 * Reconnect, by design.
 *
 * Implementation note: the entire state machine is implemented inside a
 * single `useEffect` so the closure variables (retryCount, in-flight flag,
 * timer handles) are scoped to a single mount. External callers interact
 * through `status` (state) and `retry()` (a stable callback that bumps a
 * counter; the effect picks up the change and resets the state machine).
 */
export function useConnectionStatus(options: Options = {}): {
  status: ConnectionStatus;
  retry: () => void;
} {
  const { url = HEARTBEAT_URL, intervalMs = HEARTBEAT_INTERVAL_MS } = options;
  // Initialize as 'reconnecting' until the first probe completes. Previously
  // initialized to 'connected', which caused a brief green pill flash before
  // the first HEAD probe resolved (PR #133 review SHOULD FIX #4). Probe
  // succeeds → flips to 'connected'; probe fails → already in correct state.
  const [status, setStatus] = useState<ConnectionStatus>('reconnecting');
  const [retryToken, setRetryToken] = useState(0);

  // Status ref so the visibility handler can check current state without
  // re-running the effect on every transition (which would tear down + rearm
  // the timer chain on each tick).
  const statusRef = useRef<ConnectionStatus>(status);
  statusRef.current = status;

  const retry = useCallback(() => {
    setRetryToken((n) => n + 1);
  }, []);

  useEffect(() => {
    let cancelled = false;
    let pollTimer: ReturnType<typeof setTimeout> | undefined;
    let backoffTimer: ReturnType<typeof setTimeout> | undefined;
    let retryCount = 0;
    /** Guard against overlapping probes when visibilitychange fires mid-flight. */
    let inFlight = false;

    // Manual retry resets the state machine.
    if (retryToken > 0) {
      setStatus('reconnecting');
    }

    const clearTimers = () => {
      if (pollTimer) clearTimeout(pollTimer);
      if (backoffTimer) clearTimeout(backoffTimer);
      pollTimer = undefined;
      backoffTimer = undefined;
    };

    const probe = async (): Promise<boolean> => {
      try {
        await fetch(url, { method: 'HEAD', mode: 'no-cors', cache: 'no-store' });
        return true;
      } catch {
        return false;
      }
    };

    const heartbeat = async () => {
      if (inFlight || cancelled) return;
      inFlight = true;
      // Clear any pending timers — we're firing now.
      clearTimers();
      try {
        const ok = await probe();
        if (cancelled) return;
        if (ok) {
          retryCount = 0;
          setStatus('connected');
          pollTimer = setTimeout(() => void heartbeat(), intervalMs);
          return;
        }
        // Failure path
        retryCount += 1;
        // Off-by-one fix (PR #133 review SHOULD FIX #5): increment FIRST, then
        // compare. Previously `retryCount >= MAX_RETRIES` checked before
        // increment meant the FOURTH failure tripped disconnect, not the third.
        if (retryCount >= MAX_RETRIES) {
          setStatus('disconnected');
          return;
        }
        setStatus('reconnecting');
        const delay = BACKOFF_MS[retryCount - 1] ?? BACKOFF_MS[BACKOFF_MS.length - 1];
        backoffTimer = setTimeout(() => void heartbeat(), delay);
      } finally {
        inFlight = false;
      }
    };

    const onVisibility = () => {
      if (cancelled) return;
      if (document.visibilityState !== 'visible') return;
      // Don't auto-revive from disconnected — that state is sticky until
      // the user clicks the Reconnect button. Visibility change only
      // accelerates the next probe in the polling loop.
      if (statusRef.current === 'disconnected') return;
      void heartbeat();
    };
    document.addEventListener('visibilitychange', onVisibility);

    void heartbeat();

    return () => {
      cancelled = true;
      clearTimers();
      document.removeEventListener('visibilitychange', onVisibility);
    };
  }, [url, intervalMs, retryToken]);

  return { status, retry };
}
