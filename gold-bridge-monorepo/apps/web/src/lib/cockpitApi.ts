import type {
  CockpitAction,
  CockpitActionPreview,
  CockpitActionResult,
  CockpitIntent,
  CockpitIntentResult,
  CockpitState,
  DeploymentGuide,
  ReadinessReport
} from '../types';

const API_BASE = import.meta.env.VITE_COCKPIT_API_URL || 'http://127.0.0.1:8787';

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      'content-type': 'application/json',
      ...(init?.headers || {})
    }
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json.error || `Cockpit API HTTP ${res.status}`);
  return json as T;
}

export function fetchCockpitState() {
  return api<CockpitState>('/api/state');
}

export async function fetchCockpitActions() {
  const payload = await api<{ actions: CockpitAction[] }>('/api/actions');
  return payload.actions;
}

export function previewCockpitAction(id: string, env: Record<string, string>) {
  return api<CockpitActionPreview>(`/api/actions/${id}/preview`, {
    method: 'POST',
    body: JSON.stringify({ env })
  });
}

export function runCockpitAction(id: string, env: Record<string, string>, confirmation: string) {
  return api<CockpitActionResult>(`/api/actions/${id}/run`, {
    method: 'POST',
    body: JSON.stringify({ env, confirmation })
  });
}

export async function fetchCockpitIntents() {
  const payload = await api<{ intents: CockpitIntent[] }>('/api/intents');
  return payload.intents;
}

export function previewCockpitIntent(id: string, args: Record<string, string>) {
  return api<CockpitIntent>(`/api/intents/${id}/preview`, {
    method: 'POST',
    body: JSON.stringify({ args })
  });
}

export function reconcileCockpitIntent(
  id: string,
  txHash: string,
  confirmation: string,
  contractAddress?: string
) {
  return api<CockpitIntentResult>(`/api/intents/${id}/reconcile`, {
    method: 'POST',
    body: JSON.stringify({ txHash, contractAddress, confirmation })
  });
}

export function fetchReadinessReport() {
  return api<ReadinessReport>('/api/readiness');
}

export function fetchDeploymentGuide() {
  return api<DeploymentGuide>('/api/guide');
}

export function exportReadinessReport(manualNotes: Record<string, string>) {
  return api<ReadinessReport>('/api/readiness/export', {
    method: 'POST',
    body: JSON.stringify({ manualNotes })
  });
}
