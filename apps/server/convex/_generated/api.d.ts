/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";
import type * as agentLogs from "../agentLogs.js";
import type * as crons from "../crons.js";
import type * as getSnapshot from "../getSnapshot.js";
import type * as heartbeat from "../heartbeat.js";
import type * as http from "../http.js";
import type * as mock from "../mock.js";
import type * as verify from "../verify.js";

/**
 * A utility for referencing Convex functions in your app's API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
declare const fullApi: ApiFromModules<{
  agentLogs: typeof agentLogs;
  crons: typeof crons;
  getSnapshot: typeof getSnapshot;
  heartbeat: typeof heartbeat;
  http: typeof http;
  mock: typeof mock;
  verify: typeof verify;
}>;
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;
