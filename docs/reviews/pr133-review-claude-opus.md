# PR #133 Review — Bundle D: Web Shell + Cockpit

| Field | Value |
|-------|-------|
| **PR** | [#133 — merge: bundle D — web shell + cockpit](https://github.com/OmniPass-world/clan-world/pull/133) |
| **Author** | claude-do |
| **Base** | `dev` ← `merge/bundle-d` |
| **Scope** | +2,317 / -324 across 23 files (all `apps/web/` + `.world/ports.yml` + `.gitignore`) |
| **Review date** | 2026-04-28 |
| **Model** | Claude Opus 4.6 |
| **Method** | 12-agent swarm (3 waves: 7 parallel broad → 3 parallel deep → 2 parallel specialist) |

## Bundles combined

- **#110** — Migrate Playwright default port to port-for lookup
- **#112** — Phase 4-B DEMO_MODE flag gating mock data in WorldMap
- **#100** — Cockpit Phase A 3-col 2-row layout shell with placeholder tabs
- **#106** — Cockpit Phase A.5b live tmux iframes + app header + connection indicator

---

## Summary Stats

| Category | Count |
|----------|-------|
| **MUST FIX** | 3 |
| **SHOULD FIX** | 18 |
| **DEFER** | 12 |
| **SKIP / FALSE POSITIVE** | 8 |
| **Total unique findings** | 41 |

---

## Triage Table

### MUST FIX — Blocking merge

| # | File | Lines | Finding | Agents |
|---|------|-------|---------|--------|
| 1 | `apps/web/tests/e2e/02-demo-mode.spec.ts` | 25–52 | **Demo-mode test skip vs build mismatch.** Skip condition reads `process.env.VITE_CLANWORLD_DEMO_MODE` with no default, while `playwright.config.ts` defaults to `'true'` in `webServer.env`. When env is unset (typical `pnpm test:e2e`), the OFF test block runs against an ON build — assertions will either false-pass or false-fail. The ON block is always skipped when env is unset. Tests cannot be trusted as-is. **Fix:** Align skip logic with `?? 'true'` matching the webServer default, or use Playwright projects with explicit env per suite. | W1-A1, W1-A5, W3-A11 (confirmed ×3) |
| 2 | `apps/web/src/WorldMap.tsx` | 1203–1212 | **Canned travel `setTimeout` IDs never cancelled on unmount.** The initial burst fires 4 `setTimeout(..., i * 250)` calls, but cleanup only runs `clearInterval(interval)`. Timer IDs are not stored or cleared, so callbacks can fire after teardown and call `spawnTravel` on destroyed Pixi objects — potential runtime error or stale graphics. **Fix:** Store `setTimeout` IDs in an array, `clearTimeout` each in the effect cleanup. | W1-A1, W1-A7, W2-A8 (confirmed ×3) |
| 3 | `apps/web/src/WorldMap.tsx` | 9, 56; `App.tsx` 5 | **Circular module dependency: `WorldMap` ↔ `App`.** `WorldMap.tsx` imports `DEMO_MODE` from `./App`; `App.tsx` imports `WorldMap` (via `MainApp`). This creates a module cycle that can cause undefined bindings during initialization, breaks test isolation, and complicates refactoring/lazy-loading. **Fix:** Extract `DEMO_MODE` (and related env flags) to a leaf module like `config/env.ts` imported by both files. | W1-A1, W1-A3, W2-A8 (confirmed ×3) |

### SHOULD FIX — Address in this PR before merge

| # | File | Lines | Finding | Agents |
|---|------|-------|---------|--------|
| 4 | `apps/web/src/hooks/useConnectionStatus.ts` | 60, 108–112 | **Initial state `'connected'` before any probe completes.** Users briefly see a green "connected" pill before the first `no-cors` HEAD probe resolves. **Fix:** Initialize as `'reconnecting'` or add a `'checking'` state for mount. | W1-A1, W2-A9 |
| 5 | `apps/web/src/hooks/useConnectionStatus.ts` | 6–8, 116–123 | **MAX_RETRIES=3 but 4 failed probes trigger disconnect (off-by-one).** `retryCount >= MAX_RETRIES` checked before increment means the fourth failure triggers disconnect, not the third. **Fix:** Rename constant or adjust predicate to match intent. | W1-A1, W2-A9 |
| 6 | `apps/web/src/WorldMap.tsx` | 1222–1251 | **`scoreboardClans` computed as unmemoized IIFE every render.** Sorting + mapping snapshot rows runs on every parent re-render. **Fix:** Wrap in `useMemo` keyed on `snapshot`, `agentLogs`. | W1-A7, W2-A8 |
| 7 | `apps/web/src/WorldMap.tsx` | 1059–1088 | **Bandit pulse Pixi ticker runs every frame even when `shouldPulse` is false.** `onTick` is always registered and runs per-frame, resetting alphas. **Fix:** Conditionally register ticker only when `shouldPulse` is true; remove when false. | W1-A7, W2-A8 |
| 8 | `apps/web/src/WorldMap.tsx` | 1216–1221 | **Misleading comment about scoreboard when DEMO_MODE is off.** Comment says scoreboard hides when demo is off, but live snapshot data will populate it. **Fix:** Update comment to reflect actual behavior. | W1-A1, W2-A8 |
| 9 | `apps/web/src/main.tsx` 64–66; `App.tsx` 64–68 | — | **`isCockpitPath` / `isCockpitRoute()` duplicated.** Same `startsWith('/cockpit')` logic in two files — drift risk. **Fix:** Extract to a shared `config/routes.ts` module. | W1-A3, W2-A10 |
| 10 | `apps/web/src/pages/Cockpit.tsx`; `WorldMap.tsx` 60–71; `cockpit-tokens.ts` 79–84 | — | **ELDERS roster vs MOCK_CLANS identity mismatch.** Cockpit panels show Storm Riders/Iron Guard/Crimson/Verdant Wardens; WorldMap mock shows Iron Guard/Ember Hand/Dawn Watch/Storm Riders. Same grid position can display different clan names. **Fix:** Single source of truth for clan roster. | W1-A3, W2-A10 |
| 11 | `apps/web/src/WorldMap.tsx` | 183–184 | **`anyApi` with eslint suppression bypasses Convex type safety.** `useQuery(anyApi.getSnapshot)` is cast to `SnapshotData | undefined` — no compile-time check against Convex schema. **Fix:** Import generated `api` types from `convex/_generated/api`. | W1-A4, W2-A8 |
| 12 | `apps/web/src/components/cockpit/shared/WorldMapBoundary.tsx` | 8–79; `WorldMap.tsx` 324–548 | **Error boundary does not catch async Pixi init failures.** `WorldMapBoundary` is a class error boundary (catches synchronous render errors only). Pixi init runs in `useEffect` via `.then()` with no `.catch()` — rejected promises are unhandled rejections, not caught by the boundary. **Fix:** Add `.catch()` on `app.init()` chain that sets error state, or catch async failures inside WorldMap. | W1-A3, W2-A8, W2-A10 |
| 13 | `apps/web/src/components/cockpit/tabs/TerminalTab.tsx` | 53–57 | **Iframe `sandbox="allow-scripts allow-same-origin"` is permissive.** Scripts in the iframe run in `cockpit.clan-world.com` origin. Any XSS/bug in ttyd assets can interact with same-origin cookies/APIs. **Fix:** Ensure ttyd is started read-only; restrict who can reach ttyd URLs via network/auth; consider `referrerPolicy="no-referrer"`. | W1-A2 |
| 14 | `apps/web/.env.example` | 22 | **`VITE_CLANWORLD_DEMO_MODE=true` in committed example file.** Building from `.env.example` without editing bakes mock data into production. **Fix:** Default to `false` or blank with a comment; keep `true` only in `.env.development.local`. | W1-A2, W2-A10 |
| 15 | `apps/web/src/WorldMap.tsx` | 694–766 | **Async `Assets.load` callbacks lack mount guard.** Clan sigil/base asset loads resolve with `.then()` but only check `mounted`/`appRef` loosely. Fast unmount can still run `viewport.addChild(sprite)` after teardown. **Fix:** Add `if (cancelled) return` guard inside each `.then()` callback. | W2-A8 (new) |
| 16 | `apps/web/src/components/cockpit/shared/CockpitTabBar.tsx` | 62–114 | **Missing ARIA tab semantics.** Tabs use `<button>` with `aria-pressed` but no `role="tablist"`, `role="tab"`, `aria-selected`, `aria-controls`, or `role="tabpanel"` on content. Screen readers cannot identify this as a tab widget. **Fix:** Implement WAI-ARIA APG Tabs pattern. | W3-A12 |
| 17 | `apps/web/src/components/cockpit/CockpitHeader.tsx` | 148–211 | **Connection status changes not announced to assistive tech.** Status transitions are visual-only + `title` attribute (unreliable for SR). No `aria-live` region. **Fix:** Add `aria-live="polite"` region or `role="status"` wrapper. | W3-A12 |
| 18 | (PR metadata) | — | **PR body missing `Closes #N`.** Repo convention requires one PR closing one issue. Bundle body references #110/#112/#100/#106 but no tracking issue. **Fix:** Add `Closes #<tracking-issue>` or document exception. | W1-A6 |
| 19 | `apps/web/tests/e2e/04-cockpit-shell.spec.ts` | 83–117 | **Disconnected-state test is timing-heavy (~14s worst case, 30s timeout).** Backoff schedule (2s/4s/8s × 4 failures) means slow CI can flirt with timeout ceiling. **Fix:** Consider shorter backoff override for test builds, or increase timeout buffer. | W1-A5, W3-A11 |
| 20 | `apps/web/tests/e2e/02-demo-mode.spec.ts` | 40–44, 62 | **Assertions coupled to literal `"IG"` substring.** Renames to Iron Guard mock data break tests without a real regression. **Fix:** Use `data-testid` on scoreboard entries. | W1-A5, W3-A11 |
| 21 | `apps/web/src/components/cockpit/tabs/TerminalTab.tsx` + all tabs | — | **Four ttyd iframes load simultaneously (default tab).** Each iframe boots xterm + WebSocket; no lazy loading or viewport-gating. High memory/CPU on initial cockpit load. **Fix:** Mount terminal iframe only for the active/focused panel, or use `loading="lazy"`. | W1-A7 |

### DEFER — Valid concern, track as follow-up issue

| # | File | Lines | Finding | Agents |
|---|------|-------|---------|--------|
| 22 | `apps/web/src/WorldMap.tsx` | 186–194 | **Local `SnapshotData`/`SnapshotClan` duplicate types from `@clan-world/shared`.** Divergence risk. Should import shared types. | W1-A4, W2-A8 |
| 23 | `apps/web/src/WorldMap.tsx` | 209–215 | **`MOCK_WALL_LEVELS` / `WALL_LEVEL_MAX` are dead code.** Never referenced after definition. | W1-A6, W2-A8 |
| 24 | `apps/web/src/App.tsx` | 71–79; `vite.config.ts` | **SPA fallback not configured for `/cockpit`.** Direct navigation or refresh yields 404 on static hosts without rewrite rules. | W1-A3, W2-A10 |
| 25 | `apps/web/src/App.tsx` | 64–80 | **`/cockpit` has no in-app authentication.** Intentional for judge view, but production deployment needs edge protection (VPN, Cloudflare Access, etc.). | W1-A2 |
| 26 | `apps/web/src/main.tsx` | 100–105 | **Stub Convex client (`203.0.113.1`) produces WebSocket retry console noise.** Convex client retries connections to an unroutable host. Not a bug but noisy in dev. | W1-A3, W2-A10 |
| 27 | `apps/web/src/hooks/useConnectionStatus.ts` | 93–100 | **`no-cors` HEAD probe gives limited health signal.** Opaque response settles on reachability, not health — 502/503 proxied responses look "up". | W1-A1, W2-A9 |
| 28 | `apps/web/src/WorldMap.tsx` | 1046–1056 | **Multiple `eslint-disable-next-line react-hooks/exhaustive-deps`.** Suppressed deps can hide stale-closure bugs. | W1-A4 |
| 29 | `apps/web/src/styles/cockpit-tokens.ts` | 68–84 | **ELDERS roster data mixed with visual tokens.** Separation-of-concerns: move roster to `cockpit-data.ts`. | W1-A6 |
| 30 | `apps/web/src/components/cockpit/CockpitHeader.tsx` | 126–130 | **Raw hex `#7a8a6a` instead of token for connected status color.** Minor inconsistency with cockpit token approach. | W1-A6 |
| 31 | `apps/web/src/WorldMap.tsx` | 309–311, 1301 | **`liveTick` derived from `max(snapshot?.tick, logs.length)`.** Surprising semantics for production — tick jumps based on agent log volume. | W2-A8 (new) |
| 32 | `apps/web/src/components/cockpit/tabs/ClansmanTab.tsx` | 132–157 | **HungerBar lacks `role="progressbar"` and ARIA value attributes.** "Starving" is communicated by border color alone (`1.4.1 Use of Color`). | W3-A12 |
| 33 | `apps/web/src/pages/Cockpit.tsx` | 43–126 | **No `<h1>` or heading hierarchy on cockpit page.** CockpitHeader title is a styled `<div>`. | W3-A12 |

### SKIP / FALSE POSITIVE

| # | File | Lines | Finding | Rationale |
|---|------|-------|---------|-----------|
| 34 | `apps/web/src/main.tsx` | 52–56 | ConvexProvider cast to ComponentType — library typing mismatch. | Documented workaround; not a safety issue. |
| 35 | `apps/web/src/main.tsx` | 34 | `(window as unknown as ...)` for Telegram WebApp. | Contained double-assertion; acceptable for external API. |
| 36 | `apps/web/playwright.config.ts` | 7–14 | `execSync('port-for ...')` — command injection concern. | Fixed command string, no external interpolation. |
| 37 | `apps/web/src/components/cockpit/tabs/TerminalTab.tsx` | 25 | iframe URL injection via `clanId`. | `clanId` comes from fixed `ELDERS` array (1–4), not user input. |
| 38 | `apps/web/src/hooks/useConnectionStatus.ts` | 73–148 | Timer/interval cleanup on unmount. | Cleanup is correct — `cancelled` flag + `clearTimers()` + `removeEventListener`. |
| 39 | `apps/web/src/pages/Cockpit.tsx` | 62–93 | Responsive uses CSS media queries vs JS. | Good pattern — no resize listener overhead. |
| 40 | `apps/web/playwright.config.ts` | 7–14 | port-for fallback when binary not installed. | try/catch + NaN guard + `58770` fallback — robust. |
| 41 | `apps/web/tests/e2e/04-cockpit-shell.spec.ts` | 22–35 | page.route vs page.goto race condition. | Route stubs are `await`-ed before `page.goto` — correct ordering. |

---

## Recommended Next Steps

### 1. Address MUST FIX items first (3 items)

**MF-1: Fix demo-mode test env alignment** (Finding #1)
- In `02-demo-mode.spec.ts`, change to: `const DEMO_MODE_BUILD_VALUE = process.env.VITE_CLANWORLD_DEMO_MODE ?? 'true'`
- This aligns the skip logic with the `playwright.config.ts` webServer default
- Consider separate CI jobs for ON vs OFF suites

**MF-2: Fix travel setTimeout leak** (Finding #2)
- Store timeout IDs from the stagger loop: `const staggerIds = MOCK_CLANS.map((c, i) => setTimeout(..., i * 250))`
- In cleanup: `staggerIds.forEach(clearTimeout)`

**MF-3: Break circular dependency** (Finding #3)
- Create `apps/web/src/config/env.ts` with `DEMO_MODE` and related env flag exports
- Update imports in both `App.tsx` and `WorldMap.tsx`

### 2. SHOULD FIX items grouped by theme

**State machine / hooks** (Findings #4, #5)
- Initialize `useConnectionStatus` as `'reconnecting'` and set `'connected'` only after first successful probe
- Clarify MAX_RETRIES naming vs actual behavior

**Type safety** (Findings #11, #15)
- Replace `anyApi` with generated Convex API types
- Add mount guard to async asset load callbacks

**Test robustness** (Findings #19, #20)
- Use `data-testid` instead of literal text assertions
- Consider shorter backoff for test builds

**Architecture** (Findings #9, #10, #12)
- Deduplicate `isCockpitPath`/`isCockpitRoute()` into shared module
- Unify clan roster between cockpit tokens and WorldMap mocks
- Add `.catch()` to Pixi init chain in WorldMap

**Security** (Findings #13, #14)
- Ensure ttyd is started in read-only mode; document trust model
- Change `.env.example` DEMO_MODE default to `false`

**Accessibility** (Findings #16, #17)
- Add proper ARIA tab pattern to CockpitTabBar
- Add `aria-live` region for connection status changes

**Performance** (Findings #6, #7, #21)
- Memoize `scoreboardClans` derivation
- Conditionally register bandit pulse ticker
- Consider lazy-loading terminal iframes

**Conventions** (Finding #18)
- Add `Closes #<issue>` to PR body

### 3. DEFER items → New GitHub issues

Findings #22–#33 should be tracked as GitHub issues for Phase B or post-hackathon cleanup. Key themes:
- Align types with `@clan-world/shared` (#22)
- Remove dead code (#23)
- Configure SPA fallback for production (#24)
- Add edge auth for `/cockpit` in production (#25)
- Silence stub Convex console noise (#26)
- Improve connection health signal (#27)
- Accessibility deep pass: headings, progress bars, color contrast (#32, #33)

---

## Overall PR Health Assessment

**Verdict: NEEDS WORK** — 3 MUST FIX items block merge.

The PR delivers a well-structured cockpit UI with good component decomposition, proper responsive layout (CSS media queries), correct timer cleanup in `useConnectionStatus`, and reasonable e2e test coverage for a hackathon scope. The architecture is sound — composition over inheritance, intentional auth bypass for the judge view, and a clean separation between cockpit tabs.

However, the test env mismatch (Finding #1) means e2e test results cannot be trusted, the `setTimeout` leak (Finding #2) can cause runtime errors on navigation, and the circular dependency (Finding #3) is fragile enough to warrant extraction before merging more code on top.

Once the 3 MUST FIX items are addressed, the SHOULD FIX items can be triaged by priority — type safety and test robustness items are highest value, accessibility can be batched, and performance items are optimization opportunities for later.

**Estimated effort to reach merge-ready:** ~1–2 hours for MUST FIX; ~3–4 hours for high-priority SHOULD FIX items.
