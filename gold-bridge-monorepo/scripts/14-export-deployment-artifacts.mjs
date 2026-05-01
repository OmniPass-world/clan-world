#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {
  readEnvFile,
  repoRootFromScript,
  loadDeployment,
  chainConfig,
  transceiverAddress,
} from './lib/deployment.mjs';

const root = repoRootFromScript();
const env = readEnvFile(path.join(root, '.env'));
const args = process.argv.slice(2);
const stdout = args.includes('--stdout');
const outIdx = args.indexOf('--out');
const outPath = outIdx >= 0 ? args[outIdx + 1] : path.join(root, 'artifacts', 'deployment-summary.json');

const deployment = loadDeployment(root, env);
const solanaChainName = env.NTT_SOLANA_CHAIN || 'Solana';
const baseChainName = env.NTT_BASE_CHAIN || 'BaseSepolia';
const solana = chainConfig(deployment, solanaChainName) || {};
const base = chainConfig(deployment, baseChainName) || {};

const summary = {
  generatedAt: new Date().toISOString(),
  network: deployment.network || env.WORMHOLE_NETWORK || 'unknown',
  chains: {
    solana: {
      nttChain: solanaChainName,
      rpcUrl: env.SOLANA_RPC_URL || '',
      deployer: env.SOLANA_DEPLOYER_ADDRESS || '',
      tokenMint: env.SOLANA_TOKEN_MINT || solana.token || '',
      tokenDecimals: Number(env.SOLANA_TOKEN_DECIMALS || 9),
      manager: env.SOLANA_NTT_MANAGER_ADDRESS || solana.manager || '',
      transceiver: env.SOLANA_NTT_TRANSCEIVER_ADDRESS || transceiverAddress(solana),
      mode: solana.mode || '',
    },
    base: {
      nttChain: baseChainName,
      rpcUrl: env.BASE_RPC_URL || '',
      explorerUrl: env.BASE_EXPLORER_URL || '',
      deployer: env.EVM_DEPLOYER_ADDRESS || '',
      tokenAddress: env.BASE_TOKEN_ADDRESS || base.token || '',
      tokenDecimals: 9,
      tokenImplementation: env.BASE_TOKEN_IMPLEMENTATION_ADDRESS || '',
      proxyAdmin: env.BASE_PROXY_ADMIN_ADDRESS || '',
      timelock: env.BASE_TIMELOCK_ADDRESS || '',
      manager: env.BASE_NTT_MANAGER_ADDRESS || base.manager || '',
      transceiver: env.BASE_NTT_TRANSCEIVER_ADDRESS || transceiverAddress(base),
      mode: base.mode || '',
    },
  },
  transactionHashes: {
    baseFunding: env.BASE_FUNDING_TX || '',
    baseTokenDeploy: env.BASE_TOKEN_DEPLOY_TX || '',
    baseSetMinter: env.BASE_SET_MINTER_TX || '',
    solanaToBaseProof: env.SOLANA_TO_BASE_PROOF_TX || '',
    baseToSolanaApprove: env.BASE_TO_SOLANA_APPROVE_TX || '',
    baseToSolanaProof: env.BASE_TO_SOLANA_PROOF_TX || '',
  },
  notes: [
    'Private keys and mnemonic phrases are intentionally excluded.',
    'Archive this file with deployment.json and tx hashes after each testnet or production deployment.',
  ],
};

const json = `${JSON.stringify(summary, null, 2)}\n`;
if (stdout) {
  process.stdout.write(json);
} else {
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, json);
  console.log(`Wrote deployment summary to ${path.relative(root, outPath)}`);
}
