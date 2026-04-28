import { describe, it, expect } from 'vitest';
import type { IConvexClient } from '@clan-world/shared/adapters';
import type {
  IElderMemoryStore,
  IElderPeerInbox,
  PeerMessage,
} from '@clan-world/agents/seams';
import { composeSituationBlock } from '../src/composeSituationBlock';

function fakeConvex(overrides: Partial<IConvexClient> = {}): IConvexClient {
  return {
    async getSnapshot() {
      return {
        tick: 12,
        tickEpoch: { startedAt: 1700000000, durationMs: 60000 },
        regions: [{ id: 'r1', name: 'North', ownerClanId: '1' }],
        clans: [{ id: '1', name: 'Wolfclan', treasury: '1000' }],
      };
    },
    async getClanFullView(clanId: string) {
      return {
        clan: { id: clanId, name: 'Wolfclan', treasury: '1000' },
        controlledRegions: [{ id: 'r1', name: 'North', ownerClanId: clanId }],
        pendingOrders: [],
        whispers: [],
      };
    },
    async postLog() {},
    subscribeWhispers() {
      return () => {};
    },
    ...overrides,
  };
}

function fakeMemory(map: Record<string, string>): IElderMemoryStore {
  return {
    async recall(k: string) {
      return map[k];
    },
    async save(k: string, v: string) {
      map[k] = v;
    },
    async snapshot() {
      return { ...map };
    },
  };
}

function fakePeerInbox(messages: PeerMessage[]): IElderPeerInbox {
  return {
    async send() {},
    async inbox() {
      return messages;
    },
  };
}

describe('composeSituationBlock', () => {
  it('produces a block with all required sections in order', async () => {
    const block = await composeSituationBlock(
      { elder: 1, clanId: '1', tick: 12 },
      {
        convex: fakeConvex(),
        memory: fakeMemory({ strategy: 'expand-north', last_tick_handled: '11' }),
        peerInbox: fakePeerInbox([
          {
            fromClanId: '2',
            toClanId: '1',
            message: 'truce until tick 20?',
            tick: 11,
            sentAt: '2024-01-01T00:00:00Z',
          },
        ]),
      },
    );

    // Section order: Identity, Tick state, World snapshot, Your clan, Peer messages, Memory, Action.
    const sections = [
      '## Identity',
      '## Tick state',
      '## World snapshot',
      '## Your clan',
      '## Peer messages',
      '## Memory',
      '## Action',
    ];
    let lastIdx = -1;
    for (const s of sections) {
      const idx = block.indexOf(s);
      expect(idx, `section ${s} missing`).toBeGreaterThanOrEqual(0);
      expect(idx, `section ${s} out of order`).toBeGreaterThan(lastIdx);
      lastIdx = idx;
    }

    expect(block).toContain('Tick 12 — Elder 1 (Clan 1)');
    expect(block).toContain('You are Elder 1, ruling Clan 1');
    expect(block).toContain('treasury: 1000');
    expect(block).toContain('truce until tick 20?');
    expect(block).toContain('strategy: expand-north');
  });

  it('handles empty peer inbox + empty memory gracefully', async () => {
    const block = await composeSituationBlock(
      { elder: 3, clanId: '3', tick: 1 },
      {
        convex: fakeConvex({
          async getSnapshot() {
            return {
              tick: 1,
              tickEpoch: { startedAt: 0, durationMs: 20000 },
              regions: [],
              clans: [],
            };
          },
          async getClanFullView() {
            return {
              clan: { id: '3', name: 'Stub', treasury: '0' },
              controlledRegions: [],
              pendingOrders: [],
              whispers: [],
            };
          },
        }),
        memory: fakeMemory({}),
        peerInbox: fakePeerInbox([]),
      },
    );
    expect(block).toContain('## Peer messages');
    expect(block).toContain('- (none)');
    expect(block).toContain('## Memory');
    expect(block).toContain('first tick, or post-clear bootstrap');
  });

  it('renders pending orders with their kind + payload', async () => {
    const block = await composeSituationBlock(
      { elder: 2, clanId: '2', tick: 5 },
      {
        convex: fakeConvex({
          async getClanFullView(clanId: string) {
            return {
              clan: { id: clanId, name: 'Bearclan', treasury: '500' },
              controlledRegions: [],
              pendingOrders: [
                { kind: 'mission', payload: { target: 'r2', squad: ['c1'] } },
                { kind: 'transfer', payload: { to: '3', amount: '100' } },
              ],
              whispers: [],
            };
          },
        }),
        memory: fakeMemory({}),
        peerInbox: fakePeerInbox([]),
      },
    );
    expect(block).toMatch(/mission: \{"target":"r2"/);
    expect(block).toMatch(/transfer: \{"to":"3"/);
  });
});
