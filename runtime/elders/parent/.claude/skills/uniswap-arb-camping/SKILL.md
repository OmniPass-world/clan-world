---
name: uniswap-arb-camping
description: Strategy for monitoring market for arbitrage opportunities and queuing scheduled buys/sells when spreads widen. Use when you have a worker free and your strategy seed favors trader behavior.
---

# Uniswap arb camping

The "camping" pattern: park scheduled market actions ahead of expected price moves rather than reacting after the fact. Used when you have spare worker capacity and your archetype tilts trader.

## When to camp

- You have a worker in Waiting state at Unicorn Town with cooldown clear.
- You have a thesis about which way a token will move (e.g. "another clan's wood-rich mission completes tick N+2 → wood price drops").
- The cost of a missed scheduled action (one wasted tick of carry) is less than the upside.

## Mechanic

A scheduled market action is queued at submit time but doesn't execute until the heartbeat after the trigger condition clears. So you're effectively pre-committing a trade at a future price. Your `maxGoldIn` (for buys) bounds the worst-case slippage.

## How to size

1. Read current spread from `elder world snapshot` (returns regions + clans; market state surfaces here in S2 — dedicated `elder market *` subcommands TBD per Phase 2 economy work).
2. Estimate expected price drift from public missions visible in the same snapshot.
3. Set `maxGoldIn` to current price × (1 + acceptable slippage).
4. Queue with `elder clan submit-orders <orders.json>` containing a `MarketBuy` or `MarketSell` order shape.

## When NOT to camp

- Cooldown not clear — the order will fail silently and you waste a worker-tick.
- Treasury below 3 ticks of upkeep — opportunity cost of locked gold is too high.
- Market queue is already full of scheduled orders — yours executes after a heartbeat delay; the thesis may not survive.
- You're playing the Iron Guard archetype — defenders shouldn't camp markets, that's the trader play.

## Memory save pattern

If a camp pays off:

```bash
elder memory save arb:wood-tick-47 "camped MarketBuy 5e18 wood @maxGoldIn 8e18, executed @6.2e18, +28% on entry"
```

Future-you uses this to update your pattern recognition.

---

*S2 placeholder. The actual `MarketBuy` order shape is `(token, amountOut, maxGoldIn)` — exact-output buy per v4.1 patched addendum + IClanWorld.sol §A7. Sell is exact-input.*
