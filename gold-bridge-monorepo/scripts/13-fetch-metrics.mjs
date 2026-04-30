#!/usr/bin/env node
import path from 'node:path';
import { readEnvFile, repoRootFromScript, loadDeployment, chainConfig } from './lib/deployment.mjs';

const root = repoRootFromScript();
const env = readEnvFile(path.join(root, '.env'));
let deployment = null;
try { deployment = loadDeployment(root, env); } catch { deployment = { chains: {} }; }

const solanaToken = env.SOLANA_TOKEN_MINT || chainConfig(deployment, env.NTT_SOLANA_CHAIN || 'Solana')?.token;
const baseToken = env.BASE_TOKEN_ADDRESS || chainConfig(deployment, env.NTT_BASE_CHAIN || 'BaseSepolia')?.token;
const solanaRpc = env.SOLANA_RPC_URL;
const baseRpc = env.BASE_RPC_URL;

async function rpc(url, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!res.ok) throw new Error(`RPC HTTP ${res.status}`);
  const json = await res.json();
  if (json.error) throw new Error(JSON.stringify(json.error));
  return json.result;
}

async function solanaSupply() {
  if (!solanaRpc || !solanaToken) return null;
  return rpc(solanaRpc, {
    jsonrpc: '2.0',
    id: 1,
    method: 'getTokenSupply',
    params: [solanaToken]
  });
}

async function evmTotalSupply() {
  if (!baseRpc || !baseToken) return null;
  const result = await rpc(baseRpc, {
    jsonrpc: '2.0',
    id: 1,
    method: 'eth_call',
    params: [{ to: baseToken, data: '0x18160ddd' }, 'latest']
  });
  return BigInt(result).toString();
}

const out = { generatedAt: new Date().toISOString(), solana: {}, base: {} };
try { out.solana.tokenSupply = await solanaSupply(); } catch (err) { out.solana.error = String(err.message || err); }
try { out.base.totalSupplyRaw = await evmTotalSupply(); } catch (err) { out.base.error = String(err.message || err); }
console.log(JSON.stringify(out, null, 2));
