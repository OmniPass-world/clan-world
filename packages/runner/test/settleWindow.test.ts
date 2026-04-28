import { describe, it, expect } from 'vitest';
import { settleWindow } from '../src/settleWindow';

describe('settleWindow', () => {
  it('resolves with "settled" after the timeout elapses', async () => {
    const start = Date.now();
    const result = await settleWindow(80);
    const elapsed = Date.now() - start;
    expect(result).toBe('settled');
    // Allow a generous lower bound to account for timer drift on shared CI.
    expect(elapsed).toBeGreaterThanOrEqual(70);
  });

  it('resolves immediately with "aborted" if signal is already aborted', async () => {
    const ctl = new AbortController();
    ctl.abort();
    const start = Date.now();
    const result = await settleWindow(10_000, ctl.signal);
    expect(result).toBe('aborted');
    expect(Date.now() - start).toBeLessThan(50);
  });

  it('resolves with "aborted" if signal aborts during the wait', async () => {
    const ctl = new AbortController();
    setTimeout(() => ctl.abort(), 30);
    const start = Date.now();
    const result = await settleWindow(10_000, ctl.signal);
    const elapsed = Date.now() - start;
    expect(result).toBe('aborted');
    expect(elapsed).toBeLessThan(500);
  });
});
