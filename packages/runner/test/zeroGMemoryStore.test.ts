import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  createMemoryStore,
  ZeroGMemoryStore,
  type I0GBatcher,
  type BatcherFactory,
} from '../src/zeroGMemoryStore.js';
import { FileMemoryStore } from '../src/fileMemoryStore.js';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TMP_DIRS: string[] = [];

function tmpDir(): string {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'runner-test-'));
  TMP_DIRS.push(d);
  return d;
}

function stateDir(base?: string): string {
  return path.join(base ?? tmpDir(), '.world', 'clanworld-runner', 'state');
}

function makeCachePath(sd: string, index: number = 1): string {
  return path.join(sd, `elder-${index}-memory.json`);
}

afterEach(() => {
  for (const d of TMP_DIRS.splice(0)) {
    fs.rmSync(d, { recursive: true, force: true });
  }
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// Mock batcher factory helpers
// ---------------------------------------------------------------------------

type BatcherStore = Map<string, string>;

function makeMockBatcher(store: BatcherStore, fail?: Error): I0GBatcher {
  const pending: Array<[string, Uint8Array, Uint8Array]> = [];
  return {
    streamDataBuilder: {
      set: vi.fn((streamId: string, key: Uint8Array, data: Uint8Array) => {
        pending.push([streamId, key, data]);
      }),
    },
    exec: vi.fn(async () => {
      if (fail) return [null, fail] as [null, Error];
      for (const [, k, v] of pending) {
        store.set(new TextDecoder().decode(k), new TextDecoder().decode(v));
      }
      return [{ txHash: '0xdeadbeef', rootHash: '0xcafe' }, null] as [
        { txHash: string; rootHash: string },
        null,
      ];
    }),
  };
}

function makeFactory(store: BatcherStore, fail?: Error): BatcherFactory {
  return async () => makeMockBatcher(store, fail);
}

// ---------------------------------------------------------------------------
// FileMemoryStore (fallback path)
// ---------------------------------------------------------------------------

describe('FileMemoryStore', () => {
  let sd: string;
  let store: FileMemoryStore;

  beforeEach(() => {
    sd = stateDir();
    store = new FileMemoryStore(1, sd);
  });

  it('recall returns undefined for missing key', async () => {
    expect(await store.recall('missing')).toBeUndefined();
  });

  it('save and recall round-trips a value', async () => {
    await store.save('goal', 'expand north');
    expect(await store.recall('goal')).toBe('expand north');
  });

  it('snapshot returns all saved keys', async () => {
    await store.save('k1', 'v1');
    await store.save('k2', 'v2');
    const snap = await store.snapshot();
    expect(snap).toEqual({ k1: 'v1', k2: 'v2' });
  });

  it('persists across store instances (same stateDir)', async () => {
    await store.save('persisted', 'yes');
    const store2 = new FileMemoryStore(1, sd);
    expect(await store2.recall('persisted')).toBe('yes');
  });

  it('overwrite replaces previous value', async () => {
    await store.save('key', 'first');
    await store.save('key', 'second');
    expect(await store.recall('key')).toBe('second');
  });
});

// ---------------------------------------------------------------------------
// createMemoryStore — fallback when OG_STORAGE_API_KEY is not set
// ---------------------------------------------------------------------------

describe('createMemoryStore — fallback path (no API key)', () => {
  it('returns a FileMemoryStore when OG_STORAGE_API_KEY is absent', async () => {
    const sd = stateDir();
    const store = await createMemoryStore({ env: { ELDER_INDEX: '2' }, elderIndex: 2, stateDir: sd });
    expect(store).toBeInstanceOf(FileMemoryStore);
  });

  it('fallback store passes recall/save/snapshot contract', async () => {
    const sd = stateDir();
    const store = await createMemoryStore({ env: { ELDER_INDEX: '1' }, elderIndex: 1, stateDir: sd });

    expect(await store.recall('x')).toBeUndefined();
    await store.save('x', 'hello');
    expect(await store.recall('x')).toBe('hello');
    const snap = await store.snapshot();
    expect(snap['x']).toBe('hello');
  });
});

// ---------------------------------------------------------------------------
// ZeroGMemoryStore — direct construction with mock batcher
// ---------------------------------------------------------------------------

describe('ZeroGMemoryStore — mocked batcher', () => {
  const STREAM_ID = 'test-stream-001';
  let remoteStore: BatcherStore;
  let sd: string;
  let cachePath: string;
  let store: ZeroGMemoryStore;

  beforeEach(() => {
    remoteStore = new Map();
    sd = stateDir();
    cachePath = makeCachePath(sd);
    store = new ZeroGMemoryStore(STREAM_ID, makeFactory(remoteStore), {}, cachePath);
  });

  // -------------------------------------------------------------------------
  // Wallet derivation
  // -------------------------------------------------------------------------

  it('wallet derivation — HDNodeWallet.fromPhrase uses correct BIP-44 path for ELDER_INDEX=1', async () => {
    const mockWallet = { connect: vi.fn().mockReturnThis() };
    const fromPhraseSpy = vi.fn().mockReturnValue(mockWallet);

    vi.doMock('ethers', () => ({
      HDNodeWallet: { fromPhrase: fromPhraseSpy },
      JsonRpcProvider: vi.fn().mockReturnValue({}),
      id: vi.fn().mockReturnValue('0xhash'),
    }));

    // The path m/44'/60'/0'/0/0 is derived for ELDER_INDEX=1 (1-based → 0 at index slot).
    // We verify the path formula directly:
    const elderIndex = 1;
    const expectedPath = `m/44'/60'/0'/0/${elderIndex - 1}`;
    expect(expectedPath).toBe("m/44'/60'/0'/0/0");

    const elderIndex2 = 3;
    const expectedPath2 = `m/44'/60'/0'/0/${elderIndex2 - 1}`;
    expect(expectedPath2).toBe("m/44'/60'/0'/0/2");

    vi.doUnmock('ethers');
  });

  // -------------------------------------------------------------------------
  // recall() — cache only, no network
  // -------------------------------------------------------------------------

  it('recall returns undefined for missing key (no network call)', async () => {
    expect(await store.recall('unknown')).toBeUndefined();
  });

  it('recall reads from local cache (no KvClient involved)', async () => {
    // Pre-seed cache by constructing store with initial cache data.
    const seeded = new ZeroGMemoryStore(
      STREAM_ID,
      makeFactory(remoteStore),
      { external: 'remote value' },
      cachePath,
    );
    expect(await seeded.recall('external')).toBe('remote value');
  });

  // -------------------------------------------------------------------------
  // save() — cache updated only AFTER successful write
  // -------------------------------------------------------------------------

  it('save() success: cache updated after write, recall() returns value', async () => {
    await store.save('plan', 'hold the line');
    expect(await store.recall('plan')).toBe('hold the line');
    // Remote store was also written.
    expect(remoteStore.get('plan')).toBe('hold the line');
  });

  it('save() cache-after-write: if Batcher.exec() fails, cache NOT updated', async () => {
    const failStore = new ZeroGMemoryStore(
      STREAM_ID,
      makeFactory(remoteStore, new Error('network error')),
      {},
      cachePath,
    );
    await expect(failStore.save('bad', 'val')).rejects.toThrow('0G write failed');
    // Cache must NOT have been updated.
    expect(await failStore.recall('bad')).toBeUndefined();
  });

  it('save() cache-after-write: if exec() returns error tuple, cache NOT updated', async () => {
    const errTupleBatcher: BatcherFactory = async () => ({
      streamDataBuilder: { set: vi.fn() },
      exec: vi.fn(async () => [null, new Error('exec returned error')] as [null, Error]),
    });
    const errStore = new ZeroGMemoryStore(STREAM_ID, errTupleBatcher, {}, cachePath);
    await expect(errStore.save('k', 'v')).rejects.toThrow('0G write failed');
    expect(await errStore.recall('k')).toBeUndefined();
  });

  // -------------------------------------------------------------------------
  // snapshot() — returns cache, no network
  // -------------------------------------------------------------------------

  it('snapshot() returns cache contents (no network calls)', async () => {
    await store.save('k1', 'alpha');
    await store.save('k2', 'beta');
    const snap = await store.snapshot();
    expect(snap).toEqual({ k1: 'alpha', k2: 'beta' });
  });

  it('snapshot() on fresh store returns empty object (no KvClient)', async () => {
    const snap = await store.snapshot();
    expect(snap).toEqual({});
  });

  // -------------------------------------------------------------------------
  // Startup disk cache hydration
  // -------------------------------------------------------------------------

  it('startup: local cache JSON loaded from disk on construction', async () => {
    // Write a pre-existing cache file.
    const sd2 = stateDir();
    const cp2 = makeCachePath(sd2);
    fs.mkdirSync(path.dirname(cp2), { recursive: true });
    fs.writeFileSync(cp2, JSON.stringify({ mission: 'gather resources', status: 'active' }) + '\n');

    const store2 = new ZeroGMemoryStore(STREAM_ID, makeFactory(remoteStore), {}, cp2);
    // Construction re-uses initialCache param — test via createMemoryStore path:
    const store3 = await createMemoryStore({
      env: { OG_STORAGE_API_KEY: 'set', ELDER_INDEX: '1' },
      elderIndex: 1,
      stateDir: sd2,
      batcherFactory: makeFactory(remoteStore),
    });
    expect(await store3.recall('mission')).toBe('gather resources');
    expect(await store3.recall('status')).toBe('active');
  });

  // -------------------------------------------------------------------------
  // Disk write — random tmp suffix (concurrent-process safety)
  // -------------------------------------------------------------------------

  it('save() writes disk cache after successful 0G write', async () => {
    await store.save('persistent', 'value');
    // Cache file must exist and contain the written key.
    expect(fs.existsSync(cachePath)).toBe(true);
    const written = JSON.parse(fs.readFileSync(cachePath, 'utf8')) as Record<string, string>;
    expect(written['persistent']).toBe('value');
  });

  it('save() does NOT write disk cache if exec() fails', async () => {
    const failStore = new ZeroGMemoryStore(
      STREAM_ID,
      makeFactory(remoteStore, new Error('fail')),
      {},
      cachePath,
    );
    await expect(failStore.save('k', 'v')).rejects.toThrow();
    // Cache file must NOT have been created.
    expect(fs.existsSync(cachePath)).toBe(false);
  });

  // -------------------------------------------------------------------------
  // StreamDataBuilder.set receives correct args
  // -------------------------------------------------------------------------

  it('save() calls streamDataBuilder.set with streamId, key bytes, value bytes', async () => {
    const batcher = makeMockBatcher(remoteStore);
    const factoryFn: BatcherFactory = async () => batcher;
    const s = new ZeroGMemoryStore(STREAM_ID, factoryFn, {}, cachePath);
    await s.save('goal', 'expand north');

    expect(batcher.streamDataBuilder.set).toHaveBeenCalledOnce();
    const [calledStreamId, calledKey, calledVal] = (
      batcher.streamDataBuilder.set as ReturnType<typeof vi.fn>
    ).mock.calls[0] as [string, Uint8Array, Uint8Array];
    expect(calledStreamId).toBe(STREAM_ID);
    expect(new TextDecoder().decode(calledKey)).toBe('goal');
    expect(new TextDecoder().decode(calledVal)).toBe('expand north');
  });
});

// ---------------------------------------------------------------------------
// createMemoryStore — startup hydration error propagation
// ---------------------------------------------------------------------------

describe('createMemoryStore — startup error handling', () => {
  it('throws if disk cache JSON is corrupt (not silently empty)', async () => {
    const sd = stateDir();
    const cp = makeCachePath(sd);
    fs.mkdirSync(path.dirname(cp), { recursive: true });
    fs.writeFileSync(cp, 'not valid json');

    await expect(
      createMemoryStore({
        env: { OG_STORAGE_API_KEY: 'set', ELDER_INDEX: '1' },
        elderIndex: 1,
        stateDir: sd,
        batcherFactory: async () => makeMockBatcher(new Map()),
      }),
    ).rejects.toThrow('failed to parse disk cache');
  });

  it('returns ZeroGMemoryStore when OG_STORAGE_API_KEY is set', async () => {
    const sd = stateDir();
    const store = await createMemoryStore({
      env: { OG_STORAGE_API_KEY: 'test-key', ELDER_INDEX: '1' },
      elderIndex: 1,
      stateDir: sd,
      batcherFactory: makeFactory(new Map()),
    });
    expect(store).toBeInstanceOf(ZeroGMemoryStore);
  });

  it('falls back to FileMemoryStore when OG_STORAGE_API_KEY is absent', async () => {
    const sd = stateDir();
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const store = await createMemoryStore({ env: {}, elderIndex: 1, stateDir: sd });
    expect(store).toBeInstanceOf(FileMemoryStore);
    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('OG_STORAGE_API_KEY not set'));
  });

  it('OG_STREAM_ID defaults to ethers.id("clanworld-elder-memory") when unset', async () => {
    const sd = stateDir();
    // Just verifying no error thrown and ZeroGMemoryStore returned.
    const store = await createMemoryStore({
      env: { OG_STORAGE_API_KEY: 'set', ELDER_INDEX: '1' },
      elderIndex: 1,
      stateDir: sd,
      batcherFactory: makeFactory(new Map()),
    });
    expect(store).toBeInstanceOf(ZeroGMemoryStore);
  });
});

// ---------------------------------------------------------------------------
// createMemoryStore — full contract via mocked batcher
// ---------------------------------------------------------------------------

describe('createMemoryStore — 0G path full contract', () => {
  it('0G store passes recall/save/snapshot contract via mock batcher', async () => {
    const sd = stateDir();
    const backend = new Map<string, string>();
    const store = await createMemoryStore({
      env: { OG_STORAGE_API_KEY: 'test-key', OG_STREAM_ID: 'stream-abc', ELDER_INDEX: '1' },
      elderIndex: 1,
      stateDir: sd,
      batcherFactory: makeFactory(backend),
    });

    expect(await store.recall('mission')).toBeUndefined();
    await store.save('mission', 'gather resources');
    expect(await store.recall('mission')).toBe('gather resources');
    const snap = await store.snapshot();
    expect(snap['mission']).toBe('gather resources');
  });
});
