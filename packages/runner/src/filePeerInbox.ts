/**
 * FilePeerInbox — S2 file-based implementation of IElderPeerInbox.
 *
 * Stores peer messages as JSONL files at:
 *   <stateDir>/peer-inbox/elder-{clanId}.jsonl
 *
 * - send() appends to the RECIPIENT's JSONL file.
 * - inbox() reads the CALLER's own JSONL file (non-destructive).
 * - Idempotent: deduplicates by (fromClanId, tick, msgId).
 *
 * Used as the fallback when AXL_API_KEY is not set.
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { randomUUID } from 'node:crypto';
import type { IElderPeerInbox, PeerMessage } from '@clan-world/agents/src/seams/index.js';

// MED 5: strict clanId whitelist — alphanumeric, hyphens, underscores, 1-64 chars.
// Prevents path traversal via clanId containing '/' or '..'.
const CLAN_ID_RE = /^[a-zA-Z0-9_-]{1,64}$/;

function assertSafeClanId(clanId: string): void {
  if (!CLAN_ID_RE.test(clanId)) {
    throw new Error(
      `[FilePeerInbox] invalid clanId: ${JSON.stringify(clanId)} — ` +
        `must match /^[a-zA-Z0-9_-]{1,64}$/`,
    );
  }
}

export function defaultStateDir(base: string = os.homedir()): string {
  return path.join(base, '.world', 'clanworld-runner', 'state');
}

function inboxPath(clanId: string, stateDir: string): string {
  return path.join(stateDir, 'peer-inbox', `elder-${clanId}.jsonl`);
}

/** Entry stored on disk (superset of PeerMessage, includes msgId for dedup). */
interface InboxEntry extends PeerMessage {
  msgId: string;
}

export class FilePeerInbox implements IElderPeerInbox {
  readonly #myClanId: string;
  readonly #stateDir: string;

  constructor(myClanId: string, stateDir: string = defaultStateDir()) {
    // MED 5: validate myClanId on construction to catch bad IDs early.
    assertSafeClanId(myClanId);
    this.#myClanId = myClanId;
    this.#stateDir = stateDir;
  }

  async send(toClanId: string, message: string, tick: number): Promise<void> {
    // MED 5: validate toClanId before using in filesystem path.
    assertSafeClanId(toClanId);

    // UUID suffix guarantees a unique msgId — no need to read the file before appending.
    // MED 5: removed O(n) read-before-write; dedup is the inbox reader's responsibility
    // (Elder layer), not the sender's. The UUID suffix makes collision impossible in practice.
    const randomSuffix = randomUUID().slice(0, 8);
    const entry: InboxEntry = {
      fromClanId: this.#myClanId,
      toClanId,
      message,
      tick,
      sentAt: new Date().toISOString(),
      msgId: `${this.#myClanId}:${tick}:${Date.now()}-${randomSuffix}`,
    };
    const file = inboxPath(toClanId, this.#stateDir);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.appendFileSync(file, JSON.stringify(entry) + '\n', 'utf8');
  }

  async inbox(): Promise<PeerMessage[]> {
    const file = inboxPath(this.#myClanId, this.#stateDir);
    if (!fs.existsSync(file)) return [];
    const lines = this.#readLines(file);
    const messages: PeerMessage[] = [];
    const seen = new Set<string>();
    for (const line of lines) {
      try {
        const entry = JSON.parse(line) as InboxEntry;
        const key = `${entry.fromClanId}:${entry.tick}:${entry.msgId ?? ''}`;
        if (!seen.has(key)) {
          seen.add(key);
          const { msgId: _msgId, ...msg } = entry;
          messages.push(msg);
        }
      } catch {
        /* skip malformed line */
      }
    }
    return messages;
  }

  #readLines(file: string): string[] {
    return fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
  }
}
