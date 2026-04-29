import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type { IConvexClient, IChainClient } from '@clan-world/shared/adapters';
import type { WorldSnapshot, ClanFullView, Whisper } from '@clan-world/shared';
import { runCommand, readMemory, writeMemory, UsageError } from '../cli.js';

// Minimal stub factory helpers — only methods the CLI uses
function makeConvex(overrides: Partial<IConvexClient> = {}): IConvexClient {
  return {
    getSnapshot: vi.fn(async () => ({
      tick: 42,
      tickEpoch: { startedAt: 1000, durationMs: 20_000 },
      regions: [],
      clans: [],
    } satisfies WorldSnapshot)),
    getClanFullView: vi.fn(async (clanId: string) => ({
      clan: { id: clanId, name: `Test Clan ${clanId}`, treasury: '100' },
      controlledRegions: [],
      pendingOrders: [],
      whispers: [],
    } satisfies ClanFullView)),
    postLog: vi.fn(async () => {}),
    subscribeWhispers: vi.fn((_clanId: string, _onWhisper: (w: Whisper) => void) => () => {}),
    ...overrides,
  };
}

function makeChain(overrides: Partial<IChainClient> = {}): IChainClient {
  return {
    getCurrentTick: vi.fn(async () => 0),
    submitOrders: vi.fn(async () => ({ txHash: '0xdeadbeef' })),
    getClanFullView: vi.fn(async (clanId: string) => ({
      clan: { id: clanId, name: `Chain Clan ${clanId}`, treasury: '0' },
      controlledRegions: [],
      pendingOrders: [],
      whispers: [],
    } satisfies ClanFullView)),
    ...overrides,
  };
}

const TMP_DIRS: string[] = [];
function tmpHome(): string {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'elder-test-'));
  TMP_DIRS.push(d);
  return d;
}
afterEach(() => {
  for (const d of TMP_DIRS.splice(0)) {
    fs.rmSync(d, { recursive: true, force: true });
  }
});

describe('world snapshot', () => {
  it('returns data from mocked convex client', async () => {
    const convex = makeConvex();
    const out = await runCommand('world', 'snapshot', [], { convex, chain: makeChain() });
    const parsed = JSON.parse(out) as WorldSnapshot;
    expect(parsed.tick).toBe(42);
    expect(convex.getSnapshot).toHaveBeenCalledOnce();
  });
});

describe('clan view', () => {
  it('returns data from mocked convex client', async () => {
    const convex = makeConvex();
    const out = await runCommand('clan', 'view', ['clan-1'], { convex, chain: makeChain() });
    const parsed = JSON.parse(out) as ClanFullView;
    expect(parsed.clan.id).toBe('clan-1');
    expect(convex.getClanFullView).toHaveBeenCalledWith('clan-1');
  });

  it('throws UsageError when clanId is missing', async () => {
    await expect(
      runCommand('clan', 'view', [], { convex: makeConvex(), chain: makeChain() }),
    ).rejects.toBeInstanceOf(UsageError);
  });
});

describe('clan submit-orders', () => {
  it('parses json file and calls chain client', async () => {
    const home = tmpHome();
    const ordersFile = path.join(home, 'orders.json');
    fs.writeFileSync(
      ordersFile,
      JSON.stringify({
        clanId: '1',
        orders: [{ kind: 'mission', payload: { clansmanId: 5, gotoRegion: 2, action: 1 } }],
      }),
    );
    const chain = makeChain();
    const out = await runCommand('clan', 'submit-orders', [ordersFile], {
      convex: makeConvex(),
      chain,
    });
    const result = JSON.parse(out) as { txHash: string };
    expect(result.txHash).toBe('0xdeadbeef');
    expect(chain.submitOrders).toHaveBeenCalledWith('1', expect.arrayContaining([expect.objectContaining({ kind: 'mission' })]));
  });

  it('throws UsageError on malformed orders JSON', async () => {
    const home = tmpHome();
    const file = path.join(home, 'bad.json');
    fs.writeFileSync(file, 'not json');
    await expect(runCommand('clan', 'submit-orders', [file], { convex: makeConvex(), chain: makeChain() })).rejects.toThrow(UsageError);
  });
});

describe('memory save/recall', () => {
  let home: string;
  const env = { ELDER_N: '2' };

  beforeEach(() => {
    home = tmpHome();
  });

  it('round-trips a value', async () => {
    const deps = { convex: makeConvex(), chain: makeChain() };
    await runCommand('memory', 'save', ['plan', 'expand east'], deps, env, home);
    const out = await runCommand('memory', 'recall', ['plan'], deps, env, home);
    expect(out.trim()).toBe('expand east');
  });

  it('reports missing topic', async () => {
    const out = await runCommand('memory', 'recall', ['nonexistent'], { convex: makeConvex(), chain: makeChain() }, env, home);
    expect(out.trim()).toBe('no memory for nonexistent');
  });

  it('persists across readMemory calls', async () => {
    const deps = { convex: makeConvex(), chain: makeChain() };
    await runCommand('memory', 'save', ['key1', 'val1'], deps, env, home);
    await runCommand('memory', 'save', ['key2', 'val2'], deps, env, home);
    const mem = readMemory(2, home);
    expect(mem['key1']).toBe('val1');
    expect(mem['key2']).toBe('val2');
  });

  it('normalizes permissions when saving to an existing memory file', async () => {
    const file = path.join(home, '.world', 'clanworld-runner', 'state', 'elder-2-memory.json');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, '{}\n', { encoding: 'utf8', mode: 0o644 });
    fs.chmodSync(file, 0o644);

    writeMemory(2, { plan: 'expand east' }, home);

    expect(fs.statSync(file).mode & 0o777).toBe(0o600);
  });
});

describe('peer whisper/inbox', () => {
  let home: string;
  const env = { ELDER_N: '3' };

  beforeEach(() => {
    home = tmpHome();
  });

  it('sends whisper to recipient inbox file', async () => {
    const deps = { convex: makeConvex(), chain: makeChain() };
    const whisperOut = await runCommand('peer', 'whisper', ['clan-7', 'hello there'], deps, env, home);
    expect(whisperOut.trim()).toBe('whisper sent');

    // Recipient reads their own inbox (elder-clan-7.jsonl)
    const recipientInbox = path.join(home, '.world', 'clanworld-runner', 'state', 'peer-inbox', 'elder-clan-7.jsonl');
    expect(fs.existsSync(recipientInbox)).toBe(true);
    const content = fs.readFileSync(recipientInbox, 'utf8');
    expect(content).toContain('from":3');
    expect(content).toContain('hello there');
  });

  it('prints inbox empty when no messages', async () => {
    const out = await runCommand('peer', 'inbox', [], { convex: makeConvex(), chain: makeChain() }, env, home);
    expect(out.trim()).toBe('inbox empty');
  });

  it('each recipient gets their own inbox file', async () => {
    const deps = { convex: makeConvex(), chain: makeChain() };
    await runCommand('peer', 'whisper', ['1', 'msg one'], deps, env, home);
    await runCommand('peer', 'whisper', ['2', 'msg two'], deps, env, home);
    const inbox1 = path.join(home, '.world', 'clanworld-runner', 'state', 'peer-inbox', 'elder-1.jsonl');
    const inbox2 = path.join(home, '.world', 'clanworld-runner', 'state', 'peer-inbox', 'elder-2.jsonl');
    expect(fs.existsSync(inbox1)).toBe(true);
    expect(fs.existsSync(inbox2)).toBe(true);
    expect(fs.readFileSync(inbox1, 'utf8')).toContain('msg one');
    expect(fs.readFileSync(inbox2, 'utf8')).toContain('msg two');
  });

  it('peer whisper writes to recipient inbox, not sender inbox', async () => {
    const env1 = { ELDER_N: '1' };
    const deps = { convex: makeConvex(), chain: makeChain() };
    await runCommand('peer', 'whisper', ['2', 'hello'], deps, env1, home);
    // should write to elder-2.jsonl, NOT elder-1.jsonl
    const recipientFile = path.join(home, '.world', 'clanworld-runner', 'state', 'peer-inbox', 'elder-2.jsonl');
    const senderFile = path.join(home, '.world', 'clanworld-runner', 'state', 'peer-inbox', 'elder-1.jsonl');
    expect(fs.existsSync(recipientFile)).toBe(true);
    expect(fs.existsSync(senderFile)).toBe(false);
  });
});

describe('ack-clear', () => {
  let home: string;
  const env = { ELDER_N: '1' };

  beforeEach(() => {
    home = tmpHome();
  });

  it('creates marker file with timestamp', async () => {
    const deps = { convex: makeConvex(), chain: makeChain() };
    const out = await runCommand('ack-clear', undefined, [], deps, env, home);
    expect(out.trim()).toBe('ack cleared');

    const flagPath = path.join(home, '.world', 'clanworld-runner', 'state', 'elder-1-ack.flag');
    expect(fs.existsSync(flagPath)).toBe(true);
    const content = fs.readFileSync(flagPath, 'utf8').trim();
    expect(new Date(content).getTime()).toBeGreaterThan(0);
  });
});

describe('ELDER_N validation', () => {
  const deps = { convex: makeConvex(), chain: makeChain() };

  it('throws UsageError when ELDER_N is missing for memory recall', async () => {
    await expect(runCommand('memory', 'recall', ['topic'], deps, {})).rejects.toThrow(UsageError);
  });

  it('throws UsageError when ELDER_N is out of range', async () => {
    await expect(runCommand('memory', 'recall', ['topic'], deps, { ELDER_N: '5' })).rejects.toThrow(UsageError);
  });
});

describe('unknown command', () => {
  it('throws UsageError', async () => {
    await expect(
      runCommand('unknown', 'cmd', [], { convex: makeConvex(), chain: makeChain() }),
    ).rejects.toBeInstanceOf(UsageError);
  });
});
