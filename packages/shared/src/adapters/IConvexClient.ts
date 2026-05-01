import type { FunctionReference } from 'convex/server';
import { ConvexHttpClient } from 'convex/browser';
import { anyApi } from 'convex/server';
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

// TODO(handcoded-types-audit): move Convex function references behind a server-owned
// export shim so shared can use generated API types without depending on apps/server.
const getSnapshotRef = anyApi.getSnapshot!.getSnapshot as FunctionReference<'query'>;
// getClanFullView doesn't exist in Phase 4 convex schema yet; use anyApi so it resolves at runtime
const getClanFullViewRef = anyApi.clan!.getClanFullView as FunctionReference<'query'>;

class RealConvexClient implements IConvexClient {
  private readonly http: ConvexHttpClient;

  constructor(url: string) {
    this.http = new ConvexHttpClient(url);
  }

  async getSnapshot(): Promise<WorldSnapshot> {
    try {
      return await this.http.query(getSnapshotRef) as WorldSnapshot;
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      if (msg.includes('not found') || msg.includes('Could not find')) {
        console.warn('[RealConvexClient] getSnapshot query not found on server, using stub data');
        return { tick: 0, tickEpoch: { startedAt: 0, durationMs: 20_000 }, regions: [], clans: [] };
      }
      throw err;
    }
  }

  async getClanFullView(clanId: string): Promise<ClanFullView> {
    try {
      return await this.http.query(getClanFullViewRef, { clanId }) as ClanFullView;
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      if (msg.includes('not found') || msg.includes('Could not find')) {
        console.warn('[RealConvexClient] getClanFullView query not found on server, using stub data');
        return {
          clan: { id: clanId, name: `Stub Clan ${clanId}`, treasury: '0' },
          controlledRegions: [],
          pendingOrders: [],
          whispers: [],
        };
      }
      throw err;
    }
  }

  async postLog(_level: 'info' | 'warn' | 'error', _message: string): Promise<void> {
    // Phase 4: postLog via Convex not yet used by CLI path
  }

  subscribeWhispers(_clanId: string, _onWhisper: (w: Whisper) => void): () => void {
    // ConvexHttpClient is non-reactive; WebSocket subscriptions need ConvexClient
    return () => {};
  }
}

export function createConvexClient(): IConvexClient {
  if (readEnv('CLAN_WORLD_USE_STUB_CONVEX') === 'true') {
    return new StubConvexClient();
  }
  const url = readEnv('CONVEX_URL');
  if (!url) {
    console.warn('[ConvexClient] CONVEX_URL not set — using stub data. Set CLAN_WORLD_USE_STUB_CONVEX=true to silence.');
    return new StubConvexClient();
  }
  return new RealConvexClient(url);
}
