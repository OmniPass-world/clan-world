import { goldDeployment } from '../generated/goldDeployment';
import { formatUnits } from './format';
import type { MetricSnapshot } from '../types';

async function jsonRpc<T>(url: string, body: unknown): Promise<T> {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!res.ok) throw new Error(`RPC HTTP ${res.status}`);
  const json = await res.json();
  if (json.error) throw new Error(json.error.message || JSON.stringify(json.error));
  return json.result as T;
}

async function fetchSolanaSupply() {
  if (!goldDeployment.solana.rpcUrl || !goldDeployment.solana.token) return null;
  return jsonRpc<{ value: { amount: string; uiAmountString: string } }>(goldDeployment.solana.rpcUrl, {
    jsonrpc: '2.0',
    id: 1,
    method: 'getTokenSupply',
    params: [goldDeployment.solana.token]
  });
}

async function fetchBaseTotalSupply() {
  if (!goldDeployment.base.rpcUrl || !goldDeployment.base.token) return null;
  const hex = await jsonRpc<string>(goldDeployment.base.rpcUrl, {
    jsonrpc: '2.0',
    id: 1,
    method: 'eth_call',
    params: [{ to: goldDeployment.base.token, data: '0x18160ddd' }, 'latest']
  });
  return BigInt(hex).toString();
}

export async function fetchMetrics(): Promise<MetricSnapshot> {
  const snapshot: MetricSnapshot = { updatedAt: new Date().toISOString() };
  const errors: string[] = [];

  try {
    const solana = await fetchSolanaSupply();
    if (solana?.value) {
      snapshot.solanaSupplyRaw = solana.value.amount;
      snapshot.solanaSupplyUi = solana.value.uiAmountString;
    }
  } catch (error) {
    errors.push(`Solana: ${String((error as Error).message || error)}`);
  }

  try {
    const baseRaw = await fetchBaseTotalSupply();
    if (baseRaw !== null) {
      snapshot.baseSupplyRaw = baseRaw;
      snapshot.baseSupplyUi = formatUnits(baseRaw, goldDeployment.base.decimals);
    }
  } catch (error) {
    errors.push(`Base: ${String((error as Error).message || error)}`);
  }

  if (errors.length) snapshot.error = errors.join(' | ');
  return snapshot;
}
