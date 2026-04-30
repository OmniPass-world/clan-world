import { goldDeployment } from '../generated/goldDeployment';
import type { HistoryItem } from '../types';

const LOCAL_HISTORY_KEY = 'gold-bridge-history-v1';

export function readLocalHistory(): HistoryItem[] {
  try {
    return JSON.parse(localStorage.getItem(LOCAL_HISTORY_KEY) || '[]');
  } catch {
    return [];
  }
}

export function writeLocalHistory(items: HistoryItem[]) {
  localStorage.setItem(LOCAL_HISTORY_KEY, JSON.stringify(items.slice(0, 50)));
}

export function addLocalHistory(item: Omit<HistoryItem, 'id' | 'timestamp'>) {
  const next: HistoryItem = {
    id: crypto.randomUUID(),
    timestamp: new Date().toISOString(),
    ...item
  };
  writeLocalHistory([next, ...readLocalHistory()]);
  return next;
}

export async function fetchWormholescanHistory(): Promise<HistoryItem[]> {
  const isTestnet = goldDeployment.network !== 'Mainnet';
  const baseUrl = isTestnet
    ? 'https://api.testnet.wormholescan.io/api/v1'
    : 'https://api.wormholescan.io/api/v1';
  const tokenAddress = goldDeployment.solana.token || goldDeployment.base.token;
  if (!tokenAddress) return [];

  const url = new URL(`${baseUrl}/native-token-transfer`);
  url.searchParams.set('tokenAddress', tokenAddress);
  url.searchParams.set('pageSize', '10');
  url.searchParams.set('sortOrder', 'desc');

  const response = await fetch(url.toString());
  if (!response.ok) throw new Error(`Wormholescan HTTP ${response.status}`);
  const data = await response.json();
  const operations = Array.isArray(data.operations) ? data.operations : [];

  return operations.map((op: any) => {
    const props = op.content?.standarizedProperties || {};
    const sourceTx = op.sourceChain?.transaction?.txHash;
    const targetTx = op.targetChain?.transaction?.txHash;
    return {
      id: op.id || `${op.emitterChain}-${op.sequence}`,
      timestamp: op.targetChain?.timestamp || op.sourceChain?.timestamp || new Date().toISOString(),
      direction: `${props.fromChain || op.emitterChain || '?'} → ${props.toChain || '?'}`,
      amount: props.amount || op.content?.payload?.nttMessage?.trimmedAmount?.amount || 'unknown',
      status: op.targetChain ? 'Completed' : op.vaa ? 'Emitted' : 'In progress',
      sourceTx,
      targetTx
    } satisfies HistoryItem;
  });
}
