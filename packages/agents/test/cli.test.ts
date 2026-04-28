import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type { IConvexClient, IChainClient } from '@clan-world/shared/adapters';
import type { WorldSnapshot, ClanFullView, Whisper, Tick } from '@clan-world/shared';
import { runCommand, UsageError, inboxFile, recipientInboxFile, ackFile } from '../src/cli.js';

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const STUB_SNAPSHOT: WorldSnapshot = {
  tick: 7,
  tickEpoch: { startedAt: 1700000000, durationMs: 60000 },
  regions: [{ id: 'r1', name: 'Forest', ownerClanId: '1' }],
  clans: [{ id: '1', name: 'Wolfclan', treasury: '1000' }],
};

const STUB_CLAN_VIEW: ClanFullView = {
  clan: { id: '1', name: 'Wolfclan', treasury: '1000' },
  controlledRegions: [{ id: 'r1', name: 'Forest', ownerClanId: '1' }],
  pendingOrders: [],
  whispers: [],
};

// ---------------------------------------------------------------------------
// Stub factories
// ---------------------------------------------------------------------------

function makeConvex(overrides: Partial<IConvexClient> = {}): IConvexClient {
  return {
    async getSnapshot() { return STUB_SNAPSHOT; },
    async getClanFullView() { return STUB_CLAN_VIEW; },
    async postLog() {},
    subscribeWhispers(_clanId: string, _onWhisper: (w: Whisper) => void): () => void { return () => {}; },
    ...overrides,
  };
}

function makeChain(overrides: Partial<IChainClient> = {}): IChainClient {
  return {
    async submitOrders() { return { txHash: '0xdeadbeef' }; },
    async getCurrentTick(): Promise<Tick> { return 0; },
    async getClanFullView(clanId: string): Promise<ClanFullView> {
      return {
        clan: { id: clanId, name: `chain-${clanId}`, treasury: '0' },
        controlledRegions: [],
        pendingOrders: [],
        whispers: [],
      };
    },
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Test setup
// ---------------------------------------------------------------------------

let tmpDir: string;
let deps: { convex: ReturnType<typeof makeConvex>; chain: ReturnType<typeof makeChain> };

beforeEach(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'elder-cli-test-'));
  deps = { convex: makeConvex(), chain: makeChain() };
});

afterEach(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// world snapshot
// ---------------------------------------------------------------------------

describe('world snapshot', () => {
  it('returns JSON-parseable WorldSnapshot with correct tick', async () => {
    const out = await runCommand('world', 'snapshot', [], deps, {}, tmpDir);
    const parsed = JSON.parse(out) as WorldSnapshot;
    expect(parsed.tick).toBe(7);
    expect(parsed.regions).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// clan view
// ---------------------------------------------------------------------------

describe('clan view', () => {
  it('returns ClanFullView with correct clan name', async () => {
    const out = await runCommand('clan', 'view', ['1'], deps, {}, tmpDir);
    const parsed = JSON.parse(out) as ClanFullView;
    expect(parsed.clan.name).toBe('Wolfclan');
    expect(parsed.clan.id).toBe('1');
  });

  it('throws UsageError when clanId is missing', async () => {
    await expect(
      runCommand('clan', 'view', [], deps, {}, tmpDir),
    ).rejects.toBeInstanceOf(UsageError);
  });
});

// ---------------------------------------------------------------------------
// clan submit-orders
// ---------------------------------------------------------------------------

describe('clan submit-orders', () => {
  it('reads orders file, calls chain.submitOrders, returns txHash', async () => {
    const ordersFile = path.join(tmpDir, 'orders.json');
    fs.writeFileSync(ordersFile, JSON.stringify({ clanId: '1', orders: [{ kind: 'mission', payload: {} }] }));
    const out = await runCommand('clan', 'submit-orders', [ordersFile], deps, {}, tmpDir);
    expect(out).toContain('0xdeadbeef');
  });

  it('throws UsageError when file does not exist', async () => {
    await expect(
      runCommand('clan', 'submit-orders', [path.join(tmpDir, 'no-such-file.json')], deps, {}, tmpDir),
    ).rejects.toBeInstanceOf(UsageError);
  });

  it('throws UsageError on bad JSON', async () => {
    const badFile = path.join(tmpDir, 'bad.json');
    fs.writeFileSync(badFile, 'not valid json {{');
    await expect(
      runCommand('clan', 'submit-orders', [badFile], deps, {}, tmpDir),
    ).rejects.toBeInstanceOf(UsageError);
  });

  it('throws UsageError when clanId is missing from file', async () => {
    const ordersFile = path.join(tmpDir, 'orders.json');
    fs.writeFileSync(ordersFile, JSON.stringify({ orders: [{ kind: 'mission', payload: {} }] }));
    await expect(
      runCommand('clan', 'submit-orders', [ordersFile], deps, {}, tmpDir),
    ).rejects.toBeInstanceOf(UsageError);
  });

  it('throws UsageError when orders is not an array', async () => {
    const ordersFile = path.join(tmpDir, 'orders.json');
    fs.writeFileSync(ordersFile, JSON.stringify({ clanId: '1', orders: 'not-an-array' }));
    await expect(
      runCommand('clan', 'submit-orders', [ordersFile], deps, {}, tmpDir),
    ).rejects.toBeInstanceOf(UsageError);
  });
});

// ---------------------------------------------------------------------------
// memory recall / save
// ---------------------------------------------------------------------------

describe('memory recall/save', () => {
  const env = { ELDER_N: '1' };

  it('recall with no saved memory returns "no memory for <key>"', async () => {
    const out = await runCommand('memory', 'recall', ['strategy'], deps, env, tmpDir);
    expect(out).toBe('no memory for strategy\n');
  });

  it('save + recall round-trips value (including multi-word)', async () => {
    await runCommand('memory', 'save', ['plan', 'expand', 'east', 'now'], deps, env, tmpDir);
    const out = await runCommand('memory', 'recall', ['plan'], deps, env, tmpDir);
    expect(out.trim()).toBe('expand east now');
  });

  it('throws UsageError when topic is missing from recall', async () => {
    await expect(
      runCommand('memory', 'recall', [], deps, env, tmpDir),
    ).rejects.toBeInstanceOf(UsageError);
  });

  it('throws UsageError when value is missing from save', async () => {
    await expect(
      runCommand('memory', 'save', ['key'], deps, env, tmpDir),
    ).rejects.toBeInstanceOf(UsageError);
  });
});

// ---------------------------------------------------------------------------
// peer whisper
// ---------------------------------------------------------------------------

describe('peer whisper', () => {
  it('writes JSON line to recipientInboxFile with correct from/to/msg', async () => {
    await runCommand('peer', 'whisper', ['5', 'attack at dawn'], deps, { ELDER_N: '2' }, tmpDir);

    const file = recipientInboxFile('5', tmpDir);
    expect(fs.existsSync(file)).toBe(true);

    const line = fs.readFileSync(file, 'utf8').trim();
    const entry = JSON.parse(line) as { from: number; to: string; msg: string };
    expect(entry.from).toBe(2);
    expect(entry.to).toBe('5');
    expect(entry.msg).toBe('attack at dawn');
  });
});

// ---------------------------------------------------------------------------
// peer inbox
// ---------------------------------------------------------------------------

describe('peer inbox', () => {
  it('returns "inbox empty" when no messages', async () => {
    const out = await runCommand('peer', 'inbox', [], deps, { ELDER_N: '1' }, tmpDir);
    expect(out).toBe('inbox empty\n');
  });

  it('returns formatted message line after whisper written to own inbox', async () => {
    // Write a whisper entry directly to elder-1's inbox (ELDER_N=1 reads elder-1.jsonl)
    const inboxPath = inboxFile(1, tmpDir);
    fs.mkdirSync(path.dirname(inboxPath), { recursive: true });
    const entry = JSON.stringify({ from: 2, to: '1', msg: 'hello from elder 2', ts: '2024-01-01T00:00:00.000Z' });
    fs.writeFileSync(inboxPath, entry + '\n', 'utf8');

    const out = await runCommand('peer', 'inbox', [], deps, { ELDER_N: '1' }, tmpDir);
    expect(out).toContain('from=2');
    expect(out).toContain('hello from elder 2');
  });
});

// ---------------------------------------------------------------------------
// ack-clear
// ---------------------------------------------------------------------------

describe('ack-clear', () => {
  it('writes the ack flag file and returns "ack cleared"', async () => {
    const out = await runCommand('ack-clear', undefined, [], deps, { ELDER_N: '1' }, tmpDir);
    expect(out).toBe('ack cleared\n');

    const flagPath = ackFile(1, tmpDir);
    expect(fs.existsSync(flagPath)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// unknown command
// ---------------------------------------------------------------------------

describe('unknown command', () => {
  it('throws UsageError with usage text', async () => {
    await expect(
      runCommand('mystery', 'cmd', [], deps, {}, tmpDir),
    ).rejects.toBeInstanceOf(UsageError);

    try {
      await runCommand('mystery', 'cmd', [], deps, {}, tmpDir);
    } catch (err) {
      expect(err).toBeInstanceOf(UsageError);
      expect((err as UsageError).message).toContain('usage:');
    }
  });
});

// ---------------------------------------------------------------------------
// Issue #94 regression: peer whisper/inbox desync when ELDER_N != clanId
// ---------------------------------------------------------------------------

describe('issue #94 regression — peer whisper/inbox desync', () => {
  it('demonstrates desync when ELDER_N != clanId', async () => {
    // Issue #94: inbox reads by ELDER_N, whisper writes by clanId.
    // Round-trip works only when clanId === String(elderN) (S2 default).
    // Fix tracked in issue #94.

    // Elder 2 whispers to clan "5" (which is NOT elder 5's default clanId in S2 1:1 mapping)
    await runCommand('peer', 'whisper', ['5', 'hello'], deps, { ELDER_N: '2' }, tmpDir);

    // Whisper written to elder-5.jsonl (keyed by recipient clanId)
    expect(fs.existsSync(recipientInboxFile('5', tmpDir))).toBe(true);

    // But peer inbox for ELDER_N=1 reads elder-1.jsonl — NOT elder-5.jsonl
    // If elder 1's actual clanId were "5", it would miss this whisper
    const out = await runCommand('peer', 'inbox', [], deps, { ELDER_N: '1' }, tmpDir);
    expect(out).toBe('inbox empty\n');

    // Document: fix tracked in issue #94 (option A: ELDER_CLAN_ID env + read by clanId)
  });
});
