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

export interface CockpitCheck {
  id: string;
  label: string;
  ok: boolean;
  detail?: string;
}

export interface CockpitAction {
  id: string;
  label: string;
  description: string;
  group: string;
  command: string;
  mutates: boolean;
  risk: 'low' | 'medium' | 'high' | 'critical' | string;
  envFields: Record<string, string>;
  requiredConfirmation: string;
}

export interface CockpitActionPreview extends CockpitAction {
  cwd: string;
  envOverrides: Record<string, string>;
  willUseLocalSecrets: boolean;
}

export interface CockpitActionResult {
  id: string;
  label: string;
  command: string;
  envOverrides: Record<string, string>;
  startedAt: string;
  finishedAt: string;
  ok: boolean;
  exitCode: number;
  stdout: string;
  stderr: string;
}

export interface CockpitIntent {
  id: string;
  label: string;
  description: string;
  kind: 'transaction' | 'deployment';
  chainId: number;
  risk: 'low' | 'medium' | 'high' | 'critical' | string;
  expectedSigner?: string;
  to?: `0x${string}`;
  value?: string;
  data?: `0x${string}`;
  abi?: unknown[];
  bytecode?: `0x${string}`;
  args?: unknown[];
  requiredConfirmation: string;
  expectedStateChange: string;
  artifactUpdate?: string[];
}

export interface CockpitIntentResult {
  id: string;
  txHash: string;
  contractAddress?: string;
  updates: Record<string, string>;
  backupPath?: string;
  notes: string[];
}

export type ReadinessStatus = 'pass' | 'fail' | 'unknown' | 'manual';

export interface ReadinessItem {
  id: string;
  category: string;
  label: string;
  status: ReadinessStatus;
  detail: string;
  evidence?: string;
  fix?: string;
  critical: boolean;
}

export interface ReadinessReport {
  generatedAt: string;
  network: string;
  canGo: boolean;
  summary: Record<ReadinessStatus, number>;
  items: ReadinessItem[];
  manualNotes?: Record<string, string>;
  exportPath?: string;
}

export interface CockpitState {
  generatedAt: string;
  environment: {
    wormholeNetwork: string;
    isMainnet: boolean;
    nttProjectDir: string;
    envFilePresent: boolean;
    hasSolanaKeypairPath: boolean;
    hasEvmPrivateKey: boolean;
    walletConnectProjectIdConfigured: boolean;
    rpc: { solana: string; base: string };
  };
  addresses: {
    solana: {
      chain: string;
      explorerCluster?: string;
      deployer: string;
      token: string;
      manager: string;
      transceiver: string;
      owner: string;
      mode: string;
    };
    base: {
      chain: string;
      explorerUrl: string;
      deployer: string;
      token: string;
      implementation: string;
      proxyAdmin: string;
      timelock: string;
      manager: string;
      transceiver: string;
      owner: string;
      pauser: string;
      mode: string;
    };
  };
  ntt: Record<string, {
    version: string;
    mode: string;
    paused: boolean | null;
    owner: string;
    manager: string;
    transceiverThreshold: number | null;
    outboundLimit: string;
    inboundLimits: Record<string, string>;
  }>;
  authority: {
    configured: Record<string, string>;
    base: {
      tokenOwner: string;
      tokenMinter: string;
      proxyAdminOwner: string;
      timelock: string;
      timelockMinDelay: string;
      recoveryDisabled: boolean | null;
    };
    solana: { nttOwner: string };
  };
  balances: {
    solanaDeployerSol: string;
    solanaDeployerGold: string;
    baseDeployerEth: string;
    baseDeployerGold: string;
    errors: string[];
  };
  token: {
    solanaSupply: string;
    solanaDecimals?: string;
    baseSupply: string;
    baseDecimals: string;
    owner: string;
    minter: string;
    recoveryDisabled: boolean | null;
    errors: string[];
  };
  proxy: {
    admin: string;
    implementation: string;
    proxyAdminOwner: string;
    timelockMinDelay: string;
    errors: string[];
  };
  transactions: Record<string, string>;
  artifacts: {
    deploymentSummaryPath: string;
    deploymentJsonPresent: boolean;
    generatedWebConfigPresent: boolean;
  };
  checks: CockpitCheck[];
}
