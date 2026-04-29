import fs from 'node:fs';
import { createPublicClient, createWalletClient, http, fallback, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import type { ClanFullView, ClanOrder, Tick } from '../types';
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

// Minimal ABI — only the two read functions we call.
const CLAN_WORLD_ABI = [
  {
    type: 'function',
    name: 'getWorldSnapshot',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'tuple',
        components: [
          { name: 'currentTick', type: 'uint64' },
          { name: 'seasonStartTick', type: 'uint64' },
          { name: 'seasonEndTick', type: 'uint64' },
          { name: 'seasonFinalized', type: 'bool' },
          { name: 'winterActive', type: 'bool' },
          { name: 'winterStartsAtTick', type: 'uint64' },
          { name: 'winterEndsAtTick', type: 'uint64' },
          { name: 'activeBanditId', type: 'uint32' },
          { name: 'currentTickSeed', type: 'bytes32' },
          {
            name: 'leaderboard',
            type: 'tuple[]',
            components: [
              { name: 'clanId', type: 'uint32' },
              { name: 'owner', type: 'address' },
              { name: 'monumentLevel', type: 'uint8' },
              { name: 'baseLevel', type: 'uint8' },
              { name: 'wallLevel', type: 'uint8' },
              { name: 'livingClansmen', type: 'uint8' },
              { name: 'state', type: 'uint8' },
              { name: 'lootValue', type: 'uint256' },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getClanFullView',
    inputs: [{ name: '', type: 'uint32' }],
    outputs: [
      {
        name: '',
        type: 'tuple',
        components: [
          {
            name: 'clan',
            type: 'tuple',
            components: [
              {
                name: 'clan',
                type: 'tuple',
                components: [
                  { name: 'clanId', type: 'uint32' },
                  { name: 'iftTokenId', type: 'uint256' },
                  { name: 'owner', type: 'address' },
                  { name: 'clanState', type: 'uint8' },
                  { name: 'baseRegion', type: 'uint8' },
                  { name: 'baseLevel', type: 'uint8' },
                  { name: 'wallLevel', type: 'uint8' },
                  { name: 'monumentLevel', type: 'uint8' },
                  { name: 'livingClansmen', type: 'uint8' },
                  { name: 'lastSettledTick', type: 'uint64' },
                  { name: 'starvationStartsAtTick', type: 'uint64' },
                  { name: 'coldDamage', type: 'uint16' },
                  { name: 'goldBalance', type: 'uint256' },
                  { name: 'blueprintBalance', type: 'uint256' },
                  { name: 'vaultWood', type: 'uint256' },
                  { name: 'vaultIron', type: 'uint256' },
                  { name: 'vaultWheat', type: 'uint256' },
                  { name: 'vaultFish', type: 'uint256' },
                ],
              },
              { name: 'isStarving', type: 'bool' },
              { name: 'lootValue', type: 'uint256' },
              { name: 'derivedAtTick', type: 'uint64' },
            ],
          },
          // clansmen, westPlot, eastPlot etc. omitted — not needed for Wave 0 mapping
          {
            name: 'clansmen',
            type: 'tuple[]',
            components: [
              {
                name: 'clansman',
                type: 'tuple',
                components: [
                  {
                    name: 'clansman',
                    type: 'tuple',
                    components: [
                      { name: 'clansmanId', type: 'uint32' },
                      { name: 'clanId', type: 'uint32' },
                      { name: 'state', type: 'uint8' },
                      { name: 'currentRegion', type: 'uint8' },
                      { name: 'cooldownEndsAtTs', type: 'uint64' },
                      { name: 'lastMissionNonce', type: 'uint64' },
                      { name: 'carryWood', type: 'uint256' },
                      { name: 'carryIron', type: 'uint256' },
                      { name: 'carryWheat', type: 'uint256' },
                      { name: 'carryFish', type: 'uint256' },
                    ],
                  },
                  {
                    name: 'activeMission',
                    type: 'tuple',
                    components: [
                      { name: 'active', type: 'bool' },
                      { name: 'nonce', type: 'uint64' },
                      { name: 'clansmanId', type: 'uint32' },
                      { name: 'startRegion', type: 'uint8' },
                      { name: 'targetRegion', type: 'uint8' },
                      { name: 'action', type: 'uint8' },
                      { name: 'startTick', type: 'uint64' },
                      { name: 'arrivalTick', type: 'uint64' },
                      { name: 'actionStartTick', type: 'uint64' },
                      { name: 'missionSeed', type: 'bytes32' },
                      { name: 'marketMode', type: 'uint8' },
                      { name: 'targetClanId', type: 'uint32' },
                      { name: 'marketToken', type: 'address' },
                      { name: 'marketAmount', type: 'uint256' },
                      { name: 'maxGoldIn', type: 'uint256' },
                    ],
                  },
                  { name: 'effectiveRegion', type: 'uint8' },
                  { name: 'derivedAtTick', type: 'uint64' },
                ],
              },
              {
                name: 'activeMission',
                type: 'tuple',
                components: [
                  { name: 'active', type: 'bool' },
                  { name: 'nonce', type: 'uint64' },
                  { name: 'clansmanId', type: 'uint32' },
                  { name: 'startRegion', type: 'uint8' },
                  { name: 'targetRegion', type: 'uint8' },
                  { name: 'action', type: 'uint8' },
                  { name: 'startTick', type: 'uint64' },
                  { name: 'arrivalTick', type: 'uint64' },
                  { name: 'actionStartTick', type: 'uint64' },
                  { name: 'missionSeed', type: 'bytes32' },
                  { name: 'marketMode', type: 'uint8' },
                  { name: 'targetClanId', type: 'uint32' },
                  { name: 'marketToken', type: 'address' },
                  { name: 'marketAmount', type: 'uint256' },
                  { name: 'maxGoldIn', type: 'uint256' },
                ],
              },
            ],
          },
          {
            name: 'westPlot',
            type: 'tuple',
            components: [
              { name: 'state', type: 'uint8' },
              { name: 'region', type: 'uint8' },
              { name: 'remainingWheat', type: 'uint256' },
              { name: 'regrowUntilTick', type: 'uint64' },
            ],
          },
          {
            name: 'eastPlot',
            type: 'tuple',
            components: [
              { name: 'state', type: 'uint8' },
              { name: 'region', type: 'uint8' },
              { name: 'remainingWheat', type: 'uint256' },
              { name: 'regrowUntilTick', type: 'uint64' },
            ],
          },
          { name: 'incomingDefenderIds', type: 'uint32[]' },
          { name: 'thisClanDefendingBaseId', type: 'uint32' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    name: 'submitClanOrders',
    type: 'function',
    inputs: [
      { name: 'clanId', type: 'uint32' },
      {
        name: 'orders',
        type: 'tuple[]',
        components: [
          { name: 'clansmanId', type: 'uint32' },
          { name: 'gotoRegion', type: 'uint8' },
          { name: 'action', type: 'uint8' },
          { name: 'targetClanId', type: 'uint32' },
          { name: 'marketToken', type: 'address' },
          { name: 'marketAmount', type: 'uint256' },
          { name: 'maxGoldIn', type: 'uint256' },
        ],
      },
    ],
    outputs: [
      {
        name: 'results',
        type: 'tuple[]',
        components: [
          { name: 'clansmanId', type: 'uint32' },
          { name: 'status', type: 'uint8' },
          { name: 'cooldownEndsAtTs', type: 'uint64' },
          { name: 'missionNonce', type: 'uint64' },
        ],
      },
    ],
    stateMutability: 'nonpayable',
  },
] as const;

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
    });
    return Number(snapshot.currentTick); // safe: tick values are small enough to fit Number precisely in Wave 0
  }

  async submitOrders(clanId: string, orders: ClanOrder[]): Promise<{ txHash: string }> {
    // Wave 0: single-Elder only — concurrent nonce coordination deferred to Wave 1
    const parsedClanId = parseInt(clanId, 10);
    if (isNaN(parsedClanId) || String(parsedClanId) !== clanId.trim()) {
      throw new Error(`submitOrders: clanId must be a decimal integer, got '${clanId}'`);
    }

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
    const result = await this.client.readContract({
      address: this.contractAddress,
      abi: CLAN_WORLD_ABI,
      functionName: 'getClanFullView',
      args: [parseInt(clanId, 10)],
    });

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
