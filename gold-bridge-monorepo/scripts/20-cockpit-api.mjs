#!/usr/bin/env node
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  chainConfig,
  loadDeployment,
  readEnvFile,
  transceiverAddress,
} from './lib/deployment.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const port = Number(process.env.COCKPIT_API_PORT || 8787);
const host = process.env.COCKPIT_API_HOST || '127.0.0.1';
const envPath = process.env.ENV_FILE || path.join(root, '.env');
const env = () => readEnvFile(envPath);

const ADMIN_SLOT = '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103';
const IMPLEMENTATION_SLOT = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc';
const ZERO_WORD = '0x0000000000000000000000000000000000000000000000000000000000000000';
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

const ACTIONS = [
  action('doctor', 'Doctor', 'Validate local tools and .env presence.', 'setup', 'pnpm run doctor', { mutates: false }),
  action('ntt-init', 'Initialize NTT project', 'Create the local Wormhole NTT project.', 'deploy', 'pnpm run ntt:init'),
  action('ntt-overrides', 'Write RPC overrides', 'Write NTT RPC override config from .env.', 'deploy', 'pnpm run ntt:overrides'),
  action('deploy-base-token', 'Deploy Base GOLD proxy', 'Deploy upgradeable Base GOLD, timelock, implementation, and ProxyAdmin.', 'deploy', 'pnpm run deploy:base-token', { risk: 'high' }),
  action('ntt-add-solana', 'Deploy Solana NTT', 'Add Solana locking-mode NTT manager and transceiver.', 'deploy', 'pnpm run ntt:add-solana', { risk: 'high' }),
  action('ntt-add-base', 'Deploy Base NTT', 'Add Base burning-mode NTT manager and transceiver.', 'deploy', 'pnpm run ntt:add-base', { risk: 'high' }),
  action('ntt-push', 'Push NTT config', 'Push local NTT config to both chains.', 'config', 'pnpm run ntt:push', { risk: 'high' }),
  action('set-base-minter', 'Set Base minter', 'Schedule or send Base GOLD minter handoff to the Base NTT manager.', 'config', 'pnpm run base:set-minter', { risk: 'high' }),
  action('preflight', 'Run preflight', 'Validate decimals, minter, proxy ownership, and NTT status.', 'verify', 'pnpm run preflight', { mutates: false }),
  action('proxy-info', 'Print proxy info', 'Read Base GOLD proxy, implementation, owner, minter, and timelock info.', 'verify', 'pnpm run base:proxy-info', { mutates: false }),
  action('ntt-status', 'NTT status', 'Compare NTT deployment.json with on-chain configuration.', 'verify', 'pnpm run ntt:status', { mutates: false }),
  action('web-export', 'Export web config', 'Generate frontend deployment config from current artifacts.', 'artifact', 'pnpm run web:export-config'),
  action('artifacts-export', 'Export artifacts', 'Write deployment-summary.json for archival.', 'artifact', 'pnpm run artifacts:export'),
  action('test-solana-to-base', 'Proof Solana to Base', 'Run a small Solana to Base bridge proof.', 'proof', 'pnpm run ntt:test-transfer', {
    risk: 'high',
    env: {
      TEST_TRANSFER_SOURCE_CHAIN: 'Solana',
      TEST_TRANSFER_DESTINATION_CHAIN: '${NTT_BASE_CHAIN}',
      TEST_TRANSFER_AMOUNT: '',
      TEST_TRANSFER_DESTINATION_ADDRESS: '',
    },
  }),
  action('test-base-to-solana', 'Proof Base to Solana', 'Run a small Base to Solana bridge proof.', 'proof', 'pnpm run ntt:test-transfer', {
    risk: 'high',
    env: {
      TEST_TRANSFER_SOURCE_CHAIN: '${NTT_BASE_CHAIN}',
      TEST_TRANSFER_DESTINATION_CHAIN: 'Solana',
      TEST_TRANSFER_AMOUNT: '',
      TEST_TRANSFER_DESTINATION_ADDRESS: '',
      TEST_TRANSFER_DESTINATION_MSG_VALUE: '${TEST_TRANSFER_DESTINATION_MSG_VALUE}',
    },
  }),
  action('recover-base-dry-run', 'Preview Base recovery', 'Preview Base to Solana recovery without submitting.', 'recovery', 'pnpm run liquidity:recover-base', {
    risk: 'medium',
    mutates: false,
    env: { RECOVERY_EXECUTE: 'false', RECOVERY_AMOUNT: '', RECOVERY_DESTINATION_SOLANA_ADDRESS: '' },
  }),
  action('recover-base-execute', 'Execute Base recovery', 'Bridge operator-held Base GOLD back to Solana.', 'recovery', 'pnpm run liquidity:recover-base', {
    risk: 'critical',
    env: { RECOVERY_EXECUTE: 'true', RECOVERY_AMOUNT: '', RECOVERY_DESTINATION_SOLANA_ADDRESS: '' },
  }),
  action('timelock-schedule', 'Schedule timelock call', 'Schedule an arbitrary timelock target and calldata.', 'upgrade', 'pnpm run timelock:schedule', {
    risk: 'critical',
    env: { TIMELOCK_TARGET_ADDRESS: '', TIMELOCK_CALLDATA: '', TIMELOCK_VALUE: '0' },
  }),
  action('timelock-execute', 'Execute timelock call', 'Execute a ready timelock target and calldata.', 'upgrade', 'pnpm run timelock:execute', {
    risk: 'critical',
    env: { TIMELOCK_TARGET_ADDRESS: '', TIMELOCK_CALLDATA: '', TIMELOCK_VALUE: '0' },
  }),
];

function action(id, label, description, group, command, options = {}) {
  const [bin, ...args] = command.split(' ');
  return {
    id,
    label,
    description,
    group,
    command,
    bin,
    args,
    mutates: options.mutates ?? true,
    risk: options.risk || (options.mutates === false ? 'low' : 'medium'),
    env: options.env || {},
  };
}

function isMainnet(currentEnv) {
  return String(currentEnv.WORMHOLE_NETWORK || '').toLowerCase() === 'mainnet'
    || String(currentEnv.NTT_BASE_CHAIN || '').toLowerCase() === 'base';
}

function confirmationFor(actionDef, currentEnv) {
  if (!actionDef.mutates) return '';
  if (isMainnet(currentEnv) || actionDef.risk === 'critical') return `type ${actionDef.id.toUpperCase()} ${currentEnv.WORMHOLE_NETWORK || 'UNKNOWN'}`;
  if (actionDef.risk === 'high') return `type ${actionDef.id}`;
  return '';
}

function resolveTemplate(value, currentEnv) {
  return String(value || '').replace(/\$\{([^}]+)\}/g, (_, key) => currentEnv[key] || '');
}

function previewAction(id, body = {}) {
  const currentEnv = env();
  const actionDef = ACTIONS.find((candidate) => candidate.id === id);
  if (!actionDef) throw httpError(404, `Unknown action: ${id}`);
  const overrides = normalizeOverrides(actionDef, currentEnv, body.env || {});
  return {
    ...publicAction(actionDef, currentEnv),
    cwd: root,
    envOverrides: overrides,
    requiredConfirmation: confirmationFor(actionDef, currentEnv),
    willUseLocalSecrets: actionDef.command.includes('deploy')
      || actionDef.command.includes('ntt:')
      || actionDef.command.includes('base:')
      || actionDef.command.includes('timelock:')
      || actionDef.command.includes('liquidity:'),
  };
}

function normalizeOverrides(actionDef, currentEnv, overrides) {
  const out = {};
  for (const [key, value] of Object.entries(actionDef.env || {})) {
    out[key] = resolveTemplate(overrides[key] ?? value, currentEnv);
  }
  for (const [key, value] of Object.entries(overrides || {})) {
    if (key.startsWith('VITE_') || key.includes('PRIVATE_KEY')) continue;
    out[key] = String(value);
  }
  return out;
}

function publicAction(actionDef, currentEnv) {
  return {
    id: actionDef.id,
    label: actionDef.label,
    description: actionDef.description,
    group: actionDef.group,
    command: actionDef.command,
    mutates: actionDef.mutates,
    risk: actionDef.risk,
    envFields: Object.fromEntries(Object.entries(actionDef.env || {}).map(([key, value]) => [key, resolveTemplate(value, currentEnv)])),
    requiredConfirmation: confirmationFor(actionDef, currentEnv),
  };
}

async function runAction(id, body = {}) {
  const currentEnv = env();
  const actionDef = ACTIONS.find((candidate) => candidate.id === id);
  if (!actionDef) throw httpError(404, `Unknown action: ${id}`);
  const required = confirmationFor(actionDef, currentEnv);
  if (required && body.confirmation !== required) {
    throw httpError(400, `Confirmation mismatch. Expected: ${required}`);
  }
  const envOverrides = normalizeOverrides(actionDef, currentEnv, body.env || {});
  const startedAt = new Date().toISOString();
  const result = await spawnCommand(actionDef.bin, actionDef.args, {
    cwd: root,
    env: { ...process.env, ...currentEnv, ...envOverrides, PATH: toolPath(process.env.PATH || '') },
  });
  return {
    id,
    label: actionDef.label,
    command: actionDef.command,
    envOverrides: maskEnv(envOverrides),
    startedAt,
    finishedAt: new Date().toISOString(),
    ...result,
  };
}

function toolPath(currentPath) {
  const candidates = [
    path.join(process.env.HOME || '', '.foundry/bin'),
    path.join(process.env.HOME || '', '.bun/bin'),
    path.join(process.env.HOME || '', '.local/bin'),
  ].filter((candidate) => candidate && fs.existsSync(candidate));
  return [...candidates, currentPath].filter(Boolean).join(':');
}

function spawnCommand(bin, args, options) {
  return new Promise((resolve) => {
    const child = spawn(bin, args, { ...options, shell: false });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
    child.on('error', (error) => resolve({ ok: false, exitCode: -1, stdout, stderr: String(error.message || error) }));
    child.on('close', (code) => resolve({ ok: code === 0, exitCode: code ?? -1, stdout, stderr }));
  });
}

function maskEnv(values) {
  const masked = {};
  for (const [key, value] of Object.entries(values)) {
    masked[key] = key.includes('PRIVATE_KEY') || key.includes('SECRET') || key.includes('MNEMONIC') ? '[redacted]' : value;
  }
  return masked;
}

async function buildState() {
  const currentEnv = env();
  const deployment = safeLoadDeployment(currentEnv);
  const summary = readJson(path.join(root, 'artifacts', 'deployment-summary.json'));
  const solanaChainName = currentEnv.NTT_SOLANA_CHAIN || 'Solana';
  const baseChainName = currentEnv.NTT_BASE_CHAIN || 'BaseSepolia';
  const solanaDeployment = chainConfig(deployment, solanaChainName) || {};
  const baseDeployment = chainConfig(deployment, baseChainName) || {};

  const addresses = {
    solana: {
      chain: solanaChainName,
      explorerCluster: currentEnv.VITE_SOLANA_EXPLORER_CLUSTER || (isMainnet(currentEnv) ? '' : 'devnet'),
      deployer: currentEnv.SOLANA_DEPLOYER_ADDRESS || summary?.chains?.solana?.deployer || '',
      token: currentEnv.SOLANA_TOKEN_MINT || solanaDeployment.token || summary?.chains?.solana?.tokenMint || '',
      manager: currentEnv.SOLANA_NTT_MANAGER_ADDRESS || solanaDeployment.manager || summary?.chains?.solana?.manager || '',
      transceiver: currentEnv.SOLANA_NTT_TRANSCEIVER_ADDRESS || transceiverAddress(solanaDeployment) || summary?.chains?.solana?.transceiver || '',
      owner: solanaDeployment.owner || '',
      mode: solanaDeployment.mode || '',
    },
    base: {
      chain: baseChainName,
      explorerUrl: currentEnv.BASE_EXPLORER_URL || currentEnv.VITE_BASE_EXPLORER_URL || (baseChainName === 'Base' ? 'https://basescan.org' : 'https://sepolia.basescan.org'),
      deployer: currentEnv.EVM_DEPLOYER_ADDRESS || summary?.chains?.base?.deployer || '',
      token: currentEnv.BASE_TOKEN_ADDRESS || baseDeployment.token || summary?.chains?.base?.tokenAddress || '',
      implementation: currentEnv.BASE_TOKEN_IMPLEMENTATION_ADDRESS || summary?.chains?.base?.tokenImplementation || '',
      proxyAdmin: currentEnv.BASE_PROXY_ADMIN_ADDRESS || summary?.chains?.base?.proxyAdmin || '',
      timelock: currentEnv.BASE_TIMELOCK_ADDRESS || summary?.chains?.base?.timelock || '',
      manager: currentEnv.BASE_NTT_MANAGER_ADDRESS || baseDeployment.manager || summary?.chains?.base?.manager || '',
      transceiver: currentEnv.BASE_NTT_TRANSCEIVER_ADDRESS || transceiverAddress(baseDeployment) || summary?.chains?.base?.transceiver || '',
      owner: baseDeployment.owner || '',
      pauser: baseDeployment.pauser || baseDeployment.transceivers?.wormhole?.pauser || '',
      mode: baseDeployment.mode || '',
    },
  };

  const live = await liveState(currentEnv, addresses, deployment);
  return {
    generatedAt: new Date().toISOString(),
    environment: {
      wormholeNetwork: currentEnv.WORMHOLE_NETWORK || deployment?.network || summary?.network || 'unknown',
      isMainnet: isMainnet(currentEnv),
      nttProjectDir: currentEnv.NTT_PROJECT_DIR || 'ntt',
      envFilePresent: fs.existsSync(envPath),
      hasSolanaKeypairPath: Boolean(currentEnv.SOLANA_KEYPAIR_PATH),
      hasEvmPrivateKey: Boolean(currentEnv.EVM_PRIVATE_KEY),
      walletConnectProjectIdConfigured: Boolean(currentEnv.VITE_WALLET_CONNECT_PROJECT_ID),
      rpc: {
        solana: currentEnv.SOLANA_RPC_URL || currentEnv.VITE_SOLANA_RPC_URL || '',
        base: currentEnv.BASE_RPC_URL || currentEnv.VITE_BASE_RPC_URL || '',
      },
    },
    addresses,
    ntt: {
      solana: nttView(solanaDeployment),
      base: nttView(baseDeployment),
    },
    authority: authorityView(currentEnv, addresses, live),
    balances: live.balances,
    token: live.token,
    proxy: live.proxy,
    transactions: summary?.transactionHashes || {},
    artifacts: {
      deploymentSummaryPath: path.relative(root, path.join(root, 'artifacts', 'deployment-summary.json')),
      deploymentJsonPresent: Boolean(deployment),
      generatedWebConfigPresent: fs.existsSync(path.join(root, 'apps/web/src/generated/goldDeployment.ts')),
    },
    checks: checksView(currentEnv, addresses, live, deployment),
  };
}

function safeLoadDeployment(currentEnv) {
  try {
    return loadDeployment(root, currentEnv);
  } catch {
    return null;
  }
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function nttView(chain) {
  return {
    version: chain?.version || '',
    mode: chain?.mode || '',
    paused: chain?.paused ?? null,
    owner: chain?.owner || '',
    manager: chain?.manager || '',
    transceiverThreshold: chain?.transceivers?.threshold ?? null,
    outboundLimit: chain?.limits?.outbound || '',
    inboundLimits: chain?.limits?.inbound || {},
  };
}

function authorityView(currentEnv, addresses, live) {
  return {
    configured: {
      timelockProposer: currentEnv.TIMELOCK_PROPOSER || '',
      timelockExecutor: currentEnv.TIMELOCK_EXECUTOR || '',
      timelockAdmin: currentEnv.TIMELOCK_ADMIN || '',
      initialMinter: currentEnv.EVM_INITIAL_MINTER || '',
    },
    base: {
      tokenOwner: live.token.owner || '',
      tokenMinter: live.token.minter || '',
      proxyAdminOwner: live.proxy.proxyAdminOwner || '',
      timelock: addresses.base.timelock,
      timelockMinDelay: live.proxy.timelockMinDelay || '',
      recoveryDisabled: live.token.recoveryDisabled,
    },
    solana: {
      nttOwner: addresses.solana.owner,
    },
  };
}

function checksView(currentEnv, addresses, live, deployment) {
  const expectedDecimals = Number(currentEnv.SOLANA_TOKEN_DECIMALS || 9);
  const checks = [
    check('env', 'Environment file present', fs.existsSync(envPath)),
    check('solana-token', 'Solana GOLD mint configured', Boolean(addresses.solana.token)),
    check('base-token', 'Base GOLD token configured', Boolean(addresses.base.token)),
    check('deployment-json', 'NTT deployment.json present', Boolean(deployment)),
    check('base-decimals', `Base decimals are ${expectedDecimals}`, live.token.baseDecimals === '' || Number(live.token.baseDecimals) === expectedDecimals, live.token.baseDecimals || 'not loaded'),
    check('base-minter', 'Base minter is Base NTT manager', !live.token.minter || !addresses.base.manager || live.token.minter.toLowerCase() === addresses.base.manager.toLowerCase(), live.token.minter || 'not loaded'),
    check('proxy-admin-owner', 'ProxyAdmin owned by timelock', !addresses.base.timelock || !live.proxy.proxyAdminOwner || live.proxy.proxyAdminOwner.toLowerCase() === addresses.base.timelock.toLowerCase(), live.proxy.proxyAdminOwner || 'not loaded'),
    check('token-owner', 'Token owner is timelock', !addresses.base.timelock || !live.token.owner || live.token.owner.toLowerCase() === addresses.base.timelock.toLowerCase(), live.token.owner || 'not loaded'),
  ];
  return checks;
}

function check(id, label, ok, detail = '') {
  return { id, label, ok: Boolean(ok), detail };
}

async function liveState(currentEnv, addresses, deployment) {
  const balances = {
    solanaDeployerSol: '',
    solanaDeployerGold: '',
    baseDeployerEth: '',
    baseDeployerGold: '',
    errors: [],
  };
  const token = {
    solanaSupply: '',
    baseSupply: '',
    baseDecimals: '',
    owner: '',
    minter: '',
    recoveryDisabled: null,
    errors: [],
  };
  const proxy = {
    admin: '',
    implementation: '',
    proxyAdminOwner: '',
    timelockMinDelay: '',
    errors: [],
  };

  const solanaRpc = currentEnv.SOLANA_RPC_URL || currentEnv.VITE_SOLANA_RPC_URL;
  const baseRpc = currentEnv.BASE_RPC_URL || currentEnv.VITE_BASE_RPC_URL;
  await Promise.all([
    populateSolanaLive(solanaRpc, addresses, balances, token),
    populateBaseLive(baseRpc, addresses, balances, token, proxy),
  ]);

  if (deployment?.chains) {
    token.deploymentNetwork = deployment.network || '';
  }
  return { balances, token, proxy };
}

async function populateSolanaLive(rpcUrl, addresses, balances, token) {
  if (!rpcUrl) return;
  try {
    if (addresses.solana.deployer) {
      const lamports = await solanaRpc(rpcUrl, 'getBalance', [addresses.solana.deployer]);
      balances.solanaDeployerSol = lamports?.value !== undefined ? formatUnits(lamports.value, 9) : '';
    }
    if (addresses.solana.token) {
      const supply = await solanaRpc(rpcUrl, 'getTokenSupply', [addresses.solana.token]);
      token.solanaSupply = supply?.value?.uiAmountString || '';
    }
    if (addresses.solana.deployer && addresses.solana.token) {
      const accounts = await solanaRpc(rpcUrl, 'getTokenAccountsByOwner', [
        addresses.solana.deployer,
        { mint: addresses.solana.token },
        { encoding: 'jsonParsed' },
      ]);
      const amount = accounts?.value?.[0]?.account?.data?.parsed?.info?.tokenAmount?.uiAmountString;
      balances.solanaDeployerGold = amount || '0';
    }
  } catch (error) {
    balances.errors.push(`Solana: ${String(error.message || error)}`);
  }
}

async function populateBaseLive(rpcUrl, addresses, balances, token, proxy) {
  if (!rpcUrl || !addresses.base.token) return;
  try {
    if (addresses.base.deployer) {
      balances.baseDeployerEth = formatUnits(await evmRpc(rpcUrl, 'eth_getBalance', [addresses.base.deployer, 'latest']), 18);
      balances.baseDeployerGold = formatUnits(await ethCall(rpcUrl, addresses.base.token, encodeCall('balanceOf(address)', addresses.base.deployer)), 9);
    }
    token.baseSupply = formatUnits(await ethCall(rpcUrl, addresses.base.token, '0x18160ddd'), 9);
    token.baseDecimals = String(Number(BigInt(await ethCall(rpcUrl, addresses.base.token, '0x313ce567'))));
    token.owner = addressFromWord(await ethCall(rpcUrl, addresses.base.token, '0x8da5cb5b'));
    token.minter = addressFromWord(await ethCall(rpcUrl, addresses.base.token, '0x07546172'));
    token.recoveryDisabled = booleanFromWord(await ethCall(rpcUrl, addresses.base.token, '0x1276155f'));
  } catch (error) {
    token.errors.push(`Base token: ${String(error.message || error)}`);
  }

  try {
    const adminWord = await evmRpc(rpcUrl, 'eth_getStorageAt', [addresses.base.token, ADMIN_SLOT, 'latest']);
    const implementationWord = await evmRpc(rpcUrl, 'eth_getStorageAt', [addresses.base.token, IMPLEMENTATION_SLOT, 'latest']);
    proxy.admin = adminWord && adminWord !== ZERO_WORD ? addressFromWord(adminWord) : '';
    proxy.implementation = implementationWord && implementationWord !== ZERO_WORD ? addressFromWord(implementationWord) : '';
    if (proxy.admin) proxy.proxyAdminOwner = addressFromWord(await ethCall(rpcUrl, proxy.admin, '0x8da5cb5b'));
    if (addresses.base.timelock) proxy.timelockMinDelay = BigInt(await ethCall(rpcUrl, addresses.base.timelock, '0xf27a0c92')).toString();
  } catch (error) {
    proxy.errors.push(`Base proxy: ${String(error.message || error)}`);
  }
}

async function solanaRpc(url, method, params) {
  return jsonRpc(url, { jsonrpc: '2.0', id: Date.now(), method, params });
}

async function evmRpc(url, method, params) {
  return jsonRpc(url, { jsonrpc: '2.0', id: Date.now(), method, params });
}

async function ethCall(url, to, data) {
  return evmRpc(url, 'eth_call', [{ to, data }, 'latest']);
}

async function jsonRpc(url, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`RPC HTTP ${res.status}`);
  const json = await res.json();
  if (json.error) throw new Error(json.error.message || JSON.stringify(json.error));
  return json.result;
}

function encodeCall(signature, address) {
  if (signature !== 'balanceOf(address)') throw new Error(`Unsupported signature: ${signature}`);
  return `0x70a08231${address.toLowerCase().replace(/^0x/, '').padStart(64, '0')}`;
}

function addressFromWord(word) {
  if (!word || word === '0x') return '';
  return `0x${word.slice(-40)}`;
}

function booleanFromWord(word) {
  if (!word || word === '0x') return null;
  return BigInt(word) !== 0n;
}

function formatUnits(raw, decimals) {
  const value = typeof raw === 'bigint' ? raw : BigInt(raw || 0);
  const negative = value < 0n;
  const digits = (negative ? -value : value).toString().padStart(decimals + 1, '0');
  const whole = digits.slice(0, -decimals);
  const fraction = digits.slice(-decimals).replace(/0+$/, '');
  return `${negative ? '-' : ''}${whole}${fraction ? `.${fraction}` : ''}`;
}

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

async function parseBody(req) {
  let body = '';
  for await (const chunk of req) body += chunk.toString();
  if (!body) return {};
  try {
    return JSON.parse(body);
  } catch {
    throw httpError(400, 'Request body must be valid JSON.');
  }
}

function send(res, status, payload) {
  const json = JSON.stringify(payload, null, 2);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': process.env.COCKPIT_CORS_ORIGIN || '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'content-type',
  });
  res.end(json);
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'OPTIONS') return send(res, 204, {});
    const url = new URL(req.url || '/', `http://${req.headers.host}`);
    if (req.method === 'GET' && url.pathname === '/api/state') return send(res, 200, await buildState());
    if (req.method === 'GET' && url.pathname === '/api/actions') {
      const currentEnv = env();
      return send(res, 200, { actions: ACTIONS.map((item) => publicAction(item, currentEnv)) });
    }
    const actionMatch = url.pathname.match(/^\/api\/actions\/([^/]+)\/(preview|run)$/);
    if (req.method === 'POST' && actionMatch) {
      const [, id, mode] = actionMatch;
      const body = await parseBody(req);
      return send(res, 200, mode === 'preview' ? previewAction(id, body) : await runAction(id, body));
    }
    return send(res, 404, { error: 'Not found' });
  } catch (error) {
    return send(res, error.status || 500, { error: String(error.message || error) });
  }
});

server.listen(port, host, () => {
  console.log(`GOLD cockpit API listening on http://${host}:${port}`);
});
