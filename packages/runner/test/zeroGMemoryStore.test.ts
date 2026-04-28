import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  createMemoryStore,
  ZeroGMemoryStore,
  type I0GKvClient,
  type I0GKvWriter,
  type KvWriterFactory,
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

afterEach(() => {
  for (const d of TMP_DIRS.splice(0)) {
    fs.rmSync(d, { recursive: true, force: true });
  }
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// FileMemoryStore (fallback path)
// ---------------------------------------------------------------------------

describe('FileMemoryStore', () => {
  let stateDir: string;
  let store: FileMemoryStore;

  beforeEach(() => {
    stateDir = path.join(tmpDir(), '.world', 'clanworld-runner', 'state');
    store = new FileMemoryStore(1, stateDir);
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
    const store2 = new FileMemoryStore(1, stateDir);
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
    const sd = path.join(tmpDir(), '.world', 'clanworld-runner', 'state');
    const store = await createMemoryStore({
      env: { ELDER_N: '2' },
      elderN: 2,
      stateDir: sd,
    });
    expect(store).toBeInstanceOf(FileMemoryStore);
  });

  it('fallback store passes recall/save/snapshot contract', async () => {
    const sd = path.join(tmpDir(), '.world', 'clanworld-runner', 'state');
    const store = await createMemoryStore({
      env: { ELDER_N: '1' },
      elderN: 1,
      stateDir: sd,
    });

    expect(await store.recall('x')).toBeUndefined();
    await store.save('x', 'hello');
    expect(await store.recall('x')).toBe('hello');
    const snap = await store.snapshot();
    expect(snap['x']).toBe('hello');
  });
});

// ---------------------------------------------------------------------------
// ZeroGMemoryStore — mocked 0G branch
// ---------------------------------------------------------------------------

function makeKvStore(): Map<string, Uint8Array> {
  return new Map();
}

function makeMockClient(kvStore: Map<string, Uint8Array>): I0GKvClient {
  return {
    // Fix 1: key is now a "0x<hex>" string — decode back to UTF-8 for kvStore lookup.
    getValue: vi.fn(async (_streamId: string, key: string) => {
      const k = Buffer.from(key.replace(/^0x/, ''), 'hex').toString('utf8');
      const data = kvStore.get(k);
      if (data === undefined) return null;
      return { startIndex: BigInt(0), data };
    }),
  };
}

function makeMockWriterFactory(
  kvStore: Map<string, Uint8Array>,
): KvWriterFactory {
  return (_streamId: string): I0GKvWriter => {
    const pending = new Map<Uint8Array, Uint8Array>();
    return {
      set: vi.fn((key: Uint8Array, value: Uint8Array) => {
        pending.set(key, value);
      }),
      exec: vi.fn(async () => {
        for (const [k, v] of pending) {
          kvStore.set(new TextDecoder().decode(k), v);
        }
      }),
    };
  };
}

describe('ZeroGMemoryStore — mocked 0G client', () => {
  const STREAM_ID = 'test-stream-001';
  let kvStore: Map<string, Uint8Array>;
  let mockClient: I0GKvClient;
  let writerFactory: KvWriterFactory;
  let store: ZeroGMemoryStore;

  beforeEach(() => {
    kvStore = makeKvStore();
    mockClient = makeMockClient(kvStore);
    writerFactory = makeMockWriterFactory(kvStore);
    store = new ZeroGMemoryStore(STREAM_ID, mockClient, writerFactory);
  });

  it('recall returns undefined for missing key', async () => {
    expect(await store.recall('unknown')).toBeUndefined();
    // Fix 1: verify getValue receives 0x-hex-encoded key (not raw Uint8Array).
    expect(mockClient.getValue).toHaveBeenCalledOnce();
    const [calledStream, calledKey] = (mockClient.getValue as ReturnType<typeof vi.fn>).mock.calls[0] as [string, string];
    expect(calledStream).toBe(STREAM_ID);
    expect(calledKey).toBe('0x' + Buffer.from('unknown', 'utf8').toString('hex'));
  });

  it('Fix 1 — recall() passes 0x-hex-encoded key to KvClient.getValue', async () => {
    await store.recall('goal');
    const [, calledKey] = (mockClient.getValue as ReturnType<typeof vi.fn>).mock.calls[0] as [string, string];
    const expectedHex = '0x' + Buffer.from('goal', 'utf8').toString('hex');
    expect(calledKey).toBe(expectedHex); // e.g. "0x676f616c"
  });

  it('save calls writer set + exec, then recall returns written value', async () => {
    await store.save('plan', 'hold the line');
    expect(await store.recall('plan')).toBe('hold the line');
    expect(mockClient.getValue).not.toHaveBeenCalled(); // served from write-through cache
  });

  it('recall hits KvClient on cache miss, returns value from 0G', async () => {
    // Pre-populate 0G store directly (simulating external write).
    kvStore.set('external', new TextEncoder().encode('remote value'));
    expect(await store.recall('external')).toBe('remote value');
    expect(mockClient.getValue).toHaveBeenCalledOnce();
  });

  it('snapshot reflects all written keys', async () => {
    await store.save('k1', 'alpha');
    await store.save('k2', 'beta');
    const snap = await store.snapshot();
    expect(snap).toEqual({ k1: 'alpha', k2: 'beta' });
  });

  it('recall does not throw on getValue returning null', async () => {
    await expect(store.recall('absent')).resolves.toBeUndefined();
  });

  it('Fix 2 — recall() re-throws RPC/network errors (error discrimination)', async () => {
    // "Key not found" is signalled by null return (→ undefined), not by throwing.
    // Any exception from getValue is a transport/auth failure and must propagate
    // so callers can distinguish a missing key from a broken store.
    (mockClient.getValue as ReturnType<typeof vi.fn>).mockRejectedValueOnce(new Error('rpc timeout'));
    await expect(store.recall('flaky')).rejects.toThrow('rpc timeout');
  });

  it('save propagates exec() rejection (storage failure throws)', async () => {
    const failWriter: KvWriterFactory = (_sid: string) => ({
      set: vi.fn(),
      exec: vi.fn(async () => { throw new Error('disk full'); }),
    });
    const failStore = new ZeroGMemoryStore(STREAM_ID, mockClient, failWriter);
    await expect(failStore.save('bad', 'val')).rejects.toThrow('disk full');
  });
});

// ---------------------------------------------------------------------------
// createMemoryStore — 0G path (mocked SDK)
// ---------------------------------------------------------------------------

describe('createMemoryStore — 0G path (mocked client)', () => {
  it('returns ZeroGMemoryStore when OG_STORAGE_API_KEY + OG_STREAM_ID are set', async () => {
    const kvStore = makeKvStore();
    const store = await createMemoryStore({
      env: {
        OG_STORAGE_API_KEY: 'test-key',
        OG_STREAM_ID: 'stream-abc',
        OG_KV_RPC: 'http://localhost:9999',
      },
      kvClient: makeMockClient(kvStore),
      kvWriterFactory: makeMockWriterFactory(kvStore),
    });
    expect(store).toBeInstanceOf(ZeroGMemoryStore);
  });

  it('0G store passes recall/save/snapshot contract via mocks', async () => {
    const kvStore = makeKvStore();
    const store = await createMemoryStore({
      env: {
        OG_STORAGE_API_KEY: 'test-key',
        OG_STREAM_ID: 'stream-abc',
      },
      kvClient: makeMockClient(kvStore),
      kvWriterFactory: makeMockWriterFactory(kvStore),
    });

    expect(await store.recall('mission')).toBeUndefined();
    await store.save('mission', 'gather resources');
    expect(await store.recall('mission')).toBe('gather resources');
    const snap = await store.snapshot();
    expect(snap['mission']).toBe('gather resources');
  });

  it('falls back to FileMemoryStore when OG_STREAM_ID is missing', async () => {
    const sd = path.join(tmpDir(), '.world', 'clanworld-runner', 'state');
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const store = await createMemoryStore({
      env: { OG_STORAGE_API_KEY: 'test-key' },
      elderN: 1,
      stateDir: sd,
    });
    expect(store).toBeInstanceOf(FileMemoryStore);
    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('OG_STREAM_ID not set'));
  });
});
