/**
 * Wait `ms` milliseconds before resolving — gives the Elders time to read
 * the situation block, reason, and submit on-chain orders before the runner
 * advances the chain via heartbeat().
 *
 * Default in `RunnerConfig` is 90s. Tests pass a small value via the same
 * function so this is intentionally minimal — no shortcuts, no jitter.
 *
 * Returns early if `signal` is aborted; the tick loop uses this to react to
 * SIGTERM mid-window without waiting the full settle period.
 */
export function settleWindow(ms: number, signal?: AbortSignal): Promise<'settled' | 'aborted'> {
  return new Promise(resolve => {
    if (signal?.aborted) {
      resolve('aborted');
      return;
    }
    const timer = setTimeout(() => {
      cleanup();
      resolve('settled');
    }, ms);
    const onAbort = (): void => {
      clearTimeout(timer);
      cleanup();
      resolve('aborted');
    };
    signal?.addEventListener('abort', onAbort);
    function cleanup(): void {
      signal?.removeEventListener('abort', onAbort);
    }
  });
}
