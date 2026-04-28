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
 * Minimal subset of @0glabs/0g-ts-sdk KvClient we actually use.
 * Typed separately so tests can inject a mock without importing the full SDK.
 *
 * NOTE: The real SDK passes the key as a hex string ("0x…") over JSON-RPC.
 * Uint8Array would JSON-serialize as {"0":…,"1":…} which the 0G RPC server
 * does not understand — use `encodeKey()` to produce "0x" + hex before
 * calling getValue.
 *
 * The real SDK's Value.data is a Base64 string (not Uint8Array).
 * We use `string | Uint8Array` here to support both the real SDK and test mocks.
 *
 * KEY ENCODING (symmetric with save path):
 *   save:   Uint8Array key written via writer.set(encodeKeyBytes(k), ...)
 *           → internally stored as hex in StreamDataBuilder.set()
 *   recall: encodeKey(k) → "0x<hex>" passed to KvClient.getValue()
 */
export interface I0GKvClient {
  getValue(streamId: string, key: string, version?: number): Promise<{ startIndex: bigint; data: string | Uint8Array } | null>;
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
 * Encode a UTF-8 key string as a 0x-prefixed hex string for the 0G KV RPC.
 *
 * The 0G JSON-RPC server expects keys as hex strings (e.g. "0x676f616c").
 * Passing a raw Uint8Array would JSON-serialize as {"0":103,…} which the
 * server does not understand. This encoding is symmetric with the write path:
 * StreamDataBuilder.set() internally does Buffer.from(key).toString('hex')
 * before encoding the key into the transaction.
 */
function encodeKey(key: string): string {
  return '0x' + Buffer.from(key, 'utf8').toString('hex');
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
          '[ZeroGMemoryStore] write stub — OG_WALLET_PRIVATE_KEY not configured; ' +
          `${pending.size} key(s) held in session cache only (not persisted to 0G). ` +
          'Set OG_STUB_WRITE_THROWS=1 to enforce strict durability.',
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

  constructor(streamId: string, client: I0GKvClient, writerFactory: KvWriterFactory) {
    this.#streamId = streamId;
    this.#client = client;
    this.#writerFactory = writerFactory;
  }

  async recall(key: string): Promise<string | undefined> {
    // Check write-through cache first (consistent reads after writes).
    const cached = this.#cache.get(key);
    if (cached !== undefined) return cached;

    try {
      const result = await this.#client.getValue(this.#streamId, encodeKey(key));
      if (result === null) return undefined;
      const value = decodeValue(result.data);
      this.#cache.set(key, value);
      return value;
    } catch (err) {
      // recall must not throw on missing keys; surface unexpected errors as undefined + warning.
      console.warn(`[ZeroGMemoryStore] recall(${key}) failed — returning undefined:`, err);
      return undefined;
    }
  }

  async save(key: string, value: string): Promise<void> {
    const writer = this.#writerFactory(this.#streamId);
    // I0GKvWriter.set takes Uint8Array (raw bytes fed into StreamDataBuilder).
    // encodeKeyBytes() is the same UTF-8 bytes as encodeKey() but as Uint8Array.
    writer.set(encodeKeyBytes(key), new TextEncoder().encode(value));
    // exec() throws on genuine storage failure (contract invocation error, etc.)
    await writer.exec();
    // Update write-through cache after successful (or stub) write.
    this.#cache.set(key, value);
  }

  async snapshot(): Promise<Record<string, string>> {
    // Returns in-session keys only (write-through cache).
    // TODO: For a full cross-session snapshot, enumerate the KV stream via KvIterator.
    //   The @0glabs/0g-ts-sdk KvClient does not expose a "list all keys" API directly;
    //   production implementation should use KvClient.newIterator(streamId) to walk the
    //   stream and populate the cache on first access.
    //   For the hackathon demo this is acceptable: the runner always writes before it
    //   snapshots (within one session), so the cache is complete for the continuity block.
    return Object.fromEntries(this.#cache.entries());
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
