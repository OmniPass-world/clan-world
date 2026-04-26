# Hackathon Coding Rules

These two rules override default "good engineering" instincts for the duration of the hackathon (Submission 1 — 2026-04-26, Submission 2 — 2026-05-05). Hackathon time is the bottleneck. After Submission 2 ships and the codebase has real users, these rules can be revisited.

The rules are normative. PR reviewers (human + agent) reject changes that violate them.

---

## Rule 1 — Minimal tests only

**Write happy-path tests + a few important error cases. Nothing else.**

A failing happy-path test is the only kind that should block a PR.

### What this means

- Each public function/component/route gets ONE happy-path test that exercises the success route end-to-end.
- A few critical error cases get a test each — only the ones that would corrupt state or silently lose user input. Examples that qualify: missing required env var, malformed onchain payload, Convex mutation rejected by schema. Examples that do NOT qualify: every possible enum branch, every off-by-one, every type-coercion edge.
- Integration over unit when both fit. One test that proves the seam works beats five mocks proving the units mock correctly.
- If a test takes >10 minutes to write, it's probably not happy-path. Stop and ask.

### What to skip

- **Regression tests** for bugs that haven't happened. We will add these post-hackathon when bugs surface.
- **Exhaustive coverage** of branches, enum values, error-message strings, defensive null checks.
- **"Coverage for completeness"** suites. Coverage % is not a hackathon goal.
- **Snapshot tests** unless the snapshot is a contract artifact (e.g., a Solidity ABI).
- **Property-based tests** unless the function is a pure data transform that's central to the demo.
- **Mocking everything.** Prefer real adapters with stub backends (we have stubs for a reason).

### Applies to

- `vitest` in `apps/web`, `apps/server`, `apps/orchestrator`, `packages/agents`, `packages/shared`.
- `playwright` if/when added.
- `forge test` in `packages/contracts` — same principle: deploy + heartbeat + getCurrentTick. Skip fuzz tests on every getter.

### Anti-patterns

```ts
// BAD — testing every branch of an enum
describe('regionStatus', () => {
  it('handles ACTIVE', () => { /* ... */ });
  it('handles DORMANT', () => { /* ... */ });
  it('handles CONTESTED', () => { /* ... */ });
  it('handles RUINED', () => { /* ... */ });
  it('handles UNKNOWN', () => { /* ... */ });
});

// GOOD — one happy path, one critical error
describe('regionStatus', () => {
  it('returns the region status from a snapshot', () => { /* ... */ });
  it('throws on a malformed snapshot (would corrupt state)', () => { /* ... */ });
});
```

---

## Rule 2 — Env var simplicity

**ONE env var per concept. Sensible defaults. No duplicates. No backwards-compat shims.**

This codebase has no production users yet. Break env-var names freely when something better appears.

### What this means

- Each conceptual configuration value has exactly ONE name. If a value reaches both server and browser, the browser variant uses the Vite-required `VITE_` prefix on the SAME base name (e.g., `WORLD_APP_ID` server / `VITE_WORLD_APP_ID` browser). That is one concept, two transport names — fine. What's NOT fine is `WORLD_ID_APP_ID` AND `WORLD_APP_ID` both meaning "the World mini app's app id."
- Sensible defaults baked into code so most users can deploy with an empty `.env.local`. Required-no-default values are the exception, not the rule.
- When you rename or restructure: rename in all readers, delete the old name, ship. Do NOT add a fallback like `readEnv('NEW_NAME') ?? readEnv('OLD_NAME')`. That fallback becomes permanent technical debt within a week.
- Complex config (nested objects, JSON-encoded blobs) only when truly needed. When needed: colocated with the consumer, with a sensible default and a one-line comment explaining the shape.

### What to skip

- **Duplicate env vars** that mean the same thing under different names.
- **Backwards-compat shims.** Delete the old name. Update every reader. Move on.
- **Required env vars without a working default** if a stub default would let the system boot.
- **Config-file generators, env-var validators, "12-factor app" scaffolding.** Hackathon doesn't pay for this.

### Server-vs-browser duality (the legitimate case)

Vite only exposes vars prefixed with `VITE_` to the browser bundle. Some values legitimately need to reach both contexts. The pattern is:

- ONE base name (e.g., `WORLD_APP_ID`).
- Server-side: `WORLD_APP_ID` in `.env.local`, read directly via `process.env`.
- Browser-side: `VITE_WORLD_APP_ID` in `.env.local`, read via `import.meta.env.VITE_WORLD_APP_ID`.
- Code uses the `readEnv('WORLD_APP_ID')` helper in `packages/shared/src/adapters/_env.ts`, which tries both transport prefixes transparently.

This is one concept with two transport names. It's allowed. What violates Rule 2 is having BOTH `WORLD_APP_ID` and `WORLD_ID_APP_ID` server-side, or `VITE_WORLD_APP_ID` and `VITE_WORLD_MINI_APP_ID` browser-side.

### Applies to

- `.env.template` at repo root.
- Every adapter factory in `packages/shared/src/adapters/`.
- Every Convex config under `apps/server/`.
- Foundry deploy scripts that read env (`packages/contracts/script/`).
- Orchestrator and agent CLI flag/env handling.

### Anti-patterns

```bash
# BAD — two names for the same World mini app id
WORLD_ID_APP_ID=...
VITE_WORLD_APP_ID=...

# GOOD — one base name, with the Vite-required browser variant
WORLD_APP_ID=...
VITE_WORLD_APP_ID=...
```

```ts
// BAD — backwards-compat shim
const appId = readEnv('WORLD_APP_ID') ?? readEnv('WORLD_ID_APP_ID');

// GOOD — one canonical name, hard fail if unset and required
const appId = readEnv('WORLD_APP_ID');
if (!appId) throw new Error('WORLD_APP_ID is required for World mini app integration');
```

---

## When to revisit

Both rules expire when ClanWorld has live users. Until then: speed, clarity, and minimum config win every tradeoff. If a reviewer feels strongly that a rule should not apply to a specific PR, they raise it on the PR — they don't carve out a side workflow.
