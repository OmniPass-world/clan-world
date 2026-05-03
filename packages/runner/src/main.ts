import os from 'node:os';
import path from 'node:path';
import { createConvexClient } from '@clan-world/shared/adapters';
import { configFromEnv, RunnerCastHeartbeat } from './runnerCastHeartbeat';
import { startHeartbeatScheduler } from './heartbeatScheduler';
import { tickLoop, type PerElderDeps } from './tickLoop';
import { makeSettleLatch } from './settleLatch';
import { TmuxRunnerInbox } from './tmuxRunnerInbox';
import { ELDER_IDS, type ElderId, type RunnerConfig } from './types';
import { createMemoryStore } from './zeroGMemoryStore';
import { createPeerInbox } from './axlPeerInbox';

/**
 * Default state directory. Matches the layout the Elder CLI reads/writes
 * (`packages/agents/src/cli.ts::stateDir`).
 */
function defaultStateDir(): string {
  return path.join(os.homedir(), '.world', 'clanworld-runner', 'state');
}

/**
 * Bootstrap block sent immediately after `/clear` so the freshly reset Elder
 * session knows who it is. The runner sends a full situation block on the
 * next tick — this is just the "you are Elder N, clan X, await tick" preamble.
 */
function bootstrapBlock(elder: ElderId, clanId: string): string {
  return [
    `# Bootstrap — Elder ${elder} (Clan ${clanId})`,
    '',
    `You are Elder ${elder} of Clan ${clanId} in ClanWorld. Your context was just reset.`,
    'A full situation block will arrive on the next tick. Until then, you can use the `elder` CLI to:',
    '- `elder world snapshot`             — read current world state',
    `- \`elder clan view ${clanId}\`     — read your clan's state`,
    '- `elder memory recall <key>`        — restore continuity from prior cycles',
    '- `elder peer inbox`                  — read whispers',
    '',
    'Wait for the next tick.',
  ].join('\n');
}

function loadConfig(env: NodeJS.ProcessEnv = process.env): RunnerConfig {
  const stateDir = env['CLAN_WORLD_RUNNER_STATE_DIR'] ?? defaultStateDir();
  const pollIntervalMs = parseIntEnv(env, 'RUNNER_POLL_INTERVAL_MS', 5_000);
  const settleWindowSec = parseIntEnv(env, 'RUNNER_SETTLE_WINDOW_SEC', 90);
  const deliveryTimeoutMs = parseIntEnv(env, 'RUNNER_DELIVERY_TIMEOUT_MS', 10_000);
  const ackTimeoutMs = parseIntEnv(env, 'RUNNER_ACK_TIMEOUT_MS', 30_000);
  const heartbeatCheckIntervalMs = parseIntEnv(env, 'RUNNER_HEARTBEAT_CHECK_INTERVAL_MS', 30_000);
  const tmuxSessionPrefix = env['RUNNER_TMUX_SESSION_PREFIX'] ?? 'elder';
  const elderToClanId: Record<ElderId, string> = {
    1: env['ELDER_1_CLAN_ID'] ?? '1',
    2: env['ELDER_2_CLAN_ID'] ?? '2',
    3: env['ELDER_3_CLAN_ID'] ?? '3',
    4: env['ELDER_4_CLAN_ID'] ?? '4',
  };
  return {
    pollIntervalMs,
    settleWindowSec,
    deliveryTimeoutMs,
    ackTimeoutMs,
    heartbeatCheckIntervalMs,
    stateDir,
    tmuxSessionPrefix,
    elderToClanId,
  };
}

function parseIntEnv(env: NodeJS.ProcessEnv, key: string, fallback: number): number {
  const v = env[key];
  if (!v) return fallback;
  const n = parseInt(v, 10);
  if (!Number.isFinite(n) || n <= 0) {
    throw new Error(`${key} must be a positive integer; got '${v}'`);
  }
  return n;
}

async function main(): Promise<void> {
  console.log(`[runner] starting ClanWorld runner daemon at ${new Date().toISOString()}`);

  const config = loadConfig();
  const memoryBackend = process.env['OG_STORAGE_ENABLED'] ? '0G-KV' : 'local-file';
  const peerBackend =
    process.env['AXL_API_KEY'] && process.env['AXL_NETWORK_ID'] ? 'axl' : 'file';
  console.log('[runner] config:', {
    stateDir: config.stateDir,
    pollIntervalMs: config.pollIntervalMs,
    settleWindowSec: config.settleWindowSec,
    tmuxSessionPrefix: config.tmuxSessionPrefix,
    elderToClanId: config.elderToClanId,
    memory: memoryBackend,
    peer: peerBackend,
  });
  console.log(`[runner] memory=${memoryBackend} peer=${peerBackend}`);

  const convex = createConvexClient();
  const heartbeatCaller = new RunnerCastHeartbeat(configFromEnv());

  const perElder = {} as Record<ElderId, PerElderDeps>;
  for (const elder of ELDER_IDS) {
    const clanId = config.elderToClanId[elder];
    // Memory adapter selection: ZeroGMemoryStore if OG_STORAGE_ENABLED is set,
    // FileMemoryStore otherwise. Pass elderIndex explicitly so we don't depend
    // on ELDER_INDEX env (the runner serves all 4 Elders, not just one).
    const memory = await createMemoryStore({
      elderIndex: elder,
      clanId,
      stateDir: config.stateDir,
    });
    // Peer transport selection: AxlPeerInbox if AXL_API_KEY + AXL_NETWORK_ID set,
    // FilePeerInbox otherwise. Pass elder + myClanId explicitly so the factory
    // does not depend on per-process ELDER_N env (multi-elder runner).
    const peerInbox = await createPeerInbox({
      elder,
      myClanId: clanId,
      stateDir: config.stateDir,
    });
    perElder[elder] = {
      inbox: new TmuxRunnerInbox({
        elder,
        sessionPrefix: config.tmuxSessionPrefix,
        stateDir: config.stateDir,
        bootstrapBlock: bootstrapBlock(elder, clanId),
      }),
      memory,
      peerInbox,
    };
  }

  const abort = new AbortController();
  let shuttingDown = false;
  const onSignal = (sig: string): void => {
    if (shuttingDown) return;
    shuttingDown = true;
    console.log(`[runner] ${sig} received — shutting down cleanly`);
    abort.abort();
  };
  process.on('SIGTERM', () => onSignal('SIGTERM'));
  process.on('SIGINT', () => onSignal('SIGINT'));

  const settleLatch = makeSettleLatch();

  startHeartbeatScheduler({
    heartbeatCaller,
    signal: abort.signal,
    checkIntervalMs: config.heartbeatCheckIntervalMs,
    settleLatch,
  });

  try {
    await tickLoop({
      convex,
      perElder,
      config,
      signal: abort.signal,
      settleLatch,
    });
  } finally {
    console.log('[runner] tick loop exited');
  }
}

main().catch(err => {
  console.error('[runner] fatal:', err);
  process.exit(1);
});
