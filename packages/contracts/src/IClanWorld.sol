// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IClanWorld
 * @notice Canonical seam interface for the ClanWorld v4 hackathon build.
 *
 * Synthesized from:
 *   - clanworld_v4_spec.md (mechanics)
 *   - clanworld_v4_1_addendum.md (locked clarifications)
 *   - clanworld_v4_2_state_schema_interface_spec.md (state schema)
 *   - clanworld_v4_3_schema_patch.md (final lockdowns)
 *   - clanworld_v4_4_ui_indexer_getters.md (UI convenience aggregators)
 *
 * This is the contract surface every other workstream depends on.
 * Treat field names, event names, struct layouts, and enum order as STABLE.
 *
 * Implementation lives behind this interface. Mocks and indexer types are
 * derived from it. Do not change without coordinating with all streams.
 */

// =============================================================================
// CONSTANTS
// =============================================================================

library ClanWorldConstants {
    // World cadence
    uint64 internal constant HEARTBEAT_INTERVAL_SECONDS = 60;
    uint64 internal constant TICKS_PER_WINTER_CYCLE = 110;
    uint64 internal constant WINTER_DURATION_TICKS = 10;
    uint64 internal constant SEASON_DURATION_TICKS = 360;

    // Bandit cadence
    uint64 internal constant BANDIT_COOLDOWN_TICKS = 10;
    uint64 internal constant BANDIT_CAMP_TICKS = 3;
    uint64 internal constant BANDIT_REST_TICKS = 2;
    uint8  internal constant BANDIT_MAX_ATTACK_ATTEMPTS = 6;

    // Clansman cadence
    uint64 internal constant CLANSMAN_COOLDOWN_SECONDS = 60;

    // Carry caps (per clansman)
    uint256 internal constant WOOD_CAP  = 15e18;
    uint256 internal constant IRON_CAP  = 5e18;
    uint256 internal constant WHEAT_CAP = 40e18;
    uint256 internal constant FISH_CAP  = 8e18;

    // Gathering yields
    uint256 internal constant WOOD_BASE_YIELD = 2e18;
    uint256 internal constant WOOD_CRIT_BONUS = 1e18;
    uint16  internal constant WOOD_CRIT_BPS = 2000;            // 20%

    uint256 internal constant IRON_BASE_YIELD = 5e17;          // 0.5e18
    uint16  internal constant GOLD_FROM_IRON_BPS = 200;        // 2%
    uint256 internal constant GOLD_FROM_IRON_AMOUNT = 1e18;

    uint16  internal constant FISH_DOCKS_BPS = 2500;           // 25%
    uint16  internal constant FISH_DEEP_BPS = 7500;            // 75%

    // Upkeep
    uint256 internal constant WHEAT_UPKEEP_PER_CLANSMAN = 1e18;
    uint256 internal constant FISH_UPKEEP_PER_CLANSMAN = 1e17; // 0.1
    uint256 internal constant WINTER_WOOD_BURN_PER_BASE = 1e18;
    uint16  internal constant WINTER_UPKEEP_MULTIPLIER_BPS = 20000; // 2x

    // Wheat plots
    uint64  internal constant WHEAT_PLOT_REGROW_TICKS = 4;
    uint256 internal constant WHEAT_PLOT_STARTING_WHEAT = 100e18;

    // Bandit combat
    uint16 internal constant BANDIT_BASE_STEAL_BPS = 2000;        // 20%
    uint16 internal constant BANDIT_DROP_TO_DEFENDERS_BPS = 5000; // 50%

    // Region IDs (1-indexed; 0 = NOOP / unset sentinel)
    uint8 internal constant REGION_NOOP          = 0;
    uint8 internal constant REGION_FOREST        = 1;
    uint8 internal constant REGION_MOUNTAINS     = 2;
    uint8 internal constant REGION_UNICORN_TOWN  = 3;
    uint8 internal constant REGION_WEST_FARMS    = 4;
    uint8 internal constant REGION_EAST_FARMS    = 5;
    uint8 internal constant REGION_WEST_DOCKS    = 6;
    uint8 internal constant REGION_EAST_DOCKS    = 7;
    uint8 internal constant REGION_DEEP_SEA      = 8;

    // Sentinels
    uint32 internal constant CLAN_ID_NULL = 0;     // valid clan IDs start at 1
    uint32 internal constant BANDIT_ID_NULL = 0;
}

// =============================================================================
// ENUMS
// =============================================================================

enum ClanState {
    ACTIVE,
    DEAD
}

enum ClansmanState {
    WAITING,
    TRAVELING,
    ACTING,
    DEAD
}

enum BanditState {
    NONE,
    CAMPING,
    RESTING,
    ATTACKING,
    DEFEATED,
    ESCAPED
}

enum WheatPlotState {
    Harvestable,
    Regrowing,
    WinterLocked
}

enum ResourceType {
    Wood,
    Iron,
    Wheat,
    Fish
}

enum ActionType {
    None,
    ChopWood,
    MineIron,
    FishDocks,
    FishDeepSea,
    HarvestWheat,
    DepositResources,
    BuildWall,
    UpgradeBase,
    UpgradeMonument,
    DefendBase,
    MarketBuy,
    MarketSell,
    Wait
}

enum MarketExecutionMode {
    None,
    Immediate,
    Scheduled
}

enum StatusCode {
    OK,
    ERR_CLAN_DEAD,
    ERR_CLAN_NOT_OWNED,
    ERR_CLANSMAN_DEAD,
    ERR_INVALID_CLANSMAN,
    ERR_INVALID_REGION,
    ERR_INVALID_ACTION,
    ERR_INVALID_TARGET,
    ERR_COOLDOWN_ACTIVE,
    ERR_NOT_WAITING,
    ERR_NOT_IN_UNICORN_TOWN,
    ERR_NOT_AT_HOMEBASE,
    ERR_NOT_AT_TARGET_BASE,
    ERR_NOT_DEFENDABLE,
    ERR_MISSING_RESOURCES,
    ERR_EMPTY_CARGO,
    ERR_PLOT_NOT_READY,
    ERR_PLOT_EMPTY,
    ERR_MARKET_ZERO_AMOUNT,
    ERR_MARKET_UNSUPPORTED_TOKEN,
    ERR_IMMEDIATE_MARKET_NOT_ELIGIBLE,
    ERR_MARKET_BUY_OVER_CAPACITY,
    ERR_MARKET_BUY_MAX_GOLD_EXCEEDED,
    ERR_WORLD_TICK_MISMATCH,
    ERR_NO_ACTIVE_BANDIT,
    ERR_SEASON_ENDED,
    ERR_NOT_ENOUGH_GOLD,
    ERR_CARRY_FULL
}

// =============================================================================
// CORE STATE STRUCTS (raw storage shape)
// =============================================================================

struct WorldState {
    uint64 currentTick;
    uint64 seasonStartTick;
    uint64 seasonEndTick;
    bool   seasonFinalized;

    uint64 nextHeartbeatAtTs;
    uint64 nextBanditSpawnEligibleTick;
    uint16 currentBanditSpawnChanceBps;
    bytes32 currentTickSeed;

    uint32 activeBanditId;       // 0 if none
    bool   winterActive;
    uint64 winterStartsAtTick;
    uint64 winterEndsAtTick;     // 0 if not active

    uint64 nextCommitSequence;   // global FIFO sequence for scheduled market actions
}

struct TreasuryState {
    address treasuryOwner;
    uint256 prizePotGold;

    bool poolsSeeded;

    address woodToken;
    address wheatToken;
    address fishToken;
    address ironToken;
    address goldToken;
    address blueprintToken;

    address woodGoldPool;
    address wheatGoldPool;
    address fishGoldPool;
    address ironGoldPool;
}

struct Clan {
    uint32 clanId;
    uint256 iftTokenId;
    address owner;
    ClanState clanState;

    uint8 baseRegion;
    uint8 baseLevel;
    uint8 wallLevel;
    uint8 monumentLevel;
    uint8 livingClansmen;

    uint64 lastSettledTick;
    uint64 starvationStartsAtTick; // 0 = none

    uint16 coldDamage;             // resets to 0 at winter end

    uint256 goldBalance;
    uint256 blueprintBalance;

    uint256 vaultWood;
    uint256 vaultIron;
    uint256 vaultWheat;
    uint256 vaultFish;
}

struct WheatPlot {
    WheatPlotState state;
    uint8 region;                  // West Farms or East Farms
    uint256 remainingWheat;
    uint64 regrowUntilTick;
}

struct Clansman {
    uint32 clansmanId;
    uint32 clanId;
    ClansmanState state;
    uint8 currentRegion;

    uint64 cooldownEndsAtTs;
    uint64 lastMissionNonce;

    uint256 carryWood;
    uint256 carryIron;
    uint256 carryWheat;
    uint256 carryFish;
}

struct Mission {
    bool active;

    uint64 nonce;
    uint32 clansmanId;

    uint8 startRegion;
    uint8 targetRegion;
    ActionType action;

    uint64 startTick;
    uint64 arrivalTick;
    uint64 actionStartTick;

    bytes32 missionSeed;
    MarketExecutionMode marketMode;

    uint32 targetClanId;   // DefendBase only
    address marketToken;   // market token for buy/sell
    uint256 marketAmount;  // exact-in for sell, exact-out for buy
    uint256 maxGoldIn;     // market_buy only, 0 otherwise
}

struct BanditTroop {
    uint32 banditId;
    BanditState state;

    uint8 currentRegion;
    uint8 attackAttemptsMade;
    uint64 stateEnteredTick;
    uint64 nextActionTick;

    uint8 tier;
    uint16 attackPower;            // derived from tier; tier is canonical (v4.3 §G)

    uint256 carryWood;
    uint256 carryIron;
    uint256 carryWheat;
    uint256 carryFish;
}

struct ScheduledMarketAction {
    uint64 executeAtTick;
    uint64 commitSequence;        // global monotonic FIFO order
    uint32 clanId;
    uint32 clansmanId;
    ActionType action;            // MarketBuy or MarketSell

    address marketToken;
    uint256 marketAmount;         // exact-in for sell, exact-out for buy
    uint256 maxGoldIn;            // buy only, 0 otherwise
}

struct DefenseContribution {
    uint32 clansmanId;
    uint32 clanId;
    uint16 defensePoints;
}

struct PackedRoute {
    uint8 travelTicks;
    bytes8 path;                  // ordered region ids, e.g. [6,4,3,2,0,0,0,0]
}

// =============================================================================
// DERIVED VIEW STRUCTS (read-only, settled forward to current tick)
// =============================================================================

struct DerivedClanState {
    Clan clan;                    // settled to current tick
    bool isStarving;
    uint256 lootValue;            // current weighted loot value
    uint64 derivedAtTick;
}

struct DerivedClansmanState {
    Clansman clansman;            // settled to current tick
    Mission activeMission;        // active=false if none
    uint8 effectiveRegion;        // for traveling, derived from route + elapsed ticks
    uint64 derivedAtTick;
}

// =============================================================================
// WRITE INPUT / OUTPUT STRUCTS
// =============================================================================

struct ClanOrder {
    uint32 clansmanId;
    uint8 gotoRegion;
    ActionType action;

    uint32 targetClanId;          // DefendBase only
    address marketToken;
    uint256 marketAmount;
    uint256 maxGoldIn;
}

struct OrderResult {
    uint32 clansmanId;
    StatusCode status;
    uint64 cooldownEndsAtTs;
    uint64 missionNonce;
}

struct PoolSeedConfig {
    uint256 woodSeed;
    uint256 wheatSeed;
    uint256 fishSeed;
    uint256 ironSeed;
    uint256 goldSeedForWood;
    uint256 goldSeedForWheat;
    uint256 goldSeedForFish;
    uint256 goldSeedForIron;
}

// =============================================================================
// UI INDEXER AGGREGATOR STRUCTS (v4.4 additions)
// =============================================================================

struct LeaderboardEntry {
    uint32 clanId;
    address owner;
    uint8 monumentLevel;
    uint8 baseLevel;
    uint8 wallLevel;
    uint8 livingClansmen;
    ClanState state;
    uint256 lootValue;            // settled
}

struct WorldSnapshot {
    uint64 currentTick;
    uint64 seasonStartTick;
    uint64 seasonEndTick;
    bool   seasonFinalized;
    bool   winterActive;
    uint64 winterStartsAtTick;
    uint64 winterEndsAtTick;
    uint32 activeBanditId;
    bytes32 currentTickSeed;

    LeaderboardEntry[] leaderboard;
}

struct ClansmanFullView {
    DerivedClansmanState clansman;
    Mission activeMission;
}

struct ClanFullView {
    DerivedClanState clan;
    ClansmanFullView[] clansmen;
    WheatPlot westPlot;
    WheatPlot eastPlot;
    uint32[] incomingDefenderIds;     // workers from other clans defending us
    uint32   thisClanDefendingBaseId; // 0 if none
}

struct PoolReserves {
    address resourceToken;
    uint256 resourceReserve;
    uint256 goldReserve;
    uint256 spotPriceGoldPerResource; // = goldReserve * 1e18 / resourceReserve, or 0
}

struct MarketState {
    PoolReserves wood;
    PoolReserves wheat;
    PoolReserves fish;
    PoolReserves iron;

    uint64 currentTick;
    ScheduledMarketAction[] currentTickQueue;
    ScheduledMarketAction[] nextTickQueue;
}

struct ActiveBanditView {
    bool   exists;
    uint32 banditId;
    BanditState state;
    uint8  currentRegion;
    uint8  attackAttemptsMade;
    uint8  maxAttemptsRemaining;
    uint64 stateEnteredTick;
    uint64 nextActionTick;
    uint8  tier;
    uint16 attackPower;

    uint256 carryWood;
    uint256 carryIron;
    uint256 carryWheat;
    uint256 carryFish;

    uint32 projectedTargetClanId;     // 0 if no eligible target in current region
    uint256 projectedTargetLootValue;
}

struct RegionOccupant {
    uint32 clansmanId;
    uint32 clanId;
    ClansmanState state;
    ActionType currentAction;
    uint64 missionNonce;
}

// =============================================================================
// EVENTS
// =============================================================================

interface IClanWorldEvents {
    // ----- world clock -----
    event TickAdvanced(uint64 closedTick, uint64 openedTick, bytes32 tickSeed);
    event WinterStarted(uint64 indexed tick);
    event WinterEnded(uint64 indexed tick);
    event SeasonFinalized(uint64 indexed tick, uint32[] rankedClanIds);

    // ----- clan lifecycle -----
    event ClanSpawned(
        uint32 indexed clanId,
        address indexed owner,
        uint256 iftTokenId,
        uint8 baseRegion,
        uint64 atTick
    );
    event ClanSettled(uint32 indexed clanId, uint64 settledToTick);
    event ClanEliminated(uint32 indexed clanId, uint64 indexed tick);
    event ClanStarvationChanged(uint32 indexed clanId, bool isStarving, uint64 atTick);

    // ----- missions -----
    event MissionAssigned(
        uint32 indexed clanId,
        uint32 indexed clansmanId,
        uint64 missionNonce,
        ActionType action,
        uint8 startRegion,
        uint8 targetRegion,
        uint64 startTick,
        uint64 arrivalTick
    );
    event MissionInterrupted(
        uint32 indexed clanId,
        uint32 indexed clansmanId,
        uint64 oldMissionNonce,
        uint64 newMissionNonce
    );
    event MissionCompleted(
        uint32 indexed clanId,
        uint32 indexed clansmanId,
        uint64 missionNonce,
        ActionType action
    );
    event WorkerArrived(
        uint32 indexed clanId,
        uint32 indexed clansmanId,
        uint8 region,
        uint64 tick
    );

    // ----- gathering / vault movement -----
    event ResourcesGathered(
        uint32 indexed clanId,
        uint32 indexed clansmanId,
        ActionType action,
        uint256 woodGained,
        uint256 ironGained,
        uint256 wheatGained,
        uint256 fishGained,
        uint256 goldBonus,
        uint64 atTick
    );
    event ResourcesDeposited(
        uint32 indexed clanId,
        uint32 indexed clansmanId,
        uint256 wood,
        uint256 iron,
        uint256 wheat,
        uint256 fish,
        uint64 atTick
    );

    // ----- building -----
    event WallLevelChanged(uint32 indexed clanId, uint8 oldLevel, uint8 newLevel, uint64 atTick);
    event BaseLevelChanged(uint32 indexed clanId, uint8 oldLevel, uint8 newLevel, uint64 atTick);
    event MonumentLevelChanged(uint32 indexed clanId, uint8 oldLevel, uint8 newLevel, uint64 atTick);

    // ----- market -----
    event ImmediateMarketActionExecuted(
        uint32 indexed clanId,
        uint32 indexed clansmanId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint64 atTick
    );
    event ScheduledMarketActionExecuted(
        uint64 indexed executeAtTick,
        uint64 indexed commitSequence,
        uint32 indexed clanId,
        uint32 clansmanId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    event ScheduledMarketActionCommitted(
        uint64 indexed executeAtTick,
        uint64 indexed commitSequence,
        uint32 indexed clanId,
        uint32 clansmanId,
        ActionType action,
        address marketToken,
        uint256 marketAmount,
        uint256 maxGoldIn
    );
    event MarketActionFailed(
        uint32 indexed clanId,
        uint32 indexed clansmanId,
        ActionType action,
        StatusCode reason
    );

    // ----- bandits -----
    event BanditSpawned(uint32 indexed banditId, uint8 region, uint8 tier, uint16 attackPower);
    event BanditStateChanged(
        uint32 indexed banditId,
        BanditState oldState,
        BanditState newState,
        uint8 region,
        uint64 atTick
    );
    event BanditMoved(uint32 indexed banditId, uint8 fromRegion, uint8 toRegion, uint64 atTick);
    event BanditAttackResolved(
        uint32 indexed banditId,
        uint32 indexed targetClanId,
        bool defended,
        uint16 attackPower,
        uint16 totalDefense,
        uint16 wallLevelAfter,
        uint256 stolenWood,
        uint256 stolenIron,
        uint256 stolenWheat,
        uint256 stolenFish,
        uint64 atTick
    );
    event BanditDefeated(uint32 indexed banditId, uint32 indexed targetClanId, uint64 atTick);
    event BanditEscaped(uint32 indexed banditId, uint64 atTick);
    event BlueprintAwarded(uint32 indexed clanId, uint32 indexed banditId, uint256 amount);
    event LootDistributedToDefender(
        uint32 indexed banditId,
        uint32 indexed clanId,
        uint32 indexed clansmanId,
        uint256 wood,
        uint256 iron,
        uint256 wheat,
        uint256 fish
    );

    // ----- winter cold damage -----
    event ColdDamageApplied(uint32 indexed clanId, uint16 oldDamage, uint16 newDamage, uint64 atTick);
    event ClansmanDiedFromCold(uint32 indexed clanId, uint64 atTick);

    // ----- OTC transfers -----
    event GoldTransferred(uint32 indexed fromClanId, uint32 indexed toClanId, uint256 amount, uint64 atTick);
    event VaultResourceTransferred(
        uint32 indexed fromClanId,
        uint32 indexed toClanId,
        ResourceType resource,
        uint256 amount,
        uint64 atTick
    );
    event BlueprintTransferred(uint32 indexed fromClanId, uint32 indexed toClanId, uint256 amount, uint64 atTick);

    // ----- treasury / pools -----
    event PoolsSeeded(
        address woodGoldPool,
        address wheatGoldPool,
        address fishGoldPool,
        address ironGoldPool
    );
}

// =============================================================================
// MAIN INTERFACE
// =============================================================================

interface IClanWorld is IClanWorldEvents {

    // -------------------------------------------------------------------------
    // World progression
    // -------------------------------------------------------------------------

    /// @notice Permissionless heartbeat. Closes the current tick, resolves
    ///         scheduled market actions and world events, advances the tick.
    ///         Rate-limited by WorldState.nextHeartbeatAtTs.
    function heartbeat() external;

    /// @notice Lazily settle a clan forward to current tick. Idempotent.
    function settleClan(uint32 clanId) external;

    /// @notice Finalize the current season. Permissionless after seasonEndTick.
    function finalizeSeason() external;

    // -------------------------------------------------------------------------
    // Clan lifecycle
    // -------------------------------------------------------------------------

    /// @notice Mint a new clan iNFT and spawn its homebase in a valid region.
    function mintClan(address to) external returns (uint32 clanId, uint256 iftTokenId);

    /// @notice Submit one or more orders for a single clan's clansmen.
    ///         Per-order failures do not revert the tx.
    function submitClanOrders(uint32 clanId, ClanOrder[] calldata orders)
        external
        returns (OrderResult[] memory);

    // -------------------------------------------------------------------------
    // Treasury / pool seeding
    // -------------------------------------------------------------------------

    /// @notice Owner-only. Seeds the four Unicorn Town pools at deploy time.
    function seedPools(PoolSeedConfig calldata cfg) external;

    // -------------------------------------------------------------------------
    // OTC transfers (clan-to-clan, sender must be ACTIVE per v4.3 §M)
    // -------------------------------------------------------------------------

    function transferGold(uint32 fromClanId, uint32 toClanId, uint256 amount) external;

    function transferVaultResource(
        uint32 fromClanId,
        uint32 toClanId,
        ResourceType resource,
        uint256 amount
    ) external;

    function transferBlueprint(uint32 fromClanId, uint32 toClanId, uint256 amount) external;

    function transferBundle(
        uint32 fromClanId,
        uint32 toClanId,
        uint256 gold,
        uint256 blueprint,
        uint256 wood,
        uint256 iron,
        uint256 wheat,
        uint256 fish
    ) external;

    // -------------------------------------------------------------------------
    // Raw read getters (committed storage, no settlement simulation)
    // -------------------------------------------------------------------------

    function getWorldState() external view returns (WorldState memory);

    function getTreasuryState() external view returns (TreasuryState memory);

    function getClan(uint32 clanId) external view returns (Clan memory);

    function getClansman(uint32 clansmanId) external view returns (Clansman memory);

    function getActiveMission(uint32 clansmanId) external view returns (Mission memory);

    function getBanditTroop(uint32 banditId) external view returns (BanditTroop memory);

    function getWheatPlots(uint32 clanId)
        external
        view
        returns (WheatPlot memory west, WheatPlot memory east);

    function getScheduledMarketActionsForTick(uint64 tick)
        external
        view
        returns (ScheduledMarketAction[] memory);

    function getActiveDefenders(uint32 targetClanId)
        external
        view
        returns (uint32[] memory clansmanIds);

    // -------------------------------------------------------------------------
    // Derived read getters (read-only simulation forward to current tick)
    //
    // Per v4.3 §J ("Derived Getter Non-Mutation Rule"), these MUST NOT mutate
    // any storage, including settlement checkpoints, cached flags, or queues.
    // -------------------------------------------------------------------------

    function getDerivedClanState(uint32 clanId)
        external
        view
        returns (DerivedClanState memory);

    function getDerivedClansmanState(uint32 clansmanId)
        external
        view
        returns (DerivedClansmanState memory);

    /// @notice Non-binding preview. Bandit targeting is recomputed at attack
    ///         resolution time using then-current eagerly settled state.
    function getBanditTargetPreview(uint32 banditId)
        external
        view
        returns (uint32 previewClanId);

    function quoteTravel(uint8 srcRegion, uint8 dstRegion)
        external
        view
        returns (uint8 travelTicks, bytes8 path);

    function quoteLootValueRaw(uint32 clanId) external view returns (uint256 lootValue);

    function quoteLootValueSettled(uint32 clanId) external view returns (uint256 lootValue);

    // -------------------------------------------------------------------------
    // UI indexer aggregator getters (v4.4 additions)
    //
    // These are pure compositions of the derived getters above and exist only
    // to reduce indexer RPC traffic. They MUST follow the same non-mutation
    // rule as the underlying derived getters.
    // -------------------------------------------------------------------------

    /// @notice Single-call top-level world state plus per-clan leaderboard data.
    ///         Drives top HUD bar, season clock, winter indicator, leaderboard.
    function getWorldSnapshot() external view returns (WorldSnapshot memory);

    /// @notice Single-call complete clan rendering data: derived clan + all
    ///         clansmen with derived state and active missions + plot states +
    ///         defender bookkeeping. Drives the entire sprite layer.
    function getClanFullView(uint32 clanId) external view returns (ClanFullView memory);

    /// @notice Single-call market panel data: 4 pool reserves + spot prices +
    ///         scheduled queues for current and next tick. Drives market UI
    ///         and indexer's per-tick price-history sampling.
    function getMarketState() external view returns (MarketState memory);

    /// @notice Single-call bandit drama state, including projected target if
    ///         attack resolved this tick. Drives the bandit warning UI.
    function getActiveBanditView() external view returns (ActiveBanditView memory);

    /// @notice Optional. List clansmen currently in a region for tap-to-inspect
    ///         tooltips. Can be derived clientside; included for completeness.
    function getRegionPopulation(uint8 region)
        external
        view
        returns (RegionOccupant[] memory);
}
