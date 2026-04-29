/**
 * AxlPeerInbox — Phase 8 IElderPeerInbox backed by Gensyn AXL peer transport.
 *
 * S2 degrade-gracefully pattern:
 *   - AXL_API_KEY not set OR AXL_NETWORK_ID empty → logs warning, falls back to FilePeerInbox.
 *   - AXL_API_KEY set → uses AxlClient for durable peer messaging.
 *
 * AXL transport model (see https://docs.gensyn.ai/tech/agent-exchange-layer):
 *   - AXL runs as a local sidecar node at 127.0.0.1:9002 (configurable via AXL_NODE_URL).
 *   - send()  → POST /send with X-Destination-Peer-Id header (ed25519 public key of recipient).
 *   - inbox() → GET  /recv polls the inbound FIFO queue; called repeatedly until 204.
 *   - Channel naming: each clan's Elder owns a dedicated AXL keypair;
 *     AXL_PEER_ID_{CLAN_ID} env vars map clanId → ed25519 pubkey for routing.
 *   - AXL_API_KEY is used as the local node's auth token (Bearer) in headers for
 *     managed-node deployments that require it; left empty for pure-local nodes.
 *   - AXL_NETWORK_ID scopes the channel namespace (e.g. "mainnet", "testnet").
 *
 * Idempotency:
 *   - Deduplication by (fromClanId, tick, msgId) is maintained in an in-memory Set.
 *   - The de-dup Set is NOT persisted across runner restarts; for hard exactly-once
 *     semantics, wire IElderMemoryStore to persist seen message IDs.
 *
 * Crash durability:
 *   - inbox() persists drained messages to a JSONL journal file before returning them.
 *   - On construction, the journal is replayed into the in-memory cache so messages
 *     survive runner crashes. The Elder layer is responsible for marking messages as
 *     consumed — the transport must not lose them.
 *
 * TODO: Production hardening —
 *   - Retry logic on transient AXL POST /send failures.
 *   - Persist dedup Set into IElderMemoryStore so re-delivery across restarts is handled.
 *   - Subscribe via long-poll or WebSocket once AXL exposes a streaming /recv variant.
 *   - Wire AXL_PRIVATE_KEY for ed25519 message signing (current stub trusts local node).
 */
import fs from 'node:fs';
import path from 'node:path';
import type { IElderPeerInbox, PeerMessage } from '@clan-world/agents/seams';
import { FilePeerInbox } from './filePeerInbox';
import { defaultStateDir } from './fileMemoryStore';
import { appendRestrictedFileSync } from './restrictedFile';
import { type ElderId } from './types';

// ---------------------------------------------------------------------------
// AXL HTTP client interface
// ---------------------------------------------------------------------------

/**
 * Minimal typed interface for the AXL local node HTTP API.
 *
 * AXL nodes expose a REST API at 127.0.0.1:9002:
 *   POST /send  — fire-and-forget unicast to a peer ed25519 pubkey
 *   GET  /recv  — poll inbound queue (FIFO); returns 204 when empty
 *
 * Typed separately so tests can inject a mock without starting a real AXL node.
 *
 * NOTE: No official npm SDK exists for AXL as of Phase 8 (2026-04-27).
 * AXL is implemented as a Go binary communicating over local HTTP.
 * See https://github.com/gensyn-ai/axl and the API spec at docs/api.md.
 * TODO: Replace with a typed SDK import once Gensyn publishes one to npm.
 */
export interface IAxlClient {
  /**
   * Send a message to a peer identified by their ed25519 public key.
   * Fire-and-forget — AXL does not provide delivery acknowledgement.
   *
   * @param toPeerId  - 64-char hex-encoded ed25519 public key of the recipient node.
   * @param body      - raw message payload (UTF-8 JSON string for our use).
   */
  send(toPeerId: string, body: string): Promise<void>;

  /**
   * Poll the inbound queue for the next message.
   *
   * Returns null if the queue is empty (AXL returns 204 No Content).
   * Returns the message body and sender peer ID otherwise.
   */
  recv(): Promise<{ fromPeerId: string; body: string } | null>;
}

// ---------------------------------------------------------------------------
// AXL wire envelope stored inside message body
// ---------------------------------------------------------------------------

interface AxlEnvelope {
  fromClanId: string;
  toClanId: string;
  message: string;
  tick: number;
  /** ISO 8601 timestamp; optional for forward-compat but validated if present. */
  sentAt?: string | number;
  msgId: string;
  networkId: string;
}

// ---------------------------------------------------------------------------
// Type guard for AxlEnvelope — validates untrusted network input (LOW 6)
// ---------------------------------------------------------------------------

function isAxlEnvelope(val: unknown): val is AxlEnvelope {
  if (typeof val !== 'object' || val === null) return false;
  const obj = val as Record<string, unknown>;
  // Required fields:
  if (
    typeof obj['fromClanId'] !== 'string' ||
    typeof obj['toClanId'] !== 'string' ||
    typeof obj['message'] !== 'string' ||
    typeof obj['tick'] !== 'number' ||
    typeof obj['msgId'] !== 'string' ||
    typeof obj['networkId'] !== 'string'
  ) {
    return false;
  }
  // LOW 6: sentAt is optional but when present must be string or number.
  if (
    obj['sentAt'] !== undefined &&
    typeof obj['sentAt'] !== 'string' &&
    typeof obj['sentAt'] !== 'number'
  ) {
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Clan ID validation — prevents path traversal via myClanId (HIGH 2)
// ---------------------------------------------------------------------------

/** Alphanumeric, hyphens, underscores, 1–64 chars. Same pattern as FilePeerInbox. */
const CLAN_ID_RE = /^[a-zA-Z0-9_-]{1,64}$/;

function assertSafeClanId(clanId: string): void {
  if (!CLAN_ID_RE.test(clanId)) {
    throw new Error(
      `[AxlPeerInbox] invalid clanId: ${JSON.stringify(clanId)} — ` +
        `must match /^[a-zA-Z0-9_-]{1,64}$/`,
    );
  }
}

// ---------------------------------------------------------------------------
// JournalEntry type guard (MED 3)
// ---------------------------------------------------------------------------

function isJournalEntry(val: unknown): val is JournalEntry {
  if (typeof val !== 'object' || val === null) return false;
  const obj = val as Record<string, unknown>;
  // sentAt is required in PeerMessage (string); when present must be string or number.
  if (
    obj['sentAt'] !== undefined &&
    typeof obj['sentAt'] !== 'string' &&
    typeof obj['sentAt'] !== 'number'
  ) {
    return false;
  }
  return (
    typeof obj['fromClanId'] === 'string' &&
    typeof obj['toClanId'] === 'string' &&
    typeof obj['tick'] === 'number' &&
    typeof obj['msgId'] === 'string' &&
    typeof obj['message'] === 'string'
  );
}

// ---------------------------------------------------------------------------
// Real AXL HTTP client
// ---------------------------------------------------------------------------

/**
 * Concrete HTTP client talking to a local AXL node.
 * Requires AXL_NODE_URL (default: http://127.0.0.1:9002).
 */
export class AxlHttpClient implements IAxlClient {
  readonly #baseUrl: string;
  readonly #authHeader: string | undefined;

  constructor(baseUrl: string, apiKey?: string) {
    this.#baseUrl = baseUrl.replace(/\/$/, '');
    this.#authHeader = apiKey ? `Bearer ${apiKey}` : undefined;
  }

  async send(toPeerId: string, body: string): Promise<void> {
    // TODO: When @gensyn/axl-sdk or equivalent ships on npm, replace this
    // hand-rolled fetch with the SDK's typed send() method.
    const headers: Record<string, string> = {
      'Content-Type': 'application/octet-stream',
      'X-Destination-Peer-Id': toPeerId,
    };
    if (this.#authHeader) headers['Authorization'] = this.#authHeader;

    const res = await fetch(`${this.#baseUrl}/send`, {
      method: 'POST',
      headers,
      body: new TextEncoder().encode(body),
    });

    if (!res.ok) {
      throw new Error(`[AxlHttpClient] POST /send failed: ${res.status} ${res.statusText}`);
    }
  }

  async recv(): Promise<{ fromPeerId: string; body: string } | null> {
    // TODO: When @gensyn/axl-sdk ships, use SDK's recv() instead.
    const headers: Record<string, string> = {};
    if (this.#authHeader) headers['Authorization'] = this.#authHeader;

    const res = await fetch(`${this.#baseUrl}/recv`, { headers });

    if (res.status === 204) return null; // queue empty
    if (!res.ok) {
      throw new Error(`[AxlHttpClient] GET /recv failed: ${res.status} ${res.statusText}`);
    }

    const fromPeerId = res.headers.get('X-From-Peer-Id') ?? 'unknown';
    const buf = await res.arrayBuffer();
    const body = new TextDecoder().decode(buf);
    return { fromPeerId, body };
  }
}

// ---------------------------------------------------------------------------
// Journal entry — PeerMessage + msgId, persisted for crash durability
// ---------------------------------------------------------------------------

interface JournalEntry extends PeerMessage {
  msgId: string;
}

// ---------------------------------------------------------------------------
// AxlPeerInbox implementation
// ---------------------------------------------------------------------------

export class AxlPeerInbox implements IElderPeerInbox {
  readonly #myClanId: string;
  readonly #networkId: string;
  readonly #client: IAxlClient;
  readonly #peerIdMap: Map<string, string>;
  readonly #seenMsgIds = new Set<string>();
  /** Session-level inbox cache — holds drained AXL messages so inbox() is non-consuming. */
  readonly #inbox: PeerMessage[] = [];
  /** Journal file path for crash-durability (HIGH 2). */
  readonly #journalPath: string | null;

  /**
   * @param myClanId    - the Elder's own clan ID (used for recv routing).
   * @param networkId   - AXL network identifier scoping the channel (e.g. "testnet").
   * @param client      - IAxlClient instance (injectable for testing).
   * @param peerIdMap   - maps clanId → AXL ed25519 pubkey. Built from env at factory time.
   * @param journalPath - path to persist drained messages for crash recovery. null = memory-only.
   */
  constructor(
    myClanId: string,
    networkId: string,
    client: IAxlClient,
    peerIdMap: Map<string, string>,
    journalPath: string | null = null,
  ) {
    // HIGH 2: validate myClanId before using it in journal path construction.
    assertSafeClanId(myClanId);
    this.#myClanId = myClanId;
    this.#networkId = networkId;
    this.#client = client;
    this.#peerIdMap = peerIdMap;
    this.#journalPath = journalPath;
    // Replay journal into in-memory cache on startup (HIGH 2).
    this.#replayJournal();
  }

  /**
   * Send a whisper to another clan's Elder.
   *
   * A fresh msgId is generated each call via #generateMsgId. For idempotent retry
   * with a stable caller-supplied msgId, IElderPeerInbox would need a sendIdempotent()
   * extension — not included in the Phase 8 interface; tracked for a future phase.
   */
  async send(toClanId: string, message: string, tick: number): Promise<void> {
    // Generate a stable msgId for this invocation.
    const msgId = this.#generateMsgId(tick);
    await this.#sendWithMsgId(toClanId, message, tick, msgId);
  }

  async inbox(): Promise<PeerMessage[]> {
    // Drain new messages from AXL into the session-local cache.
    // Non-consuming contract: callers always receive the full accumulated inbox (cache + new),
    // not just the latest batch. Consumption is the Elder's responsibility via memory store.
    await this.#drainIntoCache();
    // Return a snapshot — callers must not mutate the returned array.
    return [...this.#inbox];
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /** Generate a collision-resistant msgId for a given tick (MED 3 — stable via sendIdempotent). */
  #generateMsgId(tick: number): string {
    const randomSuffix = Math.random().toString(36).slice(2, 10);
    return `${this.#myClanId}:${tick}:${Date.now()}-${randomSuffix}`;
  }

  /** Core send implementation — shared by send() and sendIdempotent(). */
  async #sendWithMsgId(
    toClanId: string,
    message: string,
    tick: number,
    msgId: string,
  ): Promise<void> {
    const toPeerId = this.#peerIdMap.get(toClanId);
    if (!toPeerId) {
      throw new Error(
        `[AxlPeerInbox] no AXL peer ID for clanId=${toClanId} — ` +
          `set AXL_PEER_ID_${toClanId.toUpperCase().replace(/-/g, '_')} in env.`,
      );
    }

    const envelope: AxlEnvelope = {
      fromClanId: this.#myClanId,
      toClanId,
      message,
      tick,
      sentAt: new Date().toISOString(),
      msgId,
      networkId: this.#networkId,
    };

    await this.#client.send(toPeerId, JSON.stringify(envelope));
  }

  /**
   * Pull all pending messages from the AXL recv queue and append to the session inbox cache.
   * Deduplication by (fromClanId, tick, msgId) prevents re-adding on repeated drains.
   * AXL delivers messages FIFO per sender — arrival order preserved.
   *
   * Security: validates envelope.fromClanId against the known peer-to-clan map (HIGH 1).
   * If the AXL fromPeerId doesn't map to the claimed fromClanId, the message is rejected.
   *
   * Crash durability: each accepted message is appended to the journal before being
   * added to the in-memory cache (HIGH 2).
   */
  async #drainIntoCache(): Promise<void> {
    // Build reverse map: peerId → clanId for spoofing validation (HIGH 1).
    const peerToClan = new Map<string, string>();
    for (const [clanId, peerId] of this.#peerIdMap) {
      peerToClan.set(peerId, clanId);
    }

    for (;;) {
      let item: { fromPeerId: string; body: string } | null;
      try {
        item = await this.#client.recv();
      } catch (err) {
        console.warn('[AxlPeerInbox] recv() failed — stopping drain:', err);
        break;
      }
      if (item === null) break; // queue drained

      // LOW 6: validate envelope structure before trusting fields.
      let parsed: unknown;
      try {
        parsed = JSON.parse(item.body);
      } catch {
        console.warn('[AxlPeerInbox] recv: malformed JSON, skipping body:', item.body.slice(0, 80));
        continue;
      }
      if (!isAxlEnvelope(parsed)) {
        console.warn('[AxlPeerInbox] recv: envelope missing required fields, skipping');
        continue;
      }
      const envelope = parsed;

      // HIGH 1: peer spoofing check — fail-CLOSED.
      // If peerIdMap is empty (AXL_PEER_ID_* env vars not set), ALL messages are rejected.
      // Accepting with an empty map would allow any peer to spoof any clanId.
      if (peerToClan.size === 0) {
        console.warn(
          '[AxlPeerInbox] WARN: peerIdMap empty — all inbound messages rejected for security. ' +
            'Set AXL_PEER_ID_* env vars.',
        );
        continue;
      }
      const expectedClanId = peerToClan.get(item.fromPeerId);
      if (expectedClanId === undefined) {
        console.warn(
          `[AxlPeerInbox] recv: unknown fromPeerId=${item.fromPeerId}, rejecting message`,
        );
        continue;
      }
      if (expectedClanId !== envelope.fromClanId) {
        console.warn(
          `[AxlPeerInbox] recv: spoofing detected — ` +
            `fromPeerId=${item.fromPeerId} maps to clan=${expectedClanId} ` +
            `but envelope claims fromClanId=${envelope.fromClanId}. Rejecting.`,
        );
        continue;
      }

      // Filter to our network and our clan inbox.
      if (envelope.networkId !== this.#networkId) continue;
      if (envelope.toClanId !== this.#myClanId) continue;

      // Idempotency: skip duplicates by (fromClanId, tick, msgId).
      const dedupKey = `${envelope.fromClanId}:${envelope.tick}:${envelope.msgId}`;
      if (this.#seenMsgIds.has(dedupKey)) continue;
      this.#seenMsgIds.add(dedupKey);

      const msg: PeerMessage = {
        fromClanId: envelope.fromClanId,
        toClanId: envelope.toClanId,
        message: envelope.message,
        tick: envelope.tick,
        // PR #136 review #11: sentAt is optional in the envelope but required by
        // PeerMessage. Default to receive-time ISO 8601 (was empty string —
        // contract violation that confused Elders during memory recall).
        sentAt: envelope.sentAt !== undefined ? String(envelope.sentAt) : new Date().toISOString(),
      };

      // HIGH 2: persist to journal before adding to in-memory cache.
      // This ensures messages survive a runner crash between drain and Elder processing.
      this.#appendToJournal({ ...msg, msgId: envelope.msgId });

      this.#inbox.push(msg);
    }
  }

  /** Replay the journal file into the in-memory cache on startup (HIGH 2). */
  #replayJournal(): void {
    if (!this.#journalPath || !fs.existsSync(this.#journalPath)) return;
    const lines = fs.readFileSync(this.#journalPath, 'utf8').split('\n').filter(Boolean);
    for (const line of lines) {
      let parsed: unknown;
      try {
        parsed = JSON.parse(line);
      } catch {
        console.warn('[AxlPeerInbox] journal: malformed JSON line — skipping');
        continue;
      }
      // MED 3: type guard — skip corrupt/wrong-shape entries that could poison dedup state.
      if (!isJournalEntry(parsed)) {
        console.warn('[AxlPeerInbox] journal: entry missing required fields — skipping');
        continue;
      }
      const entry = parsed;
      const dedupKey = `${entry.fromClanId}:${entry.tick}:${entry.msgId}`;
      if (this.#seenMsgIds.has(dedupKey)) continue;
      this.#seenMsgIds.add(dedupKey);
      const { msgId: _msgId, ...msg } = entry;
      this.#inbox.push(msg);
    }
  }

  /** Append a single message to the journal file (HIGH 2). */
  #appendToJournal(entry: JournalEntry): void {
    if (!this.#journalPath) return;
    try {
      fs.mkdirSync(path.dirname(this.#journalPath), { recursive: true });
      appendRestrictedFileSync(this.#journalPath, JSON.stringify(entry) + '\n', {
        encoding: 'utf8',
      });
    } catch (err) {
      console.warn('[AxlPeerInbox] journal write failed — crash durability reduced:', err);
    }
  }
}

// ---------------------------------------------------------------------------
// Factory options + peer-ID map builder
// ---------------------------------------------------------------------------

export interface AxlPeerInboxOptions {
  /** Override env lookup for testing. */
  env?: Record<string, string | undefined>;
  /** Elder slot (1..4). Required for FilePeerInbox fallback construction. */
  elder?: ElderId;
  /** Override clan ID (default: derived from ELDER_N + CLAN_IDS env). */
  myClanId?: string;
  /** Override state directory for FilePeerInbox fallback and AXL journal. */
  stateDir?: string;
  /** Override AXL client (for testing). */
  axlClient?: IAxlClient;
  /** Override peer ID map (for testing). */
  peerIdMap?: Map<string, string>;
}

/**
 * Build a Map<clanId, axlPeerId> from env vars following the convention:
 *   AXL_PEER_ID_{CLAN_ID_UPPER_SNAKE} = <64-char hex pubkey>
 *
 * Example:
 *   AXL_PEER_ID_CLAN_IRON=abc123...
 *   AXL_PEER_ID_CLAN_EMBER=def456...
 *
 * Scans all env keys with the AXL_PEER_ID_ prefix.
 */
export function buildPeerIdMap(env: Record<string, string | undefined>): Map<string, string> {
  const map = new Map<string, string>();
  const PREFIX = 'AXL_PEER_ID_';
  for (const [key, val] of Object.entries(env)) {
    if (!key.startsWith(PREFIX) || !val) continue;
    // AXL_PEER_ID_CLAN_IRON → clan-iron
    const clanId = key.slice(PREFIX.length).toLowerCase().replace(/_/g, '-');
    map.set(clanId, val);
  }
  return map;
}

/**
 * Create a peer inbox adapter.
 *
 * - If AXL_API_KEY is present and AXL_NETWORK_ID is non-empty → AxlPeerInbox.
 * - Otherwise → logs a warning and returns FilePeerInbox (file-based fallback).
 */
export async function createPeerInbox(
  opts: AxlPeerInboxOptions = {},
): Promise<IElderPeerInbox> {
  const env = opts.env ?? process.env;
  const apiKey = env['AXL_API_KEY'];
  const networkId = env['AXL_NETWORK_ID'];

  if (!apiKey || !networkId) {
    console.warn(
      '[AxlPeerInbox] AXL_API_KEY or AXL_NETWORK_ID not set — falling back to file-based peer inbox.',
    );
    const elderN = parseInt(env['ELDER_N'] ?? '1', 10);
    const elder = (opts.elder ?? elderN) as ElderId;
    const myClanId = opts.myClanId ?? env['MY_CLAN_ID'] ?? String(elderN);
    return new FilePeerInbox(elder, myClanId, opts.stateDir ?? defaultStateDir());
  }

  const myClanId =
    opts.myClanId ??
    env['MY_CLAN_ID'] ??
    String(parseInt(env['ELDER_N'] ?? '1', 10));

  let client: IAxlClient;
  if (opts.axlClient) {
    client = opts.axlClient;
  } else {
    const nodeUrl = env['AXL_NODE_URL'] ?? 'http://127.0.0.1:9002';
    client = new AxlHttpClient(nodeUrl, apiKey);
  }

  const peerIdMap = opts.peerIdMap ?? buildPeerIdMap(env);
  const stateDir = opts.stateDir ?? defaultStateDir();
  const journalPath = path.join(stateDir, 'peer-inbox', `axl-journal-${myClanId}.jsonl`);

  return new AxlPeerInbox(myClanId, networkId, client, peerIdMap, journalPath);
}
