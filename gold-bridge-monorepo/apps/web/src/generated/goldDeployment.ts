import type { GoldDeployment } from '../types';

const env = import.meta.env;

export const goldDeployment: GoldDeployment = {
  network: env.VITE_WORMHOLE_NETWORK || 'Testnet',
  tokenSymbol: env.VITE_GOLD_SYMBOL || 'GOLD',
  iconUrl: env.VITE_GOLD_ICON_URL || '/gold-token.svg',
  solana: {
    chain: 'Solana',
    token: env.VITE_SOLANA_TOKEN_MINT || '',
    manager: env.VITE_SOLANA_NTT_MANAGER_ADDRESS || '',
    transceiver: env.VITE_SOLANA_NTT_TRANSCEIVER_ADDRESS || '',
    decimals: Number(env.VITE_SOLANA_TOKEN_DECIMALS || 9),
    rpcUrl: env.VITE_SOLANA_RPC_URL || 'https://api.devnet.solana.com',
    explorerCluster: env.VITE_SOLANA_EXPLORER_CLUSTER || 'devnet'
  },
  base: {
    chain: env.VITE_BASE_CHAIN || 'BaseSepolia',
    token: env.VITE_BASE_TOKEN_ADDRESS || '',
    manager: env.VITE_BASE_NTT_MANAGER_ADDRESS || '',
    transceiver: env.VITE_BASE_NTT_TRANSCEIVER_ADDRESS || '',
    decimals: Number(env.VITE_SOLANA_TOKEN_DECIMALS || 9),
    rpcUrl: env.VITE_BASE_RPC_URL || 'https://sepolia.base.org',
    explorerUrl: env.VITE_BASE_EXPLORER_URL || 'https://sepolia.basescan.org'
  },
  walletConnectProjectId: env.VITE_WALLET_CONNECT_PROJECT_ID || ''
};
