import { query, mutation } from "./_generated/server";
import { v } from "convex/values";

export const getRecentLogs = query({
  handler: async (ctx) => {
    return await ctx.db.query("agentLogs").order("desc").take(20);
  },
});

export const postLog = mutation({
  args: {
    level: v.union(v.literal("info"), v.literal("warn"), v.literal("error")),
    message: v.string(),
  },
  handler: async (ctx, { level, message }) => {
    await ctx.db.insert("agentLogs", { level, message, timestamp: Date.now() });
  },
});
