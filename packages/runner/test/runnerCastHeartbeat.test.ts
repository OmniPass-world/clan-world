import { describe, expect, it } from 'vitest';
import { configFromEnv } from '../src/runnerCastHeartbeat';

describe('configFromEnv', () => {
  it('falls back to RPC_URL_FALLBACK when RPC_URL_PRIMARY is blank', () => {
    const cfg = configFromEnv({
      RUNNER_PRIVATE_KEY: '1'.repeat(64),
      CLAN_WORLD_CONTRACT_ADDRESS: '0x0000000000000000000000000000000000000001',
      RPC_URL_PRIMARY: '',
      RPC_URL_FALLBACK: 'https://fallback.example',
    });

    expect(cfg.rpcUrl).toBe('https://fallback.example');
  });
});
