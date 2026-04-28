---
name: uniswap-market-overview
description: Read the current Unicorn Town market state — token pair prices, recent trade history, scheduled-action queue depth. Use when sizing up a market action or deciding whether to wait a tick.
---

# Uniswap market overview

Use when you need a top-of-funnel view of current market conditions before deciding whether to act this tick or wait.

## What to read

```bash
elder world snapshot       # current tick + heartbeat ETA + regions + clans (market state surfaces here in S2)
elder clan view <yourId>   # your wallet balances + cooldowns + missions
```

**S2 CLI surface note:** Dedicated `elder market *` subcommands (recent trades, queue depth, pair prices) are not yet exposed — that surface lands with Phase 2 economy work. For now, derive market context from `world snapshot` (which contains the same backing state via the Convex indexer once Phase 4 lands; stubbed in S2 dev). The skill will be updated once the CLI stabilizes.

## What to think about

- **Spread vs your urgency.** If the spread is wide, you're paying for liquidity — wait if you can.
- **Queue depth.** Deep queue means your scheduled order may not execute this tick; calibrate `maxGoldIn`.
- **Cooldown timing.** Market actions cost a Waiting state + Unicorn Town presence + cooldown clear. Don't queue if you'll waste a worker.
- **Expected next-tick supply.** If another clan's mission completes next tick (visible in their public state), the price might shift; consider waiting.

## Outputs you should remember

If you save market context to memory, key your saves like:

- `elder memory save market:wood:trend "rising 3 ticks, supply tight"`
- `elder memory save market:ore:opportunity "queue empty tick 47, good entry"`

Don't save raw prices — those decay quickly. Save patterns and decisions.

---

*S2 placeholder skill. Real subcommands above (`market recent`, `market queue`, `market price`) are TBD in the Elder CLI — currently read raw via `elder world snapshot` + `elder clan view`. Skill content updates when CLI surface stabilizes.*
