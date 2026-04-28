import {
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
 */
export async function tickLoop(deps: TickLoopDeps): Promise<void> {
  const log = deps.log ?? consoleLogger;
  let lastProcessedTick = -1;

  while (!deps.signal.aborted) {
    let chainTick: number;
    try {
      chainTick = await pollChainTick(deps.convex);
    } catch (err) {
      log.error('pollChainTick failed:', err);
      await sleepWithSignal(deps.config.pollIntervalMs, deps.signal);
      continue;
    }

    if (chainTick > lastProcessedTick && chainTick > 0) {
      log.info(`tick ${chainTick} observed (last processed: ${lastProcessedTick})`);

      // Compose + deliver to all 4 Elders in parallel. Per-Elder errors are
      // contained — one Elder being down must not block the others.
      await Promise.all(
        ELDER_IDS.map(async elder => {
          const per = deps.perElder[elder];
          try {
            const block = await composeSituationBlock(
              { elder, clanId: deps.config.elderToClanId[elder], tick: chainTick },
              { convex: deps.convex, memory: per.memory, peerInbox: per.peerInbox },
            );
            const status = await withTimeout(
              per.inbox.deliverSituationBlock(chainTick, block),
              deps.config.deliveryTimeoutMs,
              `deliverSituationBlock(elder=${elder}, tick=${chainTick})`,
            );
            if (!status.ok) {
              log.warn(`elder ${elder}: delivery returned not-ok: ${status.reason}`);
            }
          } catch (err) {
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
