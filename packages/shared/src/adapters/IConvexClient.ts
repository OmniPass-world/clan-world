import type { ClanFullView, Whisper, WorldSnapshot } from '../types';
import { readEnv } from './_env';

export interface IConvexClient {
  getSnapshot(): Promise<WorldSnapshot>;
  getClanFullView(clanId: string): Promise<ClanFullView>;
  postLog(level: 'info' | 'warn' | 'error', message: string): Promise<void>;
  subscribeWhispers(clanId: string, onWhisper: (w: Whisper) => void): () => void;
}

class StubConvexClient implements IConvexClient {
  async getSnapshot(): Promise<WorldSnapshot> {
    return {
      tick: 0,
      tickEpoch: { startedAt: 0, durationMs: 20_000 },
      regions: [],
      clans: [],
    };
  }
  async getClanFullView(clanId: string): Promise<ClanFullView> {
    return {
      clan: { id: clanId, name: `Stub Clan ${clanId}`, treasury: '0' },
      controlledRegions: [],
      pendingOrders: [],
      whispers: [],
    };
  }
  async postLog(_level: 'info' | 'warn' | 'error', _message: string): Promise<void> {
    // no-op stub
  }
  subscribeWhispers(_clanId: string, _onWhisper: (w: Whisper) => void): () => void {
    return () => {
      // no-op unsubscribe
    };
  }
}

class RealConvexClient implements IConvexClient {
  async getSnapshot(): Promise<WorldSnapshot> {
    throw new Error('RealConvexClient: not implemented (Wave 1+)');
  }
  async getClanFullView(_clanId: string): Promise<ClanFullView> {
    throw new Error('RealConvexClient: not implemented (Wave 1+)');
  }
  async postLog(_level: 'info' | 'warn' | 'error', _message: string): Promise<void> {
    throw new Error('RealConvexClient: not implemented (Wave 1+)');
  }
  subscribeWhispers(_clanId: string, _onWhisper: (w: Whisper) => void): () => void {
    throw new Error('RealConvexClient: not implemented (Wave 1+)');
  }
}

export function createConvexClient(): IConvexClient {
  return readEnv('CLAN_WORLD_USE_STUB_CONVEX') === 'true'
    ? new StubConvexClient()
    : new RealConvexClient();
}
