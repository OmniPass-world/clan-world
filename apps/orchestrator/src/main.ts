import type { ClanOrder } from '@clan-world/shared';
import { createChainClient, createConvexClient } from '@clan-world/shared/adapters';

const CLAN_ID = process.env.CLAN_ID || '1';

async function main(): Promise<void> {
  const chain = createChainClient();
  const convex = createConvexClient();

  // Get current tick
  const tick = await chain.getCurrentTick();
  console.error(`[orchestrator] tick=${tick}`);

  // Hardcoded mission for clan-1: clansman 1 chops wood in Forest
  const orders: ClanOrder[] = [
    {
      kind: 'mission',
      payload: { clansmanId: 1, gotoRegion: 0, action: 1 }, // action=1 is ChopWood
    },
  ];

  console.error(`[orchestrator] submitting orders for clan-${CLAN_ID}...`);
  const { txHash, results } = await chain.submitOrders(CLAN_ID, orders);
  const failedResults = results.filter(result => result.status !== 0);
  console.error(`[orchestrator] tx submitted: ${txHash}; results=${JSON.stringify(results)}`);
  if (failedResults.length > 0) {
    console.error(`[orchestrator] ${failedResults.length} order(s) returned non-OK status`);
  }

  try {
    await convex.postLog(
      failedResults.length > 0 ? 'warn' : 'info',
      `Elder Aldric (clan-${CLAN_ID}): ChopWood submitted — txHash=${txHash} tick=${tick} results=${JSON.stringify(results)}`,
    );
  } catch (err) {
    console.error('[orchestrator] convex log failed (non-fatal):', err);
  }

  // Print final JSON summary to stdout
  process.stdout.write(
    JSON.stringify({ tick, txHash, results, clan: CLAN_ID, mission: 'ChopWood-Forest' }, null, 2) + '\n',
  );
}

main().catch(err => {
  console.error('[orchestrator] fatal:', err);
  process.exit(1);
});
