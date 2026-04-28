import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { execSync } from 'node:child_process';
import path from 'node:path';

// Canonical port resolved from port-for registry (clan-world slot 587, env=dev).
// Falls back to FALLBACK_PORT (canonical value from .world/ports.yml) when port-for is
// unavailable (CI, non-do-box hosts). PORT env override takes precedence.
const FALLBACK_PORT = 58740;
const DEFAULT_PORT = (() => {
  if (process.env.PORT) {
    const p = parseInt(process.env.PORT, 10);
    return Number.isNaN(p) ? FALLBACK_PORT : p;
  }
  try {
    const port = parseInt(execSync('port-for clan-world-frontend-dev', { encoding: 'utf8' }).trim(), 10);
    return Number.isNaN(port) ? FALLBACK_PORT : port;
  } catch {
    return FALLBACK_PORT;
  }
})();

// envDir: load .env.local from the monorepo root, not the web app folder.
// .env.local lives at <repo-root>/.env.local and is shared with server/agents.
// Without this, VITE_* values are undefined at build time and the prod bundle
// has no Convex URL / World App ID baked in (white screen).
export default defineConfig({
  plugins: [react()],
  envDir: path.resolve(__dirname, '../..'),
  server: {
    port: DEFAULT_PORT,
    host: '127.0.0.1',
  },
});
