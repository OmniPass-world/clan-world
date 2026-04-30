import type { config } from '@wormhole-foundation/wormhole-connect';
import { nttRoutes } from '@wormhole-foundation/wormhole-connect/ntt';
import { goldDeployment } from '../generated/goldDeployment';

type ConnectChain = NonNullable<config.WormholeConnectConfig['chains']>[number];
type NttConfig = Parameters<typeof nttRoutes>[0];
type RpcConfig = NonNullable<config.WormholeConnectConfig['rpcs']>;

function hasNttConfig() {
  const chains = [goldDeployment.solana, goldDeployment.base];
  return chains.every((chain) => chain.token && chain.manager && chain.transceiver);
}

export function makeWormholeConnectConfig(): config.WormholeConnectConfig | null {
  if (!hasNttConfig()) return null;

  const symbol = goldDeployment.tokenSymbol;
  const nttTokenKey = `${symbol}_NTT`;
  const solanaChain = goldDeployment.solana.chain as ConnectChain;
  const baseChain = goldDeployment.base.chain as ConnectChain;
  const ntt: NttConfig = {
    tokens: {
      [nttTokenKey]: [
        {
          chain: solanaChain,
          manager: goldDeployment.solana.manager,
          token: goldDeployment.solana.token,
          transceiver: [{ address: goldDeployment.solana.transceiver, type: 'wormhole' }]
        },
        {
          chain: baseChain,
          manager: goldDeployment.base.manager,
          token: goldDeployment.base.token,
          transceiver: [{ address: goldDeployment.base.transceiver, type: 'wormhole' }]
        }
      ]
    }
  };

  const rpcs: RpcConfig = {};
  if (goldDeployment.solana.rpcUrl) rpcs[solanaChain] = goldDeployment.solana.rpcUrl;
  if (goldDeployment.base.rpcUrl) rpcs[baseChain] = goldDeployment.base.rpcUrl;

  return {
    network: goldDeployment.network as config.WormholeConnectConfig['network'],
    chains: [solanaChain, baseChain],
    tokens: [symbol],
    rpcs,
    ui: {
      title: `${symbol} Bridge`,
      walletConnectProjectId: goldDeployment.walletConnectProjectId || undefined,
      disableUserInputtedTokens: true,
      defaultInputs: {
        source: { chain: solanaChain, token: goldDeployment.solana.token },
        destination: { chain: baseChain, token: goldDeployment.base.token }
      }
    },
    routes: [...nttRoutes(ntt)],
    tokensConfig: {
      [`${symbol}solana`]: {
        symbol,
        tokenId: {
          chain: solanaChain,
          address: goldDeployment.solana.token
        },
        icon: goldDeployment.iconUrl,
        decimals: goldDeployment.solana.decimals
      },
      [`${symbol}base`]: {
        symbol,
        tokenId: {
          chain: baseChain,
          address: goldDeployment.base.token
        },
        icon: goldDeployment.iconUrl,
        decimals: goldDeployment.base.decimals
      }
    }
  };
}
