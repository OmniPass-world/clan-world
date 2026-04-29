import fs from 'node:fs';
import path from 'node:path';
import type { IElderPeerInbox, PeerMessage } from '@clan-world/agents/seams';
import { assertSafeInboxKey } from '@clan-world/shared';
import { ELDER_IDS, type ElderId } from './types';

/**
 * S2 stub of `IElderPeerInbox` backed by per-recipient JSONL files.
 *
 * File layout: `${stateDir}/peer-inbox/elder-{recipient}.jsonl`
 *
 * Each line is a JSON-encoded `PeerMessage`. Append-only; consumption is the
 * Elder's responsibility (it tracks last-read offset in its own memory store).
 *
 * Wire format on disk MATCHES the format the Elder CLI's `peer whisper`
 * command writes (see `packages/agents/src/cli.ts`):
 *   {from: number, to: string, msg: string, ts: string}
 * We translate to/from the seam's `PeerMessage` shape inside `parseLine()`
 * (called from `inbox()`), so the runner-side and Elder-side writers stay
 * file-compatible.
 *
 * Idempotency note: per the seam contract, dedup is OPTIONAL ("implementations
 * that guarantee exactly-once must deduplicate by (fromClanId, tick, msgId)").
 * This S2 stub does NOT dedup — `send()` always appends. Callers that need
 * exactly-once must dedup at the consumer side, or wrap this in a dedup layer.
 *
 * Routing note: reads use `ELDER_N`, matching the CLI's `peer inbox` reader
 * (`inboxFile(n)`). Writes resolve recipient clan ids through `ELDER_{N}_CLAN_ID`
 * env mappings when present, so non-default mappings still land on the same
 * elder-N inbox key.
 */
export class FilePeerInbox implements IElderPeerInbox {
  private readonly inboxDir: string;
  private readonly ownClanId: string;
  private readonly elderN: string;

  constructor(elder: ElderId, ownClanId: string, stateDir: string) {
    this.inboxDir = path.join(stateDir, 'peer-inbox');
    this.ownClanId = ownClanId;
    // Resolve own inbox key. Priority (changed 2026-04-28 — PR #136 review #3):
    //   1. process.env.ELDER_N — ONLY if it matches String(elder). This preserves
    //      CLI compatibility (single process with ELDER_N=N + elder=N) while
    //      preventing the multi-elder cross-talk bug (4 instances spawned by
    //      main.ts each see ELDER_N=1 from .env.local but have distinct elder
    //      args 1-4 — only instance 1 takes ELDER_N's path; 2/3/4 ignore it).
    //   2. inboxKeyForClanId(ownClanId) — uses ELDER_${slot}_CLAN_ID mappings
    //      when set (runner mode); falls through to ownClanId verbatim for
    //      tests with raw clan ids.
    //   3. String(elder) — final fallback if mapping returned empty.
    const envElderN = process.env['ELDER_N'];
    if (envElderN !== undefined && envElderN === String(elder)) {
      this.elderN = envElderN;
    } else {
      this.elderN = inboxKeyForClanId(ownClanId) || String(elder);
    }
    assertSafeInboxKey(this.elderN);
  }

  async send(toClanId: string, message: string, tick: number): Promise<void> {
    const inboxKey = inboxKeyForClanId(toClanId);
    // PR #136 review #2 — path traversal: validate inbox key is a single safe path
    // segment before composing the filename. Rejects '..', '/', null bytes, and
    // anything else that could escape the inboxDir. Mirrors axlPeerInbox's guard.
    assertSafeInboxKey(inboxKey);
    const file = path.join(this.inboxDir, `elder-${inboxKey}.jsonl`);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    // CLI uses `from: <Elder N>` (number); the seam uses `fromClanId: string`.
    // We write BOTH so either reader can parse — see `read()` below.
    const sentAt = new Date().toISOString();
    const entry = {
      fromClanId: this.ownClanId,
      toClanId,
      message,
      tick,
      sentAt,
      // Back-compat with the Elder CLI inbox-list formatter:
      from: this.ownClanId,
      to: toClanId,
      msg: message,
      ts: sentAt,
    };
    fs.appendFileSync(file, JSON.stringify(entry) + '\n', 'utf8');
  }

  async inbox(): Promise<PeerMessage[]> {
    assertSafeInboxKey(this.elderN);
    const file = path.join(this.inboxDir, `elder-${this.elderN}.jsonl`);
    if (!fs.existsSync(file)) return [];
    const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
    const out: PeerMessage[] = [];
    for (const line of lines) {
      const parsed = parseLine(line, this.ownClanId);
      if (parsed) out.push(parsed);
    }
    return out;
  }
}

function inboxKeyForClanId(clanId: string, env: NodeJS.ProcessEnv = process.env): string {
  for (const elder of ELDER_IDS) {
    const mappedClanId = env[`ELDER_${elder}_CLAN_ID`] ?? String(elder);
    if (mappedClanId === clanId) return String(elder);
  }
  return clanId;
}

interface CliShape {
  from?: number | string;
  to?: string;
  msg?: string;
  ts?: string;
}
interface SeamShape {
  fromClanId?: string;
  toClanId?: string;
  message?: string;
  tick?: number;
  sentAt?: string;
}

function parseLine(line: string, ownClanId: string): PeerMessage | undefined {
  let raw: CliShape & SeamShape;
  try {
    raw = JSON.parse(line) as CliShape & SeamShape;
  } catch {
    return undefined;
  }
  const fromClanId = raw.fromClanId ?? (raw.from !== undefined ? String(raw.from) : undefined);
  const toClanId = raw.toClanId ?? raw.to ?? ownClanId;
  const message = raw.message ?? raw.msg;
  const sentAt = raw.sentAt ?? raw.ts;
  if (!fromClanId || !message || !sentAt) return undefined;
  return {
    fromClanId,
    toClanId,
    message,
    tick: raw.tick ?? 0,
    sentAt,
  };
}
