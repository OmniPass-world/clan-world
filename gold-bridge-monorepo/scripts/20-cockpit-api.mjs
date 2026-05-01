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
const BYTES32_ZERO = ZERO_WORD;
const BASE_CHAIN_IDS = { BaseSepolia: 84532, Base: 8453 };

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

const INTENTS = [
  intent('deploy-base-gold-proxy', 'Deploy Base GOLD proxy with wallet', 'Wallet-signed deployment of the one-shot upgradeable GOLD deployer helper.', 'deployment', 'high'),
  intent('deploy-gold-v2-implementation', 'Deploy GOLD V2 implementation', 'Wallet-signed deployment of the recovery-free GOLD implementation.', 'deployment', 'high'),
  intent('schedule-set-minter', 'Schedule minter handoff', 'Schedule setMinter(Base NTT manager) through the timelock.', 'transaction', 'high'),
  intent('execute-set-minter', 'Execute minter handoff', 'Execute the scheduled setMinter(Base NTT manager) operation.', 'transaction', 'high'),
  intent('schedule-upgrade-v2', 'Schedule V2 upgrade', 'Schedule ProxyAdmin upgradeAndCall(proxy, V2 implementation, empty bytes) through timelock.', 'transaction', 'critical'),
  intent('execute-upgrade-v2', 'Execute V2 upgrade', 'Execute the scheduled V2 upgrade operation through timelock.', 'transaction', 'critical'),
  intent('schedule-recovery-allowlist', 'Schedule recovery allowlist', 'Schedule setRecoveryAllowed(source, allowed) through timelock.', 'transaction', 'critical'),
  intent('disable-recovery-forever', 'Disable recovery forever', 'Schedule disableRecoveryForever() through timelock.', 'transaction', 'critical'),
];

function intent(id, label, description, kind, risk) {
  return { id, label, description, kind, risk };
}

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

function baseChainId(currentEnv) {
  return BASE_CHAIN_IDS[currentEnv.NTT_BASE_CHAIN || 'BaseSepolia'] || 84532;
}

function confirmationFor(actionDef, currentEnv) {
  if (!actionDef.mutates) return '';
  if (isMainnet(currentEnv) || actionDef.risk === 'critical') return `type ${actionDef.id.toUpperCase()} ${currentEnv.WORMHOLE_NETWORK || 'UNKNOWN'}`;
  if (actionDef.risk === 'high') return `type ${actionDef.id}`;
  return '';
}

function intentConfirmation(intentDef, currentEnv) {
  if (isMainnet(currentEnv) || intentDef.risk === 'critical') return `type ${intentDef.id.toUpperCase()} ${currentEnv.WORMHOLE_NETWORK || 'UNKNOWN'}`;
  if (intentDef.risk === 'high') return `type ${intentDef.id}`;
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

function publicIntent(intentDef, currentEnv) {
  return {
    ...intentDef,
    chainId: baseChainId(currentEnv),
    requiredConfirmation: intentConfirmation(intentDef, currentEnv),
  };
}

function previewIntent(id, body = {}) {
  const currentEnv = env();
  const intentDef = INTENTS.find((candidate) => candidate.id === id);
  if (!intentDef) throw httpError(404, `Unknown intent: ${id}`);
  const args = body.args || {};
  if (isMainnet(currentEnv) && id === 'deploy-base-gold-proxy') {
    throw httpError(400, 'Mainnet Base proxy deployment is dry-run/export only until final rehearsal is approved.');
  }
  const common = {
    ...publicIntent(intentDef, currentEnv),
    expectedSigner: expectedBaseSigner(currentEnv),
    value: '0',
    artifactUpdate: [],
  };

  if (id === 'deploy-base-gold-proxy') {
    const artifact = contractArtifact('UpgradeableGoldDeployer.sol', 'UpgradeableGoldDeployer');
    const deployer = expectedBaseSigner(currentEnv);
    return {
      ...common,
      abi: artifact.abi,
      bytecode: artifact.bytecode.object || artifact.bytecode,
      args: [
        currentEnv.BASE_TOKEN_NAME || 'Gold',
        currentEnv.BASE_TOKEN_SYMBOL || 'GOLD',
        currentEnv.EVM_INITIAL_MINTER || deployer,
        currentEnv.TIMELOCK_PROPOSER || deployer,
        currentEnv.TIMELOCK_EXECUTOR || ZERO_ADDRESS,
        currentEnv.TIMELOCK_ADMIN || ZERO_ADDRESS,
        BigInt(currentEnv.TIMELOCK_DELAY_SECONDS || 86400).toString(),
      ],
      expectedStateChange: 'Deploy helper, implementation, timelock, proxy token, and ProxyAdmin; reconcile writes Base token addresses.',
      artifactUpdate: ['BASE_TOKEN_ADDRESS', 'BASE_TOKEN_IMPLEMENTATION_ADDRESS', 'BASE_TIMELOCK_ADDRESS', 'BASE_PROXY_ADMIN_ADDRESS', 'BASE_TOKEN_DEPLOY_TX'],
    };
  }

  if (id === 'deploy-gold-v2-implementation') {
    const artifact = contractArtifact('GoldBridgeTokenV2.sol', 'GoldBridgeTokenV2');
    return {
      ...common,
      abi: artifact.abi,
      bytecode: artifact.bytecode.object || artifact.bytecode,
      args: [],
      expectedStateChange: 'Deploy a new GoldBridgeTokenV2 implementation; reconcile records the candidate implementation address.',
      artifactUpdate: ['BASE_TOKEN_V2_IMPLEMENTATION_ADDRESS'],
    };
  }

  const addresses = currentAddresses(currentEnv);
  if (!addresses.base.timelock) throw httpError(400, 'BASE_TIMELOCK_ADDRESS is required for wallet-signed timelock intents.');
  const value = BigInt(args.TIMELOCK_VALUE || 0).toString();
  let target = addresses.base.token;
  let inner = '0x';
  let expectedStateChange = '';

  if (id === 'schedule-set-minter' || id === 'execute-set-minter') {
    target = addresses.base.token;
    inner = encodeCall('setMinter', [addresses.base.manager || args.BASE_NTT_MANAGER_ADDRESS]);
    expectedStateChange = 'Base GOLD minter becomes the Base NTT manager.';
  } else if (id === 'schedule-upgrade-v2' || id === 'execute-upgrade-v2') {
    target = addresses.base.proxyAdmin || args.BASE_PROXY_ADMIN_ADDRESS;
    const implementation = args.NEW_IMPLEMENTATION_ADDRESS || currentEnv.BASE_TOKEN_V2_IMPLEMENTATION_ADDRESS || '';
    inner = encodeCall('upgradeAndCall', [addresses.base.token, implementation, '0x']);
    expectedStateChange = 'Base GOLD proxy implementation slot points to the supplied V2 implementation.';
  } else if (id === 'schedule-recovery-allowlist') {
    target = addresses.base.token;
    inner = encodeCall('setRecoveryAllowed', [args.RECOVERY_SOURCE_ADDRESS, args.RECOVERY_ALLOWED || 'true']);
    expectedStateChange = 'Recovery allowlist for the source address is updated through the timelock.';
  } else if (id === 'disable-recovery-forever') {
    target = addresses.base.token;
    inner = '0xf43809e2';
    expectedStateChange = 'Base GOLD recovery hook is permanently disabled.';
  }

  if (!target || !isAddress(target)) throw httpError(400, `Missing or invalid target for ${id}.`);
  const isExecute = id.startsWith('execute-');
  const data = isExecute
    ? encodeCall('execute', [target, value, inner, args.TIMELOCK_PREDECESSOR || BYTES32_ZERO, args.TIMELOCK_SALT || BYTES32_ZERO])
    : encodeCall('schedule', [target, value, inner, args.TIMELOCK_PREDECESSOR || BYTES32_ZERO, args.TIMELOCK_SALT || BYTES32_ZERO, args.TIMELOCK_DELAY_SECONDS || currentEnv.TIMELOCK_DELAY_SECONDS || '0']);

  return {
    ...common,
    to: addresses.base.timelock,
    data,
    expectedStateChange,
  };
}

async function reconcileIntent(id, body = {}) {
  const currentEnv = env();
  const intentDef = INTENTS.find((candidate) => candidate.id === id);
  if (!intentDef) throw httpError(404, `Unknown intent: ${id}`);
  const required = intentConfirmation(intentDef, currentEnv);
  if (required && body.confirmation !== required) throw httpError(400, `Confirmation mismatch. Expected: ${required}`);
  if (!body.txHash) throw httpError(400, 'txHash is required.');

  const updates = {};
  const notes = [];
  if (id === 'deploy-base-gold-proxy') {
    if (!body.contractAddress || !isAddress(body.contractAddress)) throw httpError(400, 'contractAddress is required for deploy reconciliation.');
    const baseRpc = currentEnv.BASE_RPC_URL || currentEnv.VITE_BASE_RPC_URL;
    const helper = body.contractAddress;
    updates.BASE_TOKEN_ADDRESS = addressFromWord(await ethCall(baseRpc, helper, '0xec556889'));
    updates.BASE_TOKEN_IMPLEMENTATION_ADDRESS = addressFromWord(await ethCall(baseRpc, helper, '0x5c60da1b'));
    updates.BASE_TIMELOCK_ADDRESS = addressFromWord(await ethCall(baseRpc, helper, '0xd33219b4'));
    const adminWord = await evmRpc(baseRpc, 'eth_getStorageAt', [updates.BASE_TOKEN_ADDRESS, ADMIN_SLOT, 'latest']);
    updates.BASE_PROXY_ADMIN_ADDRESS = addressFromWord(adminWord);
    updates.BASE_TOKEN_DEPLOY_TX = body.txHash;
    notes.push(`Deployed helper ${helper}.`);
  } else if (id === 'deploy-gold-v2-implementation') {
    if (!body.contractAddress || !isAddress(body.contractAddress)) throw httpError(400, 'contractAddress is required for V2 implementation reconciliation.');
    updates.BASE_TOKEN_V2_IMPLEMENTATION_ADDRESS = body.contractAddress;
    notes.push('Recorded V2 implementation candidate.');
  } else {
    updates[`${id.toUpperCase().replaceAll('-', '_')}_TX`] = body.txHash;
    notes.push('Transaction hash recorded for operator evidence.');
  }

  const backupPath = writeEnvUpdates(updates);
  return { id, txHash: body.txHash, contractAddress: body.contractAddress || '', updates, backupPath, notes };
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

async function buildReadinessReport({ write = false, manualNotes = {} } = {}) {
  const state = await buildState();
  const items = readinessItems(state);
  const summary = { pass: 0, fail: 0, unknown: 0, manual: 0 };
  for (const item of items) summary[item.status] += 1;
  const report = {
    generatedAt: new Date().toISOString(),
    network: state.environment.wormholeNetwork,
    canGo: items.every((item) => !item.critical || item.status === 'pass' || item.status === 'manual'),
    summary,
    items,
    manualNotes,
  };
  if (write) {
    const stamp = report.generatedAt.replace(/[:.]/g, '-');
    const outPath = path.join(root, 'artifacts', `readiness-report-${stamp}.json`);
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, `${JSON.stringify(report, null, 2)}\n`);
    report.exportPath = path.relative(root, outPath);
  }
  return report;
}

async function buildDeploymentGuide() {
  const state = await buildState();
  const readiness = await buildReadinessReport();
  const steps = guideSteps(state, readiness);
  const phases = guidePhases(steps);
  const currentStep = steps.find((step) => step.status === 'ready')
    || steps.find((step) => step.status === 'manual')
    || steps.find((step) => step.status !== 'done')
    || steps[steps.length - 1];
  const blockingIssues = steps
    .filter((step) => step.status === 'blocked' || step.status === 'failed')
    .flatMap((step) => step.blockedBy.map((issue) => `${step.label}: ${issue}`));
  return {
    generatedAt: new Date().toISOString(),
    currentStepId: currentStep?.id || '',
    recommendedNextAction: nextActionText(currentStep),
    blockingIssues,
    phases,
    steps,
  };
}

function guidePhases(steps) {
  const definitions = [
    ['environment', 'Environment and Wallets', 'Confirm local tools, chain pair, RPCs, and operator wallets.'],
    ['base-proxy', 'Base GOLD Proxy', 'Deploy or reconcile the upgradeable 9-decimal Base GOLD token stack.'],
    ['ntt', 'NTT Project and Managers', 'Create the Wormhole NTT project and deploy locking/burning managers.'],
    ['handoff', 'Rate Limits and Minter Handoff', 'Set conservative limits and hand Base minting to the NTT manager.'],
    ['proof', 'Verification and Proof Transfers', 'Run preflight, status, and tiny two-way bridge proofs.'],
    ['evidence', 'Artifacts and Go/No-Go', 'Export public evidence and record remaining human approvals.'],
  ];
  return definitions.map(([id, label, description]) => {
    const phaseSteps = steps.filter((step) => step.phase === id);
    return {
      id,
      label,
      description,
      stepIds: phaseSteps.map((step) => step.id),
      done: phaseSteps.filter((step) => step.status === 'done').length,
      total: phaseSteps.length,
    };
  });
}

function guideSteps(state, readiness) {
  const readinessById = Object.fromEntries(readiness.items.map((item) => [item.id, item]));
  const done = (ok) => ok ? 'done' : 'ready';
  const blocked = (depends) => depends.some((id) => {
    const step = id.includes(':') ? null : null;
    return step;
  });
  const steps = [
    step({
      id: 'environment',
      phase: 'environment',
      label: 'Confirm environment',
      description: 'Make sure the helper, RPCs, tooling, and chain pair are correct before touching contracts.',
      why: 'Most deployment mistakes start as wrong-network or stale-env mistakes.',
      mode: 'read-only',
      status: done(state.environment.envFilePresent && Boolean(state.environment.rpc.solana) && Boolean(state.environment.rpc.base)),
      primaryActionId: 'doctor',
      risk: 'low',
      fixedInputs: [
        field('wormholeNetwork', 'Wormhole network', state.environment.wormholeNetwork, false, true),
        field('solanaChain', 'Solana chain', state.addresses.solana.chain, false, true),
        field('baseChain', 'Base chain', state.addresses.base.chain, false, true),
        field('decimals', 'GOLD decimals', '9', false, true),
      ],
      editableInputs: [
        field('SOLANA_RPC_URL', 'Solana RPC', state.environment.rpc.solana, true),
        field('BASE_RPC_URL', 'Base RPC', state.environment.rpc.base, true),
        field('NTT_PROJECT_DIR', 'NTT project dir', state.environment.nttProjectDir, true),
      ],
      outputs: [
        field('envFile', '.env present', String(state.environment.envFilePresent), false),
        field('walletConnect', 'WalletConnect project id', state.environment.walletConnectProjectIdConfigured ? 'configured' : 'development fallback or missing', false),
      ],
      postconditions: [
        evidence('Doctor', 'Run the Doctor check from this step or the Deploy tab.', '', state.environment.envFilePresent ? 'pass' : 'fail'),
      ],
    }),
    step({
      id: 'connect-wallets',
      phase: 'environment',
      label: 'Connect operator wallets',
      description: 'Connect the EVM deployer through Reown/AppKit and the Solana wallet for identity and destination prefills.',
      why: 'The guide can compare connected wallets to expected deployers and use the EVM wallet for Base transactions.',
      mode: 'manual',
      status: 'manual',
      risk: 'low',
      fixedInputs: [field('mainnetPolicy', 'Mainnet key policy', state.environment.isMainnet ? 'wallet/timelock only' : 'testnet local scripts allowed', false, true)],
      editableInputs: [field('VITE_WALLET_CONNECT_PROJECT_ID', 'WalletConnect project id', state.environment.walletConnectProjectIdConfigured ? 'configured' : '', true)],
      outputs: [
        field('expectedEvmSigner', 'Expected EVM signer', state.addresses.base.deployer || 'connected wallet on fresh deploy', false),
        field('expectedSolanaSigner', 'Expected Solana signer', state.addresses.solana.deployer || 'configured payer', false),
      ],
      postconditions: [evidence('Wallet state', 'Visible in the top status strip after connection.', '', 'manual')],
    }),
    step({
      id: 'deploy-base-proxy',
      phase: 'base-proxy',
      label: 'Deploy Base GOLD proxy',
      description: 'Wallet-sign the Base GOLD proxy stack deployment and reconcile local addresses.',
      why: 'This creates the 9-decimal Base representation that Wormhole NTT will mint/burn.',
      mode: 'wallet-signed',
      status: stepStatus(Boolean(state.addresses.base.token && state.proxy.admin), ['environment']),
      dependsOn: ['environment'],
      primaryIntentId: 'deploy-base-gold-proxy',
      risk: 'high',
      fixedInputs: [
        field('proxyPattern', 'Proxy pattern', 'TransparentUpgradeableProxy', false, true),
        field('tokenDecimals', 'Token decimals', '9', false, true),
      ],
      editableInputs: [
        field('BASE_TOKEN_NAME', 'Token name', 'Gold', true),
        field('BASE_TOKEN_SYMBOL', 'Token symbol', 'GOLD', true),
        field('TIMELOCK_DELAY_SECONDS', 'Timelock delay seconds', state.proxy.timelockMinDelay || '86400', true),
      ],
      advancedInputs: [
        field('TIMELOCK_PROPOSER', 'Timelock proposer', state.authority.configured.timelockProposer, true),
        field('TIMELOCK_EXECUTOR', 'Timelock executor', state.authority.configured.timelockExecutor, true),
        field('TIMELOCK_ADMIN', 'Timelock admin', state.authority.configured.timelockAdmin, true),
      ],
      outputs: [
        field('BASE_TOKEN_ADDRESS', 'Base GOLD proxy', state.addresses.base.token, false),
        field('BASE_TOKEN_IMPLEMENTATION_ADDRESS', 'Implementation', state.addresses.base.implementation || state.proxy.implementation, false),
        field('BASE_PROXY_ADMIN_ADDRESS', 'ProxyAdmin', state.addresses.base.proxyAdmin || state.proxy.admin, false),
        field('BASE_TIMELOCK_ADDRESS', 'Timelock', state.addresses.base.timelock, false),
      ],
      postconditions: [
        readinessEvidence(readinessById, 'proxy-shape'),
        readinessEvidence(readinessById, 'base-decimals'),
      ],
    }),
    step({
      id: 'ntt-init',
      phase: 'ntt',
      label: 'Initialize NTT project',
      description: 'Create the local Wormhole NTT project and RPC override file.',
      why: 'NTT CLI owns the deployment.json shape used by later manager deploys and status checks.',
      mode: 'local-cli',
      status: stepStatus(state.artifacts.deploymentJsonPresent, ['deploy-base-proxy']),
      dependsOn: ['deploy-base-proxy'],
      primaryActionId: 'ntt-init',
      risk: 'medium',
      editableInputs: [
        field('NTT_PROJECT_DIR', 'NTT project dir', state.environment.nttProjectDir, true),
        field('SOLANA_RPC_URL', 'Solana RPC', state.environment.rpc.solana, true),
        field('BASE_RPC_URL', 'Base RPC', state.environment.rpc.base, true),
      ],
      postconditions: [evidence('deployment.json', state.artifacts.deploymentJsonPresent ? 'present' : 'not present', '', state.artifacts.deploymentJsonPresent ? 'pass' : 'fail')],
    }),
    step({
      id: 'deploy-solana-ntt',
      phase: 'ntt',
      label: 'Deploy Solana NTT manager',
      description: 'Run the local CLI helper to deploy Solana locking-mode NTT manager and transceiver.',
      why: 'Solana remains canonical and locking-mode keeps canonical GOLD on Solana while Base mints/burns.',
      mode: 'local-cli',
      status: stepStatus(state.ntt.solana?.mode === 'locking' && Boolean(state.addresses.solana.manager), ['ntt-init']),
      dependsOn: ['ntt-init'],
      primaryActionId: 'ntt-add-solana',
      risk: 'high',
      fixedInputs: [field('mode', 'NTT mode', 'locking', false, true)],
      editableInputs: [
        field('SOLANA_TOKEN_MINT', 'Solana GOLD mint', state.addresses.solana.token, true),
        field('NTT_SOLANA_PRIORITY_FEE', 'Priority fee', '', true),
      ],
      advancedInputs: [field('NTT_SOLANA_PROGRAM_KEYPAIR', 'Program keypair path', '', true, false, true)],
      outputs: [
        field('SOLANA_NTT_MANAGER_ADDRESS', 'Solana NTT manager', state.addresses.solana.manager, false),
        field('SOLANA_NTT_TRANSCEIVER_ADDRESS', 'Solana transceiver', state.addresses.solana.transceiver, false),
      ],
      postconditions: [readinessEvidence(readinessById, 'solana-ntt-mode')],
    }),
    step({
      id: 'deploy-base-ntt',
      phase: 'ntt',
      label: 'Deploy Base NTT manager',
      description: 'Run the local CLI helper to deploy Base burning-mode NTT manager and transceiver.',
      why: 'Base burning mode lets NTT mint inbound GOLD and burn outbound Base GOLD.',
      mode: 'local-cli',
      status: stepStatus(state.ntt.base?.mode === 'burning' && Boolean(state.addresses.base.manager), ['deploy-solana-ntt']),
      dependsOn: ['deploy-solana-ntt'],
      primaryActionId: 'ntt-add-base',
      risk: 'high',
      fixedInputs: [field('mode', 'NTT mode', 'burning', false, true)],
      editableInputs: [field('BASE_TOKEN_ADDRESS', 'Base GOLD proxy', state.addresses.base.token, true)],
      outputs: [
        field('BASE_NTT_MANAGER_ADDRESS', 'Base NTT manager', state.addresses.base.manager, false),
        field('BASE_NTT_TRANSCEIVER_ADDRESS', 'Base transceiver', state.addresses.base.transceiver, false),
      ],
      postconditions: [readinessEvidence(readinessById, 'base-ntt-mode')],
    }),
    step({
      id: 'push-rate-limits',
      phase: 'handoff',
      label: 'Push conservative rate limits',
      description: 'Review deployment.json rate limits and push NTT config to both chains.',
      why: 'Rate limits reduce blast radius before meaningful liquidity exists.',
      mode: 'local-cli',
      status: stepStatus(readinessById['rate-limits']?.status === 'pass', ['deploy-base-ntt']),
      dependsOn: ['deploy-base-ntt'],
      primaryActionId: 'ntt-push',
      risk: 'high',
      editableInputs: [
        field('solanaOutboundLimit', 'Solana outbound limit', state.ntt.solana?.outboundLimit || '', true),
        field('baseOutboundLimit', 'Base outbound limit', state.ntt.base?.outboundLimit || '', true),
      ],
      postconditions: [readinessEvidence(readinessById, 'rate-limits')],
    }),
    step({
      id: 'handoff-minter',
      phase: 'handoff',
      label: 'Schedule and execute minter handoff',
      description: 'Wallet-sign timelock operations so Base GOLD minter becomes the Base NTT manager.',
      why: 'Inbound bridge transfers cannot mint Base GOLD until this handoff is complete.',
      mode: 'wallet-signed',
      status: stepStatus(equalsAddress(state.token.minter, state.addresses.base.manager), ['push-rate-limits']),
      dependsOn: ['push-rate-limits'],
      primaryIntentId: equalsAddress(state.token.minter, state.addresses.base.manager) ? 'execute-set-minter' : 'schedule-set-minter',
      risk: 'high',
      fixedInputs: [
        field('target', 'Token target', state.addresses.base.token, false, true),
        field('newMinter', 'New minter', state.addresses.base.manager, false, true),
      ],
      outputs: [field('minter', 'Current minter', state.token.minter, false)],
      postconditions: [readinessEvidence(readinessById, 'base-minter')],
    }),
    step({
      id: 'preflight',
      phase: 'proof',
      label: 'Run preflight and NTT status',
      description: 'Run read-only checks against token decimals, proxy ownership, minter, and NTT on-chain config.',
      why: 'This catches the easy-to-miss wiring mistakes before bridge proof transfers.',
      mode: 'read-only',
      status: stepStatus(state.checks.every((check) => check.ok), ['handoff-minter']),
      dependsOn: ['handoff-minter'],
      primaryActionId: 'preflight',
      risk: 'low',
      postconditions: state.checks.map((checkItem) => evidence(checkItem.label, checkItem.detail || '', '', checkItem.ok ? 'pass' : 'fail')),
    }),
    step({
      id: 'proof-transfers',
      phase: 'proof',
      label: 'Run tiny two-way proof transfers',
      description: 'Run a tiny Solana to Base transfer and a tiny Base to Solana transfer, then record tx evidence.',
      why: 'A two-way proof is the strongest rehearsal evidence before production liquidity.',
      mode: 'local-cli',
      status: stepStatus(Boolean(state.transactions.solanaToBaseProof && state.transactions.baseToSolanaProof), ['preflight']),
      dependsOn: ['preflight'],
      primaryActionId: state.transactions.solanaToBaseProof ? 'test-base-to-solana' : 'test-solana-to-base',
      risk: 'high',
      editableInputs: [
        field('TEST_TRANSFER_AMOUNT', 'Proof amount', '0.5', true),
        field('TEST_TRANSFER_DESTINATION_ADDRESS', 'Destination wallet', '', true),
      ],
      postconditions: [
        readinessEvidence(readinessById, 'proof-solana-base'),
        readinessEvidence(readinessById, 'proof-base-solana'),
      ],
    }),
    step({
      id: 'export-artifacts',
      phase: 'evidence',
      label: 'Export artifacts and web config',
      description: 'Generate app config and deployment-summary evidence after all addresses and proof txs are known.',
      why: 'This creates the public address book and deployment evidence needed for handoff.',
      mode: 'local-cli',
      status: stepStatus(state.artifacts.generatedWebConfigPresent && Boolean(state.transactions.solanaToBaseProof), ['proof-transfers']),
      dependsOn: ['proof-transfers'],
      primaryActionId: state.artifacts.generatedWebConfigPresent ? 'artifacts-export' : 'web-export',
      risk: 'medium',
      outputs: [
        field('deploymentSummaryPath', 'Deployment summary', state.artifacts.deploymentSummaryPath, false),
        field('webConfig', 'Generated web config', String(state.artifacts.generatedWebConfigPresent), false),
      ],
      postconditions: [readinessEvidence(readinessById, 'deployment-artifact')],
    }),
    step({
      id: 'go-no-go',
      phase: 'evidence',
      label: 'Export Go/No-Go report',
      description: 'Review computed checks, fill manual approval notes, and export a readiness report.',
      why: 'This is the final operator evidence bundle before production or ClanWorld handoff.',
      mode: 'manual',
      status: readiness.canGo ? 'done' : 'manual',
      dependsOn: ['export-artifacts'],
      risk: 'critical',
      postconditions: readiness.items.map((item) => evidence(item.label, item.detail, item.evidence || '', item.status)),
    }),
  ];

  const statusById = {};
  for (const current of steps) {
    const blockers = (current.dependsOn || []).filter((dep) => statusById[dep] !== 'done');
    current.blockedBy = [...(current.blockedBy || []), ...blockers.map((dep) => `Complete ${steps.find((stepItem) => stepItem.id === dep)?.label || dep} first.`)];
    if (blockers.length && current.status !== 'done') current.status = 'blocked';
    statusById[current.id] = current.status;
  }
  return steps;
}

function step(config) {
  return {
    dependsOn: [],
    fixedInputs: [],
    editableInputs: [],
    advancedInputs: [],
    outputs: [],
    postconditions: [],
    evidence: [],
    blockedBy: [],
    ...config,
  };
}

function stepStatus(done, blockers = []) {
  if (done) return 'done';
  return blockers.length ? 'ready' : 'ready';
}

function field(key, label, value, editable, fixed = false, secret = false, help = '') {
  return { key, label, value: String(value || ''), editable, fixed, secret, help };
}

function evidence(label, value, href = '', status = '') {
  return { label, value: String(value || ''), href, status };
}

function readinessEvidence(items, id) {
  const item = items[id];
  if (!item) return evidence(id, 'not loaded', '', 'unknown');
  return evidence(item.label, item.detail, item.evidence || '', item.status);
}

function nextActionText(step) {
  if (!step) return 'Guide complete.';
  if (step.status === 'done') return 'All guide steps are complete.';
  if (step.status === 'blocked') return step.blockedBy[0] || 'Resolve blockers before continuing.';
  if (step.primaryIntentId) return `Prepare wallet transaction: ${step.label}.`;
  if (step.primaryActionId) return `Preview and run: ${step.label}.`;
  if (step.mode === 'manual') return `Review and record evidence: ${step.label}.`;
  return step.label;
}

function readinessItems(state) {
  const expectedDecimals = '9';
  const hasTx = (key) => Boolean(state.transactions?.[key]);
  const item = (id, category, label, status, detail, fix, critical = true, evidence = '') => ({
    id,
    category,
    label,
    status,
    detail,
    fix,
    critical,
    evidence,
  });
  const passFail = (ok, failDetail, passDetail) => ok
    ? ['pass', passDetail || 'Validated.']
    : ['fail', failDetail];
  const unknownIfMissing = (value, label) => value ? ['pass', String(value)] : ['unknown', `${label} is not available.`];

  const [solanaTokenStatus, solanaTokenDetail] = unknownIfMissing(state.addresses.solana.token, 'Solana token mint');
  const [baseTokenStatus, baseTokenDetail] = unknownIfMissing(state.addresses.base.token, 'Base token');
  const [solanaDecimalsStatus, solanaDecimalsDetail] = state.token.solanaDecimals
    ? passFail(state.token.solanaDecimals === expectedDecimals, `Expected Solana decimals ${expectedDecimals}, got ${state.token.solanaDecimals}.`, `Solana decimals ${state.token.solanaDecimals}.`)
    : ['unknown', 'Solana decimals not loaded from RPC.'];
  const [baseDecimalsStatus, baseDecimalsDetail] = state.token.baseDecimals
    ? passFail(state.token.baseDecimals === expectedDecimals, `Expected Base decimals ${expectedDecimals}, got ${state.token.baseDecimals}.`, `Base decimals ${state.token.baseDecimals}.`)
    : ['unknown', 'Base decimals not loaded from RPC.'];

  const codeOk = sourceContains('packages/contracts/src/GoldBridgeToken.sol', 'GOLD_DECIMALS = 9')
    && fs.existsSync(path.join(root, 'packages/contracts/out/UpgradeableGoldDeployer.sol/UpgradeableGoldDeployer.json'));

  return [
    item('solana-token', 'Token', 'Solana GOLD mint configured', solanaTokenStatus, solanaTokenDetail, 'Set SOLANA_TOKEN_MINT to the canonical GOLD SPL mint.'),
    item('solana-decimals', 'Token', 'Solana GOLD has 9 decimals', solanaDecimalsStatus, solanaDecimalsDetail, 'Confirm the canonical mint is 9 decimals or redeploy Base token design.'),
    item('base-token', 'Token', 'Base GOLD proxy configured', baseTokenStatus, baseTokenDetail, 'Deploy or reconcile Base GOLD proxy.'),
    item('base-decimals', 'Token', 'Base GOLD has 9 decimals', baseDecimalsStatus, baseDecimalsDetail, 'Deploy the 9-decimal GoldBridgeToken proxy.'),
    item('contract-code', 'Code', 'Contract source/artifacts match 9-decimal bridge design', codeOk ? 'pass' : 'fail', codeOk ? 'GoldBridgeToken source and deploy artifact found.' : 'Contract source or Foundry artifact missing.', 'Run forge build/test and confirm GoldBridgeToken fixes decimals at 9.'),
    item('proxy-shape', 'Base Proxy', 'Base token is ERC-1967 proxy', state.proxy.admin && state.proxy.implementation ? 'pass' : 'fail', state.proxy.admin ? `ProxyAdmin ${state.proxy.admin}, implementation ${state.proxy.implementation}.` : 'Proxy slots were not found.', 'Deploy the transparent proxy stack or fix BASE_TOKEN_ADDRESS.'),
    item('token-owner', 'Authorities', 'Token owner is timelock', equalsAddress(state.token.owner, state.addresses.base.timelock) ? 'pass' : 'fail', `owner=${state.token.owner || 'unknown'}, timelock=${state.addresses.base.timelock || 'unknown'}.`, 'Transfer token ownership to the timelock.'),
    item('proxy-admin-owner', 'Authorities', 'ProxyAdmin owner is timelock', equalsAddress(state.proxy.proxyAdminOwner, state.addresses.base.timelock) ? 'pass' : 'fail', `proxyAdminOwner=${state.proxy.proxyAdminOwner || 'unknown'}, timelock=${state.addresses.base.timelock || 'unknown'}.`, 'Transfer ProxyAdmin ownership to the timelock.'),
    item('base-minter', 'Authorities', 'Base minter is Base NTT manager', equalsAddress(state.token.minter, state.addresses.base.manager) ? 'pass' : 'fail', `minter=${state.token.minter || 'unknown'}, manager=${state.addresses.base.manager || 'unknown'}.`, 'Schedule and execute setMinter(Base NTT manager).'),
    item('timelock-delay', 'Authorities', 'Production timelock delay is nonzero on mainnet', state.environment.isMainnet ? (Number(state.proxy.timelockMinDelay || 0) > 0 ? 'pass' : 'fail') : 'manual', state.environment.isMainnet ? `delay=${state.proxy.timelockMinDelay || 'unknown'} seconds.` : `Testnet delay=${state.proxy.timelockMinDelay || 'unknown'} seconds; choose production delay manually.`, 'Set production TIMELOCK_DELAY_SECONDS before mainnet deployment.'),
    item('solana-ntt-mode', 'NTT', 'Solana NTT is locking mode', state.ntt.solana?.mode === 'locking' ? 'pass' : 'fail', `mode=${state.ntt.solana?.mode || 'unknown'}.`, 'Deploy/add Solana NTT in locking mode.'),
    item('base-ntt-mode', 'NTT', 'Base NTT is burning mode', state.ntt.base?.mode === 'burning' ? 'pass' : 'fail', `mode=${state.ntt.base?.mode || 'unknown'}.`, 'Deploy/add Base NTT in burning mode.'),
    item('ntt-not-paused', 'NTT', 'NTT managers are not paused', state.ntt.solana?.paused === false && state.ntt.base?.paused === false ? 'pass' : 'fail', `solana=${String(state.ntt.solana?.paused)}, base=${String(state.ntt.base?.paused)}.`, 'Unpause managers only after confirming configuration.'),
    item('rate-limits', 'NTT', 'Rate limits are configured and conservative', hasRateLimit(state.ntt.solana) && hasRateLimit(state.ntt.base) ? 'pass' : 'fail', `solana outbound=${state.ntt.solana?.outboundLimit || 'unknown'}, base outbound=${state.ntt.base?.outboundLimit || 'unknown'}.`, 'Set nonzero conservative outbound and inbound limits in deployment.json and push.'),
    item('deployment-artifact', 'Evidence', 'Deployment summary artifact exists', state.artifacts.deploymentJsonPresent && state.artifacts.generatedWebConfigPresent ? 'pass' : 'fail', `deploymentJson=${state.artifacts.deploymentJsonPresent}, webConfig=${state.artifacts.generatedWebConfigPresent}.`, 'Run artifacts export and web config export.'),
    item('proof-solana-base', 'Evidence', 'Tiny Solana to Base proof recorded', hasTx('solanaToBaseProof') ? 'pass' : 'fail', state.transactions.solanaToBaseProof || 'missing tx.', 'Run a tiny Solana -> Base transfer and record tx.'),
    item('proof-base-solana', 'Evidence', 'Tiny Base to Solana proof recorded', hasTx('baseToSolanaProof') ? 'pass' : 'fail', state.transactions.baseToSolanaProof || 'missing tx.', 'Run a tiny Base -> Solana transfer and record tx.'),
    item('walletconnect-project', 'Operations', 'Production WalletConnect project id configured', state.environment.isMainnet ? (state.environment.walletConnectProjectIdConfigured ? 'pass' : 'fail') : 'manual', state.environment.walletConnectProjectIdConfigured ? 'WalletConnect project id configured.' : 'Development fallback may be in use.', 'Set VITE_WALLET_CONNECT_PROJECT_ID for production.', false),
    item('external-review', 'Operations', 'External/security review completed', 'manual', 'Requires human review evidence.', 'Attach review notes before mainnet liquidity.', true),
    item('clanworld-integration', 'ClanWorld', 'ClanWorld integration plan approved', 'manual', 'Deferred until the other GOLD PR is ready.', 'Approve final bridged GOLD handoff plan before ClanWorld liquidity.', true),
  ];
}

function sourceContains(relativePath, pattern) {
  try {
    return fs.readFileSync(path.join(root, relativePath), 'utf8').includes(pattern);
  } catch {
    return false;
  }
}

function equalsAddress(a, b) {
  return Boolean(a && b && String(a).toLowerCase() === String(b).toLowerCase());
}

function hasRateLimit(ntt) {
  if (!ntt?.outboundLimit || ntt.outboundLimit === '0' || ntt.outboundLimit === '0.000000000') return false;
  return Object.values(ntt.inboundLimits || {}).some((value) => value && value !== '0' && value !== '0.000000000');
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
    solanaDecimals: '',
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
      token.solanaDecimals = supply?.value?.decimals !== undefined ? String(supply.value.decimals) : '';
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

function addressFromWord(word) {
  if (!word || word === '0x') return '';
  return `0x${word.slice(-40)}`;
}

function booleanFromWord(word) {
  if (!word || word === '0x') return null;
  return BigInt(word) !== 0n;
}

function currentAddresses(currentEnv) {
  const deployment = safeLoadDeployment(currentEnv);
  const summary = readJson(path.join(root, 'artifacts', 'deployment-summary.json'));
  const baseChainName = currentEnv.NTT_BASE_CHAIN || 'BaseSepolia';
  const solanaChainName = currentEnv.NTT_SOLANA_CHAIN || 'Solana';
  const baseDeployment = chainConfig(deployment, baseChainName) || {};
  const solanaDeployment = chainConfig(deployment, solanaChainName) || {};
  return {
    solana: {
      token: currentEnv.SOLANA_TOKEN_MINT || solanaDeployment.token || summary?.chains?.solana?.tokenMint || '',
      manager: currentEnv.SOLANA_NTT_MANAGER_ADDRESS || solanaDeployment.manager || summary?.chains?.solana?.manager || '',
    },
    base: {
      token: currentEnv.BASE_TOKEN_ADDRESS || baseDeployment.token || summary?.chains?.base?.tokenAddress || '',
      manager: currentEnv.BASE_NTT_MANAGER_ADDRESS || baseDeployment.manager || summary?.chains?.base?.manager || '',
      timelock: currentEnv.BASE_TIMELOCK_ADDRESS || summary?.chains?.base?.timelock || '',
      proxyAdmin: currentEnv.BASE_PROXY_ADMIN_ADDRESS || summary?.chains?.base?.proxyAdmin || '',
    },
  };
}

function expectedBaseSigner(currentEnv) {
  return currentEnv.EVM_DEPLOYER_ADDRESS || '';
}

function contractArtifact(sourceFile, contractName) {
  const artifactPath = path.join(root, 'packages/contracts/out', sourceFile, `${contractName}.json`);
  if (!fs.existsSync(artifactPath)) {
    throw httpError(400, `Missing contract artifact: ${path.relative(root, artifactPath)}. Run pnpm test:contracts or forge build first.`);
  }
  return JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
}

function isAddress(value) {
  return /^0x[a-fA-F0-9]{40}$/.test(String(value || ''));
}

function strip0x(value) {
  return String(value || '').replace(/^0x/, '');
}

function encodeUint(value) {
  return BigInt(value || 0).toString(16).padStart(64, '0');
}

function encodeAddress(value) {
  if (!isAddress(value)) throw httpError(400, `Invalid address: ${value || 'empty'}`);
  return strip0x(value).padStart(64, '0').toLowerCase();
}

function encodeBool(value) {
  return encodeUint(String(value) === 'true' || value === true ? 1 : 0);
}

function encodeBytes32(value) {
  const raw = strip0x(value || BYTES32_ZERO);
  if (!/^[a-fA-F0-9]{64}$/.test(raw)) throw httpError(400, `Invalid bytes32: ${value}`);
  return raw.toLowerCase();
}

function encodeBytes(value) {
  const raw = strip0x(value || '0x');
  if (!/^[a-fA-F0-9]*$/.test(raw) || raw.length % 2 !== 0) throw httpError(400, `Invalid bytes: ${value}`);
  return `${encodeUint(raw.length / 2)}${raw.padEnd(Math.ceil(raw.length / 64) * 64, '0')}`;
}

function encodeCall(name, args) {
  if (name === 'balanceOf(address)') return `0x70a08231${encodeAddress(args)}`;
  if (name === 'setMinter') return `0xfca3b5aa${encodeAddress(args[0])}`;
  if (name === 'setRecoveryAllowed') return `0x36aec413${encodeAddress(args[0])}${encodeBool(args[1])}`;
  if (name === 'execute') {
    const [target, value, data, predecessor, salt] = args;
    return `0x134008d3${encodeAddress(target)}${encodeUint(value)}${encodeUint(160)}${encodeBytes32(predecessor)}${encodeBytes32(salt)}${encodeBytes(data)}`;
  }
  if (name === 'schedule') {
    const [target, value, data, predecessor, salt, delay] = args;
    return `0x01d5062a${encodeAddress(target)}${encodeUint(value)}${encodeUint(192)}${encodeBytes32(predecessor)}${encodeBytes32(salt)}${encodeUint(delay)}${encodeBytes(data)}`;
  }
  if (name === 'upgradeAndCall') {
    const [proxy, implementation, data] = args;
    return `0x9623609d${encodeAddress(proxy)}${encodeAddress(implementation)}${encodeUint(96)}${encodeBytes(data)}`;
  }
  throw new Error(`Unsupported call: ${name}`);
}

function writeEnvUpdates(updates) {
  if (!Object.keys(updates).length) return '';
  const original = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';
  const backupPath = `${envPath}.${new Date().toISOString().replace(/[:.]/g, '-')}.bak`;
  fs.writeFileSync(backupPath, original);
  const lines = original ? original.split(/\r?\n/) : [];
  const remaining = { ...updates };
  const next = lines.map((line) => {
    const match = line.match(/^([A-Z0-9_]+)=/);
    if (!match || !(match[1] in remaining)) return line;
    const key = match[1];
    const value = remaining[key];
    delete remaining[key];
    return `${key}=${value}`;
  });
  for (const [key, value] of Object.entries(remaining)) next.push(`${key}=${value}`);
  fs.writeFileSync(envPath, `${next.join('\n').replace(/\n*$/, '')}\n`);
  return path.relative(root, backupPath);
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
    if (req.method === 'GET' && url.pathname === '/api/guide') return send(res, 200, await buildDeploymentGuide());
    if (req.method === 'GET' && url.pathname === '/api/readiness') return send(res, 200, await buildReadinessReport());
    if (req.method === 'POST' && url.pathname === '/api/readiness/export') {
      const body = await parseBody(req);
      return send(res, 200, await buildReadinessReport({ write: true, manualNotes: body.manualNotes || {} }));
    }
    if (req.method === 'GET' && url.pathname === '/api/actions') {
      const currentEnv = env();
      return send(res, 200, { actions: ACTIONS.map((item) => publicAction(item, currentEnv)) });
    }
    if (req.method === 'GET' && url.pathname === '/api/intents') {
      const currentEnv = env();
      return send(res, 200, { intents: INTENTS.map((item) => publicIntent(item, currentEnv)) });
    }
    const actionMatch = url.pathname.match(/^\/api\/actions\/([^/]+)\/(preview|run)$/);
    if (req.method === 'POST' && actionMatch) {
      const [, id, mode] = actionMatch;
      const body = await parseBody(req);
      return send(res, 200, mode === 'preview' ? previewAction(id, body) : await runAction(id, body));
    }
    const intentMatch = url.pathname.match(/^\/api\/intents\/([^/]+)\/(preview|reconcile)$/);
    if (req.method === 'POST' && intentMatch) {
      const [, id, mode] = intentMatch;
      const body = await parseBody(req);
      return send(res, 200, mode === 'preview' ? previewIntent(id, body) : await reconcileIntent(id, body));
    }
    return send(res, 404, { error: 'Not found' });
  } catch (error) {
    return send(res, error.status || 500, { error: String(error.message || error) });
  }
});

server.listen(port, host, () => {
  console.log(`GOLD cockpit API listening on http://${host}:${port}`);
});
