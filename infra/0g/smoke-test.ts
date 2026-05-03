/**
 * 0G mainnet smoke test — proves all 4 elder wallets can save + recall via the
 * real 0G KV backend (not the FileMemoryStore fallback).
 *
 * Usage:
 *   pnpm tsx infra/0g/smoke-test.ts
 *
 * Reads ELDER_MNEMONIC from ~/.secrets/clanworld-elder-wallets.json (key
 * `mnemonic12`). Wallets are funded with 50 0G each — see the 0G deployment
 * notes under docs/planning/V1/ for the cost model.
 *
 * Exit 0 = all 4 elders round-tripped. Exit 1 = any failure.
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createMemoryStore } from '../../packages/runner/src/zeroGMemoryStore.js';

const SECRETS_PATH = join(homedir(), '.secrets', 'clanworld-elder-wallets.json');

interface WalletsFile {
  mnemonic12: string;
  elders: Array<{ index: number; address: string; derivationPath: string }>;
}

function loadMnemonic(): { mnemonic: string; elderCount: number } {
  const raw = readFileSync(SECRETS_PATH, 'utf8');
  const parsed = JSON.parse(raw) as WalletsFile;
  if (!parsed.mnemonic12 || parsed.elders.length !== 4) {
    throw new Error(
      `${SECRETS_PATH}: expected mnemonic12 + 4 elders, got mnemonic=${!!parsed.mnemonic12} elders=${parsed.elders.length}`,
    );
  }
  return { mnemonic: parsed.mnemonic12, elderCount: parsed.elders.length };
}

async function smokeOneElder(elderIndex: number, mnemonic: string): Promise<boolean> {
  const env = {
    ...process.env,
    OG_STORAGE_ENABLED: 'true',
    ELDER_MNEMONIC: mnemonic,
    ELDER_INDEX: String(elderIndex),
  };

  console.log(`\n--- elder ${elderIndex} ---`);
  const store = await createMemoryStore({ elderIndex, env });
  const key = `smoke-${Date.now()}`;
  const value = `elder-${elderIndex}-roundtrip`;

  console.log(`[smoke] elder ${elderIndex}: save key=${key} value=${value}`);
  const t0 = Date.now();
  await store.save(key, value);
  const saveMs = Date.now() - t0;
  console.log(`[smoke] elder ${elderIndex}: save took ${saveMs}ms`);

  const recalled = await store.recall(key);
  if (recalled !== value) {
    console.error(`[smoke] elder ${elderIndex}: recall MISMATCH expected="${value}" got="${recalled}"`);
    return false;
  }

  console.log(`[smoke] elder ${elderIndex}: roundtrip OK`);
  return true;
}

async function main(): Promise<void> {
  const { mnemonic, elderCount } = loadMnemonic();
  console.log(`[smoke] loaded wallets file (${elderCount} elders); starting roundtrip per elder.`);

  const results: Array<{ elder: number; ok: boolean; err?: string }> = [];
  for (let i = 1; i <= elderCount; i += 1) {
    try {
      const ok = await smokeOneElder(i, mnemonic);
      results.push({ elder: i, ok });
    } catch (err) {
      results.push({ elder: i, ok: false, err: err instanceof Error ? err.message : String(err) });
      console.error(`[smoke] elder ${i}: FAIL`, err);
    }
  }

  console.log('\n=== SUMMARY ===');
  for (const r of results) {
    console.log(`  elder ${r.elder}: ${r.ok ? 'OK' : `FAIL (${r.err ?? 'roundtrip mismatch'})`}`);
  }

  const allOk = results.every((r) => r.ok);
  if (!allOk) process.exit(1);
  console.log('\n[smoke] all 4 elders OK on 0G mainnet.');
}

main().catch((err) => {
  console.error('[smoke] fatal', err);
  process.exit(1);
});
