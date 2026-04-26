// MOCK_MODE=true in .env.local is a dev convention for this environment.
// This seeder is called manually via `pnpm convex run mock:seedMockState`.
// Nothing reads MOCK_MODE at runtime yet — it's a placeholder toggle for Wave 1.

import { mutation } from "./_generated/server";

const MOCK_REGIONS = [
  { id: "forest", name: "Forest", ownerClanId: "clan-iron" },
  { id: "mountains", name: "Mountains", ownerClanId: "clan-ember" },
  { id: "unicorn-town", name: "Unicorn Town", ownerClanId: null },
  { id: "west-farms", name: "West Farms", ownerClanId: "clan-dawn" },
  { id: "east-farms", name: "East Farms", ownerClanId: "clan-storm" },
  { id: "west-docks", name: "West Docks", ownerClanId: "clan-iron" },
  { id: "east-docks", name: "East Docks", ownerClanId: "clan-ember" },
  { id: "deep-sea", name: "Deep Sea", ownerClanId: null },
];

const MOCK_CLANS = [
  { id: "clan-iron", name: "Iron Guard", treasury: "1000000000000000000000" },
  { id: "clan-ember", name: "Ember Hand", treasury: "750000000000000000000" },
  { id: "clan-dawn", name: "Dawn Watch", treasury: "500000000000000000000" },
  { id: "clan-storm", name: "Storm Riders", treasury: "250000000000000000000" },
];

export const seedMockState = mutation({
  handler: async (ctx) => {
    // Insert mock snapshot
    await ctx.db.insert("worldSnapshot", {
      tick: 42,
      tickEpochStartedAt: Math.floor(Date.now() / 1000) - 42 * 20,
      tickEpochDurationMs: 20_000,
      regions: MOCK_REGIONS,
      clans: MOCK_CLANS,
    });

    // Seed 5 agent log entries
    const logs = [
      { level: "info" as const, message: "Agent initialized — tick 42" },
      { level: "info" as const, message: "Clan Iron Guard dispatched 3 clansmen to Forest" },
      { level: "warn" as const, message: "Bandit troop spotted near Mountains (tier 2)" },
      { level: "info" as const, message: "Clan Ember Hand completed resource deposit" },
      { level: "error" as const, message: "Heartbeat delayed — RPC timeout, retrying" },
    ];
    for (const log of logs) {
      await ctx.db.insert("agentLogs", { ...log, timestamp: Date.now() });
    }
  },
});
