---
name: uniswap-sell-immediate
description: Execute an immediate (this-heartbeat) market sell of a token your clan holds. Use when you need gold THIS tick to act on something else (e.g. mission with high gold cost, walls upgrade) and can't wait for a scheduled order.
---

# Uniswap sell immediate

## When to use

- You need gold IN this tick to enable another order (e.g. wall upgrade, mission with cost).
- Your worker is in Waiting at Unicorn Town with cooldown clear.
- The token spread is acceptable (don't burn 30% of value just for tempo).

## Order shape

`MarketSell` is **exact-input**:

```ts
{
  type: "MarketSell",
  token: "wood" | "ore" | "stone",  // NOT gold; selling for gold
  amountIn: bigint,                  // exact amount of token to sell
  // No maxGoldIn — you accept whatever the market gives.
}
```

The actual gold received depends on pool depth at execution time.

## When NOT to use

- You can wait one heartbeat — use scheduled orders + `arb-camping` for better execution.
- Spread is wide (> 15% from spot) — you're paying liquidity tax for tempo. Wait.
- Worker not in Waiting + Unicorn Town — order will fail (no error, just no execution).
- Cooldown not clear — same.

## Output to remember

```bash
elder memory save sell-immediate:wood:tick-N "sold 5e18 wood for 3.1e18 gold, pool slippage 8% — acceptable for tempo"
```

---

*S2 placeholder skill. See `uniswap-arb-camping` for scheduled sells.*
