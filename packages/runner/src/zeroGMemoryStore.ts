/**
 * ZeroGMemoryStore — Phase 7 IElderMemoryStore backed by 0G KV storage (mainnet).
 *
 * Write-through cache pattern:
 *   save(key, value)  → write to 0G via Batcher.exec() AND update local cache
 *   recall(key)       → read from local cache ONLY (no KvClient needed)
 *   snapshot()        → return local cache (no 0G read needed)
 *
 * On startup: local cache is hydrated from disk (same JSON file as FileMemoryStore).
 * This gives cross-session durability for reads without a public KV read node.
 *
 * Wallet: derived from ELDER_MNEMONIC + ELDER_INDEX (BIP-44 path m/44'/60'/0'/0/{index-1}).
 * No PRIVATE_KEY env var required.
 *
 * Mainnet config:
 *   EVM_RPC=https://evmrpc.0g.ai
 *   INDEXER_RPC=https://indexer-storage-turbo.0g.ai
 *   FLOW_CONTRACT=0x62D4144dB0F0a6fBBaeb6296c785C71B3D57C526
 *   CHAIN_ID=16661
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import type { IElderMemoryStore } from '@clan-world/agents/seams';
import { FileMemoryStore, defaultStateDir } from './fileMemoryStore.js';

// ---------------------------------------------------------------------------
// Interfaces for testability
// ---------------------------------------------------------------------------

/**
 * Minimal abstraction over the real Batcher from @0glabs/0g-ts-sdk.
 * Real: new Batcher(version, storageNodes, flowContract, providerUrl)
 * Injected in tests to avoid network calls.
 */
export interface I0GBatcher {
  streamDataBuilder: {
    set(streamId: string, key: Uint8Array, data: Uint8Array): void;
  };
  exec(): Promise<[{ txHash: string; rootHash: string } | null, Error | null]>;
}

/**
 * Factory that creates a fresh Batcher for each save() call.
 * Injected in tests via ZeroGMemoryStoreOptions.batcherFactory.
 */
export type BatcherFactory = () => Promise<I0GBatcher>;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Encode a UTF-8 key as Uint8Array for StreamDataBuilder.set(). */
function encodeKeyBytes(key: string): Uint8Array {
  return new TextEncoder().encode(key);
}

// ---------------------------------------------------------------------------
// Disk-cache helpers (write-through persistence layer)
// ---------------------------------------------------------------------------

function cacheFilePath(stateDir: string, elderIndex: number): string {
  return path.join(stateDir, `elder-${elderIndex}-memory.json`);
}

function readCacheFromDisk(filePath: string): Record<string, string> {
  if (!fs.existsSync(filePath)) return {};
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8')) as Record<string, string>;
  } catch {
    return {};
  }
}

function writeCacheToDisk(filePath: string, data: Record<string, string>): void {
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  // Atomic write: write to tmp then rename (POSIX rename is atomic).
  // Random suffix prevents concurrent-process collisions.
  const suffix = Math.random().toString(36).slice(2);
  const tmpPath = `${filePath}.${suffix}.tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2) + '\n', {
    encoding: 'utf8',
    mode: 0o600,
  });
  fs.renameSync(tmpPath, filePath);
}

// ---------------------------------------------------------------------------
// Named error classes
// ---------------------------------------------------------------------------

export class ZeroGValidationError extends Error {
  constructor(message: string, public readonly code: string) {
    super(message);
    this.name = 'ZeroGValidationError';
  }
}

export class ZeroGTimeoutError extends Error {
  constructor(public readonly operation: string, public readonly timeoutMs: number) {
    super(`${operation} timed out after ${timeoutMs}ms`);
    this.name = 'ZeroGTimeoutError';
  }
}

// ---------------------------------------------------------------------------
// Timeout helper
// ---------------------------------------------------------------------------

/** Wrap a promise with a timeout. Rejects with ZeroGTimeoutError if ms elapses. */
function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timerId = setTimeout(
      () => reject(new ZeroGTimeoutError(label, ms)),
      ms,
    );
    promise.then(
      value => {
        clearTimeout(timerId);
        resolve(value);
      },
      err => {
        clearTimeout(timerId);
        reject(err as Error);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Real Batcher factory
// ---------------------------------------------------------------------------

/**
 * Build a BatcherFactory using the real @0glabs/0g-ts-sdk.
 * Requires ELDER_MNEMONIC, EVM_RPC, INDEXER_RPC, FLOW_CONTRACT.
 *
 * @param env  - env vars (for non-index config like EVM_RPC, ELDER_MNEMONIC)
 * @param elderIndex - already-validated index from createMemoryStore opts — no re-read from env
 */
function buildRealBatcherFactory(
  env: Record<string, string | undefined>,
  elderIndex: number,
): BatcherFactory {
  return async (): Promise<I0GBatcher> => {
    const sdk = await import('@0glabs/0g-ts-sdk') as {
      Batcher: new (
        version: number,
        clients: unknown[],
        flow: unknown,
        provider: string,
      ) => I0GBatcher;
      FixedPriceFlow__factory: {
        connect(address: string, signer: unknown): unknown;
      };
      Indexer: new (url: string) => {
        selectNodes(n: number): Promise<[unknown[], Error | null]>;
      };
    };

    const ethers = await import('ethers');

    const mnemonic = env['ELDER_MNEMONIC'];
    if (!mnemonic) throw new ZeroGValidationError('ELDER_MNEMONIC is required', 'ELDER_MNEMONIC');

    // Use the already-validated elderIndex passed in — never re-read process.env here.
    const index = elderIndex;

    const evmRpc = env['EVM_RPC'] ?? 'https://evmrpc.0g.ai';
    const indexerRpc = env['INDEXER_RPC'] ?? 'https://indexer-storage-turbo.0g.ai';
    const flowContract = env['FLOW_CONTRACT'] ?? '0x62D4144dB0F0a6fBBaeb6296c785C71B3D57C526';

    const provider = new ethers.JsonRpcProvider(evmRpc);
    const wallet = ethers.HDNodeWallet.fromPhrase(
      mnemonic,
      undefined,
      `m/44'/60'/0'/0/${index - 1}`,
    ).connect(provider);

    const indexer = new sdk.Indexer(indexerRpc);
    const [nodes, nodeErr] = await withTimeout(
      indexer.selectNodes(1),
      30_000,
      'Indexer.selectNodes',
    );
    if (nodeErr) throw new Error(`[ZeroGMemoryStore] 0G node selection failed: ${nodeErr.message}`);

    const flow = sdk.FixedPriceFlow__factory.connect(flowContract, wallet);
    return new sdk.Batcher(1, nodes, flow, evmRpc);
  };
}

// ---------------------------------------------------------------------------
// ZeroGMemoryStore
// ---------------------------------------------------------------------------

export class ZeroGMemoryStore implements IElderMemoryStore {
  readonly #streamId: string;
  readonly #batcherFactory: BatcherFactory;
  readonly #cache: Map<string, string>;
  readonly #cacheFilePath: string;

  /**
   * @param streamId      - 0G stream ID (hex hash)
   * @param batcherFactory - factory that creates a fresh Batcher per save()
   * @param initialCache  - pre-loaded cache entries (from disk at startup)
   * @param cacheFilePath - path to persist cache JSON after each successful write
   */
  constructor(
    streamId: string,
    batcherFactory: BatcherFactory,
    initialCache: Record<string, string>,
    cacheFilePath: string,
  ) {
    this.#streamId = streamId;
    this.#batcherFactory = batcherFactory;
    this.#cache = new Map(Object.entries(initialCache));
    this.#cacheFilePath = cacheFilePath;
  }

  /**
   * Read from local cache only.
   * No KvClient / network call — mainnet has no public KV read node.
   */
  async recall(key: string): Promise<string | undefined> {
    return this.#cache.get(key);
  }

  /**
   * Write to 0G via Batcher.exec(), then update local cache + disk.
   *
   * Cache is updated ONLY after a successful 0G write.
   * If exec() throws or returns an error, cache is NOT updated (consistency).
   *
   * @throws on 0G write failure (network, wallet, contract errors).
   */
  async save(key: string, value: string): Promise<void> {
    const batcher = await this.#batcherFactory();

    batcher.streamDataBuilder.set(
      this.#streamId,
      encodeKeyBytes(key),
      new TextEncoder().encode(value),
    );

    const [tx, execErr] = await withTimeout(batcher.exec(), 30_000, 'Batcher.exec');
    if (execErr) throw new Error(`[ZeroGMemoryStore] 0G write failed: ${execErr.message}`);
    if (!tx?.txHash || !tx?.rootHash)
      throw new Error('[ZeroGMemoryStore] 0G write returned no txHash/rootHash');

    console.log(`[ZeroGMemoryStore] save ok key=${key} txHash=${tx.txHash} rootHash=${tx.rootHash}`);

    // Update cache ONLY after successful write.
    this.#cache.set(key, value);
    // Persist to disk so recall() survives restart.
    writeCacheToDisk(this.#cacheFilePath, Object.fromEntries(this.#cache.entries()));
  }

  /**
   * Return full local cache as a plain object.
   * No 0G read needed — cache is hydrated from disk at construction time.
   */
  async snapshot(): Promise<Record<string, string>> {
    return Object.fromEntries(this.#cache.entries());
  }
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

export interface ZeroGMemoryStoreOptions {
  /** Override env lookup for testing. */
  env?: Record<string, string | undefined>;
  /** Override elder index (default: ELDER_INDEX from env). */
  elderIndex?: number;
  /** Clan ID used to derive the default 0G stream namespace. */
  clanId?: string;
  /** Override state dir for the cache file. */
  stateDir?: string;
  /** Override the batcher factory (for testing — avoids real 0G/ethers calls). */
  batcherFactory?: BatcherFactory;
}

/**
 * Create a memory store.
 *
 * - If OG_STORAGE_ENABLED is set → ZeroGMemoryStore backed by 0G mainnet.
 * - Otherwise → FileMemoryStore (local JSON fallback).
 *
 * 0G path reads startup cache from disk (same JSON file as FileMemoryStore)
 * so recall() works immediately without a live 0G read node.
 *
 * @throws if disk cache hydration fails (startup failure is surfaced, not swallowed).
 */
export async function createMemoryStore(
  opts: ZeroGMemoryStoreOptions = {},
): Promise<IElderMemoryStore> {
  const env = opts.env ?? process.env;

  // Fail-fast validation — catch bad env early before any async work.
  // MED 3: strict regex — reject non-integers like "1.5" or "1abc".
  if (opts.elderIndex === undefined) {
    const rawIndex = env['ELDER_INDEX'] ?? '';
    if (!/^[1-4]$/.test(rawIndex.trim())) {
      throw new ZeroGValidationError(
        `ELDER_INDEX must be exactly 1, 2, 3, or 4 — got: "${rawIndex}"`,
        'ELDER_INDEX',
      );
    }
  } else {
    const idx = opts.elderIndex;
    if (!Number.isInteger(idx) || idx < 1 || idx > 4) {
      throw new ZeroGValidationError(
        `ELDER_INDEX must be exactly 1, 2, 3, or 4 — got: "${idx}"`,
        'ELDER_INDEX',
      );
    }
  }

  const enabled = env['OG_STORAGE_ENABLED'];

  // ELDER_MNEMONIC validation gated on OG_STORAGE_ENABLED — local/file mode skips entirely.
  if (enabled) {
    const mnemonic = env['ELDER_MNEMONIC'] ?? '';
    if (!mnemonic.trim()) {
      throw new ZeroGValidationError(
        'ELDER_MNEMONIC is required when OG_STORAGE_ENABLED is set',
        'ELDER_MNEMONIC',
      );
    }
    const words = mnemonic.trim().split(/\s+/);
    if (words.length !== 12 && words.length !== 24) {
      throw new ZeroGValidationError(
        `ELDER_MNEMONIC must be 12 or 24 words, got ${words.length}`,
        'ELDER_MNEMONIC_LENGTH',
      );
    }
  }

  if (!enabled) {
    console.warn(
      '[ZeroGMemoryStore] OG_STORAGE_ENABLED not set — falling back to local JSON file store.',
    );
    const n = opts.elderIndex ?? parseInt(env['ELDER_INDEX'] ?? '1', 10);
    return new FileMemoryStore(n, opts.stateDir ?? defaultStateDir());
  }

  const elderIndex = opts.elderIndex ?? parseInt(env['ELDER_INDEX'] ?? '1', 10);
  const clanId = opts.clanId ?? env[`ELDER_${elderIndex}_CLAN_ID`] ?? String(elderIndex);
  const streamId = env[`OG_STREAM_ID_CLAN_${clanId}`] ?? env['OG_STREAM_ID'];
  const resolvedStreamId = streamId
    ? streamId
    : await (async () => {
        const ethers = await import('ethers');
        return ethers.id(`clanworld:clan:${clanId}:memory`);
      })();

  const stateDirPath = opts.stateDir ?? defaultStateDir();
  const cachePath = cacheFilePath(stateDirPath, elderIndex);

  // Load disk cache — throws on parse failure so operator knows store is broken.
  let initialCache: Record<string, string>;
  if (fs.existsSync(cachePath)) {
    try {
      initialCache = JSON.parse(fs.readFileSync(cachePath, 'utf8')) as Record<string, string>;
    } catch (err) {
      throw new Error(
        `[ZeroGMemoryStore] failed to parse disk cache at ${cachePath}: ${(err as Error).message}`,
      );
    }
  } else {
    initialCache = {};
  }

  const batcherFactory = opts.batcherFactory ?? buildRealBatcherFactory(env, elderIndex);

  return new ZeroGMemoryStore(resolvedStreamId, batcherFactory, initialCache, cachePath);
}
