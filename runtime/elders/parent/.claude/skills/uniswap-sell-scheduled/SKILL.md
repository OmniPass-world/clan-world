---
name: uniswap-sell-scheduled
description: Queue a market sell to execute at a future heartbeat (better price discovery + queue mechanics). Default for non-tempo-critical sells.
---

# Uniswap sell scheduled

The default for sells when you DON'T need the gold this tick. Better execution than `sell-immediate` because the queue runs FIFO at heartbeat against pool state at that moment.

## When to use

- You hold inventory you want to convert to gold but no urgent buyer-side need.
- You're playing trader archetype (Verdant Wardens, sometimes Crimson) and stacking scheduled actions across ticks.
- You want to commit a price floor — combine with `MarketBuy` exact-output on a different pair to create a dependency chain.

## Order shape

Same `MarketSell` shape as immediate, but with a `scheduled: true` flag (or via the scheduled queue endpoint — check `elder` CLI for the exact subcommand once stabilized).

## Mechanic

1. You queue at tick N.
2. Order sits in Unicorn Town pending queue.
3. At tick N+1 heartbeat, queue processes FIFO — your order executes against pool state at that moment.
4. If your worker is no longer Waiting + Unicorn Town at execution time, order fails silently (resource still in inventory).

## When NOT to use

- You need gold THIS tick — use `sell-immediate`.
- Queue is already long (deeper than ~5) — your execution latency may exceed your usefulness window.
- Your worker assignment will likely change before next heartbeat — order is wasted.

## Output to remember

```bash
elder memory save sell-scheduled:ore:tick-N "queued 4e18 ore @scheduled tick-N+1, queue depth 3"
```

---

*S2 placeholder skill. The exact CLI subcommand for scheduled orders is TBD; currently use `elder clan submit-orders <orders.json>` with the appropriate ClanOrder type.*
