import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { FilePeerInbox } from '../src/filePeerInbox';

describe('FilePeerInbox', () => {
  const originalElderN = process.env['ELDER_N'];
  const originalElder3ClanId = process.env['ELDER_3_CLAN_ID'];

  afterEach(() => {
    if (originalElderN === undefined) {
      delete process.env['ELDER_N'];
    } else {
      process.env['ELDER_N'] = originalElderN;
    }
    if (originalElder3ClanId === undefined) {
      delete process.env['ELDER_3_CLAN_ID'];
    } else {
      process.env['ELDER_3_CLAN_ID'] = originalElder3ClanId;
    }
  });

  it('reads the CLI elder-N inbox even when clan id mapping differs', async () => {
    process.env['ELDER_N'] = '3';
    const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clanworld-peer-inbox-'));
    const inboxDir = path.join(stateDir, 'peer-inbox');
    fs.mkdirSync(inboxDir, { recursive: true });
    fs.writeFileSync(
      path.join(inboxDir, 'elder-3.jsonl'),
      JSON.stringify({
        from: 1,
        to: 'clan-7',
        msg: 'hold the ford',
        ts: '2026-04-28T12:00:00.000Z',
      }) + '\n',
      'utf8',
    );
    fs.writeFileSync(
      path.join(inboxDir, 'elder-clan-7.jsonl'),
      JSON.stringify({
        from: 2,
        to: 'clan-7',
        msg: 'stale mapping path',
        ts: '2026-04-28T12:01:00.000Z',
      }) + '\n',
      'utf8',
    );

    const inbox = new FilePeerInbox(3, 'clan-7', stateDir);

    await expect(inbox.inbox()).resolves.toEqual([
      {
        fromClanId: '1',
        toClanId: 'clan-7',
        message: 'hold the ford',
        tick: 0,
        sentAt: '2026-04-28T12:00:00.000Z',
      },
    ]);
  });

  it('writes to the mapped elder-N inbox for a non-default recipient clan id', async () => {
    process.env['ELDER_3_CLAN_ID'] = 'clan-7';
    const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clanworld-peer-inbox-'));
    const inbox = new FilePeerInbox(1, 'clan-1', stateDir);

    await inbox.send('clan-7', 'hold the ford', 42);

    const mappedFile = path.join(stateDir, 'peer-inbox', 'elder-3.jsonl');
    const oldClanFile = path.join(stateDir, 'peer-inbox', 'elder-clan-7.jsonl');
    expect(fs.existsSync(mappedFile)).toBe(true);
    expect(fs.existsSync(oldClanFile)).toBe(false);
    expect(fs.readFileSync(mappedFile, 'utf8')).toContain('"toClanId":"clan-7"');
  });
});
