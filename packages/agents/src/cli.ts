#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { assertSafeInboxKey, type ClanOrder } from '@clan-world/shared';
import type { IConvexClient, IChainClient } from '@clan-world/shared/adapters';
import { createConvexClient, createChainClient } from '@clan-world/shared/adapters';

export class UsageError extends Error {}

const RESTRICTED_FILE_MODE = 0o600;

function writeRestrictedFileSync(
  file: string,
  data: string,
  options: Omit<fs.WriteFileOptions, 'mode'> = {},
): void {
  fs.writeFileSync(file, data, {
    ...options,
    mode: RESTRICTED_FILE_MODE,
  });
  fs.chmodSync(file, RESTRICTED_FILE_MODE);
}

function appendRestrictedFileSync(
  file: string,
  data: string,
  options: Omit<fs.WriteFileOptions, 'mode'> = {},
): void {
  fs.appendFileSync(file, data, {
    ...options,
    mode: RESTRICTED_FILE_MODE,
  });
  fs.chmodSync(file, RESTRICTED_FILE_MODE);
}

export function getElderN(env: Record<string, string | undefined> = process.env): number {
  const val = env['ELDER_N'];
  if (!val) throw new UsageError('elder: ELDER_N env var is not set');
  const n = parseInt(val, 10);
  if (isNaN(n) || n < 1 || n > 4) throw new UsageError(`elder: ELDER_N must be an integer 1–4, got '${val}'`);
  return n;
}

export function stateDir(base: string = os.homedir()): string {
  return path.join(base, '.world', 'clanworld-runner', 'state');
}

export function memoryFile(n: number, base?: string): string {
  return path.join(stateDir(base), `elder-${n}-memory.json`);
}

export function inboxFile(n: number, base?: string): string {
  return path.join(stateDir(base), 'peer-inbox', `elder-${n}.jsonl`);
}

export function recipientInboxFile(clanId: string, base?: string): string {
  assertSafeInboxKey(clanId);
  return path.join(stateDir(base), 'peer-inbox', `elder-${clanId}.jsonl`);
}

export function ackFile(n: number, base?: string): string {
  return path.join(stateDir(base), `elder-${n}-ack.flag`);
}

export function readMemory(n: number, base?: string): Record<string, string> {
  const file = memoryFile(n, base);
  if (!fs.existsSync(file)) return {};
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8')) as Record<string, string>;
  } catch {
    return {};
  }
}

export function writeMemory(n: number, data: Record<string, string>, base?: string): void {
  const file = memoryFile(n, base);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  writeRestrictedFileSync(file, JSON.stringify(data, null, 2) + '\n', {
    encoding: 'utf8',
  });
}

export interface Deps {
  convex: IConvexClient;
  chain: IChainClient;
}

export async function runCommand(
  ns: string | undefined,
  cmd: string | undefined,
  rest: string[],
  deps: Deps,
  env: Record<string, string | undefined> = process.env,
  homeBase?: string,
): Promise<string> {
  if (ns === 'world' && cmd === 'snapshot') {
    const snapshot = await deps.convex.getSnapshot();
    return JSON.stringify(snapshot, null, 2) + '\n';
  }

  if (ns === 'clan' && cmd === 'view') {
    const [clanId] = rest;
    if (!clanId) throw new UsageError('usage: elder clan view <clanId>');
    const result = await deps.convex.getClanFullView(clanId);
    return JSON.stringify(result, null, 2) + '\n';
  }

  if (ns === 'clan' && cmd === 'submit-orders') {
    const [ordersFile] = rest;
    if (!ordersFile) throw new UsageError('usage: elder clan submit-orders <ordersJsonFile>');
    let parsed: { clanId: string; orders: ClanOrder[] };
    try {
      const raw = fs.readFileSync(ordersFile, 'utf8');
      parsed = JSON.parse(raw) as { clanId: string; orders: ClanOrder[] };
    } catch (err) {
      throw new UsageError(`elder: failed to read orders file '${ordersFile}': ${String(err)}`);
    }
    if (!parsed.clanId || !Array.isArray(parsed.orders)) {
      throw new UsageError(`elder: orders file must contain { clanId: string, orders: [...] }`);
    }
    const result = await deps.chain.submitOrders(parsed.clanId, parsed.orders);
    return JSON.stringify(result, null, 2) + '\n';
  }

  if (ns === 'memory' && cmd === 'recall') {
    const [topic] = rest;
    if (!topic) throw new UsageError('usage: elder memory recall <topic>');
    const n = getElderN(env);
    const mem = readMemory(n, homeBase);
    const val = mem[topic];
    return val !== undefined ? val + '\n' : `no memory for ${topic}\n`;
  }

  if (ns === 'memory' && cmd === 'save') {
    const [key, ...valueParts] = rest;
    if (!key || valueParts.length === 0) throw new UsageError('usage: elder memory save <key> <value>');
    const value = valueParts.join(' ');
    const n = getElderN(env);
    const mem = readMemory(n, homeBase);
    mem[key] = value;
    writeMemory(n, mem, homeBase);
    return `saved ${key}\n`;
  }

  if (ns === 'peer' && cmd === 'whisper') {
    const [clanId, ...msgParts] = rest;
    if (!clanId || msgParts.length === 0) throw new UsageError('usage: elder peer whisper <clanId> <msg>');
    const n = getElderN(env);
    const msg = msgParts.join(' ');
    const entry = JSON.stringify({ from: n, to: clanId, msg, ts: new Date().toISOString() });
    const file = recipientInboxFile(clanId, homeBase);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    appendRestrictedFileSync(file, entry + '\n', {
      encoding: 'utf8',
    });
    return 'whisper sent\n';
  }

  if (ns === 'peer' && cmd === 'inbox') {
    const n = getElderN(env);
    // Reads by ELDER_N, not clanId. Round-trips with 'peer whisper' only when
    // clanId === String(elderN). Issue #94 tracks the fix (option A: ELDER_CLAN_ID).
    const file = inboxFile(n, homeBase);
    if (!fs.existsSync(file)) return 'inbox empty\n';
    const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
    if (lines.length === 0) return 'inbox empty\n';
    return lines
      .map(line => {
        try {
          const entry = JSON.parse(line) as { from: number; to: string; msg: string; ts: string };
          return `[${entry.ts}] from=${entry.from} to=${entry.to}: ${entry.msg}`;
        } catch {
          return line;
        }
      })
      .join('\n') + '\n';
  }

  if (ns === 'ack-clear') {
    const n = getElderN(env);
    const file = ackFile(n, homeBase);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    writeRestrictedFileSync(file, new Date().toISOString() + '\n', {
      encoding: 'utf8',
    });
    return 'ack cleared\n';
  }

  throw new UsageError(
    'usage:\n' +
      '  elder world snapshot\n' +
      '  elder clan view <clanId>\n' +
      '  elder clan submit-orders <ordersJsonFile>\n' +
      '  elder memory recall <topic>\n' +
      '  elder memory save <key> <value>\n' +
      '  elder peer whisper <clanId> <msg>\n' +
      '  elder peer inbox\n' +
      '  elder ack-clear\n',
  );
}

async function main(argv: string[]): Promise<void> {
  const [, , ns, cmd, ...rest] = argv;
  const deps: Deps = {
    convex: createConvexClient(),
    chain: createChainClient(),
  };
  try {
    const out = await runCommand(ns, cmd, rest, deps);
    process.stdout.write(out);
  } catch (err) {
    if (err instanceof UsageError) {
      process.stderr.write(err.message + '\n');
      process.exit(1);
    }
    throw err;
  }
}

// Only run when executed directly (not when imported by tests or other modules)
const isMain = process.argv[1] !== undefined &&
  (process.argv[1].endsWith('/cli.ts') || process.argv[1].endsWith('/elder') || process.argv[1].endsWith('/cli.js'));

if (isMain) {
  main(process.argv).catch(err => {
    process.stderr.write(`elder: fatal: ${String(err)}\n`);
    process.exit(1);
  });
}
