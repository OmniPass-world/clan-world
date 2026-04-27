/**
 * Elder Runner — entry point.
 *
 * Memory adapter selection:
 *   - OG_STORAGE_API_KEY set   → ZeroGMemoryStore (0G KV + OG_STREAM_ID required)
 *   - OG_STORAGE_API_KEY unset → FileMemoryStore (local JSON fallback)
 *
 * Peer inbox adapter selection (Phase 8):
 *   - AXL_API_KEY + AXL_NETWORK_ID set → AxlPeerInbox (Gensyn AXL transport)
 *   - AXL_API_KEY unset or AXL_NETWORK_ID empty → FilePeerInbox (file-based fallback)
 *
 * See packages/runner/.env.example for configuration.
 */
import { createMemoryStore } from './zeroGMemoryStore.js';
import { createPeerInbox } from './axlPeerInbox.js';

async function main(): Promise<void> {
  const elderN = parseInt(process.env['ELDER_N'] ?? '1', 10);

  const memory = await createMemoryStore({ elderN });
  const peerInbox = await createPeerInbox();

  const memoryBackend = process.env['OG_STORAGE_API_KEY'] ? '0G-KV' : 'local-file';
  const peerBackend =
    process.env['AXL_API_KEY'] && process.env['AXL_NETWORK_ID'] ? 'AXL' : 'file';

  console.error(
    `[runner] elder=${elderN} memory=${memoryBackend} peer=${peerBackend}`,
  );

  // Smoke-test the adapters on startup.
  const existing = await memory.snapshot();
  console.error(`[runner] memory snapshot has ${Object.keys(existing).length} key(s)`);

  const inboxMessages = await peerInbox.inbox();
  console.error(`[runner] peer inbox has ${inboxMessages.length} message(s)`);

  // TODO: Wire Elder tick loop here (Phase 9+).
  // Both adapters are ready — pass them into the Elder agent loop.
  console.log(
    JSON.stringify(
      {
        status: 'ready',
        elderN,
        memoryBackend,
        peerBackend,
        memoryKeys: Object.keys(existing),
        inboxCount: inboxMessages.length,
      },
      null,
      2,
    ),
  );
}

main().catch(err => {
  console.error('[runner] fatal:', err);
  process.exit(1);
});
