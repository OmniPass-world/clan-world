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
    seasonFinalized: v.optional(v.boolean()),
    activeBanditId: v.optional(v.number()),
    currentTickSeed: v.optional(v.string()),
    lastUpdatedAt: v.optional(v.number()),
    lastUpdatedBlock: v.optional(v.number()),
    txHash: v.optional(v.string()),
    leaderboard: v.optional(
      v.array(
        v.object({
          clanId: v.number(),
          owner: v.string(),
          monumentLevel: v.number(),
          baseLevel: v.number(),
          wallLevel: v.number(),
          livingClansmen: v.number(),
          state: v.number(),
          lootValue: v.string(),
        })
      )
    ),
  }).index("by_tick", ["tick"]),
  chainEvents: defineTable({
    txHash: v.string(),
    logIndex: v.number(),
    blockNumber: v.number(),
    eventName: v.string(),
    args: v.any(),
    decodedAt: v.number(),
    blockHash: v.optional(v.string()),
    transactionIndex: v.optional(v.number()),
    tick: v.optional(v.number()),
    clanId: v.optional(v.number()),
    clansmanId: v.optional(v.number()),
    banditId: v.optional(v.number()),
    source: v.optional(v.string()),
  })
    .index("by_tx_log", ["txHash", "logIndex"])
    .index("by_block", ["blockNumber"])
    .index("by_event_block", ["eventName", "blockNumber"])
    .index("by_tick", ["tick"])
    .index("by_clan_tick", ["clanId", "tick"]),
  tickHistory: defineTable({
    closedTick: v.number(),
    openedTick: v.number(),
    tickSeed: v.string(),
    blockNumber: v.number(),
    txHash: v.string(),
    firedAtTs: v.optional(v.number()),
    observedAt: v.number(),
  }).index("by_closedTick", ["closedTick"]),
  eventCheckpoint: defineTable({
    lastBlock: v.number(),
    lastTxHash: v.optional(v.string()),
    lastSeenAt: v.number(),
  }),
  clanView: defineTable({
    clanId: v.number(),
    owner: v.string(),
    baseRegion: v.number(),
    clanState: v.number(),
    baseLevel: v.number(),
    wallLevel: v.number(),
    monumentLevel: v.number(),
    livingClansmen: v.number(),
    isStarving: v.boolean(),
    starvationStartsAtTick: v.number(),
    coldDamage: v.number(),
    goldBalance: v.string(),
    blueprintBalance: v.string(),
    vaultWood: v.string(),
    vaultIron: v.string(),
    vaultWheat: v.string(),
    vaultFish: v.string(),
    lootValue: v.string(),
    incomingDefenderIds: v.array(v.number()),
    thisClanDefendingBaseId: v.number(),
    westPlot: v.any(),
    eastPlot: v.any(),
    clansmen: v.array(v.any()),
    derivedAtTick: v.number(),
    refreshedAt: v.number(),
    lastUpdatedBlock: v.optional(v.number()),
  }).index("by_clanId", ["clanId"]),
  marketState: defineTable({
    pools: v.array(
      v.object({
        resourceType: v.string(),
        resourceToken: v.string(),
        reserveResource: v.string(),
        reserveGold: v.string(),
        spotPriceGoldPerResource: v.string(),
      })
    ),
    currentTick: v.number(),
    currentTickQueue: v.array(v.any()),
    nextTickQueue: v.array(v.any()),
    lastUpdatedTick: v.number(),
    lastUpdatedBlock: v.optional(v.number()),
    refreshedAt: v.number(),
  }).index("by_tick", ["currentTick"]),
  banditView: defineTable({
    exists: v.boolean(),
    id: v.number(),
    region: v.number(),
    state: v.number(),
    attackPower: v.number(),
    tier: v.number(),
    attemptsMade: v.number(),
    maxAttemptsRemaining: v.number(),
    stateEnteredTick: v.number(),
    nextActionTick: v.number(),
    carryWood: v.string(),
    carryIron: v.string(),
    carryWheat: v.string(),
    carryFish: v.string(),
    projectedTargetClanId: v.number(),
    projectedTargetLootValue: v.string(),
    refreshedAt: v.number(),
    lastUpdatedBlock: v.optional(v.number()),
  }).index("by_id", ["id"]),
  pricePoint: defineTable({
    tick: v.number(),
    resourceType: v.string(),
    priceWoodGold: v.string(),
    blockNumber: v.optional(v.number()),
    observedAt: v.number(),
  })
    .index("by_tick", ["tick"])
    .index("by_resource_tick", ["resourceType", "tick"]),
  agentLogs: defineTable({
    level: v.union(v.literal("info"), v.literal("warn"), v.literal("error")),
    message: v.string(),
    timestamp: v.number(),
  }),
  inftTokens: defineTable({
    tokenId: v.number(),
    clanId: v.number(),
    owner: v.string(),
    dataHash: v.string(),
    encryptedKeyHash: v.optional(v.string()),
    metadataUri: v.optional(v.string()),
    updatedAt: v.number(),
    txHash: v.optional(v.string()),
  }).index("by_tokenId", ["tokenId"]),
  inftTransfers: defineTable({
    tokenId: v.number(),
    clanId: v.number(),
    from: v.string(),
    to: v.string(),
    dataHash: v.string(),
    encryptedKeyHash: v.string(),
    txHash: v.string(),
    transferredAt: v.number(),
  })
    .index("by_tokenId", ["tokenId"])
    .index("by_clanId", ["clanId"]),
  memoryEntries: defineTable({
    clanId: v.number(),
    key: v.string(),
    value: v.string(),
    dataHash: v.optional(v.string()),
    source: v.union(v.literal("local"), v.literal("0g"), v.literal("demo")),
    updatedAt: v.number(),
    txHash: v.optional(v.string()),
  })
    .index("by_clan_key", ["clanId", "key"])
    .index("by_clan", ["clanId"]),
  bulletins: defineTable({
    clanId: v.number(),
    slot: v.number(),
    body: v.string(),
    updatedAt: v.number(),
    dataHash: v.optional(v.string()),
    txHash: v.optional(v.string()),
  }).index("by_clan_slot", ["clanId", "slot"]),
  verifiedNullifiers: defineTable({
    nullifier: v.string(),
  }).index("by_nullifier", ["nullifier"]),
});
