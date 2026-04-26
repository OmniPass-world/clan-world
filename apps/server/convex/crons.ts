import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();
crons.interval("heartbeat-safety-net", { seconds: 5 }, internal.heartbeat.advanceTick, {});
export default crons;
