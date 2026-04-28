import { HeartbeatRateLimitedError, type IHeartbeatCaller } from '@clan-world/agents/seams';
import type { SettleLatch } from './settleLatch';

export interface HeartbeatSchedulerDeps {
  heartbeatCaller: IHeartbeatCaller;
  /** AbortSignal for clean shutdown. */
  signal: AbortSignal;
  /** How often to check isHeartbeatDue (ms). Defaults to 30_000. */
  checkIntervalMs?: number;
  /** Logger — defaults to console. Tests pass a recorder. */
  log?: {
    info: (...args: unknown[]) => void;
    warn: (...args: unknown[]) => void;
    error: (...args: unknown[]) => void;
  };
  /**
   * Shared latch — Cycle A only fires heartbeat after Cycle B settles a new tick.
   * Compared against an internal `lastHeartbeatForTick` counter so no Convex
   * poll is needed here (avoids stale-snapshot / error-path races).
   */
  settleLatch?: SettleLatch;
}

/**
 * Cycle A — heartbeat driver (independent of Elder activity).
 *
 * Polls isHeartbeatDue() on a fixed interval. When due, fires callHeartbeat().
 * HeartbeatRateLimitedError is caught and logged — the next interval will
 * re-check isHeartbeatDue() and retry naturally when the window elapses.
 */
export function startHeartbeatScheduler(deps: HeartbeatSchedulerDeps): void {
  const log = deps.log ?? {
    info: (...a: unknown[]) => console.log('[heartbeat]', ...a),
    warn: (...a: unknown[]) => console.warn('[heartbeat]', ...a),
    error: (...a: unknown[]) => console.error('[heartbeat]', ...a),
  };
  const checkMs = deps.checkIntervalMs ?? 30_000;
  let inFlight = false;
  // Tracks the lastSettledTick value at the time of the last successful heartbeat.
  // Cycle A only fires when Cycle B has settled a tick NEWER than the last one
  // we heartbeated for — no Convex poll needed, no stale-snapshot race.
  let lastHeartbeatForTick = -1;

  if (deps.signal.aborted) return; // LOW: don't create timer if already shut down

  const timer = setInterval(() => {
    void (async () => {
      if (deps.signal.aborted) return;
      if (inFlight) return;
      inFlight = true;
      try {
        const due = await deps.heartbeatCaller.isHeartbeatDue();
        if (!due) return;
        if (deps.signal.aborted) return;
        // Only fire after Cycle B has settled a tick newer than our last heartbeat.
        // Snapshot settled BEFORE callHeartbeat() — a slow tx can take long enough
        // for Cycle B to settle the next tick; reading after the call would mark
        // the newer tick as already-heartbeated and permanently skip it.
        const settledSnapshot = deps.settleLatch ? deps.settleLatch.lastSettledTick() : -1;
        if (deps.settleLatch && settledSnapshot <= lastHeartbeatForTick) {
          log.info(`waiting for Cycle B to settle (last settled: ${settledSnapshot}, last heartbeat for: ${lastHeartbeatForTick})`);
          return;
        }
        const { txHash } = await deps.heartbeatCaller.callHeartbeat();
        log.info(`heartbeat tx confirmed: ${txHash}`);
        if (deps.settleLatch) lastHeartbeatForTick = settledSnapshot;
      } catch (err) {
        if (err instanceof HeartbeatRateLimitedError) {
          log.warn(
            `heartbeat rate-limited until ${new Date(err.nextAllowedAt * 1000).toISOString()} — will retry on next check`,
          );
          return;
        }
        log.error('heartbeat failed:', err);
      } finally {
        inFlight = false;
      }
    })();
  }, checkMs);

  deps.signal.addEventListener('abort', () => clearInterval(timer), { once: true });
}
