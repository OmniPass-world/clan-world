/**
 * Shared sentinel between Cycle A (heartbeat driver) and Cycle B (elder driver).
 * Cycle B calls markSettled(tick) after its settle window completes.
 * Cycle A checks lastSettledTick() before calling heartbeat — if the
 * current on-chain tick hasn't been settled yet, Cycle B is still working.
 */
export interface SettleLatch {
  lastSettledTick(): number;
  markSettled(tick: number): void;
}

export function makeSettleLatch(): SettleLatch {
  let _tick = -1;
  return {
    lastSettledTick: () => _tick,
    markSettled: (tick) => { if (tick > _tick) _tick = tick; },
  };
}
