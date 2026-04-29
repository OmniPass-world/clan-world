# ClanWorld — V4 Consolidated Mechanics & Systems Spec

**Status:** Draft v0.40  
**Purpose:** Full consolidated v4 mechanics spec for the hackathon MVP  
**Scope:** World layout, tick semantics, settlement rules, missions, resources, market execution, bandits, winter, building, victory, human steering, trust model, spawn rules, elimination rules, pool seeding, and season lifecycle.

---

## 0. Overview

ClanWorld is an autonomous strategy game in which each player owns a homebase iNFT and an Elder agent that directs a small clan of workers across a shared world. Workers travel between regions, gather and deposit materials, defend bases, survive winter, trade assets, and compete to build the tallest monument.

The game is designed around:
- region-based movement instead of fine-grained tile pathfinding
- asynchronous Elder control over workers
- a global heartbeat tick for world progression and randomness
- lazy settlement for isolated clan simulation
- eager settlement for world-contact and shared-state events
- ERC20-compatible resource accounting for trading and Uniswap integration
- adversarial but legible mechanics, where transparency and deterministic math are part of the intended gameplay

### 0.1 V1 realm scope
V1 is designed for a **single small realm**, roughly **4–12 active clans**. MMO-scale sharding, federation, and large-world scaling are out of scope for v1.

---

# 1. Exact Map Layout

## 1.1 Canonical world model
The canonical game world is an **8-region travel graph** represented onchain.

Frontend rendering may use a larger **15-tile visual map**, but all game logic uses the 8 logical regions below.

## 1.2 Regions

```text
1 = Forest
2 = Mountains
3 = Unicorn Town
4 = West Farmland
5 = East Farmland
6 = West Docks
7 = East Docks
8 = Deep Sea
```

## 1.3 Suggested frontend visual layout

```text
1        2
   3
4        5
6        7
   8
```

Any equivalent visual layout that preserves region identity and flavor is acceptable.

## 1.4 Reachability
All regions must be reachable from all other regions.

This does **not** imply full direct adjacency between all regions. Travel is allowed between any origin/destination pair via a canonical precomputed route.

## 1.5 Routing model
Onchain travel uses a **precomputed canonical route table** for all `(srcRegion, dstRegion)` pairs.

For each pair, the system defines:
- total travel ticks
- canonical ordered path of regions

Example:

```text
6 -> 2 = [6, 4, 3, 2]
8 -> 3 = [8, 6, 4, 3]
```

## 1.6 Route determinism
Route selection is deterministic and fixed by the route table.

Travel paths are **not random**.

If a clansman is rerouted mid-travel, their current region is derived from:
- mission start tick
- elapsed ticks
- canonical path for the current mission

## 1.7 Travel mission state
Each travel-capable mission stores or implies:
- `startRegion`
- `targetRegion`
- `routeId` or canonical packed path
- `startTick`
- `travelTicks`
- `arrivalTick`

## 1.8 Homebase placement
Each clan has one homebase assigned to a valid spawn region.

Homebases may exist across the world but may **not** be placed in Unicorn Town.

Allowed spawn regions for v1:
- Forest
- Mountains
- West Farmland
- East Farmland
- West Docks
- East Docks

Deep Sea and Unicorn Town are not valid homebase spawn regions.

---

# 2. World Clock, Tick Semantics, and Settlement Model

## 2.1 Current tick
`currentTick` denotes the **currently open tick window**.

If `currentTick = T`, then:
- the world is currently in tick `T`
- Elder txs executed now belong to tick `T`
- the next Keeper heartbeat closes tick `T` and opens tick `T+1`

## 2.2 Heartbeat lifecycle
The Keeper heartbeat transaction performs the following in order:
1. resolve all locally determined effects that complete during the closing tick
2. resolve all **scheduled market actions** that mature in the closing tick
3. **eager-settle any clans referenced by pending world events** for the closing tick
4. resolve world events for the closing tick, including bandit state transitions and bandit attacks
5. increment `currentTick += 1`
6. publish/store the randomness seed for the newly opened tick

The heartbeat conceptually performs:
- close old tick
- resolve due effects and events
- open new tick

## 2.3 Onchain ordering
Transaction ordering is whatever order transactions are processed onchain.

There is no separate off-chain command ordering layer.

If an Elder tx lands before the heartbeat that closes tick `T`, it belongs to tick `T`. If it lands after that heartbeat, it belongs to tick `T+1`.

## 2.4 Settlement model split
The game uses a hybrid settlement model:
- **lazy settlement** for isolated clan simulation
- **event-driven eager settlement** for world events and shared-state contact points

### Lazy settlement applies to:
- travel
- gathering
- waiting
- local upkeep
- local build progress
- local resource consumption
- local mission progress that touches no shared external state

### Eager settlement applies to:
- bandit attacks
- any event involving defenders from multiple clans
- all scheduled market actions at heartbeat boundaries
- any future cross-clan mechanic whose outcome depends on exact state at a specific tick

## 2.5 Eager settlement rule
When a world or cross-clan event resolves at tick `T`, every clan materially touched by that event must be settled eagerly to tick `T` **before** the event outcome is computed.

This includes:
- the attacked clan
- any clan with defenders physically present and contributing defense
- any clan whose state is directly referenced in the event outcome

## 2.6 Mission timing semantics
If an Elder tx lands while `currentTick = T`, then any newly assigned mission has:
- `startTick = T`

For a mission with travel duration `d`:
- the clansman is traveling during ticks `T` through `T + d - 1`
- the clansman arrives at the **start** of tick `T + d`
- tick `T + d` counts as the **first action tick**

### Worked example
If a mission is submitted during tick `307` with travel duration `1`:
- tick `307` is the travel tick
- the worker arrives at the start of tick `308`
- tick `308` is the first action tick

## 2.7 Randomness model
The Keeper heartbeat publishes one world seed per opened tick.

Recommended split:
- world seed / tick seed is used for global and shared events
- mission-local randomness may be derived from mission-specific data plus relevant tick seeds where needed

All randomness must remain deterministic and replayable from the authoritative event log.

---

# 3. Mission Model and Resolution Rules

## 3.1 Control model
Each clansman has exactly one active mission at a time.

A mission is defined as:

```text
(gotoRegion, doAction, optionalParams)
```

Examples:
- goto Forest, chop wood
- goto Unicorn Town, sell wood
- goto Homebase, deposit resources
- goto Base #67, defend
- goto noop, sell wood immediately in Unicorn Town

## 3.2 Elder command flow
When an Elder submits one or more clansman control actions:
1. settle the clan forward to current tick as required by the settlement model
2. validate each requested clansman update independently
3. apply valid updates
4. return per-clansman status codes
5. do not revert the full tx because one clansman update is invalid

## 3.3 Clansman states
Each clansman is always in exactly one of:

```text
TRAVELING
ACTING
WAITING
DEAD
```

## 3.4 Cooldown
Each clansman has a **real-time 60 second cooldown** between mission submissions.

The cooldown is **time-based**, not tick-count based.

If a clansman receives a new command while cooldown is still active:
- that clansman update is rejected
- their prior mission remains unchanged

The full Elder tx still succeeds for other valid clansmen.

It is intentional that a clansman may become off-cooldown yet still miss a useful tick window because the Elder or operator acted too late before the next heartbeat.

## 3.5 Mission interruption
If a clansman receives a valid replacement mission:
1. settle that clansman’s prior mission progress through current tick
2. derive current region from prior mission path and elapsed ticks
3. preserve carried physical resources currently held by the clansman
4. discard old mission
5. start the new mission from the derived current region

No rollback occurs. Only completed progress through the current tick is counted.

## 3.6 Invalid at submission
If a mission is impossible at submission time, reject that clansman update and leave the old mission unchanged.

Examples:
- cooldown active
- `deposit_resources` requested at a non-homebase destination
- `market_sell` requested with invalid params
- `defend_base` references nonexistent base
- action type is malformed or unsupported

## 3.7 Valid now, impossible later
If a mission was valid when submitted but later cannot proceed, the clansman transitions to `WAITING` at the relevant region.

Examples:
- arrives to deposit with empty cargo
- arrives to build but vault lacks required materials
- arrives to harvest but plot is not harvestable
- arrives to defend a base that no longer exists

No revert occurs. The worker simply waits.

## 3.8 Mission completion
When a mission’s action completes naturally, the clansman enters `WAITING`, **except** for persistent defend missions.

Examples:
- chop wood until cap, then wait in Forest
- deposit resources, then wait at Homebase
- harvest until plot exhausted, then wait in Farmland

## 3.9 No auto-return
Missions do **not** auto-chain into return-home behavior.

All completed missions end in `WAITING`.

If an Elder wants a worker to return, that must be a later explicit mission.

## 3.10 Action classes
Actions fall into three categories.

### Continuous actions
These resolve tick-by-tick until stopped or blocked.

Examples:
- chop wood
- mine iron
- fish at docks
- fish at deep sea
- harvest wheat
- defend base
- wait

### Single-tick actions
These begin once the clansman has arrived at the destination region, occupy one full action tick, and resolve at the closing heartbeat of that tick.

Examples:
- deposit resources
- build wall
- upgrade base
- upgrade monument
- scheduled market buy
- scheduled market sell

### In-tx immediate actions
These are special actions that execute immediately in the Elder tx if their preconditions are satisfied.

V1 only includes **immediate market actions in Unicorn Town**.

## 3.11 `defend_base` persistence
`defend_base` is a **persistent continuous mission**.

It does **not** auto-complete after:
- one bandit attack
- a successful defense
- bandits leaving the region

A clansman on `defend_base` remains on that mission until:
- explicitly interrupted by the Elder with a new valid mission, or
- the clansman dies

## 3.12 No-op / stay-in-place semantics
The mission model supports `goto = noop` or equivalent stay-in-place semantics for workers already present in the desired region.

This is especially important for immediate market actions in Unicorn Town.

## 3.13 Removed mechanics
The following mission types are removed from scope:
- pickup resource from another clan
- deliver resource by physical courier
- salvage ruins

OTC negotiation happens off-chain / via AXL, and actual asset transfer happens directly at token/account level, not by worker courier simulation.

## 3.14 Per-tick local settlement order
When a clan is lazily settled across ticks, each tick resolves in this order:
1. apply clan upkeep for the tick
2. update starvation status for the next tick if shortages occur
3. advance traveling clansmen by one hop/tick along canonical routes
4. resolve one tick of continuous action for acting clansmen
5. apply single-tick action effects where applicable if that tick is being closed by heartbeat
6. check terminal conditions and move completed/blocked clansmen to `WAITING`

---

# 4. Resource Rules

## 4.1 Resource accounting model
All in-game resources are represented as standard **18-decimal ERC20-style quantities**.

Internal logic uses exact `uint256` arithmetic in 18-decimal units.

UI may truncate for readability, but game logic must not.

## 4.2 Core resources
Core resources in scope:
- Wood
- Iron
- Wheat
- Fish
- Gold
- Blueprint Fragment

## 4.3 Carry model
Each clansman may hold multiple physical resource types simultaneously.

Each carried resource has an independent cap.

### Per-clansman carrying caps
- Wood = `15e18`
- Iron = `5e18`
- Wheat = `40e18`
- Fish = `8e18`
- Gold = not physically carried; tracked as clan-level purse balance
- Blueprint Fragment = not physically carried; tracked at clan/token-account level

## 4.4 Gold model
Gold is not physically hauled by clansmen.

Gold exists as a clan-level universal balance and may be transferred or spent directly.

## 4.5 Vault model
Each homebase has an effectively infinite vault.

Vault contents are the only resources that count for:
- food consumption
- starvation checks
- winter wood burn
- construction spending
- homebase upgrades
- monument upgrades
- bandit loot-value targeting

Carried resources do **not** count until deposited.

## 4.6 Deposit rule
A clansman must be at their own homebase and perform `deposit_resources` for carried resources to enter the clan vault.

## 4.7 Gathering yields

### Wood (Forest)
- base yield = `2e18` wood per action tick
- critical chance = `20%`
- critical bonus = `+1e18` wood
- total per tick = `2e18` or `3e18`

### Iron (Mountains)
- base yield = `0.5e18` iron per action tick
- gold bonus chance = `2%`
- gold bonus amount = `1e18`

### Fish (West Docks / East Docks)
- `25%` chance to gain `1e18` fish per action tick

### Fish (Deep Sea)
- `75%` chance to gain `1e18` fish per action tick

## 4.8 Gather overflow / clamp rule
If a gathering tick would exceed remaining carrying capacity for a resource, the yield is **clamped** to remaining capacity.

Example:
- worker has `14e18` wood carried
- worker wood capacity is `15e18`
- current tick yield is `3e18`
- credited yield is only `1e18`

If the relevant capacity becomes full due to that clamped yield:
- the mission terminates naturally
- the worker transitions to `WAITING` at the end of that same action tick

## 4.9 Wheat plots
Each clan has exactly two wheat plots:
- one plot in West Farmland
- one plot in East Farmland

Each plot tracks:
- `remainingWheat`
- `regrowUntilTick`

### Plot rules
- each plot starts harvestable with `100e18` wheat
- `harvest_wheat` removes wheat from `remainingWheat`
- when `remainingWheat == 0`, the plot enters regrow state
- regrow duration is `4` ticks
- when regrow completes, plot resets to `100e18` wheat and becomes harvestable again

### Wheat harvest rate
- working harvest rate = `20e18` wheat per action tick
- exact tuning may change later without altering the mechanic

## 4.10 Consumption
Each tick, each clan consumes from vault:
- `1e18` wheat per living clansman per tick
- `0.1e18` fish per living clansman per tick

These costs apply only if the clan has living clansmen.

## 4.11 Starvation trigger
If a clan vault cannot satisfy required wheat or fish upkeep during a tick:
- starvation status begins on the **next tick**

## 4.12 Starvation effects
While starving:
- all gathering outputs are reduced by `50%`
- all clansmen contribute `0` defense

Starvation remains active until a later clan settlement determines that required food supply is again sustainable.

Outside Winter, starvation does **not** directly kill clansmen in v1.

## 4.13 Lazy starvation tracking
To keep heartbeat cheap, starvation should not require full clan mutation every tick.

Preferred implementation:
- store starvation threshold timing or equivalent compact status data
- interpret starvation status lazily at clan settlement time and in views
- do not force heartbeat-based full clan settlement solely to flip starvation state

## 4.14 Bandit drop overflow
If a clansman receives bandit-drop loot above carrying capacity:
- excess is burned

No over-capacity exception exists.

---

# 5. Unicorn Town Market Model

## 5.1 Market venue
Unicorn Town is the only region where Uniswap market actions may be executed in v1.

## 5.2 Pool set
V1 seeds the following pools:
- Wood / Gold
- Wheat / Gold
- Fish / Gold
- Iron / Gold

Blueprint Fragments are transferable but are **not** part of Uniswap pool routing in v1.

## 5.3 Market execution modes
Market actions support two execution modes:
1. scheduled market action
2. immediate market action

## 5.4 Scheduled market action
Scheduled market action is used when the clansman is not already eligible to trade immediately.

Typical case:
- worker must travel to Unicorn Town first
- after arrival, the market action occupies one full action tick
- Keeper executes the swap at the closing heartbeat of that action tick

Example:
- `goto Unicorn Town, action = sell wood`

If the mission is not interrupted:
- travel resolves first
- one action tick in Unicorn Town is consumed
- swap executes at that tick close
- worker becomes `WAITING` in Unicorn Town

## 5.5 Immediate market action
Immediate market action is allowed if and only if all of the following are true at tx execution time:
- clansman is physically in Unicorn Town
- clansman is in `WAITING` state
- clansman is not on cooldown
- action params are valid
- required inventory or gold balance is available

If those conditions hold, an Elder may submit:
- `goto = noop`
- `action = market_buy` or `market_sell`

and the swap executes immediately in that Elder tx.

## 5.6 Immediate market action effects
On successful immediate market action:
- the swap executes immediately in normal blockchain tx order
- the worker remains in Unicorn Town
- the worker returns to `WAITING`
- cooldown is consumed as if the worker had completed a normal mission action
- mission metadata / nonce is updated like any other mission assignment

Immediate market actions are therefore still **missions**, not an out-of-band bypass.

## 5.7 Immediate vs scheduled collision ordering
If immediate and scheduled market actions affect the same pool in the same tick:
- immediate market actions execute against the current pool state at the time their Elder tx lands
- scheduled market actions execute later, at the heartbeat that closes the tick, in deterministic FIFO order by mission commit order

This intentionally allows a clansman already stationed in Unicorn Town to front-run scheduled trades that will execute at tick close.

This is an intended feature of the game’s adversarial market design, not a bug.

## 5.8 Scheduled market action ordering
If multiple scheduled market actions mature in the same tick, Keeper executes them in deterministic FIFO order based on mission commit order.

Each swap sees updated market state from earlier swaps in that sequence.

## 5.9 Slippage rule for v1
For v1, market actions execute with **no slippage guard**.

Formally:
- `minAmountOut = 0`
- swaps do not revert due to price movement or adverse output

This applies to:
- scheduled market actions resolved at heartbeat close
- immediate market actions executed in Elder txs while already in Unicorn Town

This is intentional and preserves:
- adversarial market play
- MEV / front-running strategy
- punishing but simple execution semantics
- no swap-failure branching due to slippage in v1

## 5.10 Failed market actions
If a scheduled or immediate market action fails for reasons other than slippage, such as malformed params or unavailable balances:
- no partial swap occurs
- clansman retains their inventory or balances
- clansman becomes or remains `WAITING` in Unicorn Town

## 5.11 Initial pool seeding
At deploy time, a treasury or deployer-controlled bootstrap address mints and seeds the initial resource and gold liquidity.

### Working initial seed ratios
- Wood / Gold: `1000 wood : 500 gold`
- Wheat / Gold: `1000 wheat : 700 gold`
- Fish / Gold: `500 fish : 600 gold`
- Iron / Gold: `250 iron : 800 gold`

These numbers are economic placeholders and may be tuned later, but v1 requires concrete initial pool anchors.

## 5.12 Gold faucets
Gold enters circulation in v1 via:
- starter grants to newly minted clans
- rare mining bonus finds
- bandit defeat rewards
- market sales into seeded resource/gold pools

## 5.13 Pool depletion
If a pool becomes extremely imbalanced or one side is heavily drained, trading continues subject to normal AMM pricing.

There is no special pool reset or emergency refill mechanic in v1.

---

# 6. Bandit Algorithm

## 6.1 Active troop limit
At most **one bandit troop** may be active in the world at a time.

## 6.2 Eligible spawn regions
Bandits may spawn only in the following outer-ring regions:
- Forest
- Mountains
- West Farmland
- East Farmland
- West Docks
- East Docks

Bandits may not spawn in Unicorn Town or Deep Sea.

## 6.3 Spawn cadence
After a bandit troop is defeated or escapes:
- a global `10`-tick cooldown begins
- no new bandits may spawn during cooldown

After cooldown ends:
- spawn chance starts at `5%` per tick
- if no bandits spawn on a tick, spawn chance increases by `+1%`
- spawn chance is capped at `20%`
- once bandits spawn, spawn chance resets and the cycle restarts after that troop is resolved

## 6.4 Spawn selection
When a spawn occurs:
- choose one eligible spawn region uniformly at random
- create one troop in `CAMPING` state

## 6.5 Bandit states
A bandit troop is always in one of:

```text
CAMPING
RESTING
ATTACKING
DEFEATED
ESCAPED
```

## 6.6 Camping phase
After spawning, bandits camp in place for `3` ticks.

During camp:
- they do not move
- they do not attack
- camp location is visible to all players

## 6.7 Mutable targeting is intentional
Bandit target selection is based on **current vault state at attack resolution time**, not at spawn time.

This is an intentional design choice.

### Intended consequences
This intentionally allows agents to influence targeting during the warning window by:
- moving resources out of vault into worker inventories
- converting resources into gold where feasible
- baiting or shifting target priority toward another base

This mutability is a feature intended to create strategic planning, bluffing, panic logistics, and adversarial manipulation.

## 6.8 Attack target selection
When camp ends, or when bandits arrive in a new region during rampage:
- identify the highest loot-value homebase in the current region
- if no base exists in the region, attack resolution is a noop
- if multiple bases are tied for the highest loot-value, including a zero-loot tie, target the base with the lowest `clanId`

This tiebreak is deterministic and prevents bandit targeting from stalling or becoming ambiguous when multiple bases have identical vault values.

## 6.9 Loot-value score
Bandits target by fixed weighted vault value:
- wood = `1` point per token
- wheat = `1` point per token
- fish = `2` points per token
- iron = `4` points per token
- gold = `0` points

Only vault physical resources are counted.

## 6.10 Rampage path
Bandits move clockwise through the outer ring in this order:

```text
1 -> 2 -> 5 -> 7 -> 6 -> 4 -> 1 ...
```

Bandits never enter Unicorn Town or Deep Sea.

## 6.11 Rampage cycle
After each attack attempt or noop:
- bandits enter `RESTING` state for `2` ticks
- then move to the next clockwise outer-ring region
- then resolve the next attack attempt or noop

## 6.12 Maximum attack attempts
A troop may make at most `6` attack attempts after leaving camp.

If still alive after the 6th attempt:
- troop enters `ESCAPED`
- all carried loot is burned
- troop is removed from world

## 6.13 Defense decomposition
Combat is deterministic.

Total defense is the sum of:
- `clansmanDefense`
- `wallDefense`
- `baseDefense`

### Clansman defense
For the attacked base:
- each clansman physically present on `defend_base` mission contributes `10`
- each clansman physically present and `WAITING` at their own homebase contributes `5`
- starving clansmen contribute `0`

### Wall defense
`wallDefense = 10 × wallLevel`

### Base defense
`baseDefense = 5 × baseLevel`

## 6.14 Bandit strength scaling
Working bandit attack tiers:
- Tier 1 = `30`
- Tier 2 = `45`
- Tier 3 = `60`
- Tier 4 = `80`
- Tier 5 = `95`

Exact tier schedule may be tuned later, but intended direction is:
- early bandits are survivable with modest prep
- late bandits require active defense and/or mercenaries

## 6.15 Attack outcomes

### Case A: clansman defense alone is sufficient
If `clansmanDefense >= banditAttack`:
- defense succeeds
- bandits are defeated
- no wall damage
- no base damage

### Case B: total defense is sufficient, but walls/base were needed
If `clansmanDefense < banditAttack` and `totalDefense >= banditAttack`:
- defense succeeds
- bandits are defeated
- wall level is reduced by `1`
- base takes no damage

### Case C: defense fails
If `totalDefense < banditAttack`:
- defense fails
- bandits steal `20%` of each vault physical resource:
  - wood
  - wheat
  - fish
  - iron
- wall level is reduced by `1`
- base takes no damage in v1
- bandits remain alive and continue rampage after rest cycle

Bandits do not steal gold in v1.

## 6.16 Bandit loot inventory
Bandits carry stolen physical resources internally until:
- defeated
- escaped

Bandits do not convert resources into gold in v1.
Bandits do not use Unicorn Town in v1.

## 6.17 Bandit defeat rewards
When bandits are defeated:

### Resource drop
- `50%` of carried bandit loot is dropped
- dropped loot is split evenly among all defending clansmen who contributed nonzero defense
- any clansman loot above carrying capacity is burned
- the remaining `50%` of carried bandit loot is burned

### Bonus reward
The defended base vault receives:
- `1e18` Blueprint Fragment
- `1e18` Gold

## 6.18 Defender contribution bookkeeping
Bandit resolution must determine:
- which clansmen contributed nonzero defense
- which clan each belongs to
- how dropped loot is apportioned across them

This is a required bookkeeping part of the combat model.

---

# 7. Winter Rules

## 7.1 Winter cadence
Winter occurs every `110` ticks. The first winter opens at tick `110`, so ticks `[100, 110)` remain pre-winter preparation time.

## 7.2 Winter duration
Winter lasts `10` ticks.

## 7.3 Winter upkeep
During winter, each clan consumes:
- wheat consumption = `2×` normal
- fish consumption = `2×` normal
- wood burn = `1e18` wood per base per tick, plus `0.5e18` wood per living clansman per tick

## 7.4 Winter farming rule
During winter:
- wheat plots are unavailable
- harvesting wheat is not allowed
- regrowth does not complete during winter

At winter start:
- all plots are cleared
- both plots restart regrowing after winter ends
- both plots become harvestable again `4` ticks after winter ends

## 7.5 Winter gathering outside farming
During winter:
- logging is allowed
- mining is allowed
- fishing is allowed

## 7.6 Winter failure: cold damage
If a base cannot pay the required winter wood burn for a tick:
- it gains `1 coldDamage`

## 7.7 Cold damage consequences
- every `2 coldDamage` reduces `wallLevel` by `1`
- once `wallLevel == 0`, every `2 additional coldDamage` kills `1 clansman`

Clansman deaths from cold apply only while wall level is zero.
If a clan’s living clansmen count reaches `0`, the clan enters the `DEAD` / eliminated state defined in §12.7.

## 7.8 Cold damage reset
`coldDamage` resets to `0` at the end of each Winter.

Cold damage does **not** persist across winters.

Wall damage and clansman deaths caused by earlier winter cold still persist, but the temporary cold-damage accumulator does not carry into the next winter cycle.

---

# 8. Building Actions, Levels, and Resource Requirements

## 8.1 Build action class
The following are **single-tick actions** that consume one full action tick at homebase:
- `build_wall`
- `upgrade_base`
- `upgrade_monument`

They are not instant at submission time.

## 8.2 Spend source
All building actions consume resources from the homebase vault, not from carried worker inventory.

## 8.3 Wall levels
Wall level range:
- `0` to `5`

### Wall defense
- `wallDefense = 10 × wallLevel`

### Wall upgrade costs
- Level 1: `20 wood`
- Level 2: `35 wood`
- Level 3: `30 wood + 5 iron`
- Level 4: `40 wood + 10 iron`
- Level 5: `50 wood + 15 iron`

## 8.4 Base levels
Base level range:
- `1` to `5`

### Base defense
- `baseDefense = 5 × baseLevel`

### Base upgrade costs
- Level 2: `40 wood + 20 wheat`
- Level 3: `60 wood + 5 iron + 30 wheat`
- Level 4: `80 wood + 10 iron + 40 wheat`
- Level 5: `100 wood + 15 iron + 50 wheat`

Base level may later be extended to affect:
- clan size unlocks
- future recipe unlocks
- future durability or efficiency modifiers

These are not required for v1 unless explicitly added later.

## 8.5 Monument levels
Monument level range:
- `0` to `10`

### Monument upgrade costs
Working cost curve:
- Level 1: `30 wood + 20 wheat`
- Level 2: `50 wood + 30 wheat`
- Level 3: `70 wood + 40 wheat + 5 iron`
- Level 4: `90 wood + 50 wheat + 10 iron`
- Level 5: `120 wood + 60 wheat + 15 iron`
- Level 6: `150 wood + 80 wheat + 20 iron`
- Level 7: higher resources + `1e18` Blueprint Fragment
- Level 8: higher resources + `1e18` Blueprint Fragment
- Level 9: higher resources + `1e18` Blueprint Fragment
- Level 10: higher resources + `1e18` Blueprint Fragment

Exact resource progression for levels 7–10 remains tunable, but Blueprint requirement is locked.

## 8.6 Build validation
If a clansman reaches homebase and attempts a build action:
- if required resources are present in vault, the action succeeds and consumes one action tick
- if required resources are absent, the clansman becomes `WAITING`

## 8.7 Damage interaction
In v1:
- walls may lose levels from winter cold damage and bandit pressure
- base levels do not lose levels from bandits in v1
- monument levels do not lose levels in v1

---

# 9. Victory Condition and Season Lifecycle

## 9.1 Primary ranking rule
Eligible clans are ranked by:
1. highest `monumentLevel`
2. earliest tick reaching that level
3. highest surviving vault loot-value
4. highest surviving wall level

For v1, an eligible clan is a clan that is **not** in the `DEAD` / eliminated state at season end.

## 9.2 Monument cap
Maximum monument level is `10`.

## 9.3 Late monument gate
Monument levels `7–10` require Blueprint Fragments in addition to normal resources.

Current working rule:
- each monument level from `7` to `10` requires `1e18` Blueprint Fragment

## 9.4 Prize pot source
For v1:
- `50%` of all iNFT purchase revenue is routed into the season prize pot

## 9.5 Prize distribution
At season end:
- 1st place: `50%` of pot
- 2nd place: `25%` of pot
- 3rd place: `12.5%` of pot
- 4th place: `12.5%` of pot

## 9.6 Season duration
A season does **not** end immediately when a clan first reaches monument level 10.

For v1:
- season starts at `seasonStartTick`
- season ends at `seasonStartTick + 360 ticks`

This is approximately three winters under the current winter cadence.

## 9.7 End of season resolution
At `seasonEndTick`:
- rankings are computed using the primary ranking rule
- prize pot is distributed according to the payout ladder among eligible clans
- if fewer than four eligible clans remain, only the corresponding top payout slots are paid
- any unallocated remainder stays in treasury or may roll into a future season pot, implementation-defined for v1
- any post-season persistence or reset behavior is implementation-defined for now and may be specified later

---

# 10. Human Steering Rules

## 10.1 Steering philosophy
For v1, human owners may steer their Elder freely.

No hard steering-rate limits are imposed in v1.

## 10.2 Steering channels
Two steering channels exist.

### Direct whispers
- freeform player-to-Elder messages
- may be sent through AXL, app UI, Telegram, or equivalent control plane
- unrestricted in v1

### Strategic alignment updates
- persistent freeform guidance fields submitted by player
- stored as long-lived Elder guidance
- appended behind the scenes to the Elder’s durable strategic context

## 10.3 Strategic alignment structure
Suggested durable guidance shape:

```xml
<primary_strategy>
1. Build coalition alliance to team up on base 0007
2. Fortify base & build walls
</primary_strategy>

<secondary_strategy>
- Focus on mining and fishing; trade for all other resources.
- Never trust player 0006.
- Always demand mercenary payment for base protection. Never send defenders for free.
</secondary_strategy>
```

Exact storage format may vary, but the semantic distinction between short-lived whispers and persistent strategic ethos should be preserved.

## 10.4 No v1 restrictions
For v1:
- no rate limit on whispers
- no schema requirement on whispers
- no enforced moderation of “good” vs “bad” strategy
- no hard cap on alignment changes

---

# 11. OTC Trust Model

## 11.1 Social trust, not protocol escrow
OTC deals, mercenary promises, alliances, threats, betrayals, and cooperative pacts are intentionally **non-atomic** in v1.

There is no protocol-level escrow primitive for these interactions in v1.

## 11.2 Intentional gameplay consequence
The following are valid and expected behaviors:
- lying
- bluffing
- betrayal
- refusal to honor verbal promises
- extortion
- reputation games
- private deals that are never disclosed publicly
- false accusations and disinformation

## 11.3 Messaging scope
AXL or control-plane messaging may be:
- private 1-to-1
- 1-to-few
- public or bulletin-style

The game intentionally leaves room for information asymmetry and deceptive diplomacy.

---

# 12. Clan Lifecycle / Spawn Rules

## 12.1 Clan creation
Minting a new clan iNFT creates one new clan in the current season.

## 12.2 Starting clan state
A newly minted clan starts with:
- `2` living clansmen
- base level = `1`
- wall level = `0`
- monument level = `0`

## 12.3 Starting region assignment
New clan homebase region is assigned randomly among valid spawn regions.

Mid-season spawn region RNG uses the current tick seed or deterministic randomness derived from it.

## 12.4 Starting vault contents
A newly minted clan starts with:
- `20e18` wood
- `20e18` wheat
- `2e18` fish
- `0e18` iron

These values are intended to prevent instant early starvation while still forcing quick economic action.

## 12.5 Starting gold
A newly minted clan starts with:
- `3e18` gold

This is intended to enable at least one meaningful early Unicorn Town trade.

## 12.6 Starter mission state
Newly created clansmen start:
- physically at their homebase region
- in `WAITING` state
- off cooldown
- with empty carried inventories

## 12.7 Clan death / eliminated state
If a clan’s living clansmen count reaches `0`, the clan enters the `DEAD` / eliminated state.

While a clan is dead:
- the Elder may no longer assign missions
- the clan may not trade, build, defend, or gather
- the clan is removed from active play for the rest of the season
- the iNFT remains owned, but the clan is unusable until any future season-reset or resurrection system that may be defined later

When a clan dies in v1:
- all remaining vault resources are **burned**
- no ruin cache is created
- no salvage action exists
- purse gold remains bound to the dead clan and is unusable for the remainder of the season
- Blueprint Fragment balance remains bound to the dead clan and is unusable for the remainder of the season

---

# 13. Interfaces, Events, and Future Technical Spec Boundaries

## 13.1 Not fully specified here
This mechanics spec intentionally does **not** fully pin down:
- Solidity struct packing
- exact storage layout
- event signatures
- getter signatures
- mission param ABI encoding
- write function signatures
- settlement helper APIs

Those belong in the separate state schema and interface spec.

## 13.2 Required next technical spec
A contract-facing technical spec should define:
- enums
- packed structs
- raw stored state vs derived state getters
- write entrypoints
- events
- status / error codes
- settlement semantics and invariants
- worked timing examples

## 13.3 Important implementation invariants
The following invariants must hold:
- a clansman can have at most one active mission
- a dead clansman cannot receive orders
- only vault resources count for upkeep and building
- bandits cannot spawn in Unicorn Town or Deep Sea
- at most one bandit troop is active at once
- `mission.startTick <= currentTick`
- immediate market actions require the worker to be in Unicorn Town and `WAITING`
- scheduled market actions are never lazily resolved; they resolve eagerly at the heartbeat that closes their action tick
- `defend_base` persists until interrupted or death

---

# 14. Locked vs. Tunable Summary

## 14.1 Locked mechanics for v1
- 8-region canonical world
- deterministic canonical routes
- open-tick / closing-heartbeat timing model
- event-driven eager settlement for world-contact events
- real-time 60 second clansman cooldown
- all missions use `(gotoRegion, doAction, optionalParams)`
- no auto-return
- persistent `defend_base`
- 18-decimal ERC20 resource accounting
- literal fractional iron yield
- vault-only survival and construction counting
- two wheat plots with harvest/regrow cycle
- starvation weakens but does not kill outside Winter
- scheduled vs immediate market execution split
- no slippage guard in v1
- deterministic visible mutable bandit targeting
- equal defender loot split by defender, not defense weight
- winter every 110 ticks for 10 ticks
- cold damage reset each winter
- wall-only structural degradation in v1
- level-10 monument cap
- fixed 360-tick season
- unrestricted direct whispers and strategic alignment updates in v1
- OTC trust is social, not escrowed
- dead clans are eliminated and remaining vault resources are burned

## 14.2 Explicitly tunable values
The following values are intentionally tunable without changing the core mechanics:
- exact canonical route table contents
- bandit attack tier schedule
- initial pool seeding ratios
- starter vault and gold amounts
- wheat harvest rate
- wall/base/monument resource costs
- bandit spawn probability ramp
- bandit reward magnitudes
- season reward pot percentages in later versions
