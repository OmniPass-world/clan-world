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
 * TODO: Production hardening —
 *   - Retry logic on transient AXL POST /send failures.
 *   - Persist dedup Set into IElderMemoryStore so re-delivery across restarts is handled.
 *   - Subscribe via long-poll or WebSocket once AXL exposes a streaming /recv variant.
 *   - Wire AXL_PRIVATE_KEY for ed25519 message signing (current stub trusts local node).
 */
import type { IElderPeerInbox, PeerMessage } from '@clan-world/agents/src/seams/index.js';
import { FilePeerInbox, defaultStateDir } from './filePeerInbox.js';

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
  sentAt: string;
  msgId: string;
  networkId: string;
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

  /**
   * @param myClanId  - the Elder's own clan ID (used for recv routing).
   * @param networkId - AXL network identifier scoping the channel (e.g. "testnet").
   * @param client    - IAxlClient instance (injectable for testing).
   * @param peerIdMap - maps clanId → AXL ed25519 pubkey. Built from env at factory time.
   */
  constructor(
    myClanId: string,
    networkId: string,
    client: IAxlClient,
    peerIdMap: Map<string, string>,
  ) {
    this.#myClanId = myClanId;
    this.#networkId = networkId;
    this.#client = client;
    this.#peerIdMap = peerIdMap;
  }

  async send(toClanId: string, message: string, tick: number): Promise<void> {
    const toPeerId = this.#peerIdMap.get(toClanId);
    if (!toPeerId) {
      throw new Error(
        `[AxlPeerInbox] no AXL peer ID for clanId=${toClanId} — ` +
          `set AXL_PEER_ID_${toClanId.toUpperCase().replace(/-/g, '_')} in env.`,
      );
    }

    // Use crypto random bytes for collision-free msgId even within the same tick+ms.
    const randomSuffix = Math.random().toString(36).slice(2, 10);
    const msgId = `${this.#myClanId}:${tick}:${Date.now()}-${randomSuffix}`;
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

  async inbox(): Promise<PeerMessage[]> {
    // Drain new messages from AXL into the session-local cache.
    // Non-consuming contract: callers always receive the full accumulated inbox (cache + new),
    // not just the latest batch. Consumption is the Elder's responsibility via memory store.
    await this.#drainIntoCache();
    // Return a snapshot — callers must not mutate the returned array.
    return [...this.#inbox];
  }

  /**
   * Pull all pending messages from the AXL recv queue and append to the session inbox cache.
   * Deduplication by (fromClanId, tick, msgId) prevents re-adding on repeated drains.
   * AXL delivers messages FIFO per sender — arrival order preserved.
   */
  async #drainIntoCache(): Promise<void> {
    for (;;) {
      let item: { fromPeerId: string; body: string } | null;
      try {
        item = await this.#client.recv();
      } catch (err) {
        console.warn('[AxlPeerInbox] recv() failed — stopping drain:', err);
        break;
      }
      if (item === null) break; // queue drained

      let envelope: AxlEnvelope;
      try {
        envelope = JSON.parse(item.body) as AxlEnvelope;
      } catch {
        console.warn('[AxlPeerInbox] recv: malformed envelope, skipping body:', item.body.slice(0, 80));
        continue;
      }

      // Filter to our network and our clan inbox.
      if (envelope.networkId !== this.#networkId) continue;
      if (envelope.toClanId !== this.#myClanId) continue;

      // Idempotency: skip duplicates by (fromClanId, tick, msgId).
      const dedupKey = `${envelope.fromClanId}:${envelope.tick}:${envelope.msgId}`;
      if (this.#seenMsgIds.has(dedupKey)) continue;
      this.#seenMsgIds.add(dedupKey);

      this.#inbox.push({
        fromClanId: envelope.fromClanId,
        toClanId: envelope.toClanId,
        message: envelope.message,
        tick: envelope.tick,
        sentAt: envelope.sentAt,
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Factory options + peer-ID map builder
// ---------------------------------------------------------------------------

export interface AxlPeerInboxOptions {
  /** Override env lookup for testing. */
  env?: Record<string, string | undefined>;
  /** Override clan ID (default: derived from ELDER_N + CLAN_IDS env). */
  myClanId?: string;
  /** Override state directory for FilePeerInbox fallback. */
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
    const myClanId = opts.myClanId ?? env['MY_CLAN_ID'] ?? String(elderN);
    return new FilePeerInbox(myClanId, opts.stateDir ?? defaultStateDir());
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

  return new AxlPeerInbox(myClanId, networkId, client, peerIdMap);
}
