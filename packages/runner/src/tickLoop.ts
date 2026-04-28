import {
  HeartbeatRateLimitedError,
  type DeliveryStatus,
  type IElderMemoryStore,
  type IElderPeerInbox,
  type IHeartbeatCaller,
  type IRunnerInbox,
} from '@clan-world/agents/seams';
import type { IConvexClient } from '@clan-world/shared/adapters';
import { composeSituationBlock } from './composeSituationBlock';
import { pollChainTick } from './pollChainTick';
import { settleWindow } from './settleWindow';
import { ELDER_IDS, type ElderId, type RunnerConfig } from './types';

export interface PerElderDeps {
  inbox: IRunnerInbox;
  memory: IElderMemoryStore;
  peerInbox: IElderPeerInbox;
}

export interface TickLoopDeps {
  convex: IConvexClient;
  heartbeatCaller: IHeartbeatCaller;
  perElder: Record<ElderId, PerElderDeps>;
  config: RunnerConfig;
  /** AbortSignal for clean shutdown. */
  signal: AbortSignal;
  /** Logger — defaults to console. Tests pass a recorder. */
  log?: Logger;
}

export interface Logger {
  info: (...args: unknown[]) => void;
  warn: (...args: unknown[]) => void;
  error: (...args: unknown[]) => void;
}

const consoleLogger: Logger = {
  info: (...a) => console.log('[runner]', ...a),
  warn: (...a) => console.warn('[runner]', ...a),
  error: (...a) => console.error('[runner]', ...a),
};

/**
 * Per-tick orchestration:
 *
 *   while !shuttingDown:
 *     chainTick = pollChainTick(convex)
 *     if chainTick > lastProcessedTick:
 *       for each elder in parallel:
 *         block  = composeSituationBlock(...)
 *         status = inbox.deliverSituationBlock(chainTick, block)
 *       wait settleWindow
 *       try heartbeat() (inline rate-limit retry)
 *       on success: lastProcessedTick = chainTick
 *     sleep pollIntervalMs
 *
 * Returns when `signal` is aborted.
 *
 * Design notes:
 *
 * - `lastProcessedTick` is process-local. On runner restart we lose it and
 *   may re-attempt a heartbeat for a tick that was already advanced. The
 *   on-chain `nextHeartbeatAtTs` rate limit is the safety: a redundant
 *   heartbeat reverts and surfaces as `HeartbeatRateLimitedError`, which we
 *   back off on. Persisting `lastProcessedTick` to disk is a Phase-2 follow-up.
 *
 * - We heartbeat unconditionally after the settle window, even if all 4
 *   Elder deliveries failed. This is intentional: the runner's job is to
 *   advance the chain. Per the IRunnerInbox contract, an Elder that misses
 *   delivery "loses the turn's reasoning" — the chain still advances.
 *
 * - On non-rate-limit heartbeat failure we break out of the inner retry and
 *   fall through to the outer `pollIntervalMs` sleep. The next outer
 *   iteration will see `chainTick > lastProcessedTick` again and retry
 *   delivery + heartbeat. The `TmuxRunnerInbox` idempotency check makes the
 *   re-deliver a no-op (returns 'duplicate-tick'); the cost is one extra
 *   settle-window of latency before retry. Acceptable for prototype.
 */
export async function tickLoop(deps: TickLoopDeps): Promise<void> {
  const log = deps.log ?? consoleLogger;
  let lastProcessedTick = -1;

  while (!deps.signal.aborted) {
    let chainTick: number;
    try {
      chainTick = await raceAbort(pollChainTick(deps.convex), deps.signal, 'pollChainTick');
    } catch (err) {
      if (deps.signal.aborted) break;
      log.error('pollChainTick failed:', err);
      await sleepWithSignal(deps.config.pollIntervalMs, deps.signal);
      continue;
    }

    if (chainTick > lastProcessedTick && chainTick > 0) {
      log.info(`tick ${chainTick} observed (last processed: ${lastProcessedTick})`);

      // Compose + deliver to all 4 Elders in parallel. Per-Elder errors are
      // contained — one Elder being down must not block the others or the
      // heartbeat that follows.
      await Promise.all(
        ELDER_IDS.map(async elder => {
          const per = deps.perElder[elder];
          try {
            const block = await raceAbort(
              composeSituationBlock(
                { elder, clanId: deps.config.elderToClanId[elder], tick: chainTick },
                { convex: deps.convex, memory: per.memory, peerInbox: per.peerInbox },
              ),
              deps.signal,
              `composeSituationBlock(elder=${elder})`,
            );
            // MED-1: per-delivery AbortController so a timeout OR shutdown cancels the tmux child.
            const deliveryAbort = new AbortController();
            const linkAbort = (): void => deliveryAbort.abort();
            deps.signal.addEventListener('abort', linkAbort, { once: true });
            let status: DeliveryStatus;
            try {
              status = await withTimeout(
                per.inbox.deliverSituationBlock(chainTick, block, deliveryAbort.signal),
                deps.config.deliveryTimeoutMs,
                `deliverSituationBlock(elder=${elder}, tick=${chainTick})`,
              );
            } finally {
              deliveryAbort.abort(); // cancels tmux child whether delivery succeeded, timed out, or shutdown
              deps.signal.removeEventListener('abort', linkAbort);
            }
            if (!status.ok) {
              log.warn(`elder ${elder}: delivery returned not-ok: ${status.reason}`);
            }
          } catch (err) {
            if (deps.signal.aborted) return; // clean shutdown
            log.error(`elder ${elder}: deliver/compose failed:`, err);
          }
        }),
      );

      // Settle: give Elders time to read + submit orders.
      const settleResult = await settleWindow(deps.config.settleWindowSec * 1000, deps.signal);
      if (settleResult === 'aborted') {
        log.info('settle window aborted by shutdown signal');
        break;
      }

      // Heartbeat the chain. Retry inline on rate-limit so we don't re-run
      // the (90s) settle window or re-paste situation blocks just to hit the
      // same rate-limit window again.
      let heartbeatDone = false;
      while (!heartbeatDone && !deps.signal.aborted) {
        try {
          const { txHash } = await raceAbort(deps.heartbeatCaller.callHeartbeat(), deps.signal, 'callHeartbeat');
          log.info(`heartbeat tx confirmed: ${txHash}`);
          lastProcessedTick = chainTick;
          heartbeatDone = true;
        } catch (err) {
          if (err instanceof HeartbeatRateLimitedError) {
            const waitMs = Math.max(0, err.nextAllowedAt * 1000 - Date.now());
            log.warn(
              `heartbeat rate-limited; backing off ${Math.ceil(waitMs / 1000)}s until ${new Date(
                err.nextAllowedAt * 1000,
              ).toISOString()}`,
            );
            await sleepWithSignal(waitMs, deps.signal);
            if (deps.signal.aborted) break;
            // Re-poll: if tick advanced during the wait, heartbeat already fired.
            // Wrapped in raceAbort so a hung Convex query doesn't block past SIGTERM.
            const freshTick = await raceAbort(
              pollChainTick(deps.convex),
              deps.signal,
              'pollChainTick(re-poll)',
            ).catch(() => chainTick);
            if (freshTick > chainTick) {
              log.info(`chainTick advanced to ${freshTick} during rate-limit wait — stale tick ${chainTick} dropped`);
              break;
            }
            continue; // retry callHeartbeat
          }
          log.error('heartbeat failed (non-rate-limit):', err);
          // Bail out of this tick; the next poll loop will pick it up again.
          break;
        }
      }
    }

    await sleepWithSignal(deps.config.pollIntervalMs, deps.signal);
  }
}

async function sleepWithSignal(ms: number, signal: AbortSignal): Promise<void> {
  if (ms <= 0) return;
  await new Promise<void>(resolve => {
    if (signal.aborted) {
      resolve();
      return;
    }
    const timer = setTimeout(() => {
      signal.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    const onAbort = (): void => {
      clearTimeout(timer);
      signal.removeEventListener('abort', onAbort);
      resolve();
    };
    signal.addEventListener('abort', onAbort);
  });
}

async function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`timeout after ${ms}ms: ${label}`)), ms);
  });
  try {
    return await Promise.race([p, timeout]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

/**
 * Race `p` against the abort signal. Rejects with "aborted" if signal fires first.
 * Does NOT cancel `p` — it continues running in the background (underlying ops
 * don't support cancellation). This prevents the outer loop from waiting on them
 * past the shutdown signal.
 */
function raceAbort<T>(p: Promise<T>, signal: AbortSignal, label: string): Promise<T> {
  if (signal.aborted) return Promise.reject(new Error(`aborted: ${label}`));
  return new Promise<T>((resolve, reject) => {
    const onAbort = (): void => reject(new Error(`aborted: ${label}`));
    signal.addEventListener('abort', onAbort, { once: true });
    p.then(
      v => { signal.removeEventListener('abort', onAbort); resolve(v); },
      e => { signal.removeEventListener('abort', onAbort); reject(e); },
    );
  });
}
