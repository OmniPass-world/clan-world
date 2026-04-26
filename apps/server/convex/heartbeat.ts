import { httpAction, internalMutation } from "./_generated/server";
import { internal } from "./_generated/api";

export const heartbeatWebhook = httpAction(async (ctx, request) => {
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", Allow: "POST" },
    });
  }

  const secret = process.env.WEBHOOK_SHARED_SECRET;
  const auth = request.headers.get("Authorization");
  if (!secret || auth !== `Bearer ${secret}`) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const result = await ctx.runMutation(internal.heartbeat.advanceTick, {});

  return new Response(JSON.stringify(result), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

type AdvanceTickResult =
  | { status: "ok"; tick: number }
  | { status: "no-op"; reason: string };

export const advanceTick = internalMutation({
  handler: async (ctx): Promise<AdvanceTickResult> => {
    const snap = await ctx.db.query("worldSnapshot").order("desc").first();
    if (!snap) return { status: "no-op", reason: "no snapshot to refresh" };

    // Staleness gate: only advance if the current epoch has elapsed.
    // Prevents cron from double-advancing (fires 4x/epoch) and concurrent
    // calls from inserting duplicate tick rows.
    const nowSeconds = Math.floor(Date.now() / 1000);
    const epochEndSeconds =
      snap.tickEpochStartedAt +
      Math.floor(snap.tickEpochDurationMs / 1000);
    if (nowSeconds < epochEndSeconds) {
      return { status: "no-op", reason: "epoch not yet elapsed" };
    }

    const newTick = snap.tick + 1;
    await ctx.db.insert("worldSnapshot", {
      tick: newTick,
      tickEpochStartedAt: Math.floor(Date.now() / 1000),
      tickEpochDurationMs: snap.tickEpochDurationMs,
      regions: snap.regions,
      clans: snap.clans,
    });
    await ctx.db.insert("agentLogs", {
      level: "info",
      message: `heartbeat: tick ${snap.tick} → ${newTick}`,
      timestamp: Date.now(),
    });

    return { status: "ok", tick: newTick };
  },
});
