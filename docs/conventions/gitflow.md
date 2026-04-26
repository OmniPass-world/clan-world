# Gitflow (light)

The branching model for ClanWorld. Mandatory until the project ships.

## Branches

- **`main`** — sacred. Only tagged release merges. Deploys come from here. Never push directly.
- **`dev`** — integration branch. All feature PRs target this. Default branch for the repo.
- **`feat/issue-N-short-desc`** — feature branches, one per GitHub issue. Branched off `dev`.
- **`fix/issue-N-short-desc`** — bug fix branches, same convention.
- **`docs/issue-N-short-desc`** — docs-only branches.
- **(stacked phases)** `dev-phase-N-<feature>` — for multi-phase work (S2 components likely use this). Orchestrator opens a consolidated PR `dev-phase-N → dev` per phase. PM continues forward on phase N+1 while phase N awaits review.

## Issue → branch → PR cycle

1. **Create issue.** Title is imperative ("Add foundry loop heartbeat"). Body has acceptance criteria + agent-dispatchable scope.
2. **Branch off `dev`:** `git checkout dev && git pull && git checkout -b feat/issue-N-desc`.
3. **Implement.** Commit early and often. Conventional commit format: `type(scope): desc (#N)`.
4. **Run local 3-tier swarm review** before opening the PR (see `pr-review.md`). All three GREEN.
5. **Open PR `feat/issue-N → dev`.** Body must include `Closes #N`.
6. **Cloud review** (Copilot + Gemini Code Assist) — single sanity pass per cloud-thrift policy.
7. **Address must-fix findings;** push fix commits.
8. **Merge** when all reviewers GREEN. Squash-merge preferred for hygiene.
9. **Delete branch** after merge confirms.

## Commit message format

```
type(scope): short description (#N)

Optional body explaining the why, not the what.
Multi-line is fine if the change is non-obvious.
```

`type` is one of: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`, `perf`, `build`, `ci`.

`scope` is the package or area: `web`, `server`, `orchestrator`, `contracts`, `agents`, `shared`, `env`, `scaffold`, `plan`, `readme`, `skill`.

Example: `feat(orchestrator): foundry loop heartbeat keeper (#7)`.

## Release tagging

(Wave 5+) Once `dev` is stable for a submission:

1. Open release PR `dev → main`.
2. Title: `release: Submission 1 (worldchain-sepolia)`.
3. Tag after merge: `git tag s1-v0.1.0 && git push origin s1-v0.1.0`.
4. Tag commits trigger downstream deploys (manual for hackathon scope).

## Hackathon discipline

Speed > polish, but every gate commit must be on a branch that builds and typechecks. **Never push broken `dev`.** If you're tempted to merge a half-finished PR, instead: open it as draft, finish on the branch, only mark ready-for-review when actually ready.
