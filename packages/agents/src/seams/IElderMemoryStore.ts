/**
 * IElderMemoryStore — durable Elder memory across context resets.
 *
 * S2 stub: local JSON file at ~/.world/clanworld-runner/state/elder-{N}-memory.json
 * Phase 7: 0G iNFT memory (ERC-7857 linked storage per clan; survives ownership transfer)
 *
 * Contract:
 * - Key/value store scoped to a single Elder (N).
 * - All keys are strings; values are JSON-serialisable strings.
 * - reads must not throw on missing keys (return undefined).
 * - writes must be durable: a read after a successful write must return the written value.
 * - Implementations must be safe for single-Elder single-writer use (no concurrent write guarantee required).
 */
export interface IElderMemoryStore {
  /**
   * Read the value stored for topic/key, or undefined if not set.
   */
  recall(key: string): Promise<string | undefined>;

  /**
   * Persist a value for key. Overwrites any previous value.
   *
   * Contract:
   * - Must complete before the tick loop continues (caller does not fire-and-forget).
   * - Must throw on storage failure (full disk, permission denied, 0G write error).
   */
  save(key: string, value: string): Promise<void>;

  /**
   * Return all stored key/value pairs (snapshot at call time).
   * Used by the runner to compose the continuity summary block on final-tick warning.
   */
  snapshot(): Promise<Record<string, string>>;
}
