import {
  createPublicClient,
  createWalletClient,
  defineChain,
  encodeAbiParameters,
  fallback,
  http,
  keccak256,
  parseAbiParameters,
  stringToHex,
  type Address,
  type Hex,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { readEnv } from './_env';

export interface IntelligentDataEntry {
  label: string;
  dataHash: Hex;
  uri: string;
}

export interface InftTokenView {
  tokenId: bigint;
  owner: Address;
  currentDataHash: Hex;
  encryptedKeyHash: Hex;
  data: IntelligentDataEntry[];
}

export interface InftTransferProof {
  encryptedKeyHash: Hex;
  newUri: string;
  proof: Hex;
}

export interface IInftClient {
  getToken(tokenId: bigint): Promise<InftTokenView>;
  getIntelligentData(tokenId: bigint): Promise<IntelligentDataEntry[]>;
  updateMetadata(tokenId: bigint, data: IntelligentDataEntry[], proof: Hex): Promise<Hex>;
  transfer(tokenId: bigint, to: Address, data: IntelligentDataEntry[], proof: InftTransferProof): Promise<Hex>;
  authorizeUsage(tokenId: bigint, user: Address): Promise<Hex>;
  revokeAuthorization(tokenId: bigint, user: Address): Promise<Hex>;
}

export const CLAN_AGENT_NFT_ABI = [
  {
    type: 'function',
    name: 'ownerOf',
    stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    type: 'function',
    name: 'currentDataHash',
    stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: '', type: 'bytes32' }],
  },
  {
    type: 'function',
    name: 'encryptedKeyHash',
    stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: '', type: 'bytes32' }],
  },
  {
    type: 'function',
    name: 'intelligentDataOf',
    stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [
      {
        name: '',
        type: 'tuple[]',
        components: [
          { name: 'label', type: 'string' },
          { name: 'dataHash', type: 'bytes32' },
          { name: 'uri', type: 'string' },
        ],
      },
    ],
  },
  {
    type: 'function',
    name: 'updateMetadata',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'tokenId', type: 'uint256' },
      {
        name: 'data',
        type: 'tuple[]',
        components: [
          { name: 'label', type: 'string' },
          { name: 'dataHash', type: 'bytes32' },
          { name: 'uri', type: 'string' },
        ],
      },
      { name: 'proof', type: 'bytes' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'iTransfer',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'tokenId', type: 'uint256' },
      {
        name: 'newData',
        type: 'tuple[]',
        components: [
          { name: 'label', type: 'string' },
          { name: 'dataHash', type: 'bytes32' },
          { name: 'uri', type: 'string' },
        ],
      },
      {
        name: 'transferProof',
        type: 'tuple',
        components: [
          { name: 'newDataHash', type: 'bytes32' },
          { name: 'encryptedKeyHash', type: 'bytes32' },
          { name: 'newUri', type: 'string' },
          { name: 'proof', type: 'bytes' },
        ],
      },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'authorizeUsage',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'tokenId', type: 'uint256' },
      { name: 'user', type: 'address' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'revokeAuthorization',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'tokenId', type: 'uint256' },
      { name: 'user', type: 'address' },
    ],
    outputs: [],
  },
] as const;

const ZERO_BYTES32 = `0x${'00'.repeat(32)}` as Hex;

export function hashIntelligentData(data: IntelligentDataEntry[]): Hex {
  let rolling = ZERO_BYTES32;
  for (const entry of data) {
    rolling = keccak256(
      encodeAbiParameters(
        parseAbiParameters('bytes32 rolling, string label, bytes32 dataHash, string uri'),
        [rolling, entry.label, entry.dataHash, entry.uri],
      ),
    );
  }
  return rolling;
}

export function hashMemorySnapshot(memory: Record<string, string>): Hex {
  const normalized = Object.keys(memory)
    .sort()
    .map((key) => `${key}=${memory[key] ?? ''}`)
    .join('\n');
  return keccak256(stringToHex(normalized));
}

class StubInftClient implements IInftClient {
  async getToken(tokenId: bigint): Promise<InftTokenView> {
    const data = await this.getIntelligentData(tokenId);
    return {
      tokenId,
      owner: '0x0000000000000000000000000000000000000001',
      currentDataHash: hashIntelligentData(data),
      encryptedKeyHash: keccak256(stringToHex(`demo-dek-${tokenId}`)),
      data,
    };
  }

  async getIntelligentData(tokenId: bigint): Promise<IntelligentDataEntry[]> {
    return [
      {
        label: 'memory',
        dataHash: keccak256(stringToHex(`clan-${tokenId}-memory`)),
        uri: `0g://clanworld/clan/${tokenId}/memory`,
      },
    ];
  }

  async updateMetadata(): Promise<Hex> {
    return `0x${'11'.repeat(32)}`;
  }

  async transfer(): Promise<Hex> {
    return `0x${'22'.repeat(32)}`;
  }

  async authorizeUsage(): Promise<Hex> {
    return `0x${'33'.repeat(32)}`;
  }

  async revokeAuthorization(): Promise<Hex> {
    return `0x${'44'.repeat(32)}`;
  }
}

class RealInftClient implements IInftClient {
  private readonly address: Address;
  private readonly chain = defineChain({
    id: Number(readEnv('OG_CHAIN_ID') ?? '16661'),
    name: readEnv('OG_CHAIN_NAME') ?? '0G',
    nativeCurrency: { name: '0G', symbol: '0G', decimals: 18 },
    rpcUrls: {
      default: { http: [readEnv('OG_RPC_URL') ?? readEnv('EVM_RPC') ?? 'https://evmrpc.0g.ai'] },
    },
  });
  private readonly transport = readEnv('OG_RPC_URL_FALLBACK')
    ? fallback([http(readEnv('OG_RPC_URL') ?? readEnv('EVM_RPC')), http(readEnv('OG_RPC_URL_FALLBACK'))])
    : http(readEnv('OG_RPC_URL') ?? readEnv('EVM_RPC'));
  private readonly publicClient = createPublicClient({ chain: this.chain, transport: this.transport });

  constructor() {
    const address = readEnv('OG_INFT_ADDRESS');
    if (!address) throw new Error('OG_INFT_ADDRESS is required for real iNFT mode');
    this.address = address as Address;
  }

  async getToken(tokenId: bigint): Promise<InftTokenView> {
    const [owner, currentDataHash, encryptedKeyHash, data] = await Promise.all([
      this.publicClient.readContract({
        address: this.address,
        abi: CLAN_AGENT_NFT_ABI,
        functionName: 'ownerOf',
        args: [tokenId],
      }),
      this.publicClient.readContract({
        address: this.address,
        abi: CLAN_AGENT_NFT_ABI,
        functionName: 'currentDataHash',
        args: [tokenId],
      }),
      this.publicClient.readContract({
        address: this.address,
        abi: CLAN_AGENT_NFT_ABI,
        functionName: 'encryptedKeyHash',
        args: [tokenId],
      }),
      this.getIntelligentData(tokenId),
    ]);
    return { tokenId, owner, currentDataHash, encryptedKeyHash, data };
  }

  async getIntelligentData(tokenId: bigint): Promise<IntelligentDataEntry[]> {
    const data = await this.publicClient.readContract({
      address: this.address,
      abi: CLAN_AGENT_NFT_ABI,
      functionName: 'intelligentDataOf',
      args: [tokenId],
    });
    return data.map((entry) => ({
      label: entry.label,
      dataHash: entry.dataHash,
      uri: entry.uri,
    }));
  }

  async updateMetadata(tokenId: bigint, data: IntelligentDataEntry[], proof: Hex): Promise<Hex> {
    return this.write('updateMetadata', [tokenId, data, proof]);
  }

  async transfer(tokenId: bigint, to: Address, data: IntelligentDataEntry[], proof: InftTransferProof): Promise<Hex> {
    return this.write('iTransfer', [
      to,
      tokenId,
      data,
      {
        newDataHash: hashIntelligentData(data),
        encryptedKeyHash: proof.encryptedKeyHash,
        newUri: proof.newUri,
        proof: proof.proof,
      },
    ]);
  }

  async authorizeUsage(tokenId: bigint, user: Address): Promise<Hex> {
    return this.write('authorizeUsage', [tokenId, user]);
  }

  async revokeAuthorization(tokenId: bigint, user: Address): Promise<Hex> {
    return this.write('revokeAuthorization', [tokenId, user]);
  }

  private async write(functionName: 'updateMetadata' | 'iTransfer' | 'authorizeUsage' | 'revokeAuthorization', args: readonly unknown[]): Promise<Hex> {
    const pk = readEnv('OG_INFT_PRIVATE_KEY') ?? readEnv('DEPLOYER_PRIVATE_KEY');
    if (!pk) throw new Error('OG_INFT_PRIVATE_KEY or DEPLOYER_PRIVATE_KEY is required for iNFT writes');
    const normalized = pk.startsWith('0x') ? pk : `0x${pk}`;
    if (!/^0x[0-9a-fA-F]{64}$/.test(normalized)) throw new Error('iNFT private key must be 32 bytes hex');
    const account = privateKeyToAccount(normalized as Hex);
    const walletClient = createWalletClient({ account, chain: this.chain, transport: this.transport });
    const simulation = await this.publicClient.simulateContract({
      account,
      address: this.address,
      abi: CLAN_AGENT_NFT_ABI,
      functionName,
      args: args as never,
    });
    return walletClient.writeContract(simulation.request);
  }
}

export function createInftClient(): IInftClient {
  const useStub = readEnv('CLAN_WORLD_USE_STUB_INFT');
  if (useStub === undefined || useStub === '' || useStub === 'true') {
    return new StubInftClient();
  }
  return new RealInftClient();
}
