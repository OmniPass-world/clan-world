# PR Review — Local 3-Tier Swarm

Adapted from `~/claudes-world/knowledge/sop/swarm-pr-review.md` for this repo's hackathon discipline.

## The pattern

Three local reviewers, run in parallel. All three GREEN before opening the PR. Cloud reviewers (Copilot + Gemini Code Assist) are a single sanity pass at end-of-cycle.

| Tier | Reviewer | Strengths | Invocation |
|---|---|---|---|
| 1 | Local Claude subagent (`/pr-review` skill or `code-review:code-review` agent) | Verification coverage, line-by-line bug hunting | `/pr-review` in this repo |
| 2 | Local Codex CLI | OOTB bug hunter (dominant) | `code-review-codex` subagent |
| 3 | Local Gemini flash | High-variance clutch catches | `code-review-gemini` subagent |

Easiest entry: `/swarm-review <PR-number>` runs all three in parallel and prints a consolidated triage table.

## Cloud thrift policy

- Cloud reviewers (Copilot, Gemini Code Assist) burn through monthly quotas fast.
- New rule: **local swarm is the iteration loop.** Run all 3 local tiers, apply fixes, re-run locally, REPEAT until local CLEAN before opening the PR. Cloud is a SINGLE final sanity pass.
- Max 2 cloud rounds per PR absent security-critical findings.
- Never cycle just to re-confirm.

## Triage levels

Findings are categorized:

- **MUST FIX** — blocking the merge. Bug, security issue, contract breaking change.
- **SHOULD FIX** — strong opinion, address in this PR.
- **NICE TO HAVE** — note for later, fine to defer to a follow-up.

## Per-tier comments

Each reviewer self-posts a brief signed comment on the PR identifying their tier:
- `#claude-subagent` — local Claude review
- `#codex` — local Codex review
- `#gemini-flash` (or `#gemini-pro` if escalated) — local Gemini review

After fixes, the agent that posted the original comment also posts a fix-round summary comment listing addressed/skipped/deferred findings.

## Convergence

A PR is convergent (mergeable) when:
- All 3 local tiers report CLEAN on the latest commit.
- Cloud sanity pass shows no MUST FIX findings.
- All inline comments are triaged (addressed, deferred to follow-up issue, or marked won't-fix with rationale).

The orchestrator checks all three tiers — PM-internal swarm rounds aren't a substitute for orch-level swarm review on security-sensitive code.

## When to skip the orch-level swarm

Per `~/claudes-world/knowledge/sop/pm-delegation.md` (cloud-thrift quota):

- **Skip orch swarm** for low-risk PRs (docs, scaffold, test-only changes) — trust PM's internal swarm as full signal.
- **Always run orch swarm** for: security-sensitive code (chain reads/writes, key handling), new-service releases, or on explicit request.

## Async review for multi-phase work

For 2+ phase autonomous work, PM merges on its own GREEN and moves forward without waiting for orch review. Orch reviews async, advisory-only. Two checkpoints per phase: plan TLDR before impl + merge ack.

## Hackathon-specific exceptions

Within the H0–H6 hour-by-hour for Submission 1:
- **Wave 0 (this PR):** scaffold + docs only — single tier (local Claude subagent) is fine. No security implications.
- **Wave 1+ contract code:** full 3-tier mandatory.
- **Wave 1+ frontend / agents code:** full 3-tier mandatory.
- **Demo-only fix commits during H4–H6:** single tier acceptable; code lives ~1 hour.
