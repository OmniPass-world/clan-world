import { test, expect } from '@playwright/test';

/**
 * Phase A — Cockpit layout shell.
 *
 * Verifies the structural skeleton:
 *   - /cockpit route renders without error
 *   - 3-col 2-row grid is mounted
 *   - all 4 mini-cockpits visible
 *   - world map cell visible
 *   - default tab on each mini-cockpit is "terminal"
 *   - app-level header has tick counter + connection pill (Phase A.5b)
 *
 * Phase B follow-up tests will cover:
 *   - tab switching, tick counter live updates
 *   - real Convex data → resource values, tmux mirror
 */
test.describe('cockpit shell (Phase A)', () => {
  // Default to stubbing all 4 ttyd iframes with tiny HTML so the test never
  // depends on external network. Individual tests override the route to
  // simulate connection failures.
  test.beforeEach(async ({ page }) => {
    await page.route('**/cockpit.clan-world.com/elder-*-tty/**', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'text/html',
        body: '<!DOCTYPE html><html><body data-stub="ttyd"></body></html>',
      }),
    );
  });

  test('renders 3-col 2-row layout with 4 mini-cockpits + world map', async ({
    page,
  }, testInfo) => {
    await page.goto('/cockpit');

    // No error boundary crash.
    const errorBoundary = page.locator('[data-testid="error-boundary"]');
    await expect(errorBoundary).toHaveCount(0);

    // Grid root mounts.
    await expect(page.locator('[data-testid="cockpit-root"]')).toBeVisible();
    await expect(page.locator('[data-testid="cockpit-grid"]')).toBeVisible();

    // All 4 corner mini-cockpits visible.
    for (const clanId of [1, 2, 3, 4]) {
      await expect(
        page.locator(`[data-testid="mini-cockpit-${clanId}"]`),
      ).toBeVisible();
    }

    // Center world-map cell visible (the pixi canvas mounts inside it
    // asynchronously, so we just assert the cell is in the DOM).
    await expect(page.locator('[data-testid="cockpit-worldmap"]')).toBeVisible();

    // Default tab on each mini-cockpit is "terminal" — verify by checking
    // the terminal content placeholder is the one rendered initially.
    for (const clanId of [1, 2, 3, 4]) {
      const terminalTab = page.locator(
        `[data-testid="mini-cockpit-${clanId}-tab-terminal"]`,
      );
      await expect(terminalTab).toHaveAttribute('data-active', 'true');
      await expect(
        page.locator(`[data-testid="mini-cockpit-${clanId}-content-terminal"]`),
      ).toBeVisible();
    }

    // Phase A.5b: tick counter is now app-level (single instance), not
    // per-mini-cockpit. The connection pill is also rendered once.
    await expect(page.locator('[data-testid="cockpit-header-tick"]')).toBeVisible();
    await expect(page.locator('[data-testid="cockpit-header-tick"]')).toHaveCount(1);
    await expect(
      page.locator('[data-testid="cockpit-connection-pill"]'),
    ).toBeVisible();

    // Visual debug aid.
    await page.screenshot({
      path: testInfo.outputPath('04-cockpit-shell.png'),
      fullPage: true,
    });
  });

  test('connection pill transitions to disconnected when heartbeat fails', async ({
    page,
  }) => {
    // Override the beforeEach stub: abort all elder-* iframe + heartbeat
    // requests so the heartbeat probe fails. After MAX_RETRIES (3) at
    // 2s/4s/8s backoff, total worst-case wall time to disconnected is ~14s
    // plus initial probe fail; allow a generous 30s timeout.
    await page.route('**/cockpit.clan-world.com/elder-*-tty/**', (route) =>
      route.abort('failed'),
    );

    await page.goto('/cockpit');

    const pill = page.locator('[data-testid="cockpit-connection-pill"]');
    await expect(pill).toBeVisible();

    // Wait for the pill to transition to disconnected. The state machine
    // must traverse `reconnecting` first, but we just assert the terminal
    // state to keep the test deterministic.
    await expect(pill).toHaveAttribute('data-status', 'disconnected', {
      timeout: 30_000,
    });

    // Manual reconnect button is rendered in the disconnected state.
    const retryBtn = page.locator('[data-testid="cockpit-connection-pill-retry"]');
    await expect(retryBtn).toBeVisible();

    // Clicking Reconnect bumps the state machine back into the retry loop;
    // since the route is still aborted, the pill should re-enter
    // `reconnecting` before flipping back to `disconnected`. We assert it
    // doesn't crash and remains in a known state after a click.
    await retryBtn.click();
    await expect(pill).toHaveAttribute('data-status', /reconnecting|disconnected/, {
      timeout: 5_000,
    });
  });
});
