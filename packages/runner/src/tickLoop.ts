import {
  type DeliveryStatus,
  type IElderMemoryStore,
  type IElderPeerInbox,
  type IRunnerInbox,
} from '@clan-world/agents/seams';
import type { IConvexClient } from '@clan-world/shared/adapters';
import { composeSituationBlock } from './composeSituationBlock';
import { pollChainTick } from './pollChainTick';
import { settleWindow } from './settleWindow';
import type { SettleLatch } from './settleLatch';
import { ELDER_IDS, type ElderId, type RunnerConfig } from './types';

export interface PerElderDeps {
  inbox: IRunnerInbox;
  memory: IElderMemoryStore;
  peerInbox: IElderPeerInbox;
}

export interface TickLoopDeps {
  convex: IConvexClient;
  perElder: Record<ElderId, PerElderDeps>;
  config: RunnerConfig;
  /** AbortSignal for clean shutdown. */
  signal: AbortSignal;
  /** Logger — defaults to console. Tests pass a recorder. */
  log?: Logger;
  /** Optional shared latch — Cycle A waits for Cycle B to call markSettled(tick). */
  settleLatch?: SettleLatch;
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
 * Per-tick Elder delivery loop (Cycle B):
 *
 *   while !shuttingDown:
 *     chainTick = pollChainTick(convex)
 *     if chainTick > lastProcessedTick:
 *       for each elder in parallel:
 *         block  = composeSituationBlock(...)
 *         status = inbox.deliverSituationBlock(chainTick, block)
 *       wait settleWindow
 *       settleLatch.markSettled(chainTick)
 *       lastProcessedTick = chainTick
 *     sleep pollIntervalMs
 *
 * Does NOT call heartbeat — that is Cycle A (`heartbeatScheduler`).
 * Returns when `signal` is aborted.
 *
 * Design notes:
 *
 * - `lastProcessedTick` is process-local, updated after settle window.
 *   On restart, TmuxRunnerInbox idempotency (last-tick.txt) prevents double-delivery.
 *
 * - Delivery is abort-aware: each per-Elder delivery uses its own AbortController
 *   linked to `deps.signal`, so SIGTERM cancels in-flight tmux children promptly.
 *
 * - `pollChainTick` and `composeSituationBlock` are wrapped in `raceAbort` so a
 *   hung Convex query does not block past shutdown.
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

      // Per-Elder delivery with retries. PR #136 review #1 fix (Option C):
      //   1. Attempt all 4 Elders in parallel via Promise.allSettled.
      //   2. For any failures, retry just the failed Elders up to MAX_RETRIES
      //      with backoff between attempts.
      //   3. After retries exhausted, log a prominent warning naming each
      //      still-failed Elder and ADVANCE THE TICK ANYWAY (preserves liveness).
      // This makes transient failures (network blip, tmux race, Convex hiccup)
      // self-heal mid-tick, while permanent failures don't deadlock the world.
      const MAX_RETRIES = 2;
      const RETRY_BACKOFF_MS = 500;
      const failedElders: ElderId[] = [];

      const attemptElder = async (elder: ElderId): Promise<boolean> => {
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
            if (status.reason === 'duplicate-tick') {
              log.info(`elder ${elder}: tick ${chainTick} already processed by other elder, skipping`);
              return true;
            }
            log.warn(`elder ${elder}: delivery returned not-ok: ${status.reason}`);
            return status.reason === 'aborted'; // shutdown is "ok" — don't retry
          }
          return true;
        } catch (err) {
          if (deps.signal.aborted) return true; // clean shutdown — no retry
          log.error(`elder ${elder}: deliver/compose failed:`, err);
          return false;
        }
      };

      // Initial attempt: all 4 Elders in parallel.
      const initialResults = await Promise.all(ELDER_IDS.map(attemptElder));
      ELDER_IDS.forEach((elder, idx) => {
        if (!initialResults[idx]) failedElders.push(elder);
      });

      // Retry loop: only the still-failed Elders.
      for (let attempt = 1; attempt <= MAX_RETRIES && failedElders.length > 0 && !deps.signal.aborted; attempt++) {
        log.warn(`tick ${chainTick}: retry ${attempt}/${MAX_RETRIES} for ${failedElders.length} failed elder(s): [${failedElders.join(', ')}]`);
        await sleepWithSignal(RETRY_BACKOFF_MS, deps.signal);
        const retryTargets = [...failedElders];
        failedElders.length = 0;
        const retryResults = await Promise.all(retryTargets.map(attemptElder));
        retryTargets.forEach((elder, idx) => {
          if (!retryResults[idx]) failedElders.push(elder);
        });
      }

      if (failedElders.length > 0 && !deps.signal.aborted) {
        log.error(
          `[tickLoop] WARNING: tick ${chainTick} advancing despite ${failedElders.length} elder(s) still failing after ${MAX_RETRIES} retries: [${failedElders.join(', ')}]. Game state for these clans may diverge until they recover.`,
        );
      }

      // Settle: give Elders time to read + submit orders.
      const settleResult = await settleWindow(deps.config.settleWindowSec * 1000, deps.signal);
      if (settleResult === 'aborted') {
        log.info('settle window aborted by shutdown signal');
        break;
      }
      deps.settleLatch?.markSettled(chainTick);
      lastProcessedTick = chainTick;
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
