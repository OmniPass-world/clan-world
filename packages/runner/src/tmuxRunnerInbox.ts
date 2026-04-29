import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import type { IRunnerInbox, DeliveryStatus } from '@clan-world/agents/seams';
import { writeRestrictedFileSync } from './restrictedFile';
import type { ElderId } from './types';

/**
 * `IRunnerInbox` impl that pushes situation blocks into a tmux session via
 * `tmux send-keys`.
 *
 * Idempotency contract (from `IRunnerInbox`):
 *   Re-delivering tick N's block to the same Elder while tick N is still
 *   in-flight must be a no-op. We persist the last-delivered tick to a small
 *   per-Elder marker file so idempotency survives a runner restart mid-tick.
 *
 * Multi-line paste contract:
 *   `tmux send-keys -l "$block"` sends the literal string (no key-name parsing)
 *   so newlines, dollar signs, and quotes inside the block are preserved.
 *   We then send a separate `Enter` keystroke to submit. This matches the
 *   send-keys-paste-block pattern used by `~/bin/cc-send`.
 */
export class TmuxRunnerInbox implements IRunnerInbox {
  private readonly target: string;
  private readonly markerFile: string;
  private readonly ackFlagFile: string;
  private readonly bootstrapBlock: string;
  private readonly runner: TmuxRunner;

  constructor(opts: {
    elder: ElderId;
    sessionPrefix: string;
    stateDir: string;
    bootstrapBlock: string;
    /** Override for tests — defaults to spawning real `tmux`. */
    runner?: TmuxRunner;
  }) {
    this.target = `${opts.sessionPrefix}-${opts.elder}`;
    this.markerFile = path.join(opts.stateDir, `elder-${opts.elder}-last-tick.txt`);
    // The Elder CLI writes ack to `elder-{N}-ack.flag` (see packages/agents/src/cli.ts).
    this.ackFlagFile = path.join(opts.stateDir, `elder-${opts.elder}-ack.flag`);
    this.bootstrapBlock = opts.bootstrapBlock;
    this.runner = opts.runner ?? defaultTmuxRunner;
  }

  async deliverSituationBlock(tick: number, block: string, signal?: AbortSignal): Promise<DeliveryStatus> {
    if (signal?.aborted) return { ok: false, reason: 'aborted' };
    const last = readLastTick(this.markerFile);
    if (last !== undefined && last >= tick) {
      return { ok: false, reason: 'duplicate-tick' };
    }
    try {
      await sendBlock(this.runner, this.target, block, signal);
      if (signal?.aborted) return { ok: false, reason: 'aborted' }; // don't write marker on abort
      writeLastTick(this.markerFile, tick);
      return { ok: true };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      // tmux exits non-zero when the target session does not exist
      // ("can't find session") — surface as session-down per the seam.
      if (/can't find session|no server running|session not found/i.test(msg)) {
        return { ok: false, reason: 'session-down' };
      }
      // Distinguish abort from genuine timeout: signal still present in caller scope.
      if (signal?.aborted) return { ok: false, reason: 'aborted' };
      return { ok: false, reason: 'timeout' };
    }
  }

  async waitForAckAndClear(timeoutMs: number): Promise<'ack' | 'timeout'> {
    const result = await waitForFile(this.ackFlagFile, timeoutMs);
    // Regardless of ack/timeout, perform /clear + bootstrap. The seam contract
    // says "if timeout: runner issues /clear anyway (Elder loses the turn's
    // reasoning)", so we always do the reset.
    try {
      // /clear must be submitted with Enter before bootstrap is sent; otherwise
      // the two concatenate as a single prompt and the /clear slash command is ignored.
      await this.runner.send(this.target, ['/clear'], { literal: false });
      await this.runner.send(this.target, ['Enter'], { literal: false });
      await sendBlock(this.runner, this.target, this.bootstrapBlock);
    } catch {
      // /clear failures are non-fatal — the next tick will try again.
    }
    if (result === 'found') {
      // Consume the ack flag so the next final-tick warning starts fresh.
      try {
        fs.unlinkSync(this.ackFlagFile);
      } catch {
        /* already gone — fine */
      }
      return 'ack';
    }
    return 'timeout';
  }
}

/**
 * Tmux process abstraction so tests can swap in a recorder.
 */
export interface TmuxRunner {
  send(target: string, keys: string[], opts: { literal: boolean }, signal?: AbortSignal): Promise<void>;
}

export const defaultTmuxRunner: TmuxRunner = {
  send(target, keys, opts, signal) {
    return new Promise((resolve, reject) => {
      const args = ['send-keys', '-t', target];
      if (opts.literal) args.push('-l');
      args.push(...keys);
      const child = spawn('tmux', args, { stdio: ['ignore', 'pipe', 'pipe'] });
      // TOCTOU guard: check again after spawning in case signal fired between
      // the caller's pre-check and addEventListener registration below.
      if (signal?.aborted) {
        child.kill('SIGTERM');
        reject(new Error('aborted: tmux send'));
        return;
      }
      let stderr = '';
      child.stderr.on('data', chunk => {
        stderr += String(chunk);
      });
      child.on('error', reject);
      child.on('close', code => {
        if (code === 0) resolve();
        else reject(new Error(`tmux ${args.join(' ')} exited ${code}: ${stderr.trim()}`));
      });
      if (signal) {
        const onAbort = (): void => { child.kill('SIGTERM'); };
        signal.addEventListener('abort', onAbort, { once: true });
        child.on('close', () => signal.removeEventListener('abort', onAbort));
      }
    });
  },
};

async function sendBlock(runner: TmuxRunner, target: string, block: string, signal?: AbortSignal): Promise<void> {
  // Two-step paste: literal block, then Enter to submit.
  await runner.send(target, [block], { literal: true }, signal);
  if (signal?.aborted) return; // don't send Enter if aborted mid-paste
  await runner.send(target, ['Enter'], { literal: false }, signal);
}

function readLastTick(file: string): number | undefined {
  if (!fs.existsSync(file)) return undefined;
  const raw = fs.readFileSync(file, 'utf8').trim();
  const n = parseInt(raw, 10);
  return Number.isFinite(n) ? n : undefined;
}

function writeLastTick(file: string, tick: number): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  writeRestrictedFileSync(file, `${tick}\n`, {
    encoding: 'utf8',
  });
}

async function waitForFile(file: string, timeoutMs: number): Promise<'found' | 'timeout'> {
  const start = Date.now();
  const intervalMs = 250;
  while (Date.now() - start < timeoutMs) {
    if (fs.existsSync(file)) return 'found';
    await new Promise(r => setTimeout(r, intervalMs));
  }
  return fs.existsSync(file) ? 'found' : 'timeout';
}
