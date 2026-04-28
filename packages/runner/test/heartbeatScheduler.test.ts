import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { startHeartbeatScheduler } from '../src/heartbeatScheduler';
import { HeartbeatRateLimitedError, type IHeartbeatCaller } from '@clan-world/agents/seams';
import { makeSettleLatch } from '../src/settleLatch';

function makeHeartbeatCaller(overrides: Partial<IHeartbeatCaller> = {}): IHeartbeatCaller {
  return {
    async isHeartbeatDue() { return false; },
    async callHeartbeat() { return { txHash: '0xabc' }; },
    ...overrides,
  };
}

beforeEach(() => { vi.useFakeTimers(); });
afterEach(() => { vi.useRealTimers(); });

describe('heartbeatScheduler', () => {
  it('calls callHeartbeat when isHeartbeatDue returns true', async () => {
    const callHeartbeat = vi.fn().mockResolvedValue({ txHash: '0x1' });
    const caller = makeHeartbeatCaller({
      async isHeartbeatDue() { return true; },
      callHeartbeat,
    });
    const abort = new AbortController();

    startHeartbeatScheduler({ heartbeatCaller: caller, signal: abort.signal, checkIntervalMs: 100 });

    await vi.advanceTimersByTimeAsync(110);
    expect(callHeartbeat).toHaveBeenCalledTimes(1);

    abort.abort();
  });

  it('does NOT call callHeartbeat when isHeartbeatDue returns false', async () => {
    const callHeartbeat = vi.fn().mockResolvedValue({ txHash: '0x1' });
    const caller = makeHeartbeatCaller({
      async isHeartbeatDue() { return false; },
      callHeartbeat,
    });
    const abort = new AbortController();

    startHeartbeatScheduler({ heartbeatCaller: caller, signal: abort.signal, checkIntervalMs: 100 });

    await vi.advanceTimersByTimeAsync(350);
    expect(callHeartbeat).not.toHaveBeenCalled();

    abort.abort();
  });

  it('catches HeartbeatRateLimitedError without crashing, retries on next check', async () => {
    let callCount = 0;
    const caller = makeHeartbeatCaller({
      async isHeartbeatDue() { return true; },
      async callHeartbeat() {
        callCount++;
        if (callCount === 1) {
          throw new HeartbeatRateLimitedError(Math.floor(Date.now() / 1000) + 60);
        }
        return { txHash: '0x2' };
      },
    });
    const abort = new AbortController();
    const warnLog = vi.fn();

    startHeartbeatScheduler({
      heartbeatCaller: caller,
      signal: abort.signal,
      checkIntervalMs: 100,
      log: { info: vi.fn(), warn: warnLog, error: vi.fn() },
    });

    // First interval: throws rate-limited, warn logged
    await vi.advanceTimersByTimeAsync(110);
    expect(callCount).toBe(1);
    expect(warnLog).toHaveBeenCalledTimes(1);

    // Second interval: succeeds
    await vi.advanceTimersByTimeAsync(110);
    expect(callCount).toBe(2);

    abort.abort();
  });

  it('clears the interval on signal abort', async () => {
    const callHeartbeat = vi.fn().mockResolvedValue({ txHash: '0x1' });
    const caller = makeHeartbeatCaller({
      async isHeartbeatDue() { return true; },
      callHeartbeat,
    });
    const abort = new AbortController();

    startHeartbeatScheduler({ heartbeatCaller: caller, signal: abort.signal, checkIntervalMs: 100 });
    abort.abort();

    await vi.advanceTimersByTimeAsync(350);
    expect(callHeartbeat).not.toHaveBeenCalled();
  });

  it('does not allow overlapping callHeartbeat — second interval fires while first in flight', async () => {
    let inFlightCount = 0;
    let maxConcurrent = 0;
    const callHeartbeat = vi.fn(async () => {
      inFlightCount++;
      maxConcurrent = Math.max(maxConcurrent, inFlightCount);
      await new Promise(resolve => setTimeout(resolve, 250)); // slow
      inFlightCount--;
      return { txHash: '0xslow' };
    });
    const caller = makeHeartbeatCaller({
      async isHeartbeatDue() { return true; },
      callHeartbeat,
    });
    const abort = new AbortController();
    const settleLatch = makeSettleLatch();
    settleLatch.markSettled(1); // Cycle B already settled tick 1

    startHeartbeatScheduler({ heartbeatCaller: caller, signal: abort.signal, checkIntervalMs: 100, settleLatch });

    // Fire 3 intervals (0ms, 100ms, 200ms) while first call takes 250ms
    await vi.advanceTimersByTimeAsync(310);
    expect(maxConcurrent).toBe(1); // never more than 1 in-flight
    abort.abort();
  });

  it('skips heartbeat when Cycle B has not settled the current tick', async () => {
    const callHeartbeat = vi.fn().mockResolvedValue({ txHash: '0x1' });
    const caller = makeHeartbeatCaller({
      async isHeartbeatDue() { return true; },
      callHeartbeat,
    });
    const abort = new AbortController();
    const settleLatch = makeSettleLatch(); // lastSettledTick = -1, Cycle B hasn't settled yet

    startHeartbeatScheduler({ heartbeatCaller: caller, signal: abort.signal, checkIntervalMs: 100, settleLatch });

    await vi.advanceTimersByTimeAsync(350); // 3 intervals — Cycle B unsettled, all skip
    expect(callHeartbeat).not.toHaveBeenCalled();

    // Cycle B settles a tick — Cycle A now allowed to fire
    settleLatch.markSettled(1);
    await vi.advanceTimersByTimeAsync(110);
    expect(callHeartbeat).toHaveBeenCalledTimes(1);

    abort.abort();
  });

  it('slow callHeartbeat + Cycle B advances mid-call does not permanently skip next tick', async () => {
    // Scenario: Cycle A fires for tick 1. callHeartbeat takes 250ms. During that wait,
    // Cycle B settles tick 2. Without snapshot-before-call, lastHeartbeatForTick would
    // be set to 2 after the call, making Cycle A think tick 2 was already heartbeated.
    const settleLatch = makeSettleLatch();
    settleLatch.markSettled(1); // Cycle B settled tick 1

    let resolveHeartbeat!: () => void;
    const callHeartbeat = vi.fn((): Promise<{ txHash: string }> => {
      return new Promise(resolve => {
        resolveHeartbeat = () => resolve({ txHash: '0xslow' });
      });
    });
    const caller = makeHeartbeatCaller({
      async isHeartbeatDue() { return true; },
      callHeartbeat,
    });
    const abort = new AbortController();

    startHeartbeatScheduler({ heartbeatCaller: caller, signal: abort.signal, checkIntervalMs: 100, settleLatch });

    // Trigger first interval — starts callHeartbeat for tick 1 (settledSnapshot = 1)
    await vi.advanceTimersByTimeAsync(110);
    expect(callHeartbeat).toHaveBeenCalledTimes(1);

    // Cycle B settles tick 2 WHILE callHeartbeat is still in-flight
    settleLatch.markSettled(2);

    // Resolve the slow heartbeat
    resolveHeartbeat();
    await vi.advanceTimersByTimeAsync(10); // flush microtasks

    // lastHeartbeatForTick should be 1 (the snapshot taken before the call), not 2
    // So the next interval must fire heartbeat for tick 2
    await vi.advanceTimersByTimeAsync(110);
    expect(callHeartbeat).toHaveBeenCalledTimes(2); // fired again for tick 2

    abort.abort();
  });
});
