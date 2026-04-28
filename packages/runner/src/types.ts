/**
 * Local types for the ClanWorld runner daemon.
 *
 * The runner drives 4 Elder Claude Code sessions (`elder-1` ... `elder-4`)
 * through a per-tick reasoning loop:
 *
 *   1. Poll Convex for the latest tick.
 *   2. For each Elder: compose situation block, deliver via tmux.
 *   3. Wait a settle window (~90s) for Elders to act + their txs to confirm.
 *   4. Call ClanWorld.heartbeat() to advance the chain.
 */

export type ElderId = 1 | 2 | 3 | 4;

export const ELDER_IDS: readonly ElderId[] = [1, 2, 3, 4] as const;

/**
 * Validated Elder id 1..4. Throws on anything else.
 */
export function asElderId(n: number): ElderId {
  if (n === 1 || n === 2 || n === 3 || n === 4) return n;
  throw new Error(`invalid ElderId: ${n} (must be 1..4)`);
}

export interface RunnerConfig {
  /** Milliseconds between Convex tick polls when no new tick is observed. */
  pollIntervalMs: number;
  /** Seconds to wait after delivering situation blocks before calling heartbeat. */
  settleWindowSec: number;
  /** Per-Elder timeout for `deliverSituationBlock` (ms). */
  deliveryTimeoutMs: number;
  /** Timeout when waiting for an `elder ack-clear` flag (ms). */
  ackTimeoutMs: number;
  /** State directory root (typically `~/.world/clanworld-runner/state`). */
  stateDir: string;
  /** tmux session name prefix. Each Elder lives in `${prefix}-${n}`. */
  tmuxSessionPrefix: string;
  /** Map of Elder id → clan id used for situation-block context + peer routing. */
  elderToClanId: Record<ElderId, string>;
  /** Milliseconds between isHeartbeatDue() checks in the heartbeat scheduler. */
  heartbeatCheckIntervalMs: number;
}
