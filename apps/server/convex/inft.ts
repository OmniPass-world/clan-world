import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

/**
 * Mirror mutations require INDEXER_SECRET to match the Convex env var of the
 * same name — set this on the Convex dashboard. Indexers/scripts pass it in
 * the `secret` arg. If INDEXER_SECRET is unset on the deployment, mutations
 * reject all writes (fail-closed). Demo Convex dashboards must set this before
 * the indexer ships.
 */
function requireIndexerSecret(supplied: string): void {
  const expected = process.env.INDEXER_SECRET;
  if (!expected) {
    throw new Error("INDEXER_SECRET is not configured on this Convex deployment");
  }
  if (supplied !== expected) {
    throw new Error("invalid indexer secret");
  }
}

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
    secret: v.string(),
    tokenId: v.number(),
    clanId: v.number(),
    owner: v.string(),
    dataHash: v.string(),
    encryptedKeyHash: v.optional(v.string()),
    metadataUri: v.optional(v.string()),
    txHash: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    requireIndexerSecret(args.secret);
    const { secret: _omit, ...row } = args;
    const existing = await ctx.db
      .query("inftTokens")
      .withIndex("by_tokenId", (q) => q.eq("tokenId", row.tokenId))
      .first();
    const stamped = { ...row, updatedAt: Date.now() };
    if (existing) {
      await ctx.db.patch(existing._id, stamped);
      return existing._id;
    }
    return await ctx.db.insert("inftTokens", stamped);
  },
});

export const mirrorTransfer = mutation({
  args: {
    secret: v.string(),
    tokenId: v.number(),
    clanId: v.number(),
    from: v.string(),
    to: v.string(),
    dataHash: v.string(),
    encryptedKeyHash: v.string(),
    txHash: v.string(),
  },
  handler: async (ctx, args) => {
    requireIndexerSecret(args.secret);
    const { secret: _omit, ...row } = args;
    return await ctx.db.insert("inftTransfers", {
      ...row,
      transferredAt: Date.now(),
    });
  },
});

export const mirrorMemoryEntry = mutation({
  args: {
    secret: v.string(),
    clanId: v.number(),
    key: v.string(),
    value: v.string(),
    dataHash: v.optional(v.string()),
    source: v.union(v.literal("local"), v.literal("0g"), v.literal("demo")),
    txHash: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    requireIndexerSecret(args.secret);
    const { secret: _omit, ...row } = args;
    const existing = await ctx.db
      .query("memoryEntries")
      .withIndex("by_clan_key", (q) => q.eq("clanId", row.clanId).eq("key", row.key))
      .first();
    const stamped = { ...row, updatedAt: Date.now() };
    if (existing) {
      await ctx.db.patch(existing._id, stamped);
      return existing._id;
    }
    return await ctx.db.insert("memoryEntries", stamped);
  },
});

export const mirrorBulletin = mutation({
  args: {
    secret: v.string(),
    clanId: v.number(),
    slot: v.number(),
    body: v.string(),
    dataHash: v.optional(v.string()),
    txHash: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    requireIndexerSecret(args.secret);
    const { secret: _omit, ...row } = args;
    const existing = await ctx.db
      .query("bulletins")
      .withIndex("by_clan_slot", (q) => q.eq("clanId", row.clanId).eq("slot", row.slot))
      .first();
    const stamped = { ...row, updatedAt: Date.now() };
    if (existing) {
      await ctx.db.patch(existing._id, stamped);
      return existing._id;
    }
    return await ctx.db.insert("bulletins", stamped);
  },
});
