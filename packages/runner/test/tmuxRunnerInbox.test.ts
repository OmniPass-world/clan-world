import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { TmuxRunnerInbox, type TmuxRunner } from '../src/tmuxRunnerInbox';

interface RecordedCall {
  target: string;
  keys: string[];
  literal: boolean;
}

class RecordingTmux implements TmuxRunner {
  calls: RecordedCall[] = [];
  shouldFail: false | { message: string } = false;

  async send(target: string, keys: string[], opts: { literal: boolean }, _signal?: AbortSignal): Promise<void> {
    this.calls.push({ target, keys, literal: opts.literal });
    if (this.shouldFail) {
      throw new Error(this.shouldFail.message);
    }
  }
}

let tmpDir: string;
beforeEach(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'runner-tmux-test-'));
});
afterEach(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

describe('TmuxRunnerInbox.deliverSituationBlock', () => {
  it('sends literal block then Enter to elder-N target', async () => {
    const tmux = new RecordingTmux();
    const inbox = new TmuxRunnerInbox({
      elder: 1,
      sessionPrefix: 'elder',
      stateDir: tmpDir,
      bootstrapBlock: 'bootstrap',
      runner: tmux,
    });
    const status = await inbox.deliverSituationBlock(5, 'hello\nworld');
    expect(status).toEqual({ ok: true });
    expect(tmux.calls).toHaveLength(2);
    expect(tmux.calls[0]).toEqual({
      target: 'elder-1',
      keys: ['hello\nworld'],
      literal: true,
    });
    expect(tmux.calls[1]).toEqual({
      target: 'elder-1',
      keys: ['Enter'],
      literal: false,
    });
  });

  it('returns duplicate-tick when re-delivering the same tick', async () => {
    const tmux = new RecordingTmux();
    const inbox = new TmuxRunnerInbox({
      elder: 2,
      sessionPrefix: 'elder',
      stateDir: tmpDir,
      bootstrapBlock: 'b',
      runner: tmux,
    });
    await inbox.deliverSituationBlock(7, 'block-A');
    const second = await inbox.deliverSituationBlock(7, 'block-A-retry');
    expect(second).toEqual({ ok: false, reason: 'duplicate-tick' });
    // First delivery sends 2 calls (literal + Enter); second short-circuits.
    expect(tmux.calls).toHaveLength(2);
  });

  it('also rejects an older tick after a newer one was delivered', async () => {
    const tmux = new RecordingTmux();
    const inbox = new TmuxRunnerInbox({
      elder: 3,
      sessionPrefix: 'elder',
      stateDir: tmpDir,
      bootstrapBlock: 'b',
      runner: tmux,
    });
    await inbox.deliverSituationBlock(10, 'newer');
    const older = await inbox.deliverSituationBlock(9, 'older');
    expect(older).toEqual({ ok: false, reason: 'duplicate-tick' });
  });

  it('surfaces session-down when tmux says the session is missing', async () => {
    const tmux = new RecordingTmux();
    tmux.shouldFail = { message: "tmux send-keys -t elder-4 exited 1: can't find session: elder-4" };
    const inbox = new TmuxRunnerInbox({
      elder: 4,
      sessionPrefix: 'elder',
      stateDir: tmpDir,
      bootstrapBlock: 'b',
      runner: tmux,
    });
    const status = await inbox.deliverSituationBlock(1, 'block');
    expect(status).toEqual({ ok: false, reason: 'session-down' });
  });

  it('persists the last-tick marker so idempotency survives restart', async () => {
    const tmux1 = new RecordingTmux();
    const inbox1 = new TmuxRunnerInbox({
      elder: 1,
      sessionPrefix: 'elder',
      stateDir: tmpDir,
      bootstrapBlock: 'b',
      runner: tmux1,
    });
    await inbox1.deliverSituationBlock(42, 'first-impl');

    const marker = path.join(tmpDir, 'elder-1-last-tick.txt');
    expect(fs.readFileSync(marker, 'utf8').trim()).toBe('42');

    // Simulate restart: new instance, same stateDir.
    const tmux2 = new RecordingTmux();
    const inbox2 = new TmuxRunnerInbox({
      elder: 1,
      sessionPrefix: 'elder',
      stateDir: tmpDir,
      bootstrapBlock: 'b',
      runner: tmux2,
    });
    const replay = await inbox2.deliverSituationBlock(42, 'replayed');
    expect(replay).toEqual({ ok: false, reason: 'duplicate-tick' });
    expect(tmux2.calls).toHaveLength(0);
  });
});

describe('TmuxRunnerInbox.waitForAckAndClear', () => {
  it('returns timeout and still issues /clear + bootstrap when no flag appears', async () => {
    const tmux = new RecordingTmux();
    const inbox = new TmuxRunnerInbox({
      elder: 1,
      sessionPrefix: 'elder',
      stateDir: tmpDir,
      bootstrapBlock: 'BOOT',
      runner: tmux,
    });
    const result = await inbox.waitForAckAndClear(500);
    expect(result).toBe('timeout');
    // /clear (non-literal) + Enter (non-literal) + bootstrap (literal) + Enter (non-literal) = 4 calls.
    expect(tmux.calls).toHaveLength(4);
    expect(tmux.calls[0]).toEqual({ target: 'elder-1', keys: ['/clear'], literal: false });
    expect(tmux.calls[1]).toEqual({ target: 'elder-1', keys: ['Enter'], literal: false });
    expect(tmux.calls[2]).toEqual({ target: 'elder-1', keys: ['BOOT'], literal: true });
    expect(tmux.calls[3]).toEqual({ target: 'elder-1', keys: ['Enter'], literal: false });
  });

  it('returns ack and consumes the flag file when it exists', async () => {
    const tmux = new RecordingTmux();
    const flagFile = path.join(tmpDir, 'elder-2-ack.flag');
    fs.writeFileSync(flagFile, new Date().toISOString() + '\n', 'utf8');
    const inbox = new TmuxRunnerInbox({
      elder: 2,
      sessionPrefix: 'elder',
      stateDir: tmpDir,
      bootstrapBlock: 'BOOT',
      runner: tmux,
    });
    const result = await inbox.waitForAckAndClear(500);
    expect(result).toBe('ack');
    expect(fs.existsSync(flagFile)).toBe(false);
  });
});

describe('TmuxRunnerInbox.deliverSituationBlock — abort behavior', () => {
  it('does not write last-tick marker when delivery is aborted mid-send', async () => {
    const abort = new AbortController();
    const tmux = new RecordingTmux();
    // Abort before any send
    abort.abort();
    const inbox = new TmuxRunnerInbox({
      elder: 1,
      sessionPrefix: 'elder',
      stateDir: tmpDir,
      bootstrapBlock: 'b',
      runner: tmux,
    });
    const status = await inbox.deliverSituationBlock(5, 'block', abort.signal);
    // PR #136 review #10: abort returns 'aborted' (was 'timeout' — semantic
    // mismatch made shutdown logs/metrics mis-attribute). Now distinct.
    expect(status).toEqual({ ok: false, reason: 'aborted' });
    // No marker written because signal was aborted
    const marker = path.join(tmpDir, 'elder-1-last-tick.txt');
    expect(fs.existsSync(marker)).toBe(false);
    // No tmux calls made (aborted before send)
    expect(tmux.calls).toHaveLength(0);
  });
});
