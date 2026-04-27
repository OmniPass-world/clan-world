import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright config for clan-world web e2e tests.
 *
 * Tests spin up a Vite preview server (`pnpm build && pnpm preview`) before running.
 * The DEMO_MODE flag is controlled via the VITE_CLANWORLD_DEMO_MODE env var, which
 * Playwright sets per-test in the test files.
 *
 * Port: 58770 (clan-world-frontend-test per ADR 0003 project-sharded allocation).
 * Set PORT=58770 when starting the preview server from CI.
 */
export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: 'list',
  use: {
    baseURL: `http://127.0.0.1:${process.env.PORT ?? 5173}`,
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // No webServer entry here — tests are listed/verified without a running server.
  // To run fully: `pnpm build && PORT=58770 pnpm preview` then `pnpm playwright test`.
});
