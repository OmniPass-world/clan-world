import { test, expect } from '@playwright/test';

test.describe('app renders', () => {
  test('loads index without error boundary', async ({ page }, testInfo) => {
    await page.goto('/');

    // Expect a document to be present (title may be empty in Wave 0).
    const html = page.locator('html');
    await expect(html).toBeVisible();

    // Some page content must mount — body must not be empty.
    const body = page.locator('body');
    await expect(body).not.toBeEmpty();

    // No error boundary should be rendered.
    const errorBoundary = page.locator('[data-testid="error-boundary"]');
    await expect(errorBoundary).toHaveCount(0);

    // Visual debug aid — Playwright manages the per-test output dir.
    await page.screenshot({
      path: testInfo.outputPath('01-renders-home.png'),
      fullPage: true,
    });
  });
});
