import { HeartbeatRateLimitedError, type IHeartbeatCaller } from '@clan-world/agents/seams';

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

  const timer = setInterval(() => {
    void (async () => {
      if (deps.signal.aborted) return;
      try {
        const due = await deps.heartbeatCaller.isHeartbeatDue();
        if (!due) return;
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
      }
    })();
  }, checkMs);

  deps.signal.addEventListener('abort', () => clearInterval(timer), { once: true });
}
