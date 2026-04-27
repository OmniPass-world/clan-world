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
 *
 * Phase B follow-up tests will cover:
 *   - tab switching, tick counter live updates
 *   - real Convex data → resource values, tmux mirror
 */
test.describe('cockpit shell (Phase A)', () => {
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

    // Tick counter is rendered on each panel.
    for (const clanId of [1, 2, 3, 4]) {
      await expect(
        page.locator(`[data-testid="mini-cockpit-${clanId}-tick"]`),
      ).toBeVisible();
    }

    // Visual debug aid.
    await page.screenshot({
      path: testInfo.outputPath('04-cockpit-shell.png'),
      fullPage: true,
    });
  });
});
