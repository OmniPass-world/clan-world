#!/usr/bin/env node
import path from 'node:path';
import { readEnvFile, repoRootFromScript, loadDeployment, chainConfig, transceiverAddress, fail } from './lib/deployment.mjs';

const root = repoRootFromScript();
const env = readEnvFile(path.join(root, '.env'));
const deployment = loadDeployment(root, env);
const args = process.argv.slice(2);
const getArg = (name) => {
  const idx = args.indexOf(name);
  return idx >= 0 ? args[idx + 1] : undefined;
};
const raw = args.includes('--raw');
const chain = getArg('--chain');
const field = getArg('--field');

if (chain && field) {
  const cfg = chainConfig(deployment, chain);
  if (!cfg) fail(`No chain named ${chain} in deployment.json`);
  if (field === 'transceiver') {
    console.log(transceiverAddress(cfg));
  } else {
    console.log(cfg[field] || '');
  }
  process.exit(0);
}

if (!raw) {
  console.log(`Network: ${deployment.network || env.WORMHOLE_NETWORK || 'unknown'}`);
}
for (const [name, cfg] of Object.entries(deployment.chains || {})) {
  console.log(`${name}`);
  console.log(`  mode: ${cfg.mode || ''}`);
  console.log(`  token: ${cfg.token || ''}`);
  console.log(`  manager: ${cfg.manager || ''}`);
  console.log(`  transceiver: ${transceiverAddress(cfg)}`);
}
