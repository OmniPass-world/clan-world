import { test } from '@playwright/test';

// Placeholder for message taxonomy v4.6 e2e coverage.
// Spec: ~/claudes-world/tmp/20260426-message-taxonomy-response.md
//
// Five event classes that will eventually be tested as distinct visual
// bubble styles in the world feed:
//   1. world events       — parchment-style global ticks / chain heartbeat
//   2. agent inputs       — what the Elder LLM saw in its <situation> block
//   3. agent thoughts     — internal reasoning rendered for spectator UI
//   4. agent directives   — orders the Elder issued (chain txs / mission queue)
//   5. clansman comms     — clan-internal whispers + cross-clan diplomacy
//
// Each class needs: distinct `data-testid` (e.g. `bubble-world-event`,
// `bubble-agent-input`, ...), distinct visual treatment, correct ordering in
// the feed by tick + intra-tick sequence.
//
// Unskip + flesh out once the taxonomy is implemented in apps/web.

test.describe('message bubble taxonomy v4.6 (Phase 4)', () => {
  test.skip('renders all 5 event classes with distinct styling', async () => {
    // TODO: implement when message taxonomy lands. See spec link above.
  });
});
