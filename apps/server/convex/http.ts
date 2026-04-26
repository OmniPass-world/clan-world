import { httpRouter } from "convex/server";
import { heartbeatWebhook } from "./heartbeat";
import { verifyWorldId } from "./verify";

const http = httpRouter();
http.route({ path: "/api/heartbeat-webhook", method: "POST", handler: heartbeatWebhook });
http.route({ path: "/api/verify", method: "POST", handler: verifyWorldId });
export default http;
