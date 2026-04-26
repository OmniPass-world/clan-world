import { useQuery } from 'convex/react';
import { type FunctionReference, anyApi } from 'convex/server';

// anyApi is a Proxy that lazily builds function-reference paths at runtime.
// The `!` is a TypeScript appeasement only — anyApi itself never returns null/undefined.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const getRecentLogsRef = anyApi.agentLogs!.getRecentLogs as FunctionReference<'query'>;

export interface AgentLog {
  _id: string;
  level: 'info' | 'warn' | 'error';
  message: string;
  timestamp: number;
}

export function useAgentLogs(): AgentLog[] {
  return (useQuery(getRecentLogsRef) ?? []) as AgentLog[];
}
