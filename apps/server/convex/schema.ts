import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  worldSnapshot: defineTable({
    tick: v.number(),
    tickEpochStartedAt: v.number(),
    tickEpochDurationMs: v.number(),
    // Season + winter timers (Phase 4.4)
    currentSeasonNumber: v.optional(v.number()),
    seasonStartTick: v.optional(v.number()),
    seasonEndTick: v.optional(v.number()),
    winterActive: v.optional(v.boolean()),
    winterStartsAtTick: v.optional(v.number()),
    winterEndsAtTick: v.optional(v.number()),
    nextHeartbeatAtTick: v.optional(v.number()),
    regions: v.array(
      v.object({
        id: v.string(),
        name: v.string(),
        ownerClanId: v.union(v.string(), v.null()),
      })
    ),
    clans: v.array(
      v.object({
        id: v.string(),
        name: v.string(),
        treasury: v.string(),
      })
    ),
  }),
  agentLogs: defineTable({
    level: v.union(v.literal("info"), v.literal("warn"), v.literal("error")),
    message: v.string(),
    timestamp: v.number(),
  }),
  verifiedNullifiers: defineTable({
    nullifier: v.string(),
  }).index("by_nullifier", ["nullifier"]),
});
