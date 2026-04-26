import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { heartbeatWebhook } from "./heartbeat";
import { verifyWorldId } from "./verify";

const http = httpRouter();
http.route({ path: "/api/heartbeat-webhook", method: "POST", handler: heartbeatWebhook });
http.route({ path: "/api/verify", method: "POST", handler: verifyWorldId });
http.route({
  path: "/api/verify",
  method: "OPTIONS",
  handler: httpAction(async () => new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
  })),
});
export default http;
