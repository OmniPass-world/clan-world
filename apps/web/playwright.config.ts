import { defineConfig, devices } from '@playwright/test';

// TODO: replace 58840 with port-for-resolved value once the
// `port-for --init <worktree>` slot for clan-world is registered. Until then
// PLAYWRIGHT_BASE_URL env override is the canonical way to point tests at the
// real dev server.
// Migrate to port-for clan-world-frontend-test (58770) after PR #102
// (port-for-init) merges.
const DEFAULT_PORT = 58840;
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
  webServer: {
    command: `PORT=${webServerPort} pnpm --filter @clan-world/web dev`,
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    stdout: 'pipe',
    stderr: 'pipe',
  },
});
