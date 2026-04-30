import fs from 'node:fs';
import { createPublicClient, createWalletClient, http, fallback, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import IClanWorldArtifact from '../../../contracts/abi/IClanWorld.json';
import type { ClanFullView, ClanOrder, Tick } from '../types';
import type { Abi } from 'viem';
import { readEnv } from './_env';

export interface IChainClient {
  getCurrentTick(): Promise<Tick>;
  submitOrders(clanId: string, orders: ClanOrder[]): Promise<{ txHash: string }>;
  getClanFullView(clanId: string): Promise<ClanFullView>;
}

const DEFAULT_CONTRACT_ADDRESS = '0x1BF5649f29CbB53E117a5aE969A18A71790f83E8' as const;

export const baseSepolia = defineChain({
  id: 84532,
  name: 'Base Sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://sepolia.base.org'] },
  },
});

export const CLAN_WORLD_ABI = IClanWorldArtifact.abi as Abi;

/**
 * Parse and validate a clanId string into a uint32-range integer.
 * Throws descriptive errors for negative, non-integer, empty, or overflow inputs.
 */
export function parseClanId(clanId: string, fnName: string): number {
  if (!/^\d+$/.test(clanId.trim())) {
    throw new Error(`${fnName}: clanId must be a non-negative decimal integer, got '${clanId}'`);
  }
  const parsed = Number.parseInt(clanId.trim(), 10);
  if (parsed > 0xFFFFFFFF) {
    throw new Error(`${fnName}: clanId exceeds uint32 max (4294967295), got '${clanId}'`);
  }
  if (parsed === 0) {
    throw new Error(`${fnName}: clanId 0 is reserved (clan IDs start at 1), got '${clanId}'`);
  }
  return parsed;
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
  private readonly client: ReturnType<typeof createPublicClient>;
  private readonly contractAddress: `0x${string}`;
  private readonly transport: ReturnType<typeof http> | ReturnType<typeof fallback>;

  constructor() {
    const primaryRpc = readEnv('RPC_URL_PRIMARY');
    const fallbackRpc = readEnv('RPC_URL_FALLBACK');

    this.transport =
      primaryRpc && fallbackRpc
        ? fallback([http(primaryRpc), http(fallbackRpc)])
        : http(primaryRpc ?? fallbackRpc);

    this.contractAddress = (readEnv('CLAN_WORLD_CONTRACT_ADDRESS') ??
      DEFAULT_CONTRACT_ADDRESS) as `0x${string}`;

    this.client = createPublicClient({
      chain: baseSepolia,
      transport: this.transport,
    });
  }

  async getCurrentTick(): Promise<Tick> {
    const snapshot = await this.client.readContract({
      address: this.contractAddress,
      abi: CLAN_WORLD_ABI,
      functionName: 'getWorldSnapshot',
    }) as { currentTick: bigint };
    return Number(snapshot.currentTick); // safe: tick values are small enough to fit Number precisely in Wave 0
  }

  async submitOrders(clanId: string, orders: ClanOrder[]): Promise<{ txHash: string }> {
    // Wave 0: single-Elder only — concurrent nonce coordination deferred to Wave 1
    const parsedClanId = parseClanId(clanId, 'submitOrders');

    for (const order of orders) {
      if (order.kind === 'mission') {
        const { clansmanId, gotoRegion, action } = order.payload;
        if (clansmanId === undefined || gotoRegion === undefined || action === undefined) {
          throw new Error(`submitOrders: mission order missing required payload fields (clansmanId, gotoRegion, action)`);
        }
      }
    }

    const nonMissionOrders = orders.filter(o => o.kind !== 'mission');
    if (nonMissionOrders.length > 0) {
      console.warn(`[RealChainClient] submitOrders: ${nonMissionOrders.length} non-mission order(s) skipped (Wave 0 only supports 'mission' kind)`);
    }

    const contractOrders = orders
      .filter(o => o.kind === 'mission')
      .map(o => ({
        clansmanId: Number(o.payload.clansmanId),
        gotoRegion: Number(o.payload.gotoRegion),
        action: Number(o.payload.action),
        targetClanId: 0,
        marketToken: '0x0000000000000000000000000000000000000000' as `0x${string}`,
        marketAmount: 0n,
        maxGoldIn: 0n,
      }));

    if (contractOrders.length === 0) {
      throw new Error('submitOrders: no valid mission orders to submit');
    }

    const keyPath = readEnv('ELDER_WALLET_KEY_PATH');
    let pk: string | undefined;
    let pkSource: string | undefined;
    if (keyPath) {
      try {
        pk = fs.readFileSync(keyPath, 'utf8').trim();
        pkSource = `ELDER_WALLET_KEY_PATH file at ${keyPath}`;
      } catch (err) {
        if (err && typeof err === 'object' && 'code' in err && err.code === 'ENOENT') {
          throw new Error(
            `ELDER_WALLET_KEY_PATH file not found at ${keyPath}; either set DEPLOYER_PRIVATE_KEY env var or provide a key file`,
          );
        }
        const msg = err instanceof Error ? err.message : String(err);
        throw new Error(`Failed to read ELDER_WALLET_KEY_PATH file at ${keyPath}: ${msg}`);
      }
    } else {
      const fallbackKey = readEnv('DEPLOYER_PRIVATE_KEY');
      if (fallbackKey) {
        console.warn('[RealChainClient] ELDER_WALLET_KEY_PATH not set; falling back to DEPLOYER_PRIVATE_KEY (deprecated)');
        pk = fallbackKey;
        pkSource = 'DEPLOYER_PRIVATE_KEY env var';
      }
    }
    if (!pk) throw new Error('Neither ELDER_WALLET_KEY_PATH nor DEPLOYER_PRIVATE_KEY is set');

    // Normalize: add 0x prefix if missing
    if (!pk.startsWith('0x')) pk = '0x' + pk;
    if (!/^0x[0-9a-fA-F]{64}$/.test(pk)) {
      throw new Error(
        `Invalid private key from ${pkSource ?? 'unknown source'}: expected a 64-hex-char private key (0x-prefixed optional)`,
      );
    }

    const account = privateKeyToAccount(pk as `0x${string}`);
    const walletClient = createWalletClient({
      account,
      chain: baseSepolia,
      transport: this.transport,
    });

    const hash = await walletClient.writeContract({
      address: this.contractAddress,
      abi: CLAN_WORLD_ABI,
      functionName: 'submitClanOrders',
      args: [parsedClanId, contractOrders],
    });

    return { txHash: hash };
  }

  async getClanFullView(clanId: string): Promise<ClanFullView> {
    // safe as Number: game cap ≤12 clans, well within Number.MAX_SAFE_INTEGER
    const parsedClanId = parseClanId(clanId, 'getClanFullView');
    const result = await this.client.readContract({
      address: this.contractAddress,
      abi: CLAN_WORLD_ABI,
      functionName: 'getClanFullView',
      args: [parsedClanId],
    }) as {
      clan: {
        clan: {
          clanId: number;
          goldBalance: bigint;
        };
      };
    };

    const inner = result.clan.clan;
    return {
      clan: {
        id: String(inner.clanId),
        name: `clan-${inner.clanId}`,
        treasury: String(inner.goldBalance),
      },
      // controlledRegions, pendingOrders, whispers not available in Wave 0 contract read
      controlledRegions: [], // Wave 0: omit base region from controlledRegions; populated in Wave 1 from on-chain data
      pendingOrders: [],
      whispers: [],
    };
  }
}

export function createChainClient(): IChainClient {
  return readEnv('CLAN_WORLD_USE_STUB_CHAIN') === 'true'
    ? new StubChainClient()
    : new RealChainClient();
}
