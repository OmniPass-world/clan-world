import { execSync } from 'node:child_process';
import { defineConfig, devices } from '@playwright/test';

// Canonical port resolved from port-for registry (clan-world slot 587, env=test).
// Falls back to 58770 (canonical value from .world/ports.yml) when port-for is
// unavailable (CI, non-do-box hosts). PLAYWRIGHT_BASE_URL override takes precedence.
const DEFAULT_PORT = (() => {
  try {
    const port = parseInt(execSync('port-for clan-world-frontend-test', { encoding: 'utf8' }).trim(), 10);
    return Number.isNaN(port) ? 58770 : port;
  } catch {
    return 58770;
  }
})();
const baseURL =
  process.env.PLAYWRIGHT_BASE_URL ?? `http://localhost:${DEFAULT_PORT}`;

// Derive the dev-server PORT from baseURL so that an external override of
// PLAYWRIGHT_BASE_URL also relocates the spawned Vite server. If the URL has
// no explicit port (e.g. http://staging.example.com), fall through to default.
const webServerPort = (() => {
  try {
    const parsed = new URL(baseURL);
    return parsed.port || String(DEFAULT_PORT);
  } catch {
    return String(DEFAULT_PORT);
  }
})();

export default defineConfig({
  testDir: './tests/e2e',
  outputDir: 'test-results',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium-desktop',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'chromium-mobile',
      use: { ...devices['Pixel 5'] },
    },
  ],
  // VITE_CLANWORLD_DEMO_MODE is baked into the bundle at build time; in dev-server
  // mode it's read at startup. Pass it through so external test runs (e.g.
  // `VITE_CLANWORLD_DEMO_MODE=false pnpm test:e2e`) reach the spawned Vite server.
  webServer: {
    command: `PORT=${webServerPort} pnpm --filter @clan-world/web dev`,
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    stdout: 'pipe',
    stderr: 'pipe',
    env: {
      VITE_CLANWORLD_DEMO_MODE: process.env.VITE_CLANWORLD_DEMO_MODE ?? 'true',
      VITE_DEMO_BYPASS_WORLD_GUARD: process.env.VITE_DEMO_BYPASS_WORLD_GUARD ?? 'true',
    },
  },
});
