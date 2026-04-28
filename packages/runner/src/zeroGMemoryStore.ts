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
import type { IElderMemoryStore } from '@clan-world/agents/src/seams/index.js';
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
  fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2) + '\n', 'utf8');
  fs.renameSync(tmpPath, filePath);
}

// ---------------------------------------------------------------------------
// Timeout helper
// ---------------------------------------------------------------------------

/** Wrap a promise with a timeout. Rejects with a descriptive error if ms elapses. */
function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timerId = setTimeout(
      () => reject(new Error(`${label} timed out after ${ms}ms`)),
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
 * Requires ELDER_MNEMONIC, ELDER_INDEX, EVM_RPC, INDEXER_RPC, FLOW_CONTRACT.
 */
function buildRealBatcherFactory(env: Record<string, string | undefined>): BatcherFactory {
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
    if (!mnemonic) throw new Error('[ZeroGMemoryStore] ELDER_MNEMONIC not set');

    const index = parseInt(env['ELDER_INDEX'] ?? '0', 10);
    if (!index) throw new Error('[ZeroGMemoryStore] ELDER_INDEX not set or zero');

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
  /** Override state dir for the cache file. */
  stateDir?: string;
  /** Override the batcher factory (for testing — avoids real 0G/ethers calls). */
  batcherFactory?: BatcherFactory;
}

/**
 * Create a memory store.
 *
 * - If OG_STORAGE_API_KEY is set → ZeroGMemoryStore backed by 0G mainnet.
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
  const rawIndex = opts.elderIndex ?? parseInt(env['ELDER_INDEX'] ?? '0', 10);
  if (isNaN(rawIndex) || rawIndex < 1 || rawIndex > 4) {
    throw new Error(`ELDER_INDEX must be 1–4, got: ${env['ELDER_INDEX'] ?? opts.elderIndex}`);
  }
  const words = (env['ELDER_MNEMONIC'] ?? '').trim().split(/\s+/);
  if (env['ELDER_MNEMONIC'] !== undefined && words.length !== 12 && words.length !== 24) {
    throw new Error(`ELDER_MNEMONIC must be 12 or 24 words, got: ${words.length}`);
  }

  const apiKey = env['OG_STORAGE_API_KEY'];

  if (!apiKey) {
    console.warn(
      '[ZeroGMemoryStore] OG_STORAGE_API_KEY not set — falling back to local JSON file store.',
    );
    const n = opts.elderIndex ?? parseInt(env['ELDER_INDEX'] ?? env['ELDER_N'] ?? '1', 10);
    return new FileMemoryStore(n, opts.stateDir ?? defaultStateDir());
  }

  const streamId = env['OG_STREAM_ID'];
  const resolvedStreamId = streamId
    ? streamId
    : await (async () => {
        const ethers = await import('ethers');
        return ethers.id('clanworld-elder-memory');
      })();

  const elderIndex = opts.elderIndex ?? parseInt(env['ELDER_INDEX'] ?? env['ELDER_N'] ?? '1', 10);
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

  const batcherFactory = opts.batcherFactory ?? buildRealBatcherFactory(env);

  return new ZeroGMemoryStore(resolvedStreamId, batcherFactory, initialCache, cachePath);
}
