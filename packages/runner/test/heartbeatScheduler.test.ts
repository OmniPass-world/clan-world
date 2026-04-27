import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { startHeartbeatScheduler } from '../src/heartbeatScheduler';
import { HeartbeatRateLimitedError, type IHeartbeatCaller } from '@clan-world/agents/seams';

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
});
