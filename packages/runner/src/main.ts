/**
 * Elder Runner — entry point.
 *
 * Memory adapter selection:
 *   - OG_STORAGE_API_KEY set   → ZeroGMemoryStore (0G KV + OG_STREAM_ID required)
 *   - OG_STORAGE_API_KEY unset → FileMemoryStore (local JSON fallback)
 *
 * See packages/runner/.env.example for configuration.
 */
import { createMemoryStore } from './zeroGMemoryStore.js';

async function main(): Promise<void> {
  // Do NOT parseInt here — pass raw env string to createMemoryStore so the strict
  // /^[1-4]$/ regex validator is the sole parse+validation point. Laundering via
  // parseInt would let "1.5" or "1abc" silently become 1 before validation runs.
  const memory = await createMemoryStore();

  // Read back the resolved index for logging only (after validation has passed).
  const rawIndex = process.env['ELDER_INDEX'] ?? '';
  const elderIndex = parseInt(rawIndex, 10);

  console.error(
    `[runner] elder=${elderIndex} memory=${
      process.env['OG_STORAGE_API_KEY'] ? '0G-KV' : 'local-file'
    }`,
  );

  // Smoke-test the adapter on startup.
  const existing = await memory.snapshot();
  console.error(`[runner] memory snapshot has ${Object.keys(existing).length} key(s)`);

  // TODO: Wire Elder tick loop here (Phase 8+).
  // The memory store is ready — pass it into the Elder agent loop.
  console.log(JSON.stringify({ status: 'ready', elderIndex, keys: Object.keys(existing) }, null, 2));
}

main().catch(err => {
  console.error('[runner] fatal:', err);
  process.exit(1);
});
