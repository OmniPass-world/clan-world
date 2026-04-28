import { HeartbeatRateLimitedError, type IHeartbeatCaller } from '@clan-world/agents/seams';
import type { IConvexClient } from '@clan-world/shared/adapters';
import { pollChainTick } from './pollChainTick';
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
  /** Convex client for reading current tick. Required when settleLatch is provided. */
  convex?: IConvexClient;
  /** Shared latch — Cycle A only fires heartbeat after Cycle B settles the tick. */
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

  const timer = setInterval(() => {
    void (async () => {
      if (deps.signal.aborted) return;
      if (inFlight) return;
      inFlight = true;
      try {
        const due = await deps.heartbeatCaller.isHeartbeatDue();
        if (!due) return;
        if (deps.signal.aborted) return;
        // HIGH: only fire after Cycle B has settled this tick.
        if (deps.settleLatch && deps.convex) {
          const currentTick = await pollChainTick(deps.convex).catch(() => -1);
          if (currentTick > 0 && deps.settleLatch.lastSettledTick() < currentTick) {
            log.info(`waiting for Cycle B to settle tick ${currentTick} before heartbeat`);
            return;
          }
        }
        const { txHash } = await deps.heartbeatCaller.callHeartbeat();
        log.info(`heartbeat tx confirmed: ${txHash}`);
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
