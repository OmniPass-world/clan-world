import { httpRouter } from "convex/server";
import { heartbeatWebhook } from "./heartbeat";

const http = httpRouter();
http.route({ path: "/api/heartbeat-webhook", method: "POST", handler: heartbeatWebhook });
export default http;
