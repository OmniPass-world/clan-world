# ClanWorld Bridged Gold Token Migration Scoping Document

**Status**: Research & Planning  
**Date**: 2026-05-02  
**Scope**: Comprehensive analysis of replacing ClanWorld's current 18-decimal ERC-20 gold token with a Wormhole-bridged 9-decimal token from Solana.

---

## Executive Summary

ClanWorld currently mints its own gold token (`MinimalERC20`) with 18 decimals and grants the game engine mint authority to distribute starting balances and game-earned gold. The future state switches to a bridged gold token from Solana (via Wormhole NTT) using 9 decimals, with no mint authority in the game engine. The engine will either pull from a treasury multi-sig allowance (Option A) or distribute from an internal deposit pool (Option B).

This migration affects:
1. **Token definition**: currently hardcoded at 18 decimals; must switch to 9-decimal bridge token
2. **Mint authority**: currently in `ClanWorld.sol`; must be removed entirely
3. **Gold distribution architecture**: currently implicit (engine has mint); must become explicit (allowance pull or pool balance)
4. **All decimal-coupled constants, tests, and off-chain math**: 116+ instances of `1e18` across contracts and tests must be audited and adjusted

This document inventories the surface area, identifies migration risks, and proposes a safe execution sequence following the Diamond proxy completion.

---

## 1. Current Gold Token Surface Area

### 1.1 Token Definition

**File**: `/home/claude/code/omnipass-world/clan-world/packages/contracts/src/MinimalERC20.sol`  
**Lines**: 1-72

The current gold token is a minimal ERC-20 implementation:
- **Decimals**: Fixed at 18 (line 8: `uint8 public constant decimals = 18;`)
- **Mint authority**: Single `_mint` function (lines 45-49) callable only via `seedTreasury` once per deployment (lines 37-43)
- **Key properties**:
  - One-time seed: `require(!treasurySeeded, "MinimalERC20: treasury seeded")` prevents re-minting
  - Basic ERC20 transfers: no additional features
  - No burning, pausing, or upgradeable logic

**Mint flow**:
```
MinimalERC20.seedTreasury(treasury, amount)
  → _mint(treasury, amount)
  → totalSupply += amount
  → emit Transfer(address(0), treasury, amount)
```

### 1.2 Game Engine Mint Authority & Distribution

**Primary mint sites**:

1. **Clan spawning** (starter gold):
   - `ClanWorld.sol:3215` → `clan.goldBalance = 3e18;` (direct assignment)
   - `ClanWorldStub.sol:121` → `clan.goldBalance = 3e18;`
   - `ClanLifecycleFacet.sol:40` → `clan.goldBalance = 3e18;`
   - **No ERC-20 transfer**: these are internal accounting assignments, not token transfers

2. **Bandit defeat rewards**:
   - `LibBanditCombat.sol:152` → `targetClan.goldBalance += 1e18;`
   - `ClanWorld.sol:2321` → `targetClan.goldBalance += 1e18;`

3. **Defender loot distribution**:
   - `LibBanditCombat.sol:381` → `s.clans[clanId].goldBalance += perGold;`
   - `ClanWorld.sol:2378` → `_clans[clanId].goldBalance += perGold;`

4. **Iron mining gold bonus** (2% of iron mined):
   - `LibSettlement.sol:474` → `sim.clan.goldBalance += ClanWorldConstants.GOLD_FROM_IRON_AMOUNT;` (1e18 flat)
   - `ClanWorld.sol:1618` → Same

5. **Market trades**:
   - `LibOrderMarket.sol:231, 372` → `clan.goldBalance += goldOut;` (selling resources for gold)
   - `ClanWorld.sol:4062, 4210` → Same

**Key insight**: The game engine never calls `MinimalERC20.transfer()` or `transferFrom()`. All "gold minting" is direct balance sheet manipulation on the `Clan` struct. Gold is **internal game accounting**, not backed by ERC-20 token transfers until pools are seeded.

### 1.3 Gold Token Registration in Treasury

**Files**:
- `ClanWorld.sol:4754` → `_treasury.goldToken = tokens[4];`
- `ClanWorldStub.sol:65` → `_treasury.goldToken = tokens[4];`
- `TreasuryFacet.sol:27` → `s.treasury.goldToken = tokens[4];`

The gold token address is stored but only used for:
1. Pool seeding (via `seedPools`): `_transferSeed(goldToken, pool, goldAmount)`
2. Validation: checking if a token is gold in market logic

### 1.4 Pool Seeding with Gold

**Files**:
- `ClanWorld.sol:4768-4779`
- `TreasuryFacet.sol:36-61` (Diamond version)

Pool seeding transfers ERC-20 gold from a treasury holding account to liquidity pools:
```solidity
_transferSeed(address token, address pool, uint256 amount) {
  require(MinimalERC20(token).transferFrom(msg.sender, pool, amount), "seed transfer failed");
}
```

**Gold pool seeds** (defined as public constants in `ClanWorld.sol:213-216`):
```
INITIAL_GOLD_SEED_FOR_WOOD = 500e18
INITIAL_GOLD_SEED_FOR_WHEAT = 700e18
INITIAL_GOLD_SEED_FOR_FISH = 600e18
INITIAL_GOLD_SEED_FOR_IRON = 400e18
```

**Total ERC-20 gold needed on deployment**: 2200e18 (2200 gold units in 18-decimal)

### 1.5 Gold in Market Pricing

**Decimal-coupled pricing formula**:

Files:
- `ClanWorld.sol:5597` → `pr.spotPriceGoldPerResource = rA > 0 ? (rB * 1e18) / rA : 0;`
- `MarketViewsFacet.sol:30` → Same
- `ClanWorldLens.sol:251` → Same

**Formula**: `spotPrice = (goldReserve * 1e18) / resourceReserve`

This multiplies by 1e18 to preserve precision when dividing. If gold becomes 9 decimals instead of 18, the divisor changes and prices scale by 1e9.

### 1.6 Burning/Removal

**No gold burning in current contracts**. The `LootDistributed` event logs a `burnedGold` field (lines 59 in `LibBanditCombat.sol`), but it's an event-only record of loot rounding/waste—no actual token burning.

---

## 2. Decimal-Coupled Code: 18 → 9 Migration

### 2.1 Literal Constants in Contracts (20 instances found)

**File: `/home/claude/code/omnipass-world/clan-world/packages/contracts/src/ClanWorld.sol`**
| Line | Constant | Context |
|------|----------|---------|
| 151 | `RESOURCE_UNIT = 1e18` | Generic resource unit for carry caps, etc. |
| 152 | `BLUEPRINT_UNIT = 1e18` | Blueprint denomination |
| 2321 | `targetClan.goldBalance += 1e18;` | Bandit defeat gold reward |
| 2924 | `weights[clan.baseRegion - 1] += 100 + (_lootValueRaw(clan) / 1e18);` | Bandit spawn weighting by loot value |
| 5124 | `return (200e18, 25e18, 100e18, 1e18);` | Monument upgrade cost (wood, iron, wheat, blueprints) at level 6+ |
| 5597 | `(rB * 1e18) / rA` | Market price calculation |

**File: `/home/claude/code/omnipass-world/clan-world/packages/contracts/src/ClanWorldStub.sol`**
| Line | Constant | Context |
|------|----------|---------|
| 121-124 | `clan.goldBalance = 3e18; vaultWood = 20e18; vaultWheat = 20e18; vaultFish = 2e18;` | Starter balances |
| 357-391 | Multiple `e18` literals | Upgrade costs (wood, iron, wheat) |

**File: `/home/claude/code/omnipass-world/clan-world/packages/contracts/src/IClanWorld.sol`**
| Line | Constant | Context |
|------|----------|---------|
| 45-49 | `CLANSMAN_CARRY_CAP = 10e18; WOOD_CAP = 15e18; IRON_CAP = 5e18; WHEAT_CAP = 40e18; FISH_CAP = 8e18;` | Per-clansman carry limits |
| 52 | `WOOD_YIELD_PER_TICK = 1e18` | Wood gathering yield |
| 59-62 | `IRON_BASE_YIELD = 5e17; IRON_YIELD_PER_TICK = 1.25e17; GOLD_FROM_IRON_AMOUNT = 1e18;` | Iron mining and gold bonus |
| 64-65 | `WHEAT_YIELD_PER_TICK = 5e18; FISH_YIELD_PER_TICK = 25e16;` | Wheat and fish yields |
| 71-74 | `WHEAT_UPKEEP_PER_CLANSMAN = 1e18; FISH_UPKEEP_PER_CLANSMAN = 1e17; WINTER_WOOD_BURN_PER_BASE = 1e18;` | Upkeep and burn rates |
| 81 | `WHEAT_PLOT_STARTING_WHEAT = 100e18;` | Wheat plot initialization |

**File: `/home/claude/code/omnipass-world/clan-world/packages/contracts/src/diamond/lib/LibBanditCombat.sol`**
| Line | Constant | Context |
|------|----------|---------|
| 21-22 | `RESOURCE_UNIT = 1e18; BLUEPRINT_UNIT = 1e18;` | Resource/blueprint denominations |
| 152 | `targetClan.goldBalance += 1e18;` | Bandit defeat reward |

**File: `/home/claude/code/omnipass-world/clan-world/packages/contracts/src/diamond/lib/LibBanditSpawning.sol`**
| Line | Constant | Context |
|------|----------|---------|
| 117 | `weights[clan.baseRegion - 1] += 100 + (LibScoring.lootValue(clan) / 1e18);` | Spawn weighting |

**File: `/home/claude/code/omnipass-world/clan-world/packages/contracts/src/diamond/lib/LibGameRules.sol`**
| Line | Constant | Context |
|------|----------|---------|
| 49 | `return (200e18, 25e18, 100e18, 1e18);` | Monument upgrade cost at level 6+ |

**File: `/home/claude/code/omnipass-world/clan-world/packages/contracts/src/diamond/facets/MarketViewsFacet.sol`**
| Line | Constant | Context |
|------|----------|---------|
| 30 | `(rB * 1e18) / rA` | Market price calculation |

### 2.2 Test Files: Decimal-Coupled Amounts (116 instances in .t.sol files)

**Example from `DirectTransfers.t.sol`** (50+ lines with `1e18`):
```solidity
Line 120:  uint256 amount = 1e18;
Line 137:  world.transferGold(clan1, clan2, 1e18);
Line 194:  assertEq(world.getClan(clan1).goldBalance, from0 - 1e18, "gold debited");
Line 195:  assertEq(world.getClan(clan2).goldBalance, to0 + 1e18, "gold credited");
```

**All test files with 1e18 uses**:
- `DirectTransfers.t.sol` (50+ instances)
- `BanditDefeatGoldReward.t.sol` (1 instance)
- Other test files (estimated 65+ more instances)

**Scope**: Every test fixture, assertion, and gold transfer uses e18 units. A bulk constant renaming helper (e.g., `GOLD_UNIT = 1e18` → `1e9`) will be needed.

### 2.3 Off-Chain Code: Convex/Server Side (from `apps/server/convex/indexer.ts`)

**File**: `/home/claude/code/omnipass-world/clan-world/apps/server/convex/indexer.ts:159`

```typescript
const price =
  resourceAmount > 0n
    ? ((goldAmount * 1_000_000_000_000_000_000n) / resourceAmount).toString()
    : "0";
```

This hardcoded `1_000_000_000_000_000_000n` (equivalent to `1e18`) is used to scale the price calculation when indexing market events. If gold becomes 9 decimals, this needs adjustment.

**Impact**: Prices indexed off-chain will be wrong if this scaling factor isn't updated.

### 2.4 Oracle Price Feeds & Conversion Layers

**Current status**: No oracle integration found. Prices are purely AMM-based (reserve calculations). Conversion logic is internal to the game.

---

## 3. Mint-vs-Distribute Architecture Change

### 3.1 Current Flow: Token Minting (ERC-20 Level)

```
Deploy sequence:
  1. Deploy MinimalERC20("Gold", "GOLD")
  2. Call seedTreasury(treasuryAddress, 2200e18)
     → MinimalERC20._mint(treasuryAddress, 2200e18)
     → totalSupply = 2200e18
  3. Treasury approves ClanWorld for pool seeding
  4. ClanWorld.seedPools calls transferFrom(treasury, pools, amounts)
```

**Game-level changes (NOT ERC-20 transfers)**:
- Starter gold: `clan.goldBalance = 3e18`
- Earned gold: `clan.goldBalance += 1e18`

**No burning or removal**: `totalSupply` never changes after seeding.

### 3.2 Migration Option A: Allowance Pull (Recommended for simplicity)

**Architecture**:
```
Pre-migration:
  Treasury holds X gold (via bridged token)
  Treasury.approve(ClanWorld, X)
  
Game logic (unchanged):
  clan.goldBalance is still internal accounting
  When minting was needed (currently no-op):
    → instead: pull from treasury via transferFrom
  
Pre-game start:
  ClanWorld._depositGoldFromTreasury(amount, treasury)
    → requires: treasury has approved ClanWorld for >= amount
    → clanWorld.transferFrom(treasury, clanWorld, amount)
    → _internalGoldPool += amount
    
On player earning gold:
  clan.goldBalance += amount  (unchanged)
  
On seasonal finalization / settlement:
  → reconcile internal pool vs claimed gold (future work)
```

**Pros**:
- Minimal contract changes
- No deposit/withdrawal complexity
- Game internal accounting remains untouched
- Errors cap at treasury allowance, not contract balance

**Cons**:
- Requires treasury multi-sig to grant and maintain allowance
- Treasury multi-sig drains if a bug exists in the game engine

### 3.3 Migration Option B: Direct Pool Deposit

**Architecture**:
```
Pre-migration:
  Treasury deposits X gold into ClanWorld contract
  ClanWorld._internalGoldPool = X
  
Game logic (unchanged):
  clan.goldBalance is still internal accounting
  No special mining logic needed
  
On player earning gold (unchanged):
  clan.goldBalance += amount
  
Settlement / redeem:
  players redeem goldBalance against _internalGoldPool
  (future mechanism)
```

**Pros**:
- No multi-sig coordination needed
- Simpler to reason about (pool balance = max game supply)
- No allowance bugs

**Cons**:
- More complex redemption flow later
- Contract owns significant funds
- Requires new deposit/withdraw mechanics

### 3.4 All Mint Call Sites (None in current game engine)

Searched for `mint`, `_mint`, `mintTo` across all `.sol` files:

**Results**:
- `MinimalERC20._mint` (line 45): Internal, called only by `seedTreasury`
- `IClanWorld.mintClan` (line interface): Mints NFT (iftTokenId), NOT ERC-20
- `ClanLifecycleFacet.mintClan`: Same NFT minting

**Finding**: The game engine **never mints ERC-20 tokens**. All "gold earning" is direct struct assignment. No mint sites to refactor.

### 3.5 Burn Sites (None found)

The `LootDistributedEvent` includes a `burnedGold` field but logs rounded-off loot amounts, not actual token burns. No contract code burns gold.

---

## 4. Wormhole Bridge Specifics

### 4.1 Bridge Token Characteristics

Per `docs/planning/gold-bridge-readiness-plan.md` (Phase 3 & 4):

**Bridge Token** (`GoldBridgeToken` on Base Sepolia):
- **Address (proxy)**: `0xF6F49EAf9EA71e69450191aFe22EFaed8E2f7995`
- **Decimals**: 9 (immutable post-deployment)
- **Mint/Burn**: Controlled by Wormhole NTT manager after deployment
- **Features**: Standard ERC20 + NTT mint/burn + allowlist-scoped recovery hook (V1)
- **Proxy**: Transparent upgradeable (OpenZeppelin) with timelock delay
- **Minter Handoff**: Via timelock schedule → execute after delay

**Wormhole NTT Configuration**:
- **Solana side**: Locking mode (canonical asset locked, wrapped on Base)
- **Base side**: Burning mode (receives wrapped tokens, burns on redeem to Solana)
- **Rate limits**: Testnet configured conservatively (100 GOLD per direction)

### 4.2 Bridge Integration: Key Assumptions

1. **Token is ERC-20 compatible**: Has `decimals()`, `balanceOf()`, `approve()`, `transferFrom()`
2. **ClanWorld uses as black box**: No special bridge interaction needed for game operations
3. **Mint authority is in bridge**: Game engine cannot and should not mint
4. **Supply is finite**: Bridged supply determined by Solana side + bridge mint curve

### 4.3 Cross-Chain Replay & Finality Risks

**Risk**: Bridge tx may appear on Base before Solana confirms. Game indexer may see different states on Base vs Solana.

**Mitigation**:
- Off-chain indexer should wait for confirmations (already uses 5-block depth)
- Pool reserves are independent (set at game start, not synced from bridge)
- Player bridged-GOLD deposits/withdraws are future work (not in scope for this migration)

### 4.4 Bridge Pause / Upgrade Risk

**Current**: No pausing logic in the game. If bridge pauses, players cannot redeem bridged GOLD back to Solana (future concern).

**For this migration**: Accept risk. Game only uses pool liquidity and treasury holds; player redemption is future scope.

---

## 5. Risks & Implications

### 5.1 Supply Exhaustion (Option B)

**Risk**: If engine has fixed internal pool and game awards gold faster than anticipated, pool empties.

**Mitigation**:
- Size initial deposit conservatively (stress-test estimated earn rates)
- Add monitoring: track `_internalGoldPool` vs total clan `goldBalance`
- Implement graceful degradation: disable mining if pool < threshold
- OR: Use Option A (allowance) and allow treasury to add funds dynamically

### 5.2 Decimal Precision Loss: 18 → 9

**Current**: Smallest unit = 1e-18 (1 wei)
**Bridge**: Smallest unit = 1e-9 (1 nanogold)

**Example**: A formula computing `(goldAmount * 1e18) / resourceReserve`:
- With 18-decimal gold: Result keeps full precision for prices
- With 9-decimal gold: Multiplication is now `(goldAmount * 1e9) / resourceReserve`, losing precision

**Affected calculations**:
- Market price scaling (line 5597, 251)
- Loot weighting division (line 2924)
- Any sub-wei rounding assumptions

**Mitigation**:
- Audit all division operations
- Adjust multiplier: keep same precision or accept new bounds
- Test prices with realistic pool reserves in 9-decimal units

### 5.3 Test Rebalancing

**Current test data**:
- Starter gold: `3e18` (3 gold)
- Bandit rewards: `1e18` (1 gold)
- Pool seeds: `500e18`, `700e18`, etc. (hundreds of gold units)

**With 9 decimals**: These become `3e9`, `1e9`, `500e9` in the token, but game internal accounting can stay the same IF we introduce a decimal boundary.

**Two strategies**:

1. **Normalize tests to 9e-decimal units** (native):
   - All test amounts use e9 instead of e18
   - Feels unnatural to test code written for e18 thinking
   - Harder to reason about economic balance

2. **Convert at boundary, keep internal accounting in e18** (wrapper):
   - Internal game logic still uses e18 (simplest refactor)
   - Bridge token is e9; conversion happens in deposit/withdrawal only
   - Easier to test (no widespread constant changes)
   - BUT: requires a deliberate boundary and conversion logic

**Recommendation**: Use strategy 2—keep internal accounting unchanged, add 9e→18e conversion at the treasury/pool interface. This minimizes test rewrites and keeps game logic isolated from token decimals.

### 5.4 Off-Chain Indexer Desync

**Convex indexer** (`indexer.ts:159`) hardcodes `1e18` for price scaling. If not updated:
- Prices indexed will be off by 1e9
- Market history will show incorrect historical prices

**Mitigation**: Update the constant before deploying bridged gold.

### 5.5 Treasury Safety

**Option A risk**: A contract bug that calls `transferFrom(treasury, arbitrary_recipient, balance)` drains the entire approved allowance.

**Option B risk**: A contract bug that calls `transfer(arbitrary_recipient, internalBalance)` drains the game's internal pool.

**Mitigations**:
- Thorough audit of transferFrom/transfer call sites before merging
- Limit initial treasury allowance (Option A) to ~1 season's expected gold movement
- Add access controls to prevent unauthorized calls
- Consider role-based transfer logic (e.g., only specific facets can pull gold)

### 5.6 Wormhole Upgrade Risk

**Risk**: Wormhole NTT manager could be upgraded, changing minting behavior. If ClanWorld depends on a specific token behavior and it changes, game breaks.

**Mitigation**: Treat bridge token as a black box ERC-20. Don't depend on bridge-internal mechanisms (just mint/burn interfaces). Game engine only interacts with allowance/transferFrom.

---

## 6. Recommended Migration Sequence

### 6.1 Prerequisite: Diamond Proxy Merge

**Wait for**: PR merging Diamond proxy changes into main. Current state is two parallel implementations (old `ClanWorld.sol` and new diamond facets). Migration should target **single canonical implementation**.

**Actions**:
1. Complete and merge Diamond proxy feature branch
2. Verify all tests pass with Diamond implementation
3. Ensure `IClanWorld` interface is the single source of truth

### 6.2 Phase 1: Contract Surface Cleanup (1-2 days)

**Goal**: Introduce explicit gold distribution boundary, remove any implicit minting.

**Changes**:

1. **Add gold deposit/accounting to Diamond**:
   - Add `_internalGoldPool` (uint256) to `LibStorage.AppStorage`
   - Add `depositGoldFromTreasury(address treasury, uint256 amount)` facet method (Option A/B compatible)
   - Add guard: require `treasury != address(0)`, `amount > 0`

2. **Remove reliance on MinimalERC20 minting**:
   - `seedPools` still works the same way (calls `transferFrom` on gold token)
   - Internal gold earning stays the same (no ERC20 calls)
   - Do NOT call MinimalERC20.seedTreasury in new deploy flow

3. **Add integration tests** (new file):
   - Test `depositGoldFromTreasury` with a mock ERC20
   - Test pool seeding with external ERC20 address
   - Test that game logic doesn't break with no `MinimalERC20` deployed

**Files modified**:
- `packages/contracts/src/diamond/lib/LibStorage.sol`: Add `_internalGoldPool`
- `packages/contracts/src/diamond/facets/TreasuryFacet.sol`: Add `depositGoldFromTreasury`
- `packages/contracts/test/ExternalGoldIntegration.t.sol`: New test file
- Deployment script (future): Skip MinimalERC20 deployment

### 6.3 Phase 2: Decimal Boundary Definition (1 day)

**Goal**: Define the conversion boundary and where decimals matter.

**Decision needed** (from this scoping):

> **Recommendation**: Keep internal game accounting at e18, add conversion boundary at treasury/ERC20 interface.

**Rationale**:
- Minimizes code churn across libraries/facets
- Tests remain readable (can reuse e18 values)
- Clear separation: game engine (e18) ↔ ERC20 token (e9)

**Conversion logic**:
```solidity
// In TreasuryFacet or dedicated library
function _depositGoldFromERC20(address goldToken, uint256 amount) internal {
  // amount is in ERC20 units (e9)
  // convert to internal units (e18)
  uint8 erc20Decimals = ERC20(goldToken).decimals();
  if (erc20Decimals == 9) {
    // Scale up: 1e9 → 1e18 by multiplying by 1e9
    uint256 internalAmount = amount * 10 ** (18 - 9);
    _internalGoldPool += internalAmount;
  } else if (erc20Decimals == 18) {
    // No conversion needed
    _internalGoldPool += amount;
  } else {
    revert("Unsupported gold token decimals");
  }
}
```

**Tests**:
- Test deposit with 9-decimal token
- Test deposit with 18-decimal token (backward compat for existing deployments)
- Verify internal accounting is in e18 regardless

### 6.4 Phase 3: Test Refactoring (2-3 days)

**Goal**: Update all test fixtures and assertions to work with the boundary.

**Strategy** (Option 1 - Minimal):
1. Add helper constants at the top of each test file:
   ```solidity
   uint256 constant GOLD_UNIT = 1e18; // internal units
   uint256 constant ERC20_GOLD_UNIT = 1e9; // bridge token units (for integration tests only)
   ```
2. Replace `1e18` with `GOLD_UNIT` in existing tests (mechanical change)
3. Add a few new tests that mix ERC20 and internal units to verify conversion

**Files affected**:
- All `.t.sol` files: Replace `1e18` with `GOLD_UNIT` constant (regex bulk change possible)
- Add new file `ExternalGoldIntegration.t.sol` with bridge-token-specific tests

**Verification**:
- Run full test suite after bulk replacements
- Ensure no test logic changes, only constant name changes

### 6.5 Phase 4: Deployment Script Update (1 day)

**Goal**: Support deploying with either local mock GOLD or external bridged GOLD.

**Changes to `packages/contracts/script/Deploy.s.sol`**:

1. Add env var check:
   ```solidity
   address goldToken;
   if (bytes(vm.envString("BRIDGED_GOLD_TOKEN_ADDRESS")).length > 0) {
     goldToken = vm.envAddress("BRIDGED_GOLD_TOKEN_ADDRESS");
     // Verify it's an ERC20 with decimals() == 9
     require(IERC20Extended(goldToken).decimals() == 9, "Gold must be 9 decimals");
   } else {
     // Deploy local MinimalERC20 as before
     MinimalERC20 gold = new MinimalERC20("Gold", "GOLD");
     gold.seedTreasury(treasury, 2200e18);
     goldToken = address(gold);
   }
   ```

2. Pass `goldToken` to `initTreasury` (unchanged)

3. Deployment sequence depends on which path:
   - **Local mode**: Deploy MinimalERC20, seed, approve, seedPools
   - **Bridge mode**: Treasury must already hold bridged GOLD and approve ClanWorld

**Tests**:
- Deployment with `BRIDGED_GOLD_TOKEN_ADDRESS` set
- Deployment with env var unset (local MinimalERC20 path)
- Both paths produce valid `ClanWorld` ready to play

### 6.6 Phase 5: Bridge Token Swap Integration (1 week)

**Goal**: Deploy to Base Sepolia with actual bridged GOLD.

**Prerequisites**:
- Bridge is deployed and tested (already done per `gold-bridge-readiness-plan.md`)
- Bridge token address is known
- Treasury account holds bridged GOLD

**Process**:
1. **Pre-deployment**:
   - Bridge GOLD from Solana to Base Sepolia
   - Confirm treasury account has sufficient balance for pool seeding
   - Grant ClanWorld approval: `bridgedGold.approve(clanWorld, seedAmount)`

2. **Deployment**:
   ```bash
   export BRIDGED_GOLD_TOKEN_ADDRESS="0xF6F49EAf9EA71e69450191aFe22EFaed8E2f7995"
   forge script packages/contracts/script/Deploy.s.sol:DeployScript --rpc-url base-sepolia
   ```

3. **Validation**:
   - Verify pool reserves are in bridge token (9-decimal) format
   - Verify internal clan gold balances are still e18
   - Test market operations: sell resource for gold, verify pool changes
   - Spot-check prices are reasonable (adjusted for 9-decimal base)

4. **Smoke test**:
   - Mint a clan, verify starter gold is correct (3e18 internal)
   - Perform a market trade, verify gold balance changes (internally still e18)
   - Verify pool reserves updated correctly (in 9-decimal token units)

### 6.7 Phase 6: Off-Chain Integration (1-2 days)

**Goal**: Update Convex indexer and frontend to handle 9-decimal GOLD.

**Changes**:

1. **Convex indexer** (`apps/server/convex/indexer.ts:159`):
   ```typescript
   // OLD: ((goldAmount * 1_000_000_000_000_000_000n) / resourceAmount)
   
   // NEW: Query gold token decimals at indexing time
   const goldDecimals = await getGoldTokenDecimals(); // 9 or 18
   const scalingFactor = 10n ** BigInt(18 - goldDecimals); // e9 if gold is 9-decimal
   const price = ((goldAmount * scalingFactor) / resourceAmount).toString();
   ```

2. **Frontend display** (`apps/web/src/...`):
   - Gold balances are still internal (no change)
   - Pool reserves should reflect actual token decimals (minor formatting)

**Testing**:
- Index historical market events with 9-decimal gold
- Verify prices match on-chain spot prices

### 6.8 Phase 7: Ops & Documentation (ongoing)

**Goal**: Codify the new deployment path and risks.

**Deliverables**:
1. **Migration checklist** (ops runbook):
   - Pre-bridge: confirm Solana GOLD decimals, bridge deployment
   - Deploy: ClanWorld with BRIDGED_GOLD_TOKEN_ADDRESS
   - Validate: pool reserves, internal accounting, prices
   - Sign-off: game is live with bridged GOLD

2. **Monitoring**:
   - Alert if `_internalGoldPool` < threshold
   - Alert on bridge pause/upgrade events
   - Off-chain indexer price sanity checks

3. **Recovery**:
   - If pool depletes: pause mining, redeploy with larger deposit
   - If bridge breaks: fallback plan to local MinimalERC20 (requires new deployment)

---

## 7. Detailed File List: All Decimal References

### Contracts (Production)

| File | Lines | Change | Notes |
|------|-------|--------|-------|
| MinimalERC20.sol | 8 | KEEP at 18 | Legacy local token only, bridge uses 9 |
| IClanWorld.sol | 45-81 | Audit & DOCUMENT | All resource constants; game accounting, not ERC20 |
| ClanWorld.sol | 151-152, 213-216 | KEEP (internal) | Game unit constants, not ERC20 |
| ClanWorld.sol | 2321, 2924, 5124, 5597 | AUDIT | Market logic, verify precision loss acceptable |
| ClanWorldStub.sol | 121-124, 357-391 | UPDATE for bridge | Stub uses e18; update to match real constants |
| diamond/lib/LibBanditCombat.sol | 21-22, 152 | AUDIT | Game unit, internal accounting |
| diamond/lib/LibBanditSpawning.sol | 117 | AUDIT | Loot weighting division |
| diamond/lib/LibGameRules.sol | 49 | AUDIT | Upgrade costs |
| diamond/facets/MarketViewsFacet.sol | 30 | AUDIT | Price precision |
| diamond/facets/ClanLifecycleFacet.sol | 40-43 | AUDIT | Starter gold (internal) |
| TreasuryFacet.sol | 36-61 | UPDATE | Add bridge token support, verify decimals |

**Total production files affected**: ~11

### Tests

| File | Count | Action |
|------|-------|--------|
| DirectTransfers.t.sol | 50+ | Replace `1e18` → `GOLD_UNIT` constant |
| BanditDefeatGoldReward.t.sol | 2 | Replace `1e18` → `GOLD_UNIT` |
| *.t.sol (other) | 60+ | Bulk replace via regex |
| ExternalGoldIntegration.t.sol | NEW | Add bridge-token-specific tests |

**Total test lines to update**: ~116

### Off-Chain

| File | Lines | Change |
|------|-------|--------|
| apps/server/convex/indexer.ts | 159 | Update scaling factor from 1e18 to 1e9 |
| apps/web/src/... | TBD | Minor: format gold balances & prices |

---

## 8. Risks Summary

| Risk | Severity | Mitigation |
|------|----------|-----------|
| **Decimal precision loss in prices** | Medium | Audit all division ops, test with realistic reserves |
| **Indexer price desync** | Medium | Update off-chain scaling factor before deploy |
| **Supply exhaustion (Option B)** | Medium | Stress-test earn rates, add monitoring |
| **Treasury drains (Option A)** | Low | Audit transferFrom sites, limit allowance |
| **Test suite regression** | Low | Bulk constant rename + careful verification |
| **Bridge pause/upgrade** | Low | Accept for now; future mitigation TBD |

---

## 9. Recommendations Summary

1. **Use Option A (Allowance Pull)** for simplicity and contract safety. Requires better treasury multi-sig ops than Option B, but avoids holding large gold balance in the engine contract.

2. **Keep internal game accounting at 1e18**. Add a conversion boundary at the ERC-20 interface. This minimizes churn across the codebase and keeps tests readable.

3. **Defer full bridge integration** until after Diamond proxy merge. Work is blocked on `IClanWorld` stability.

4. **Prioritize Phase 1-2** (contract cleanup + decimal boundary). These unblock downstream work and are low-risk.

5. **Test aggressively in Phase 5**. Swap-out a token with different decimals is high-risk; run extended smoke tests and price sanity checks before go-live.

6. **Update off-chain code (Phase 6)** before bridged GOLD goes live. Prices indexed with wrong scaling are hard to fix retrospectively.

7. **Establish clear handoff to Ops** (Phase 7). New migration checklist, monitoring, and recovery runbooks must be in place before production deployment.

---

## 10. Open Questions

- What is the canonical Solana GOLD mint and its exact decimals?
- Do we redeploy ClanWorld or design an in-situ migration for existing deployments?
- Should clan gold balances become player-depositable/withdrawable in the future, or remain internal game accounting?
- Who owns the production NTT manager and timelock?
- What's the production timelock delay: 24h, 48h, or longer?
- Should we implement supply exhaustion guards (mining pause, throttling) before go-live?

---

## Appendix: Constant Reference

### Game Unit Constants (Internal Accounting, e18)
```solidity
RESOURCE_UNIT = 1e18              // Generic resource base unit
BLUEPRINT_UNIT = 1e18             // Blueprint denomination
GOLD_FROM_IRON_AMOUNT = 1e18      // Iron bonus (flat)
STARTER_GOLD = 3e18               // New clan starting gold
BANDIT_DEFEAT_REWARD = 1e18       // Gold reward
```

### Pool Seeds (ERC-20 gold, will be 9 decimals on bridge)
```solidity
INITIAL_GOLD_SEED_FOR_WOOD = 500e18     (becomes 500e9 with bridge)
INITIAL_GOLD_SEED_FOR_WHEAT = 700e18   (becomes 700e9 with bridge)
INITIAL_GOLD_SEED_FOR_FISH = 600e18    (becomes 600e9 with bridge)
INITIAL_GOLD_SEED_FOR_IRON = 400e18    (becomes 400e9 with bridge)
```

### Carry Caps & Yields (e18, internal)
```solidity
WOOD_CAP = 15e18
IRON_CAP = 5e18
WHEAT_CAP = 40e18
FISH_CAP = 8e18
WOOD_YIELD_PER_TICK = 1e18
WHEAT_YIELD_PER_TICK = 5e18
FISH_YIELD_PER_TICK = 25e16
```

---

**End of Scoping Document**

