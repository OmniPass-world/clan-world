# ADR002: Bandit Spawn Probability Ramp

Date: 2026-05-01
Status: Accepted

## Context

Phase 9 implements bandit spawning as a deterministic per-region probability ramp after the global cooldown. The implementation uses basis points and currently increments each eligible region's accumulator by `1000` bps per missed spawn, capped at `8000` bps.

The planning spec previously described a slower `5%` start, `+1%` ramp, and `20%` cap. That no longer matches the implemented game loop or the UAT target cadence.

## Decision

The canonical v1 bandit spawn ramp is:

- start at `10%` per eligible region tick after cooldown
- increase by `+10%` for each eligible tick that does not spawn a bandit
- cap at `80%`
- reset the selected region's accumulator when a bandit spawns

## Consequences

This keeps bandits visible often enough for UAT and demo play without requiring long idle windows. Future changes to these values must update the contract constants, tests, planning spec, and this ADR together.
