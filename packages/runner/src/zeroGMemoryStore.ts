/**
 * ZeroGMemoryStore — Phase 7 IElderMemoryStore backed by 0G KV storage.
 *
 * S2 degrade-gracefully pattern:
 *   - OG_STORAGE_API_KEY not set → logs warning, falls back to FileMemoryStore
 *   - OG_STORAGE_API_KEY set     → uses @0glabs/0g-ts-sdk KvClient for durable storage
 *
 * 0G KV model:
 *   - Each Elder owns a "stream" (OG_STREAM_ID).
 *   - Keys are UTF-8 encoded as Uint8Array; values are UTF-8 JSON strings.
 *   - KvClient.getValue reads; Batcher + StreamDataBuilder writes.
 *
 * TODO: Production hardening —
 *   - Sign Batcher transactions with a real wallet (currently uses a dummy signer stub).
 *   - Retry logic on transient 0G RPC failures.
 *   - Version-pinned reads to avoid dirty reads during concurrent Elder migrations.
 */
import type { IElderMemoryStore } from '@clan-world/agents/src/seams/index.js';
import { FileMemoryStore, defaultStateDir } from './fileMemoryStore.js';

// ---------------------------------------------------------------------------
// 0G SDK client interface (typed against @0glabs/0g-ts-sdk@0.3.3)
// ---------------------------------------------------------------------------

/**
 * Minimal iterator interface over a 0G KV stream.
 * Matches the shape of @0glabs/0g-ts-sdk KvIterator.
 *
 * key is raw Uint8Array (the stored key bytes as returned by the RPC).
 * data is Base64 string (real SDK) or Uint8Array (test mocks).
 */
export interface I0GKvIterator {
  valid(): boolean;
  getCurrentPair(): { key: Uint8Array; data: string | Uint8Array } | undefined;
  seekToFirst(): Promise<Error | null>;
  next(): Promise<Error | null>;
}

/**
 * Minimal subset of @0glabs/0g-ts-sdk KvClient we actually use.
 * Typed separately so tests can inject a mock without importing the full SDK.
 *
 * NOTE: The real SDK passes the key as a Base64 string over JSON-RPC.
 * The JSON-RPC transport (open-jsonrpc-provider) serializes the key param
 * directly via JSON.stringify. A raw Uint8Array would serialize as
 * {"0":103,…} which the 0G RPC server does not understand. A hex string
 * would also be wrong. The correct form is Base64, matching the README
 * example: `kvClient.getValue(streamId, ethers.encodeBase64(key))`.
 *
 * // Key type confirmed from @0glabs/0g-ts-sdk@0.3.3 README:
 * // getValue() key is ethers.encodeBase64(keyBytes) — a base64 string.
 * // TypeScript signature says Bytes (ArrayLike<number>) but the runtime
 * // transport requires a base64 string to survive JSON.stringify correctly.
 *
 * The real SDK's Value.data is a Base64 string (not Uint8Array).
 * We use `string | Uint8Array` here to support both the real SDK and test mocks.
 *
 * KEY ENCODING (symmetric with save path):
 *   save:   Uint8Array key written via writer.set(encodeKeyBytes(k), ...)
 *           → internally stored as bytes in StreamDataBuilder.set()
 *   recall: encodeKey(k) → base64 string passed to KvClient.getValue()
 */
export interface I0GKvClient {
  getValue(streamId: string, key: string, version?: number): Promise<{ startIndex: bigint; data: string | Uint8Array } | null>;
  /** Returns an iterator for walking all keys in the stream. Used by snapshot() hydration. */
  newIterator(streamId: string, version?: number): I0GKvIterator;
}

/**
 * Minimal subset of the Batcher / StreamDataBuilder write path.
 */
export interface I0GKvWriter {
  set(key: Uint8Array, value: Uint8Array): void;
  exec(): Promise<void>;
}

/**
 * Factory that creates a writable batch for a given stream.
 * Real implementation wraps Batcher + StreamDataBuilder from @0glabs/0g-ts-sdk.
 */
export type KvWriterFactory = (streamId: string) => I0GKvWriter;

// ---------------------------------------------------------------------------
// Real 0G adapter (loaded dynamically when API key is present)
// ---------------------------------------------------------------------------

/**
 * Encode a UTF-8 key string as a Base64 string for the 0G KV RPC.
 *
 * The 0G JSON-RPC server expects keys as Base64 strings over HTTP JSON-RPC.
 * The transport (open-jsonrpc-provider) passes params directly to
 * JSON.stringify, so Uint8Array → {"0":103,…} (wrong) and hex "0x…" (wrong).
 * The SDK README example uses ethers.encodeBase64(keyBytes) which produces
 * standard Base64, e.g. "Z29hbA==" for the UTF-8 bytes of "goal".
 *
 * // Key type confirmed from @0glabs/0g-ts-sdk@0.3.3 README:
 * // getValue() key = ethers.encodeBase64(keyBytes) — base64 string.
 */
function encodeKey(key: string): string {
  return Buffer.from(key, 'utf8').toString('base64');
}

/** Encode a UTF-8 key string as Uint8Array for I0GKvWriter.set() (write path). */
function encodeKeyBytes(key: string): Uint8Array {
  return new TextEncoder().encode(key);
}

/**
 * Decode a value returned by the 0G SDK.
 *
 * The real @0glabs/0g-ts-sdk KvClient returns Value.data as a Base64 string.
 * Test mocks return Uint8Array for convenience.
 * We handle both to keep the real and mock paths consistent.
 */
function decodeValue(data: string | Uint8Array): string {
  if (typeof data === 'string') {
    // Base64-encoded string from the real 0G SDK — decode to UTF-8 text.
    return Buffer.from(data, 'base64').toString('utf8');
  }
  return new TextDecoder().decode(data);
}

/**
 * Build the real KvClient from @0glabs/0g-ts-sdk.
 * Imported dynamically to avoid hard-crashing if the SDK isn't installed.
 */
async function buildRealClient(rpc: string): Promise<I0GKvClient> {
  // Dynamic import keeps the fallback path free of SDK hard-dependency.
  // TODO: Replace with a static import once the package is pinned in CI.
  const sdk = await import('@0glabs/0g-ts-sdk') as {
    KvClient: new (rpc: string) => I0GKvClient;
  };
  return new sdk.KvClient(rpc);
}

/**
 * Build a KvWriterFactory using the real @0glabs/0g-ts-sdk Batcher.
 *
 * HACKATHON STUB: This writer logs a warning and skips durable 0G writes.
 * Writes ARE held in the ZeroGMemoryStore in-process cache so recall() works
 * within the same session. Cross-session durability requires wiring a real
 * Batcher (needs OG_WALLET_PRIVATE_KEY + OG_FLOW_CONTRACT).
 *
 * The IElderMemoryStore contract says "save must throw on storage failure" —
 * this stub treats "no wallet configured" as a degraded-but-running mode
 * (demo-acceptable). Set OG_STUB_WRITE_THROWS=1 to make it throw instead
 * if you want strict compliance checking in CI.
 *
 * TODO: Wire OG_WALLET_PRIVATE_KEY + OG_FLOW_CONTRACT for production writes.
 */
function buildRealWriterFactory(_streamId: string, _apiKey: string): KvWriterFactory {
  return (_sid: string): I0GKvWriter => {
    const pending = new Map<string, Uint8Array>();
    return {
      set(key: Uint8Array, value: Uint8Array): void {
        pending.set(new TextDecoder().decode(key), value);
      },
      async exec(): Promise<void> {
        // TODO: Replace with real Batcher.exec() once wallet + flow contract are configured.
        // See @0glabs/0g-ts-sdk Batcher — requires:
        //   new Batcher(version, storageNodes, flowContract, providerUrl)
        //   followed by streamDataBuilder.set(streamId, key, value) + batcher.exec()
        if (process.env['OG_STUB_WRITE_THROWS'] === '1') {
          throw new Error(
            '[ZeroGMemoryStore] write stub — OG_WALLET_PRIVATE_KEY not configured; ' +
            'refusing to silently drop writes (OG_STUB_WRITE_THROWS=1)',
          );
        }
        console.warn(
          '[ZeroGMemoryStore] WARN: save() is in-process cache only — ' +
          '0G durable write not implemented (S2 limitation). ' +
          'Data will not survive restart. Use FileMemoryStore for durability. ' +
          `(${pending.size} key(s) buffered in session cache only.) ` +
          'To wire full durability: set OG_WALLET_PRIVATE_KEY + OG_FLOW_CONTRACT. ' +
          'Set OG_STUB_WRITE_THROWS=1 to enforce strict durability in CI.',
        );
      },
    };
  };
}

// ---------------------------------------------------------------------------
// ZeroGMemoryStore
// ---------------------------------------------------------------------------

export class ZeroGMemoryStore implements IElderMemoryStore {
  readonly #streamId: string;
  readonly #client: I0GKvClient;
  readonly #writerFactory: KvWriterFactory;
  /** In-memory write-through cache so reads after writes are consistent. */
  readonly #cache = new Map<string, string>();
  /**
   * Whether #hydrateFromStore() has been called.
   * Uses a flag (not cache.size) to avoid skipping hydration when the cache
   * already has local-only entries from in-session saves before the first
   * snapshot() call.
   */
  #hydrated = false;

  constructor(streamId: string, client: I0GKvClient, writerFactory: KvWriterFactory) {
    this.#streamId = streamId;
    this.#client = client;
    this.#writerFactory = writerFactory;
  }

  async recall(key: string): Promise<string | undefined> {
    // Check write-through cache first (consistent reads after writes).
    const cached = this.#cache.get(key);
    if (cached !== undefined) return cached;

    // The 0G SDK signals "key not found" by returning null (not by throwing).
    // Any exception here is a genuine RPC/network/auth failure — re-throw so
    // callers can distinguish a missing key (→ undefined) from a broken transport.
    const result = await this.#client.getValue(this.#streamId, encodeKey(key));
    if (result === null) return undefined;
    const value = decodeValue(result.data);
    this.#cache.set(key, value);
    return value;
  }

  /**
   * Save a key/value pair.
   *
   * S2 stub: cache-only. The in-process write-through cache is updated so
   * `recall()` returns the value for the rest of this session. The backing
   * 0G Batcher write is a documented stub that logs a prominent warning
   * instead of persisting to the 0G network.
   *
   * Full durability via 0G Batcher requires wallet + contract config:
   *   - OG_WALLET_PRIVATE_KEY  (funded ETH wallet)
   *   - OG_FLOW_CONTRACT       (deployed FixedPriceFlow contract address)
   *   - StorageNode[] selected via Indexer.selectNodes()
   * This is a Phase 3 / S3 TODO — not wired for the May 5 hackathon.
   *
   * Fallback: if OG_STORAGE_API_KEY is unset, `createMemoryStore()` returns
   * a FileMemoryStore which IS durable across restarts.
   *
   * @throws if the underlying writer.exec() throws (e.g. OG_STUB_WRITE_THROWS=1
   *         or a genuine storage contract error in a future wired implementation).
   */
  async save(key: string, value: string): Promise<void> {
    // Update write-through cache first so recall() is consistent even if exec() stubs.
    this.#cache.set(key, value);
    const writer = this.#writerFactory(this.#streamId);
    // I0GKvWriter.set takes Uint8Array (raw bytes fed into StreamDataBuilder).
    // encodeKeyBytes() is the same UTF-8 bytes as encodeKey() but as Uint8Array.
    writer.set(encodeKeyBytes(key), new TextEncoder().encode(value));
    // exec() is a stub that warns prominently (S2 limitation — see JSDoc above).
    // In a future wired implementation, exec() would invoke Batcher.exec().
    await writer.exec();
  }

  async snapshot(): Promise<Record<string, string>> {
    // On first snapshot() call, hydrate from durable 0G storage so keys written
    // in a previous session are included. Subsequent calls use the populated cache
    // (write-through cache stays consistent with in-session saves).
    if (!this.#hydrated) {
      await this.#hydrateFromStore();
      this.#hydrated = true;
    }
    return Object.fromEntries(this.#cache.entries());
  }

  /**
   * Walk the 0G KV stream via KvIterator and populate #cache with all stored
   * key/value pairs. Called once on the first snapshot() invocation.
   *
   * Iterator walk: seekToFirst() → valid()/getCurrentPair()/next() loop.
   * Iterator key bytes are UTF-8 decoded back to the original string key.
   * Existing local-only cache entries (from in-session saves) take priority.
   *
   * seekToFirst returning non-null (error/empty stream) → silently returns.
   */
  async #hydrateFromStore(): Promise<void> {
    const iter = this.#client.newIterator(this.#streamId);
    const seekErr = await iter.seekToFirst();
    if (seekErr !== null) {
      // Empty stream or iterator error — no durable keys to hydrate.
      return;
    }
    while (iter.valid()) {
      const pair = iter.getCurrentPair();
      if (pair !== undefined) {
        const key = new TextDecoder().decode(pair.key);
        // In-session saves take priority over durable 0G values.
        if (!this.#cache.has(key)) {
          this.#cache.set(key, decodeValue(pair.data));
        }
      }
      const nextErr = await iter.next();
      if (nextErr !== null) break;
    }
  }
}

// ---------------------------------------------------------------------------
// Factory — creates the right adapter based on env
// ---------------------------------------------------------------------------

export interface ZeroGMemoryStoreOptions {
  /** Override env lookup for testing. */
  env?: Record<string, string | undefined>;
  /** Override elder index for the fallback path (default: ELDER_N from env). */
  elderN?: number;
  /** Override state dir for the fallback path. */
  stateDir?: string;
  /** Override the 0G client (for testing). */
  kvClient?: I0GKvClient;
  /** Override the 0G writer factory (for testing). */
  kvWriterFactory?: KvWriterFactory;
}

/**
 * Create a memory store.
 *
 * - If OG_STORAGE_API_KEY is present → returns ZeroGMemoryStore backed by 0G KV.
 * - Otherwise → logs a warning and returns FileMemoryStore (local JSON fallback).
 */
export async function createMemoryStore(
  opts: ZeroGMemoryStoreOptions = {},
): Promise<IElderMemoryStore> {
  const env = opts.env ?? process.env;
  const apiKey = env['OG_STORAGE_API_KEY'];

  if (!apiKey) {
    console.warn(
      '[ZeroGMemoryStore] OG_STORAGE_API_KEY not set — falling back to local JSON file store.',
    );
    const n = opts.elderN ?? parseInt(env['ELDER_N'] ?? '1', 10);
    return new FileMemoryStore(n, opts.stateDir ?? defaultStateDir());
  }

  const streamId = env['OG_STREAM_ID'];
  if (!streamId) {
    console.warn(
      '[ZeroGMemoryStore] OG_STREAM_ID not set — falling back to local JSON file store.',
    );
    const n = opts.elderN ?? parseInt(env['ELDER_N'] ?? '1', 10);
    return new FileMemoryStore(n, opts.stateDir ?? defaultStateDir());
  }

  const rpc = env['OG_KV_RPC'] ?? 'https://rpc-storage-testnet.0g.ai';

  let client: I0GKvClient;
  if (opts.kvClient) {
    client = opts.kvClient;
  } else {
    try {
      client = await buildRealClient(rpc);
    } catch (err) {
      console.warn('[ZeroGMemoryStore] failed to load @0glabs/0g-ts-sdk — falling back to local file store:', err);
      const n = opts.elderN ?? parseInt(env['ELDER_N'] ?? '1', 10);
      return new FileMemoryStore(n, opts.stateDir ?? defaultStateDir());
    }
  }

  const writerFactory = opts.kvWriterFactory ?? buildRealWriterFactory(streamId, apiKey);

  return new ZeroGMemoryStore(streamId, client, writerFactory);
}
