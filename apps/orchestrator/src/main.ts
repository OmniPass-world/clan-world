import type { ClanOrder } from '@clan-world/shared';
import { createChainClient, createConvexClient } from '@clan-world/shared/adapters';

async function main(): Promise<void> {
  const chain = createChainClient();
  const convex = createConvexClient();

  // Get current tick
  const tick = await chain.getCurrentTick();
  console.error(`[orchestrator] tick=${tick}`);

  // Hardcoded mission for clan-0: clansman 1 chops wood in Forest
  const orders: ClanOrder[] = [
    {
      kind: 'mission',
      payload: { clansmanId: 1, gotoRegion: 0, action: 1 }, // action=1 is ChopWood
    },
  ];

  console.error('[orchestrator] submitting orders for clan-0...');
  const { txHash } = await chain.submitOrders('0', orders);
  console.error(`[orchestrator] tx submitted: ${txHash}`);

  try {
    await convex.postLog('info', `Elder Aldric (clan-0): ChopWood submitted — txHash=${txHash} tick=${tick}`);
  } catch (err) {
    console.error('[orchestrator] convex log failed (non-fatal):', err);
  }

  // Print final JSON summary to stdout
  process.stdout.write(
    JSON.stringify({ tick, txHash, clan: '0', mission: 'ChopWood-Forest' }, null, 2) + '\n',
  );
}

main().catch(err => {
  console.error('[orchestrator] fatal:', err);
  process.exit(1);
});
