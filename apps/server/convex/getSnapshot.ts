import { query } from "./_generated/server";

export const getSnapshot = query({
  handler: async (ctx) => {
    const snap = await ctx.db.query("worldSnapshot").order("desc").first();
    if (!snap) {
      return {
        tick: 0,
        tickEpoch: { startedAt: 0, durationMs: 20_000 },
        regions: [],
        clans: [],
      };
    }
    return {
      tick: snap.tick,
      tickEpoch: {
        startedAt: snap.tickEpochStartedAt,
        durationMs: snap.tickEpochDurationMs,
      },
      regions: snap.regions,
      clans: snap.clans,
    };
  },
});
