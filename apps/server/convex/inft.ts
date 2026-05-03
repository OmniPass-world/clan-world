import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const getInftDemoState = query({
  args: { clanId: v.number() },
  handler: async (ctx, { clanId }) => {
    const token = await ctx.db
      .query("inftTokens")
      .withIndex("by_tokenId", (q) => q.eq("tokenId", clanId))
      .order("desc")
      .first();
    const transfers = await ctx.db
      .query("inftTransfers")
      .withIndex("by_clanId", (q) => q.eq("clanId", clanId))
      .order("desc")
      .take(8);
    const memory = await ctx.db
      .query("memoryEntries")
      .withIndex("by_clan", (q) => q.eq("clanId", clanId))
      .order("desc")
      .take(20);
    const bulletins = await ctx.db
      .query("bulletins")
      .filter((q) => q.eq(q.field("clanId"), clanId))
      .order("desc")
      .take(8);

    return { token, transfers, memory, bulletins };
  },
});

export const mirrorToken = mutation({
  args: {
    tokenId: v.number(),
    clanId: v.number(),
    owner: v.string(),
    dataHash: v.string(),
    encryptedKeyHash: v.optional(v.string()),
    metadataUri: v.optional(v.string()),
    txHash: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("inftTokens")
      .withIndex("by_tokenId", (q) => q.eq("tokenId", args.tokenId))
      .first();
    const row = { ...args, updatedAt: Date.now() };
    if (existing) {
      await ctx.db.patch(existing._id, row);
      return existing._id;
    }
    return await ctx.db.insert("inftTokens", row);
  },
});

export const mirrorTransfer = mutation({
  args: {
    tokenId: v.number(),
    clanId: v.number(),
    from: v.string(),
    to: v.string(),
    dataHash: v.string(),
    encryptedKeyHash: v.string(),
    txHash: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("inftTransfers", {
      ...args,
      transferredAt: Date.now(),
    });
  },
});

export const mirrorMemoryEntry = mutation({
  args: {
    clanId: v.number(),
    key: v.string(),
    value: v.string(),
    dataHash: v.optional(v.string()),
    source: v.union(v.literal("local"), v.literal("0g"), v.literal("demo")),
    txHash: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("memoryEntries")
      .withIndex("by_clan_key", (q) => q.eq("clanId", args.clanId).eq("key", args.key))
      .first();
    const row = { ...args, updatedAt: Date.now() };
    if (existing) {
      await ctx.db.patch(existing._id, row);
      return existing._id;
    }
    return await ctx.db.insert("memoryEntries", row);
  },
});

export const mirrorBulletin = mutation({
  args: {
    clanId: v.number(),
    slot: v.number(),
    body: v.string(),
    dataHash: v.optional(v.string()),
    txHash: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("bulletins")
      .withIndex("by_clan_slot", (q) => q.eq("clanId", args.clanId).eq("slot", args.slot))
      .first();
    const row = { ...args, updatedAt: Date.now() };
    if (existing) {
      await ctx.db.patch(existing._id, row);
      return existing._id;
    }
    return await ctx.db.insert("bulletins", row);
  },
});
