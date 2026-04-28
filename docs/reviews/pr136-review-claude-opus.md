# PR #136 Review — Bundle C: Runner Stack

| Field | Value |
|-------|-------|
| **PR** | [#136](https://github.com/OmniPass-world/clan-world/pull/136) |
| **Title** | merge: bundle C — runner stack (combines #93 #114 #103 #99 #111) |
| **Branch** | `merge/bundle-c` → `dev` |
| **Size** | +5,424 / −28 across 33 files |
| **Review date** | 2026-04-28 |
| **Model** | Claude Opus 4.6 (Cursor) |
| **Methodology** | 10-agent swarm: 7 parallel Wave 1 (broad sweep) + 3 parallel Wave 2 (targeted deep dives) |

---

## Summary Stats

| Category | Count |
|----------|-------|
| **MUST FIX** | 3 |
| **SHOULD FIX** | 9 |
| **DEFER** (new GH issue) | 16 |
| **SKIP / FALSE POSITIVE** | 14 |
| **Total findings** | **42** |

---

## Triage Table

### MUST FIX — Blocking merge

| # | File | Line(s) | Finding | Domain |
|---|------|---------|---------|--------|
| 1 | `runner/src/tickLoop.ts` | 87–137 | **Partial Elder failure still advances `lastProcessedTick` and calls `markSettled`.** After `Promise.all`, the code always runs `settleWindow` → `markSettled(chainTick)` → `lastProcessedTick = chainTick`, even when some per-Elder deliveries failed (caught and logged). A failed Elder never gets a retry for that tick since `chainTick > lastProcessedTick` becomes false. Heartbeat can advance via `settleLatch` even when not all Elders received the situation block. Wave 2 **CONFIRMED** — the code documents intentional degradation for liveness, but the consequence (silent tick skip + premature heartbeat) is undocumented and likely unintended for game correctness. | Correctness |
| 2 | `runner/src/filePeerInbox.ts` | 50–52 | **Path traversal in `send(toClanId, ...)`.** `inboxKeyForClanId(toClanId)` returns the raw clan ID if unmapped. No validation that it is a safe single path segment — a value containing `..` or `/` can escape `inboxDir`. Unlike `axlPeerInbox.ts` which has `assertSafeClanId`, the file backend lacks this guard. | Security / Correctness |
| 3 | `runner/src/filePeerInbox.ts` | 39–47 | **`ELDER_N` env overrides per-instance elder resolution in multi-elder mode.** Constructor reads `process.env['ELDER_N']`, and if set (e.g. from `.env.example` which defaults `ELDER_N=1`), every `FilePeerInbox` instance reads the same `elder-1.jsonl` regardless of `ownClanId` and the `elder` argument. In the multi-elder runner (`main.ts`), this causes **cross-talk** — all 4 Elders share one inbox file. | Correctness |

### SHOULD FIX — Address in this PR before merge

| # | File | Line(s) | Finding | Domain |
|---|------|---------|---------|--------|
| 4 | `runner/src/tickLoop.ts` | 163–173 | **`withTimeout` does not take an `AbortSignal`.** On SIGTERM during long delivery, shutdown can be delayed up to `deliveryTimeoutMs`. Wave 2 **QUALIFIED**: normal abort path is faster since `deliveryAbort` kills tmux children, but worst-case bound (stuck delivery) is real. Fix: race delivery against `deps.signal` or make `withTimeout` abort-aware. | Correctness |
| 5 | `runner/src/zeroGMemoryStore.ts` | 315–341 | **`OG_STORAGE_API_KEY` is a feature flag, not an API credential.** It is never passed to `buildRealBatcherFactory` or any SDK call — only its presence gates 0G mode. `README.md` calls it "0G API key", misleading operators about the security posture. Real auth depends on `ELDER_MNEMONIC`-derived wallets. Rename to `OG_STORAGE_ENABLED` or document honestly. | Security / Docs |
| 6 | `runner/src/main.ts` | 98 | **`{} as Record<ElderId, PerElderDeps>` unsafe type assertion.** Asserts a fully populated record before any keys exist. If the loop stops early, downstream code sees phantom entries. Use a builder pattern or reduce from `ELDER_IDS`. | Type Safety |
| 7 | `runner/src/axlPeerInbox.ts` | 517–519 | **`as ElderId` unsafe narrowing from `parseInt`.** Fallback path casts unchecked `parseInt(env['ELDER_N'])` to `ElderId` without validation. Could yield values outside 1–4 or NaN. | Type Safety |
| 8 | `AGENTS.md` | 9–18 | **Root `AGENTS.md` still says "Six workspace packages" and omits `packages/runner`.** Breaks progressive discovery for new contributors. | Docs |
| 9 | `.env.template` | (whole file) | **Root `.env.template` has no runner keys** (`RUNNER_*`, `OG_*`, `AXL_*`, `ELDER_*`). AGENTS.md §7 requires the root template to list all variables. | Docs |
| 10 | `runner/src/tmuxRunnerInbox.ts` | 45–46, 53–54 | **Abort-driven cancellation returns `reason: 'timeout'` instead of `'aborted'`.** Semantic mismatch — downstream logs/metrics will mis-attribute shutdown as timeout. Extend `DeliveryStatus` with `'aborted'` or map to a distinct reason. | Correctness |
| 11 | `runner/src/axlPeerInbox.ts` | 404–412 | **Missing `sentAt` defaults to empty string `''`.** `IElderPeerInbox` specifies `sentAt` as ISO 8601 — empty string violates the contract and confuses Elders. Default to `new Date().toISOString()`. | Correctness |
| 12 | `runner/README.md` | 8–18 | **Heartbeat loop pseudocode is stale.** Shows heartbeat inside the tick loop, but code decouples Cycle A (heartbeat scheduler) from Cycle B (tick loop) via `settleLatch`. Misleads readers about architecture. | Docs |

### DEFER — Valid concerns, open new GitHub issues

| # | File | Line(s) | Finding | Domain |
|---|------|---------|---------|--------|
| 13 | `runner/clanworld-runner.service` | 6–25 | **Missing systemd service hardening.** No `PrivateTmp`, `ProtectSystem`, `NoNewPrivileges`, `CapabilityBoundingSet`, memory limits, etc. Process holds private keys and API keys. | Security |
| 14 | `runner/src/axlPeerInbox.ts` | 29–34 | **AXL trust model — no cryptographic verification.** Inbound routing trusts the local AXL node; signing is TODO. Compromise of AXL sidecar could influence routing. | Security |
| 15 | `runner/src/axlPeerInbox.ts` | 171–205 | **AXL API key sent over non-TLS.** Default `AXL_NODE_URL` is `http://127.0.0.1:9002`. If operators set a remote URL, bearer token is exposed. Enforce `https:` for non-loopback hosts. | Security |
| 16 | `runner/src/axlPeerInbox.ts` | 236–287, 399–457 | **Unbounded AXL inbox memory.** `#seenMsgIds` Set and `#inbox` array grow monotonically. Journal is append-only with no rotation. Long-lived runner → unbounded RAM and disk. | Performance |
| 17 | `runner/src/composeSituationBlock.ts` + `tickLoop.ts` | 37–42, 92–104 | **5 redundant `getSnapshot()` calls per tick.** Each of 4 Elders calls `convex.getSnapshot()` independently, plus `pollChainTick`. Fetch once per tick and pass to compose. | Performance |
| 18 | `runner/src/zeroGMemoryStore.ts` | 248–252 | **Full JSON cache rewrite on every `save()`.** `writeCacheToDisk` serializes the entire `#cache` Map each time. Switch to incremental append log with periodic checkpoint. | Performance |
| 19 | `runner/src/filePeerInbox.ts` | 71–80 | **Full JSONL read per `inbox()` call.** `readFileSync` + split on entire history every tick per Elder. Append-only file grows without bound. | Performance |
| 20 | `runner/src/tickLoop.ts` | (entire module) | **Zero test coverage for tick loop.** Core orchestration path (poll → compose → deliver → settle → latch) has no tests. At minimum, one integration-style test with fakes. | Tests |
| 21 | (package layout) | — | **No `packages/runner/AGENTS.md`.** Other first-class packages have per-package guides. Inconsistent with progressive discovery pattern. | Conventions |
| 22 | (commit history) | — | **Several commits missing `(#N)` issue refs.** Affects: `feat(runner): add ClanWorld runner daemon prototype`, `fix(runner): fix-round PR #93`, `feat(runner): Phase 7/8`, `fix(runner): narrow heartbeat error upgrade`. | Conventions |
| 23 | `runner/.env.example` + `zeroGMemoryStore.ts` | 49, 15–19 | **`CHAIN_ID=16661` documented but unused.** No `env['CHAIN_ID']` read in runner source. | Docs |
| 24 | `runner/src/zeroGMemoryStore.ts` vs `fileMemoryStore.ts` | 355–363, 52–56 | **Corrupt JSON: ZeroG throws, FileMemoryStore returns `{}`.** Toggling `OG_STORAGE_API_KEY` changes startup behavior on the same file. Align policies. | Correctness |
| 25 | `runner/src/filePeerInbox.ts` + `zeroGMemoryStore.ts` | — | **`JSON.parse(...) as Record<string, string>` unvalidated.** Valid JSON with non-string values silently becomes wrong types. Add runtime shape validation. | Type Safety |
| 26 | `runner/src/zeroGMemoryStore.ts` + `axlPeerInbox.ts` | 75–83, 449–456 | **Sensitive data at rest without restrictive file permissions.** Cache and journal files follow default `umask`. Use `0o600` for sensitive files. | Security |
| 27 | `runner/src/tmuxRunnerInbox.ts` | 101–129 | **TOCTOU gap between spawn and abort listener.** Short window where abort fires after the sync check but before `addEventListener`. Partial mitigation exists. | Correctness |
| 28 | `runner/src/tickLoop.ts` | 79–84 | **No exponential backoff on `pollChainTick` failure.** During Convex outages, runner polls at constant cadence. Add backoff with jitter. | Performance |

### SKIP / FALSE POSITIVE

| # | File | Line(s) | Finding | Reason |
|---|------|---------|---------|--------|
| 29 | `runner/src/tickLoop.ts` | 175–190 | `raceAbort` doesn't cancel underlying promise | By design; documented in comments. Non-cancelled work is bounded. |
| 30 | `runner/src/main.ts` | 98–123 | Partial adapter creation on startup failure | Process exits on failure; no leaked resources. |
| 31 | `runner/src/tmuxRunnerInbox.ts` | 152–159 | `waitForFile` lacks `AbortSignal` | Bounded by `timeoutMs`; only used in delivery path. |
| 32 | `runner/src/pollChainTick.ts` | 12–14 | Full snapshot for tick query | Documented TODO for cheaper query; correctness is fine. |
| 33 | `runner/src/fileMemoryStore.ts` | 33 | `elder: number` vs `ElderId` | Minor type style; values are constrained at call sites. |
| 34 | `agents/package.json` | 7–8 | Missing `"types"` condition on `./seams` export | TypeScript resolves it anyway; minor polish. |
| 35 | `runner/tsconfig.json` | — | `include` adds `test/**/*` unlike agents | Reasonable for test support; not inconsistent. |
| 36 | `runner/src/zeroGMemoryStore.ts` | 25 | `.js` extension in import vs extensionless elsewhere | Both resolve under tsx; style-only. |
| 37 | `runner/package.json` | — | Missing `exports` map | Private package; `main` field sufficient. |
| 38 | `runner/package.json` | 7–14 | Stub `build`/`lint` scripts | Hackathon acceptable; no functional impact. |
| 39 | (commit history) | — | Merge commits non-conventional | Common practice for bundle PRs. |
| 40 | `runner/src/axlPeerInbox.ts` | 338–343 | `peerToClan` Map rebuilt per drain | Minor CPU cost; not hot path. |
| 41 | `runner/.env.example` | 9–10 | Concrete contract address in templates | Not a secret; testnet reference. |
| 42 | `runner/src/zeroGMemoryStore.ts` | 23 | Unused `os` import | Likely merge residue; no functional impact. |

---

## Review Methodology

### Wave 1 — Broad Sweep (7 agents, parallel)

| Agent | Domain | Key Findings |
|-------|--------|--------------|
| 1.1 | Correctness & Bug Hunter | CRITICAL tick loop partial failure (#1); HIGH path traversal (#2); HIGH withTimeout gap (#4) |
| 1.2 | Security & Secrets | HIGH AXL trust model (#14); HIGH systemd hardening (#13); HIGH OG_STORAGE_API_KEY naming (#5) |
| 1.3 | Architecture & Integration | MEDIUM seams placement; verified no circular deps, correct subpath exports |
| 1.4 | Type Safety & Contracts | HIGH unsafe type assertions (#6, #7); zero `any` usage confirmed |
| 1.5 | Test Coverage | HIGH tickLoop untested (#20); MEDIUM tautological wallet test; MEDIUM misleading test names |
| 1.6 | Style, Conventions & Docs | HIGH AGENTS.md gap (#8); HIGH .env.template gap (#9); MEDIUM commit message issues (#22) |
| 1.7 | Performance & Scalability | HIGH redundant snapshots (#17); HIGH unbounded caches (#16, #18, #19) |

### Wave 2 — Targeted Deep Dives (3 agents, parallel)

| Agent | Domain | Key Findings |
|-------|--------|--------------|
| 2.1 | Concurrency & Abort Handling | CONFIRMED CRITICAL #1 with full signal trace; QUALIFIED #4; CONFIRMED #10, #27 |
| 2.2 | 0G SDK Integration | CONFIRMED #5, #24, #25; wallet derivation is correct; cache coherency is maintained |
| 2.3 | Merge Conflicts & Consistency | Found HIGH #3 (ELDER_N cross-talk); no conflict markers; lockfile synced; stale README |

### Wave 3 — Not needed

Wave 1 + 2 provided comprehensive coverage across all subsystems.

---

## Recommended Next Steps

### 1. Address MUST FIX items (3 items — do first)

**#1 — Tick loop partial failure handling** (highest priority)
- Option A: Gate `markSettled` / `lastProcessedTick` on all deliveries succeeding; retry failed Elders before settling
- Option B: Accept degraded mode but document it explicitly in code comments, README, and log a prominent warning when an Elder is skipped
- Option C: Retry failed Elders up to N times within the settle window before marking settled

**#2 — filePeerInbox path traversal**
- Add `assertSafeClanId()` validation (same pattern already in `axlPeerInbox.ts`) before constructing file paths in `send()`

**#3 — ELDER_N env override in multi-elder mode**
- `FilePeerInbox` constructor should prefer the explicit `elder` parameter over `process.env['ELDER_N']` when running in multi-elder mode
- Alternatively, the multi-elder runner should `delete process.env['ELDER_N']` at startup, or `FilePeerInbox` should ignore it when `opts.elder` is provided

### 2. Address SHOULD FIX items (9 items — before merge)

Grouped by effort:

**Quick fixes** (< 10 min each):
- #5: Rename `OG_STORAGE_API_KEY` to `OG_STORAGE_ENABLED` or add clear docs
- #8: Update `AGENTS.md` to list runner as 7th package
- #9: Add runner env vars to root `.env.template`
- #10: Add `'aborted'` reason to `DeliveryStatus` and use it
- #11: Default `sentAt` to `new Date().toISOString()` when absent
- #12: Update README pseudocode to show decoupled Cycle A / Cycle B

**Medium effort** (30–60 min each):
- #4: Make `withTimeout` abort-aware or wrap delivery in `raceAbort`
- #6: Replace `as Record<ElderId, PerElderDeps>` with a builder
- #7: Validate `elderN` before casting to `ElderId`

### 3. Create DEFER issues (16 items)

Open GitHub issues for tracking. Suggested grouping:
- **Security hardening**: #13 (systemd), #14 (AXL signing), #15 (AXL TLS), #26 (file permissions)
- **Performance**: #16 (unbounded caches), #17 (snapshot dedup), #18 (cache rewrite), #19 (JSONL reads), #28 (backoff)
- **Correctness**: #24 (corrupt JSON alignment), #25 (JSON.parse validation), #27 (TOCTOU)
- **Docs & conventions**: #21 (runner AGENTS.md), #22 (commit refs), #23 (CHAIN_ID cleanup)
- **Tests**: #20 (tickLoop coverage)

### 4. Overall PR Health Assessment

**Status: NEEDS WORK**

The 3 MUST FIX items are real bugs that affect game correctness (tick skipping, cross-talk between Elders) and security (path traversal). The 9 SHOULD FIX items are mostly quick documentation and type safety improvements.

The code quality is generally high — zero `any` usage, good abort signal threading, thoughtful adapter pattern, comprehensive tests for most modules. The 4 fix rounds (r3–r6) on the 0G adapter show healthy iteration. The main gaps are in the tick loop orchestration (the CRITICAL #1), the file-based peer inbox (MUST FIX #2 and #3), and documentation keeping pace with architecture changes.

After addressing the 3 MUST FIX and 9 SHOULD FIX items, the PR should be merge-ready.
