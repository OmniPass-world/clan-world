import { QueryClient } from '@tanstack/react-query';
import { createAppKit } from '@reown/appkit/react';
import { base, baseSepolia, solana, solanaDevnet } from '@reown/appkit/networks';
import { WagmiAdapter } from '@reown/appkit-adapter-wagmi';
import { SolanaAdapter } from '@reown/appkit-adapter-solana/react';
import type { Config } from 'wagmi';

const projectId = import.meta.env.VITE_WALLET_CONNECT_PROJECT_ID || 'b56e18d47c72ab683b10814fe9495694';
const metadata = {
  name: 'GOLD Bridge Cockpit',
  description: 'Operator cockpit for the Solana to Base GOLD bridge',
  url: typeof window === 'undefined' ? 'http://localhost' : window.location.origin,
  icons: [`${typeof window === 'undefined' ? 'http://localhost' : window.location.origin}/gold-token.svg`]
};

const networks = [baseSepolia, base, solanaDevnet, solana] as [typeof baseSepolia, typeof base, typeof solanaDevnet, typeof solana];
const wagmiNetworks = [baseSepolia, base];

export const queryClient = new QueryClient();
export const wagmiAdapter = new WagmiAdapter({
  networks: wagmiNetworks,
  projectId
});

const solanaAdapter = new SolanaAdapter();

createAppKit({
  adapters: [wagmiAdapter, solanaAdapter],
  networks,
  projectId,
  metadata,
  features: {
    analytics: false,
    email: false,
    socials: false
  }
});

export const wagmiConfig: Config = wagmiAdapter.wagmiConfig;
