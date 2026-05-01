import { query } from "./_generated/server";
import { HEARTBEAT_INTERVAL_SECONDS } from "@clan-world/shared/generated/constants";

export const getSnapshot = query({
  handler: async (ctx) => {
    const snap = await ctx.db.query("worldSnapshot").order("desc").first();
    if (!snap) {
      return {
        tick: 0,
        tickEpoch: { startedAt: 0, durationMs: Number(HEARTBEAT_INTERVAL_SECONDS) * 1000 },
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
