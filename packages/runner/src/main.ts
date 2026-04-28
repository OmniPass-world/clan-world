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
  const elderIndex = parseInt(process.env['ELDER_INDEX'] ?? '1', 10);

  const memory = await createMemoryStore({ elderIndex });

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
