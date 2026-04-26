import { createPublicClient, http, fallback, defineChain } from 'viem';
import type { ClanFullView, ClanOrder, Tick } from '../types';
import { readEnv } from './_env';

export interface IChainClient {
  getCurrentTick(): Promise<Tick>;
  submitOrders(clanId: string, orders: ClanOrder[]): Promise<{ txHash: string }>;
  getClanFullView(clanId: string): Promise<ClanFullView>;
}

const DEFAULT_CONTRACT_ADDRESS = '0xC012275376b867944cd874FB2d600d6dA3B4A56e' as const;

const worldChainSepolia = defineChain({
  id: 4801,
  name: 'World Chain Sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://worldchain-sepolia.g.alchemy.com/public'] },
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

  constructor() {
    const primaryRpc = readEnv('RPC_URL_PRIMARY');
    const fallbackRpc = readEnv('RPC_URL_FALLBACK');

    const transport =
      primaryRpc && fallbackRpc
        ? fallback([http(primaryRpc), http(fallbackRpc)])
        : http(primaryRpc ?? fallbackRpc);

    this.contractAddress = (readEnv('CLAN_WORLD_CONTRACT_ADDRESS') ??
      DEFAULT_CONTRACT_ADDRESS) as `0x${string}`;

    this.client = createPublicClient({
      chain: worldChainSepolia,
      transport,
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

  async submitOrders(_clanId: string, _orders: ClanOrder[]): Promise<{ txHash: string }> {
    throw new Error(
      'RealChainClient: submitOrders not supported — use agents package for tx signing',
    );
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
