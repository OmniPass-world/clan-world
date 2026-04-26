import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  worldSnapshot: defineTable({
    tick: v.number(),
    tickEpochStartedAt: v.number(),
    tickEpochDurationMs: v.number(),
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
});
