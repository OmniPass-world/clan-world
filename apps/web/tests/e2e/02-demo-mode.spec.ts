/**
 * 02-demo-mode.spec.ts — VITE_CLANWORLD_DEMO_MODE flag smoke tests.
 *
 * These are integration-level Playwright tests. They require a running Vite
 * preview server built with the appropriate VITE_CLANWORLD_DEMO_MODE value.
 *
 * To run locally:
 *   # Demo mode ON (mock clans visible)
 *   VITE_CLANWORLD_DEMO_MODE=true pnpm build && PORT=58770 pnpm preview &
 *   pnpm playwright test tests/02-demo-mode.spec.ts --grep "demo mode ON"
 *
 *   # Demo mode OFF (placeholder visible)
 *   VITE_CLANWORLD_DEMO_MODE=false pnpm build && PORT=58770 pnpm preview &
 *   pnpm playwright test tests/02-demo-mode.spec.ts --grep "demo mode OFF"
 *
 * In CI, set VITE_CLANWORLD_DEMO_MODE at build time before each test run.
 *
 * Note: VITE_ vars are baked at BUILD time, not injected at runtime.
 * Each test variant therefore needs its own build. The tests here reflect
 * the expected DOM state after a build with the corresponding env value.
 */
import { test, expect } from '@playwright/test';

/** VITE_ env vars are baked at build time. Read what value was used. */
const DEMO_MODE_BUILD_VALUE = process.env.VITE_CLANWORLD_DEMO_MODE;

test.describe('DEMO_MODE flag — mock clans (demo mode ON)', () => {
  test.skip(
    DEMO_MODE_BUILD_VALUE !== 'true',
    'Skip: this test requires a build with VITE_CLANWORLD_DEMO_MODE=true',
  );

  test('demo mode ON: mock clan names visible in scoreboard panel', async ({ page }) => {
    // The app requires World App context OR VITE_DEMO_BYPASS_WORLD_GUARD=true to render
    // past the "Open in World App to play" gate. Set the bypass so the map renders.
    await page.goto('/?bypass=1');

    // Scoreboard pulse panel is rendered only in DEMO_MODE with scoreboardClans > 0.
    // "IG" is the Iron Guard initials rendered in the compact scoreboard.
    // This confirms MOCK_CLANS data made it through to the DOM.
    await expect(page.getByText('IG')).toBeVisible({ timeout: 10_000 });

    // No placeholder should be visible in demo mode
    await expect(page.getByTestId('no-chain-data-placeholder')).not.toBeVisible();
  });
});

test.describe('DEMO_MODE flag — empty world (demo mode OFF)', () => {
  test.skip(
    DEMO_MODE_BUILD_VALUE === 'true',
    'Skip: this test requires a build with VITE_CLANWORLD_DEMO_MODE=false (or unset)',
  );

  test('demo mode OFF: "no chain data yet" placeholder visible', async ({ page }) => {
    await page.goto('/?bypass=1');

    // Placeholder overlay is rendered when DEMO_MODE=false and no live snapshot clans.
    const placeholder = page.getByTestId('no-chain-data-placeholder');
    await expect(placeholder).toBeVisible({ timeout: 10_000 });
    await expect(placeholder).toContainText('no chain data yet');

    // Scoreboard tick panel must NOT be visible (only shown in DEMO_MODE)
    await expect(page.getByText('IG')).not.toBeVisible();
  });
});
