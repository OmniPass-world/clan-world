import { useQuery } from 'convex/react';
import { type FunctionReference, anyApi } from 'convex/server';

// anyApi path may be undefined at compile time — non-null assertion is safe here because
// the agentLogs module is guaranteed to exist in the Convex deployment.
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
