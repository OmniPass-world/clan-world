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
import type { IElderPeerInbox, PeerMessage } from '@clan-world/agents/src/seams/index.js';

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
    this.#myClanId = myClanId;
    this.#stateDir = stateDir;
  }

  async send(toClanId: string, message: string, tick: number): Promise<void> {
    const entry: InboxEntry = {
      fromClanId: this.#myClanId,
      toClanId,
      message,
      tick,
      sentAt: new Date().toISOString(),
      msgId: `${this.#myClanId}:${tick}:${Date.now()}`,
    };
    const file = inboxPath(toClanId, this.#stateDir);
    fs.mkdirSync(path.dirname(file), { recursive: true });

    // Dedup: skip if (fromClanId, tick, msgId) already present.
    if (fs.existsSync(file)) {
      const existing = this.#readLines(file);
      for (const line of existing) {
        try {
          const e = JSON.parse(line) as Partial<InboxEntry>;
          if (
            e.fromClanId === entry.fromClanId &&
            e.tick === entry.tick &&
            e.msgId === entry.msgId
          ) {
            return; // already present
          }
        } catch {
          /* skip malformed line */
        }
      }
    }
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
