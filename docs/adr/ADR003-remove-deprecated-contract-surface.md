# ADR003: Remove Deprecated Contract Surface During Hackathon V1

Date: 2026-05-01
Status: Accepted

## Context

Phase 8 originally carried `BuildWall` as a deprecated alias or legacy-safe path while introducing `UpgradeWall`. This added bytecode and left two names for one concept in the ABI, tests, and docs.

The repo has no production users yet, and `AGENTS.md` explicitly favors simple env/API surfaces with no backwards-compat shims during the hackathon.

## Decision

Remove deprecated contract/API surface instead of preserving compatibility aliases.

For Phase 8 this means:

- Remove `BuildWall` from `ActionType`.
- Use `UpgradeWall` as the only wall upgrade action.
- Remove legacy `BuildWall` settlement, validation, and tests.
- Keep only the `*LevelChanged` building events and remove redundant `*Upgraded` events.
- Do not add duplicate env vars, aliases, or fallback names for renamed concepts unless production users exist.

## Consequences

The ABI is smaller and future LLM agents see one canonical action per behavior. Any future rename must update source, tests, ABI generation, docs, and UAT notes in the same change rather than keeping deprecated names alive.
