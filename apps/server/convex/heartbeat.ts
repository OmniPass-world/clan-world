import { httpAction, internalMutation } from "./_generated/server";
import { internal } from "./_generated/api";

export const heartbeatWebhook = httpAction(async (ctx, request) => {
  if (request.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const secret = process.env.WEBHOOK_SHARED_SECRET;
  const auth = request.headers.get("Authorization");
  if (!secret || auth !== `Bearer ${secret}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const newTick = await ctx.runMutation(internal.heartbeat.advanceTick, {});
  if (newTick === null) {
    return new Response(
      JSON.stringify({ status: "no-op", reason: "no snapshot to refresh" }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ status: "ok", tick: newTick }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});

export const advanceTick = internalMutation({
  handler: async (ctx): Promise<number | null> => {
    const snap = await ctx.db.query("worldSnapshot").order("desc").first();
    if (!snap) return null;

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

    return newTick;
  },
});
