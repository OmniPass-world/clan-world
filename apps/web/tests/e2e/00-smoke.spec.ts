/**
 * Smoke test — captures all browser console + pageerror events on initial
 * load and surfaces them. This is the orchestrator's "remote DevTools" for
 * the mini app: instead of asking the user to paste console logs, run this
 * and read the failure output.
 *
 * Usage:
 *   PLAYWRIGHT_BASE_URL=http://127.0.0.1:5173 \
 *     pnpm --filter @clan-world/web exec playwright test tests/e2e/00-smoke.spec.ts
 *
 * Or with the dev server already running (default config attempts to spawn one):
 *   pnpm --filter @clan-world/web exec playwright test tests/e2e/00-smoke.spec.ts
 */
import { expect, test } from '@playwright/test';

// Filter out known-benign messages that aren't actionable.
// Keep this list minimal — false negatives (real errors swallowed) are worse
// than false positives (expected warnings re-flagged).
const BENIGN_PATTERNS: RegExp[] = [
  /SES Removing unpermitted intrinsics/i, // Worldcoin SDK lockdown.js — informational
  /MiniKit is not installed/i, // expected outside World App
  /favicon\.ico.*404/i, // no favicon shipped yet
  /Download the React DevTools/i, // dev hint
];

const isBenign = (text: string) => BENIGN_PATTERNS.some((re) => re.test(text));

test('mini app loads with no console errors', async ({ page }) => {
  const consoleErrors: string[] = [];
  const consoleWarnings: string[] = [];
  const pageErrors: { message: string; stack: string | undefined }[] = [];

  page.on('console', (msg) => {
    const text = msg.text();
    if (isBenign(text)) return;
    if (msg.type() === 'error') consoleErrors.push(`[error] ${text}`);
    if (msg.type() === 'warning') consoleWarnings.push(`[warn] ${text}`);
  });
  page.on('pageerror', (err) => {
    if (isBenign(err.message)) return;
    pageErrors.push({ message: err.message, stack: err.stack });
  });

  await page.goto('/');

  // Wait for canvas to mount — WorldMap renders one.
  // 10s gives PIXI v8 + Convex client + IDKit time to initialize.
  await page.waitForSelector('canvas', { timeout: 10_000 });

  // Give async effects a beat to fire so we capture any post-mount errors.
  await page.waitForTimeout(500);

  // Surface everything we captured before asserting — in CI/dev failure logs
  // we want to see the full picture, not just "expected 0 to equal N".
  if (pageErrors.length > 0 || consoleErrors.length > 0 || consoleWarnings.length > 0) {
    console.log('\n=== Smoke test captured browser output ===');
    if (pageErrors.length > 0) {
      console.log(`\n--- page errors (${pageErrors.length}) ---`);
      pageErrors.forEach((e) => {
        console.log(`* ${e.message}`);
        if (e.stack) console.log(e.stack.split('\n').slice(0, 6).join('\n'));
      });
    }
    if (consoleErrors.length > 0) {
      console.log(`\n--- console errors (${consoleErrors.length}) ---`);
      consoleErrors.forEach((e) => console.log(e));
    }
    if (consoleWarnings.length > 0) {
      console.log(`\n--- console warnings (${consoleWarnings.length}) ---`);
      consoleWarnings.forEach((w) => console.log(w));
    }
    console.log('=== end captured output ===\n');
  }

  expect(pageErrors, 'page errors during initial load').toHaveLength(0);
  expect(consoleErrors, 'console.error during initial load').toHaveLength(0);
  // Warnings are not a failure but logged above for visibility.
});
