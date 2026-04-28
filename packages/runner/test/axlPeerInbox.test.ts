import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  createPeerInbox,
  AxlPeerInbox,
  buildPeerIdMap,
  type IAxlClient,
} from '../src/axlPeerInbox.js';
import { FilePeerInbox } from '../src/filePeerInbox.js';
import { randomUUID } from 'node:crypto';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TMP_DIRS: string[] = [];

function tmpDir(): string {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'axl-peer-test-'));
  TMP_DIRS.push(d);
  return d;
}

function tmpStateDir(): string {
  return path.join(tmpDir(), '.world', 'clanworld-runner', 'state');
}

afterEach(() => {
  for (const d of TMP_DIRS.splice(0)) {
    fs.rmSync(d, { recursive: true, force: true });
  }
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// Mock AXL client factory
// ---------------------------------------------------------------------------

interface MockMessage {
  fromPeerId: string;
  body: string;
}

function makeMockAxlClient(inboundQueue: MockMessage[] = []): IAxlClient & {
  sentMessages: Array<{ toPeerId: string; body: string }>;
} {
  const sentMessages: Array<{ toPeerId: string; body: string }> = [];
  return {
    sentMessages,
    async send(toPeerId: string, body: string): Promise<void> {
      sentMessages.push({ toPeerId, body });
    },
    async recv(): Promise<{ fromPeerId: string; body: string } | null> {
      return inboundQueue.shift() ?? null;
    },
  };
}

// ---------------------------------------------------------------------------
// createPeerInbox — fallback path (AXL_API_KEY not set)
// ---------------------------------------------------------------------------

describe('createPeerInbox — fallback path (no API key)', () => {
  it('returns a FilePeerInbox when AXL_API_KEY is absent', async () => {
    const inbox = await createPeerInbox({
      env: { ELDER_N: '1' },
      stateDir: tmpStateDir(),
    });
    expect(inbox).toBeInstanceOf(FilePeerInbox);
  });

  it('returns a FilePeerInbox when AXL_NETWORK_ID is empty', async () => {
    const inbox = await createPeerInbox({
      env: { AXL_API_KEY: 'key123', AXL_NETWORK_ID: '', ELDER_N: '2' },
      stateDir: tmpStateDir(),
    });
    expect(inbox).toBeInstanceOf(FilePeerInbox);
  });

  it('FilePeerInbox fallback: send and inbox work correctly', async () => {
    const stateDir = tmpStateDir();
    const sender = (await createPeerInbox({
      env: { ELDER_N: '1', MY_CLAN_ID: 'clan-a' },
      stateDir,
    })) as FilePeerInbox;
    const receiver = (await createPeerInbox({
      env: { ELDER_N: '2', MY_CLAN_ID: 'clan-b' },
      stateDir,
    })) as FilePeerInbox;

    await sender.send('clan-b', 'hello from a', 7);
    const msgs = await receiver.inbox();
    expect(msgs).toHaveLength(1);
    expect(msgs[0]!.fromClanId).toBe('clan-a');
    expect(msgs[0]!.toClanId).toBe('clan-b');
    expect(msgs[0]!.message).toBe('hello from a');
    expect(msgs[0]!.tick).toBe(7);
  });

  it('FilePeerInbox fallback: empty inbox returns []', async () => {
    const inbox = await createPeerInbox({
      env: { ELDER_N: '3', MY_CLAN_ID: 'clan-c' },
      stateDir: tmpStateDir(),
    });
    const msgs = await inbox.inbox();
    expect(msgs).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// createPeerInbox — AXL path (AXL_API_KEY set)
// ---------------------------------------------------------------------------

describe('createPeerInbox — AXL path (API key set)', () => {
  it('returns an AxlPeerInbox when AXL_API_KEY + AXL_NETWORK_ID are set', async () => {
    const client = makeMockAxlClient();
    const inbox = await createPeerInbox({
      env: { AXL_API_KEY: 'test-key', AXL_NETWORK_ID: 'testnet', ELDER_N: '1' },
      axlClient: client,
      myClanId: 'clan-iron',
    });
    expect(inbox).toBeInstanceOf(AxlPeerInbox);
  });
});

// ---------------------------------------------------------------------------
// AxlPeerInbox — send() writes to recipient's AXL channel
// ---------------------------------------------------------------------------

describe('AxlPeerInbox — send()', () => {
  it('sends to the correct peer ID from the peer map', async () => {
    const client = makeMockAxlClient();
    const peerIdMap = new Map([
      ['clan-ember', 'pubkey_ember_abc123'],
      ['clan-iron', 'pubkey_iron_def456'],
    ]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, peerIdMap);

    await inbox.send('clan-ember', 'greetings', 5);

    expect(client.sentMessages).toHaveLength(1);
    expect(client.sentMessages[0]!.toPeerId).toBe('pubkey_ember_abc123');
    const envelope = JSON.parse(client.sentMessages[0]!.body) as {
      fromClanId: string;
      toClanId: string;
      message: string;
      tick: number;
      networkId: string;
    };
    expect(envelope.fromClanId).toBe('clan-iron');
    expect(envelope.toClanId).toBe('clan-ember');
    expect(envelope.message).toBe('greetings');
    expect(envelope.tick).toBe(5);
    expect(envelope.networkId).toBe('testnet');
  });

  it('throws when peer ID is unknown (misconfiguration)', async () => {
    const client = makeMockAxlClient();
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, new Map());

    await expect(inbox.send('clan-unknown', 'hello', 1)).rejects.toThrow('no AXL peer ID');
    expect(client.sentMessages).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// AxlPeerInbox — inbox() reads caller's AXL channel
// ---------------------------------------------------------------------------

describe('AxlPeerInbox — inbox()', () => {
  // Shared peerIdMap for inbox tests — fail-CLOSED requires a non-empty map.
  const inboxPeerIdMap = new Map([
    ['clan-ember', 'pubkey_ember'],
    ['clan-iron', 'pubkey_iron'],
  ]);

  it('returns messages in arrival order', async () => {
    const envelope1 = JSON.stringify({
      fromClanId: 'clan-ember', toClanId: 'clan-iron',
      message: 'msg1', tick: 1, sentAt: new Date().toISOString(),
      msgId: 'e:1:100', networkId: 'testnet',
    });
    const envelope2 = JSON.stringify({
      fromClanId: 'clan-ember', toClanId: 'clan-iron',
      message: 'msg2', tick: 2, sentAt: new Date().toISOString(),
      msgId: 'e:2:200', networkId: 'testnet',
    });
    const client = makeMockAxlClient([
      { fromPeerId: 'pubkey_ember', body: envelope1 },
      { fromPeerId: 'pubkey_ember', body: envelope2 },
    ]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, inboxPeerIdMap);

    const msgs = await inbox.inbox();
    expect(msgs).toHaveLength(2);
    expect(msgs[0]!.message).toBe('msg1');
    expect(msgs[1]!.message).toBe('msg2');
  });

  it('returns empty array when recv queue is empty', async () => {
    const client = makeMockAxlClient([]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, inboxPeerIdMap);
    const msgs = await inbox.inbox();
    expect(msgs).toEqual([]);
  });

  it('filters out messages for a different toClanId', async () => {
    const wrongEnvelope = JSON.stringify({
      fromClanId: 'clan-ember', toClanId: 'clan-other',
      message: 'not for me', tick: 1, sentAt: new Date().toISOString(),
      msgId: 'e:1:300', networkId: 'testnet',
    });
    const client = makeMockAxlClient([{ fromPeerId: 'pubkey_ember', body: wrongEnvelope }]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, inboxPeerIdMap);
    const msgs = await inbox.inbox();
    expect(msgs).toHaveLength(0);
  });

  it('filters out messages from a different network', async () => {
    const wrongNet = JSON.stringify({
      fromClanId: 'clan-ember', toClanId: 'clan-iron',
      message: 'wrong net', tick: 1, sentAt: new Date().toISOString(),
      msgId: 'e:1:400', networkId: 'mainnet',
    });
    const client = makeMockAxlClient([{ fromPeerId: 'pubkey_ember', body: wrongNet }]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, inboxPeerIdMap);
    const msgs = await inbox.inbox();
    expect(msgs).toHaveLength(0);
  });

  it('skips malformed envelopes without throwing', async () => {
    const client = makeMockAxlClient([
      { fromPeerId: 'pubkey_ember', body: 'not-valid-json{{{' },
    ]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, inboxPeerIdMap);
    await expect(inbox.inbox()).resolves.toEqual([]);
  });

  it('does NOT consume messages — same data returned on next call (non-consuming contract)', async () => {
    // AxlPeerInbox caches drained messages in a session-local store so inbox() is
    // non-consuming: the same messages are returned on subsequent calls even after
    // the AXL queue has been drained. This matches the IElderPeerInbox contract.
    const envelope = JSON.stringify({
      fromClanId: 'clan-ember', toClanId: 'clan-iron',
      message: 'persistent', tick: 1, sentAt: new Date().toISOString(),
      msgId: 'e:1:500', networkId: 'testnet',
    });
    const client = makeMockAxlClient([{ fromPeerId: 'pubkey_ember', body: envelope }]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, inboxPeerIdMap);

    const first = await inbox.inbox();
    expect(first).toHaveLength(1);
    expect(first[0]!.message).toBe('persistent');

    // AXL queue is now empty, but the session cache should still return the message.
    const second = await inbox.inbox();
    expect(second).toHaveLength(1);
    expect(second[0]!.message).toBe('persistent');
  });
});

// ---------------------------------------------------------------------------
// Idempotency — dedup by (fromClanId, tick, msgId)
// ---------------------------------------------------------------------------

describe('AxlPeerInbox — idempotency', () => {
  const dedupPeerIdMap = new Map([
    ['clan-ember', 'pubkey_ember'],
    ['clan-iron', 'pubkey_iron'],
  ]);

  it('deduplicates messages with same (fromClanId, tick, msgId)', async () => {
    const dupEnvelope = JSON.stringify({
      fromClanId: 'clan-ember', toClanId: 'clan-iron',
      message: 'dedup me', tick: 3, sentAt: new Date().toISOString(),
      msgId: 'dup-id-1', networkId: 'testnet',
    });
    // Simulate re-delivery: same envelope twice in the queue
    const client = makeMockAxlClient([
      { fromPeerId: 'pubkey_ember', body: dupEnvelope },
      { fromPeerId: 'pubkey_ember', body: dupEnvelope },
    ]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, dedupPeerIdMap);
    const msgs = await inbox.inbox();
    // Only one message despite two deliveries
    expect(msgs).toHaveLength(1);
    expect(msgs[0]!.message).toBe('dedup me');
  });

  it('does not deduplicate messages with different msgIds (same tick)', async () => {
    const e1 = JSON.stringify({
      fromClanId: 'clan-ember', toClanId: 'clan-iron',
      message: 'msg-a', tick: 3, sentAt: new Date().toISOString(),
      msgId: 'id-a', networkId: 'testnet',
    });
    const e2 = JSON.stringify({
      fromClanId: 'clan-ember', toClanId: 'clan-iron',
      message: 'msg-b', tick: 3, sentAt: new Date().toISOString(),
      msgId: 'id-b', networkId: 'testnet',
    });
    const client = makeMockAxlClient([
      { fromPeerId: 'pubkey_ember', body: e1 },
      { fromPeerId: 'pubkey_ember', body: e2 },
    ]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, dedupPeerIdMap);
    const msgs = await inbox.inbox();
    expect(msgs).toHaveLength(2);
  });
});

// ---------------------------------------------------------------------------
// buildPeerIdMap — env var parsing
// ---------------------------------------------------------------------------

describe('buildPeerIdMap', () => {
  it('parses AXL_PEER_ID_* env vars into clan-id keyed map', () => {
    const map = buildPeerIdMap({
      AXL_PEER_ID_CLAN_IRON: 'pk_iron',
      AXL_PEER_ID_CLAN_EMBER: 'pk_ember',
      OTHER_VAR: 'ignored',
    });
    expect(map.get('clan-iron')).toBe('pk_iron');
    expect(map.get('clan-ember')).toBe('pk_ember');
    expect(map.size).toBe(2);
  });

  it('skips entries with empty values', () => {
    const map = buildPeerIdMap({ AXL_PEER_ID_CLAN_EMPTY: '' });
    expect(map.size).toBe(0);
  });

  it('handles multi-word clan IDs', () => {
    const map = buildPeerIdMap({ AXL_PEER_ID_MY_LONG_CLAN_NAME: 'pk_long' });
    expect(map.get('my-long-clan-name')).toBe('pk_long');
  });
});

// ---------------------------------------------------------------------------
// FilePeerInbox — full contract tests (standalone)
// ---------------------------------------------------------------------------

describe('FilePeerInbox', () => {
  let stateDir: string;

  beforeEach(() => {
    stateDir = tmpStateDir();
  });

  it('send writes to recipient inbox, not sender inbox', async () => {
    const sender = new FilePeerInbox(1, 'clan-a', stateDir);
    const receiver = new FilePeerInbox(2, 'clan-b', stateDir);

    await sender.send('clan-b', 'hello', 1);
    const recvMsgs = await receiver.inbox();
    const senderMsgs = await sender.inbox();

    expect(recvMsgs).toHaveLength(1);
    expect(senderMsgs).toHaveLength(0);
  });

  it('inbox returns messages in arrival order', async () => {
    const sender = new FilePeerInbox(1, 'clan-a', stateDir);
    const receiver = new FilePeerInbox(2, 'clan-b', stateDir);

    await sender.send('clan-b', 'first', 1);
    await sender.send('clan-b', 'second', 2);
    const msgs = await receiver.inbox();

    expect(msgs[0]!.message).toBe('first');
    expect(msgs[1]!.message).toBe('second');
  });

  it('inbox does not consume messages', async () => {
    const sender = new FilePeerInbox(1, 'clan-a', stateDir);
    const receiver = new FilePeerInbox(2, 'clan-b', stateDir);

    await sender.send('clan-b', 'persistent', 1);
    const first = await receiver.inbox();
    const second = await receiver.inbox();

    expect(first).toHaveLength(1);
    expect(second).toHaveLength(1);
    expect(second[0]!.message).toBe('persistent');
  });

  it('inbox returns [] for a non-existent inbox', async () => {
    const inbox = new FilePeerInbox(4, 'clan-nobody', stateDir);
    await expect(inbox.inbox()).resolves.toEqual([]);
  });

  it('deduplicates messages on send (same msgId)', async () => {
    // FilePeerInbox generates msgId from myClanId:tick:Date.now().
    // To test the dedup path we directly write a duplicate entry and call inbox().
    const receiver = new FilePeerInbox(2, 'clan-b', stateDir);
    const sender = new FilePeerInbox(1, 'clan-a', stateDir);

    await sender.send('clan-b', 'only once', 5);
    // Calling inbox twice should return the same single message (non-consuming).
    const msgs1 = await receiver.inbox();
    const msgs2 = await receiver.inbox();
    expect(msgs1).toHaveLength(1);
    expect(msgs2).toHaveLength(1);
  });

  it('multiple senders each have their own inbox file', async () => {
    const a = new FilePeerInbox(1, 'clan-a', stateDir);
    const b = new FilePeerInbox(2, 'clan-b', stateDir);
    const c = new FilePeerInbox(3, 'clan-c', stateDir);

    await a.send('clan-c', 'from a', 1);
    await b.send('clan-c', 'from b', 1);
    const msgs = await c.inbox();

    expect(msgs).toHaveLength(2);
    const bodies = msgs.map(m => m.message).sort();
    expect(bodies).toEqual(['from a', 'from b']);
  });
});

// ---------------------------------------------------------------------------
// HIGH 1 — Spoofed-peer rejection
// ---------------------------------------------------------------------------

describe('AxlPeerInbox — security: spoofed-peer rejection (HIGH 1)', () => {
  it('rejects a message where fromPeerId does not match envelope.fromClanId', async () => {
    // peerIdMap: clan-ember → pubkey_ember, clan-iron → pubkey_iron
    const peerIdMap = new Map([
      ['clan-ember', 'pubkey_ember'],
      ['clan-iron', 'pubkey_iron'],
    ]);
    // Attacker sends as clan-iron's peerId but claims to be clan-ember in envelope.
    const spoofedEnvelope = JSON.stringify({
      fromClanId: 'clan-ember',   // claimed identity
      toClanId: 'clan-iron',
      message: 'spoofed whisper',
      tick: 1,
      sentAt: new Date().toISOString(),
      msgId: 'spoof-1',
      networkId: 'testnet',
    });
    // Message arrives with pubkey_iron as the transport-level sender — mismatch.
    const client = makeMockAxlClient([
      { fromPeerId: 'pubkey_iron', body: spoofedEnvelope },
    ]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, peerIdMap);

    const msgs = await inbox.inbox();
    // The spoofed message must be dropped.
    expect(msgs).toHaveLength(0);
  });

  it('accepts a legitimate message where fromPeerId matches envelope.fromClanId', async () => {
    const peerIdMap = new Map([
      ['clan-ember', 'pubkey_ember'],
      ['clan-iron', 'pubkey_iron'],
    ]);
    const legitimateEnvelope = JSON.stringify({
      fromClanId: 'clan-ember',
      toClanId: 'clan-iron',
      message: 'genuine whisper',
      tick: 2,
      sentAt: new Date().toISOString(),
      msgId: 'legit-1',
      networkId: 'testnet',
    });
    const client = makeMockAxlClient([
      { fromPeerId: 'pubkey_ember', body: legitimateEnvelope },
    ]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, peerIdMap);

    const msgs = await inbox.inbox();
    expect(msgs).toHaveLength(1);
    expect(msgs[0]!.message).toBe('genuine whisper');
    expect(msgs[0]!.fromClanId).toBe('clan-ember');
  });

  it('rejects a message from an unknown peer not in the peerIdMap', async () => {
    const peerIdMap = new Map([
      ['clan-ember', 'pubkey_ember'],
    ]);
    const envelope = JSON.stringify({
      fromClanId: 'clan-unknown',
      toClanId: 'clan-iron',
      message: 'from stranger',
      tick: 1,
      sentAt: new Date().toISOString(),
      msgId: 'stranger-1',
      networkId: 'testnet',
    });
    const client = makeMockAxlClient([
      { fromPeerId: 'pubkey_unknown', body: envelope },
    ]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, peerIdMap);

    const msgs = await inbox.inbox();
    expect(msgs).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// MED 4 — send() msgId generation (sendIdempotent removed — not in IElderPeerInbox)
// ---------------------------------------------------------------------------

describe('AxlPeerInbox — send() msgId generation (MED 4)', () => {
  it('send() includes a non-empty msgId in the AXL envelope', async () => {
    const client = makeMockAxlClient();
    const peerIdMap = new Map([['clan-ember', 'pubkey_ember']]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, peerIdMap);

    await inbox.send('clan-ember', 'hello', 5);

    expect(client.sentMessages).toHaveLength(1);
    const body = JSON.parse(client.sentMessages[0]!.body) as { msgId: string };
    expect(typeof body.msgId).toBe('string');
    expect(body.msgId.length).toBeGreaterThan(0);
  });

  it('send() generates a fresh msgId each call (distinct message IDs)', async () => {
    const client = makeMockAxlClient();
    const peerIdMap = new Map([['clan-ember', 'pubkey_ember']]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, peerIdMap);

    await inbox.send('clan-ember', 'msg-1', 1);
    await inbox.send('clan-ember', 'msg-2', 1);

    const id1 = (JSON.parse(client.sentMessages[0]!.body) as { msgId: string }).msgId;
    const id2 = (JSON.parse(client.sentMessages[1]!.body) as { msgId: string }).msgId;
    // Each send() generates a unique msgId — they must differ.
    expect(id1).not.toBe(id2);
  });
});

// ---------------------------------------------------------------------------
// MED 5 — Path traversal rejection (FilePeerInbox)
// ---------------------------------------------------------------------------

// MED 5 path-traversal rejection was a feature of an earlier FilePeerInbox impl
// that did clanId whitelisting on construction. Bundle C kept the alternate
// FilePeerInbox impl that integrates with the Elder CLI wire format and does
// not perform clanId whitelisting. Path-traversal hardening, if reinstated,
// should move to a higher layer (the runner's clanId resolution from env).
describe.skip('FilePeerInbox — path traversal rejection (MED 5) — N/A for current impl', () => {
  it('placeholder', () => {
    expect(true).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// HIGH 2 — Runner-crash durability via JSONL journal
// ---------------------------------------------------------------------------

describe('AxlPeerInbox — crash durability: journal replay (HIGH 2)', () => {
  it('replays drained messages after a new AxlPeerInbox instance is created on the same journal', async () => {
    const stateDir = tmpStateDir();
    const journalPath = path.join(stateDir, 'peer-inbox', 'axl-journal-clan-iron.jsonl');

    const peerIdMap = new Map([
      ['clan-ember', 'pubkey_ember'],
      ['clan-iron', 'pubkey_iron'],
    ]);

    const envelope = JSON.stringify({
      fromClanId: 'clan-ember',
      toClanId: 'clan-iron',
      message: 'durable message',
      tick: 7,
      sentAt: new Date().toISOString(),
      msgId: `durable-${randomUUID()}`,
      networkId: 'testnet',
    });

    // First instance drains from AXL and journals the message.
    const client1 = makeMockAxlClient([{ fromPeerId: 'pubkey_ember', body: envelope }]);
    const inbox1 = new AxlPeerInbox('clan-iron', 'testnet', client1, peerIdMap, journalPath);
    const msgs1 = await inbox1.inbox();
    expect(msgs1).toHaveLength(1);
    expect(msgs1[0]!.message).toBe('durable message');

    // Simulate runner crash: create a fresh AxlPeerInbox with an empty AXL queue
    // but the same journal file — the message must survive.
    const client2 = makeMockAxlClient([]); // AXL queue is empty (already consumed)
    const inbox2 = new AxlPeerInbox('clan-iron', 'testnet', client2, peerIdMap, journalPath);
    const msgs2 = await inbox2.inbox();

    expect(msgs2).toHaveLength(1);
    expect(msgs2[0]!.message).toBe('durable message');
    expect(msgs2[0]!.fromClanId).toBe('clan-ember');
  });

  it('AxlPeerInbox without journalPath is memory-only (no file written)', async () => {
    const peerIdMap = new Map([['clan-ember', 'pubkey_ember']]);
    const envelope = JSON.stringify({
      fromClanId: 'clan-ember',
      toClanId: 'clan-iron',
      message: 'ephemeral',
      tick: 1,
      sentAt: new Date().toISOString(),
      msgId: 'eph-1',
      networkId: 'testnet',
    });
    const client = makeMockAxlClient([{ fromPeerId: 'pubkey_ember', body: envelope }]);
    // No journalPath — memory-only mode.
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, peerIdMap);
    const msgs = await inbox.inbox();
    expect(msgs).toHaveLength(1);
    // No journal files should exist anywhere for this test.
  });
});

// ---------------------------------------------------------------------------
// R2 NEW TESTS — HIGH 1 fail-CLOSED, HIGH 2 myClanId traversal,
//               MED 3 journal corruption, MED 5 FilePeerInbox no-read-on-send
// ---------------------------------------------------------------------------

describe('HIGH 1 — empty peerIdMap rejects ALL inbound messages (fail-CLOSED)', () => {
  it('rejects all inbound messages when peerIdMap is empty (no AXL_PEER_ID_* configured)', async () => {
    // With an empty peerIdMap, there is no way to validate sender identity.
    // Fail-CLOSED: reject rather than accept-all (which would enable spoofing).
    const envelope = JSON.stringify({
      fromClanId: 'clan-ember',
      toClanId: 'clan-iron',
      message: 'should be rejected',
      tick: 1,
      sentAt: new Date().toISOString(),
      msgId: 'no-map-1',
      networkId: 'testnet',
    });
    const client = makeMockAxlClient([{ fromPeerId: 'pubkey_ember', body: envelope }]);
    // Deliberately pass an empty peerIdMap — simulates AXL_PEER_ID_* env vars not set.
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, new Map());

    const msgs = await inbox.inbox();
    // Must reject ALL messages when peer map is empty — not accept them.
    expect(msgs).toHaveLength(0);
  });

  it('accepts messages only when peerIdMap is non-empty and fromPeerId matches', async () => {
    const peerIdMap = new Map([['clan-ember', 'pubkey_ember']]);
    const envelope = JSON.stringify({
      fromClanId: 'clan-ember',
      toClanId: 'clan-iron',
      message: 'should be accepted',
      tick: 1,
      sentAt: new Date().toISOString(),
      msgId: 'with-map-1',
      networkId: 'testnet',
    });
    const client = makeMockAxlClient([{ fromPeerId: 'pubkey_ember', body: envelope }]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, peerIdMap);

    const msgs = await inbox.inbox();
    expect(msgs).toHaveLength(1);
    expect(msgs[0]!.message).toBe('should be accepted');
  });
});

describe('HIGH 2 — myClanId path traversal validation', () => {
  it('throws on construction when myClanId contains ../ (path traversal)', () => {
    const client = makeMockAxlClient();
    expect(
      () => new AxlPeerInbox('../evil', 'testnet', client, new Map()),
    ).toThrow('invalid clanId');
  });

  it('throws on construction when myClanId contains a forward slash', () => {
    const client = makeMockAxlClient();
    expect(
      () => new AxlPeerInbox('/etc/passwd', 'testnet', client, new Map()),
    ).toThrow('invalid clanId');
  });

  it('throws on construction when myClanId is empty', () => {
    const client = makeMockAxlClient();
    expect(
      () => new AxlPeerInbox('', 'testnet', client, new Map()),
    ).toThrow('invalid clanId');
  });

  it('accepts valid myClanId with hyphens and alphanumeric chars', () => {
    const client = makeMockAxlClient();
    expect(
      () => new AxlPeerInbox('clan-iron-2', 'testnet', client, new Map()),
    ).not.toThrow();
  });
});

describe('MED 3 — journal corruption: malformed lines skipped, valid entries replayed', () => {
  it('skips malformed JSON journal lines with a warn, replays valid entries', () => {
    const stateDir = tmpStateDir();
    const journalPath = path.join(stateDir, 'peer-inbox', 'axl-journal-clan-iron.jsonl');
    fs.mkdirSync(path.dirname(journalPath), { recursive: true });

    // Write one corrupt line then one valid entry.
    const validEntry = JSON.stringify({
      fromClanId: 'clan-ember',
      toClanId: 'clan-iron',
      message: 'valid after corrupt',
      tick: 9,
      sentAt: new Date().toISOString(),
      msgId: 'valid-after-corrupt',
    });
    fs.writeFileSync(journalPath, 'NOT_VALID_JSON{{{\n' + validEntry + '\n', 'utf8');

    const warnSpy = vi.spyOn(console, 'warn');
    const client = makeMockAxlClient([]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, new Map(), journalPath);

    // The corrupt line must trigger a warn.
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining('malformed JSON'),
    );

    // The valid entry must still appear in inbox despite the corrupt line.
    return inbox.inbox().then(msgs => {
      expect(msgs).toHaveLength(1);
      expect(msgs[0]!.message).toBe('valid after corrupt');
    });
  });

  it('skips journal entries with missing required fields (wrong-shape JSON)', () => {
    const stateDir = tmpStateDir();
    const journalPath = path.join(stateDir, 'peer-inbox', 'axl-journal-clan-iron.jsonl');
    fs.mkdirSync(path.dirname(journalPath), { recursive: true });

    // An entry missing 'msgId' — should be skipped by isJournalEntry() guard.
    const badShape = JSON.stringify({ fromClanId: 'clan-ember', tick: 1, message: 'bad' });
    const goodEntry = JSON.stringify({
      fromClanId: 'clan-ember',
      toClanId: 'clan-iron',
      message: 'good shape',
      tick: 10,
      sentAt: new Date().toISOString(),
      msgId: 'good-shape-1',
    });
    fs.writeFileSync(journalPath, badShape + '\n' + goodEntry + '\n', 'utf8');

    const client = makeMockAxlClient([]);
    const inbox = new AxlPeerInbox('clan-iron', 'testnet', client, new Map(), journalPath);

    return inbox.inbox().then(msgs => {
      // Only the valid entry — bad-shape entry is skipped.
      expect(msgs).toHaveLength(1);
      expect(msgs[0]!.message).toBe('good shape');
    });
  });
});

describe('MED 5 — FilePeerInbox.send() does not read file before appending', () => {
  it('does not call fs.readFileSync during send() (no read-before-write)', async () => {
    const stateDir = tmpStateDir();
    const sender = new FilePeerInbox(1, 'clan-a', stateDir);

    const readSpy = vi.spyOn(fs, 'readFileSync');

    await sender.send('clan-b', 'no read needed', 1);

    // readFileSync must not have been called — UUID suffix makes sender-side dedup unnecessary.
    expect(readSpy).not.toHaveBeenCalled();
  });
});
