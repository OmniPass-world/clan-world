import type { ClanFullView, ClanOrder, Tick } from '../types';
import { readEnv } from './_env';

export interface IChainClient {
  getCurrentTick(): Promise<Tick>;
  submitOrders(clanId: string, orders: ClanOrder[]): Promise<{ txHash: string }>;
  getClanFullView(clanId: string): Promise<ClanFullView>;
}

class StubChainClient implements IChainClient {
  async getCurrentTick(): Promise<Tick> {
    return 0;
  }
  async submitOrders(_clanId: string, _orders: ClanOrder[]): Promise<{ txHash: string }> {
    return { txHash: '0xstub' };
  }
  async getClanFullView(clanId: string): Promise<ClanFullView> {
    return {
      clan: { id: clanId, name: `clan-${clanId}`, treasury: '0' },
      controlledRegions: [],
      pendingOrders: [],
      whispers: [],
    };
  }
}

class RealChainClient implements IChainClient {
  async getCurrentTick(): Promise<Tick> {
    throw new Error('RealChainClient: not implemented (Wave 1+)');
  }
  async submitOrders(_clanId: string, _orders: ClanOrder[]): Promise<{ txHash: string }> {
    throw new Error('RealChainClient: not implemented (Wave 1+)');
  }
  async getClanFullView(_clanId: string): Promise<ClanFullView> {
    throw new Error('RealChainClient: not implemented (Wave 1+)');
  }
}

export function createChainClient(): IChainClient {
  return readEnv('CLAN_WORLD_USE_STUB_CHAIN') === 'true'
    ? new StubChainClient()
    : new RealChainClient();
}
