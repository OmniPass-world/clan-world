export type WormholeNetwork = 'Mainnet' | 'Testnet' | 'Devnet';

export interface ChainDeployment {
  chain: string;
  token: string;
  manager: string;
  transceiver: string;
  decimals: number;
  rpcUrl: string;
  explorerUrl?: string;
  explorerCluster?: string;
}

export interface GoldDeployment {
  network: WormholeNetwork | string;
  tokenSymbol: string;
  iconUrl: string;
  solana: ChainDeployment;
  base: ChainDeployment;
  walletConnectProjectId?: string;
}

export interface MetricSnapshot {
  solanaSupplyUi?: string;
  solanaSupplyRaw?: string;
  baseSupplyRaw?: string;
  baseSupplyUi?: string;
  updatedAt: string;
  error?: string;
}

export interface HistoryItem {
  id: string;
  timestamp: string;
  direction: string;
  amount: string;
  status: string;
  sourceTx?: string;
  targetTx?: string;
}
