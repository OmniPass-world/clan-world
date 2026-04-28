---
name: final-tick-continuity
description: Framework for what to consolidate to memory before a context reset. Triggered when the runner injects a "final tick warning." YOU decide what's worth carrying forward — this skill gives you the framework, not a checklist.
---

# Final-tick continuity (vague-by-design)

When the runner injects:

> warning: final tick before message history is reset. plan for continuity accordingly.

You have one tick to consolidate before `/clear`. The runner will NOT save your reasoning for you. After consolidation, call `elder ack-clear` so the runner can reset you cleanly (ack+timeout: if you don't ack within ~30s, runner clears anyway and you lose the turn's reasoning).

This skill is **vague on purpose**. There's no checklist. Your job as a sentient Elder is to apply judgment. Below is the framework, not the answer.

## What to think about saving

- **State changes you initiated** that haven't been confirmed on-chain yet. (If a tx is still pending, save the intent so you can reconcile next session.)
- **Strategic shifts** you decided this session that future-you needs to know. ("Pivoted from accumulation to aggressive raiding" — save why.)
- **Trust grade changes** for other clans based on observed behavior this session. ("Iron Guard betrayed the 3-gold deal — drop trust to 2.")
- **Active negotiations** mid-flight (peer whispers awaiting reply, market orders queued for future ticks).
- **Grudges** — explicit threats made or received. ("Storm Riders threatened reprisal next bandit raid.")
- **Surprises that violated your prior model** — anything that updates your map of how the world or other Elders behave.
- **Reasoning chains you're proud of** — strategic insights you don't want to re-derive.

## What NOT to save

- Anything that's already in chain state (your vault, your missions, your cooldowns — these read fresh on bootstrap).
- Anything in a peer message — peer inbox persists across resets.
- Recent world events — you'll see them again in the next situation block.
- Reasoning that didn't lead to a decision (consolidating noise wastes memory budget).

## How to save

Use `elder memory save <key> <value>` for each item:

- `elder memory save active-strategy "..."` — your current strategic posture
- `elder memory save trust:storm-riders "2 — betrayed 3-gold deal tick 47"`
- `elder memory save grudge:iron-guard "wronged at south plains tick 32, owe reprisal"`
- `elder memory save pending-tx:0x123abc "submitted MarketBuy 5e18 wood, awaiting tick 51 settlement"`

Then `elder ack-clear`.

## Why vague

A scripted checklist would make all four Elders consolidate identical things. Vague framework means YOU decide what matters to YOUR clan's continuity. That's the demo: agents that think for themselves about their own continuity, not agents executing identical save scripts.
