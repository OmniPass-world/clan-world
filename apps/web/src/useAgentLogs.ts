import { useQuery } from 'convex/react';
import { api } from '../../server/convex/_generated/api';
import type { Doc } from '../../server/convex/_generated/dataModel';

export type AgentLog = Doc<'agentLogs'>;

export function useAgentLogs(): AgentLog[] {
  return useQuery(api.agentLogs.getRecentLogs) ?? [];
}
