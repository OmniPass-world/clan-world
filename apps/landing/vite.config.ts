import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { execSync } from 'node:child_process';

// Canonical port resolved from port-for registry (clan-world slot 587, env=dev).
// Falls back to FALLBACK_PORT (canonical value from .world/ports.yml) when port-for is
// unavailable (CI, non-do-box hosts). PORT env override takes precedence.
const FALLBACK_PORT = 58741;
const DEFAULT_PORT = (() => {
  if (process.env.PORT) {
    const p = parseInt(process.env.PORT, 10);
    return Number.isNaN(p) ? FALLBACK_PORT : p;
  }
  try {
    const port = parseInt(execSync('port-for clan-world-landing-dev', { encoding: 'utf8' }).trim(), 10);
    return Number.isNaN(port) ? FALLBACK_PORT : port;
  } catch {
    return FALLBACK_PORT;
  }
})();

export default defineConfig({
  plugins: [react()],
  server: {
    port: DEFAULT_PORT,
    host: '127.0.0.1',
  },
});
