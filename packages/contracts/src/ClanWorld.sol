// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {
    IClanWorld,
    IClanWorldEvents,
    ClanWorldConstants,
    ClanState,
    ClansmanState,
    BanditState,
    WheatPlotState,
    ResourceType,
    ActionType,
    MarketExecutionMode,
    StatusCode,
    WorldState,
    TreasuryState,
    Clan,
    WheatPlot,
    Clansman,
    Mission,
    BanditTroop,
    ScheduledMarketAction,
    DefenseContribution,
    PackedRoute,
    DerivedClanState,
    DerivedClansmanState,
    ClanOrder,
    WithdrawResourcesData,
    OrderResult,
    PoolSeedConfig,
    LeaderboardEntry,
    WorldSnapshot,
    ClansmanFullView,
    ClanFullView,
    PoolReserves,
    MarketState,
    ActiveBanditView,
    RegionOccupant
} from "./IClanWorld.sol";
import {RNG} from "./lib/RNG.sol";
import {MinimalERC20} from "./MinimalERC20.sol";
import {StubPool} from "./StubPool.sol";
import {ReentrancyGuard} from "./util/ReentrancyGuard.sol";

/// @dev Production storage excludes derived winter fields; _worldStateView() synthesizes the public ABI shape.
struct StoredWorldState {
    uint64 currentTick;
    uint64 seasonStartTick;
    uint64 seasonEndTick;
    bool seasonFinalized;
    uint64 currentSeasonNumber;
    uint64 nextHeartbeatAtTick;
    uint64 nextHeartbeatAtTs;
    uint64 nextBanditSpawnEligibleTick;
    uint16 currentBanditSpawnChanceBps;
    bytes32 currentTickSeed;
    uint32 activeBanditId;
    uint64 nextCommitSequence;
}

/// @title ClanWorld
/// @notice Phase 1–9 real engine implementation of IClanWorld v4.
///         Implements: world clock, clan lifecycle, lazy settlement, resource gathering,
///         deposit, wheat harvest, travel, NOOP bypass, order validation, market execution,
///         and Phase 9 bandit spawn/attack/resolution.
contract ClanWorld is IClanWorld, ReentrancyGuard {
    // =========================================================================
    // STORAGE
    // =========================================================================

    StoredWorldState internal _world;
    TreasuryState private _treasury;

    mapping(uint32 => Clan) internal _clans;
    mapping(uint32 => Clansman) internal _clansmen;
    mapping(uint32 => Mission) private _missions; // keyed by clansmanId
    mapping(uint32 => WheatPlot[2]) private _wheatPlots; // [0]=west [1]=east
    mapping(uint64 => ScheduledMarketAction[]) private _scheduledMarketActions; // keyed by tick
    mapping(uint32 => uint64) private _marketMissionCommitSequence; // clansmanId => FIFO sequence captured at submit
    mapping(uint8 => uint32[]) private _defendingClansByRegion; // home region => unique defending clanIds
    mapping(uint8 => mapping(uint32 => uint256)) private _defenderCountByRegionClan; // region => clanId => clansmen count
    mapping(uint32 => uint8) private _clansmanDefendingRegion; // clansmanId => defended home region
    mapping(uint32 => BanditTroop) internal _bandits;
    mapping(uint8 => uint32[]) internal _banditsByRegion; // region => bandit IDs
    mapping(uint8 => BanditSpawnState) internal _banditSpawnByRegion;
    mapping(uint64 => bytes32) private _tickSeeds; // tick => seed
    mapping(uint32 => WallUpgradeReservation) internal _wallUpgradeReservations; // clansmanId => reserved upgrade
    mapping(uint32 => uint8) private _pendingWallUpgradesByClan; // clanId => queued, unsettled wall upgrades
    mapping(uint32 => BaseUpgradeReservation) internal _baseUpgradeReservations; // clansmanId => reserved upgrade
    mapping(uint32 => uint8) private _pendingBaseUpgradesByClan; // clanId => queued, unsettled base upgrades
    mapping(uint32 => MonumentUpgradeReservation) internal _monumentUpgradeReservations; // clansmanId => reserved upgrade
    mapping(uint32 => uint8) private _pendingMonumentUpgradesByClan; // clanId => queued, unsettled monument upgrades
    mapping(uint32 => uint256) private _reservedWoodByClan; // clanId => held, not yet debited
    mapping(uint32 => uint256) private _reservedIronByClan; // clanId => held, not yet debited
    mapping(uint32 => uint256) private _reservedWheatByClan; // clanId => held, not yet debited
    mapping(uint32 => uint256) private _reservedBlueprintByClan; // clanId => held, not yet debited
    mapping(uint32 => mapping(uint8 => uint64)) internal _monumentLevelReachedAt; // clanId => level => first reached tick

    uint32 private _nextClanId;
    uint32 private _nextClansmanId;
    uint32 internal _nextBanditId;
    uint32 internal _activeBanditCount;
    uint32[] private _allClanIds;

    // per-clan clansman list: clanId => clansmanId[]
    mapping(uint32 => uint32[]) private _clanClansmanIds;

    struct WallUpgradeReservation {
        bool active;
        uint32 clanId;
        uint64 missionNonce;
        uint8 fromLevel;
        uint8 toLevel;
        uint256 woodCost;
        uint256 ironCost;
    }

    struct BaseUpgradeReservation {
        bool active;
        uint32 clanId;
        uint64 missionNonce;
        uint8 fromLevel;
        uint8 toLevel;
        uint256 woodCost;
        uint256 ironCost;
        uint256 wheatCost;
    }

    struct MonumentUpgradeReservation {
        bool active;
        uint32 clanId;
        uint64 missionNonce;
        uint8 fromLevel;
        uint8 toLevel;
        uint256 woodCost;
        uint256 ironCost;
        uint256 wheatCost;
        uint256 blueprintCost;
    }

    // =========================================================================
    // CONSTANTS — Wheat harvest rate (not in IClanWorld constants)
    // =========================================================================

    uint64 private constant DEPOSIT_DURATION_TICKS = 1;
    uint64 private constant BUILDING_DURATION_TICKS = 1;
    uint8 private constant WALL_MAX_LEVEL = 5;
    uint8 private constant BASE_MAX_LEVEL = 5;
    uint8 private constant MONUMENT_MAX_LEVEL = 10;
    uint256 private constant WHEAT_HARVEST_RATE = 20e18;
    uint256 private constant RESOURCE_UNIT = 1e18;
    uint256 internal constant BLUEPRINT_UNIT = 1e18;
    /// @dev Caps winter crop boundary work; current clan cap keeps transitions within this budget.
    uint256 public constant MAX_CROP_TRANSITION_PER_TICK = 48;
    uint256 internal constant DOMAIN_BANDIT_SPAWN = uint256(keccak256("clanworld.bandit.spawn.v1"));
    uint64 internal constant MIN_SPAWN_COOLDOWN_TICKS = ClanWorldConstants.BANDIT_COOLDOWN_TICKS;
    uint16 internal constant BANDIT_SPAWN_PROBABILITY_INCREMENT_BPS = 1000;
    uint16 internal constant BANDIT_SPAWN_MAX_PROBABILITY_BPS = 8000;
    uint8 internal constant MAX_BANDITS_PER_REGION = 1;
    uint8 internal constant MAX_TOTAL_BANDITS = 1;
    uint8 internal constant MAX_CLANS = 12;
    // Scan cap: 2x the mint cap; derived so ranking scan grows with MAX_CLANS.
    uint256 public constant MAX_CLAN_SCAN_FOR_RANKING = MAX_CLANS * 2;
    uint64 internal constant MAX_LAZY_SETTLE_BACKLOG = 200;
    /// @dev Bandit spawn weights are a heartbeat-time heuristic. V1 has
    ///      MAX_CLANS = 12, so scanning 8 clans per tick covers the live cap in
    ///      at most two rotating heartbeats while keeping heartbeat gas bounded.
    uint256 internal constant MAX_BANDIT_SPAWN_SCAN_PER_REGION = 8;
    uint256 internal constant MAX_BANDIT_SPAWN_CLANSMEN_SCAN_PER_REGION = MAX_BANDIT_SPAWN_SCAN_PER_REGION * 4;
    /// @dev Eager settlement scans the clan-indexed bases in each spawn-candidate
    ///      region, not every clan globally per region forever. MAX_CLANS = 12,
    ///      so this settles all possible bases today while keeping the heartbeat
    ///      loop explicitly bounded if that cap grows.
    uint256 internal constant MAX_BANDIT_EAGER_SETTLE_BASE_SCAN_PER_REGION = 12;
    uint256 internal constant MAX_BANDIT_EAGER_SETTLE_DEFENDING_CLANS_PER_REGION = 12;
    uint256 internal constant MAX_BANDIT_EAGER_SETTLE_DEFENDER_SCAN_PER_REGION = 48;
    uint8 internal constant BANDIT_TIER_COUNT = 5;
    uint32 internal constant DEFEND_BASE_DEFENSE = 10;
    uint32 internal constant WAITING_HOME_DEFENSE = 5;
    uint32 internal constant CLANSMAN_MAX_DEFENSE_DAMAGE = 100;
    uint32 internal constant WALL_HP_PER_LEVEL = 100;
    uint32 internal constant BASE_HP_PER_LEVEL = 25;
    uint32 internal constant CLANSMAN_HP = 100;

    struct BanditSpawnState {
        uint64 lastSpawnTick;
        uint16 probabilityAccum;
    }

    struct SettlementSimulation {
        Clan clan;
        Clansman[] clansmen;
        Mission[] missions;
        WheatPlot[2] wheatPlots;
        uint64[11] simMonumentReachedAt;
        bool[] simWallReservationCleared;
        bool[] simBaseReservationCleared;
        bool[] simMonumentReservationCleared;
        uint256 reservedWheat; // mirrors _reservedWheatByClan[clanId] for reservation-aware upkeep simulation
    }

    struct HeldUpgradeResources {
        uint256 wood;
        uint256 iron;
        uint256 wheat;
        uint256 blueprint;
    }

    uint256 public constant INITIAL_WOOD_POOL_SEED = 1_000e18;
    uint256 public constant INITIAL_WHEAT_POOL_SEED = 1_000e18;
    uint256 public constant INITIAL_FISH_POOL_SEED = 500e18;
    uint256 public constant INITIAL_IRON_POOL_SEED = 250e18;
    uint256 public constant INITIAL_GOLD_SEED_FOR_WOOD = 500e18;
    uint256 public constant INITIAL_GOLD_SEED_FOR_WHEAT = 700e18;
    uint256 public constant INITIAL_GOLD_SEED_FOR_FISH = 600e18;
    uint256 public constant INITIAL_GOLD_SEED_FOR_IRON = 800e18;
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor() {
        _world.currentTick = 0;
        _world.nextHeartbeatAtTs = uint64(block.timestamp);
        _world.seasonStartTick = 0;
        _world.seasonEndTick = ClanWorldConstants.SEASON_DURATION_TICKS;
        _world.currentSeasonNumber = 1;
        _world.nextHeartbeatAtTick = 1; // first heartbeat will open tick 1
        _treasury.treasuryOwner = msg.sender;
        _nextClanId = 1;
        _nextClansmanId = 1;
        _nextBanditId = 1;
    }

    // =========================================================================
    // TRAVEL DISTANCE MATRIX
    // =========================================================================

    // Precomputed BFS distances for 8 regions (1-indexed; index 0 unused).
    // Adjacency:
    //   Forest(1):       Mountains(2), WestFarms(4)
    //   Mountains(2):    Forest(1), UnicornTown(3)
    //   UnicornTown(3):  Mountains(2), WestFarms(4), EastFarms(5)
    //   WestFarms(4):    Forest(1), UnicornTown(3), WestDocks(6)
    //   EastFarms(5):    UnicornTown(3), EastDocks(7)
    //   WestDocks(6):    WestFarms(4), DeepSea(8)
    //   EastDocks(7):    EastFarms(5), DeepSea(8)
    //   DeepSea(8):      WestDocks(6), EastDocks(7)
    //
    // Distance table dist[src][dst] — 0-indexed internally (region - 1).
    // Distance of 0 = same region.
    //
    // Full BFS-computed 8x8 matrix:
    //   src\dst  1  2  3  4  5  6  7  8
    //      1     0  1  2  1  3  2  4  3
    //      2     1  0  1  2  2  3  3  4
    //      3     2  1  0  1  1  2  2  3
    //      4     1  2  1  0  2  1  3  2
    //      5     3  2  1  2  0  3  1  2
    //      6     2  3  2  1  3  0  2  1
    //      7     4  3  2  3  1  2  0  1
    //      8     3  4  3  2  2  1  1  0

    function _distMatrix(uint8 src, uint8 dst) private pure returns (uint8) {
        if (src == dst) return 0;
        // Encode as (src-1)*8 + (dst-1), values from BFS
        uint8[64] memory d = [
            // src=1: to 1,2,3,4,5,6,7,8
            0,
            1,
            2,
            1,
            3,
            2,
            4,
            3,
            // src=2: to 1,2,3,4,5,6,7,8
            1,
            0,
            1,
            2,
            2,
            3,
            3,
            4,
            // src=3: to 1,2,3,4,5,6,7,8
            2,
            1,
            0,
            1,
            1,
            2,
            2,
            3,
            // src=4: to 1,2,3,4,5,6,7,8
            1,
            2,
            1,
            0,
            2,
            1,
            3,
            2,
            // src=5: to 1,2,3,4,5,6,7,8
            3,
            2,
            1,
            2,
            0,
            3,
            1,
            2,
            // src=6: to 1,2,3,4,5,6,7,8
            2,
            3,
            2,
            1,
            3,
            0,
            2,
            1,
            // src=7: to 1,2,3,4,5,6,7,8
            4,
            3,
            2,
            3,
            1,
            2,
            0,
            1,
            // src=8: to 1,2,3,4,5,6,7,8
            3,
            4,
            3,
            2,
            2,
            1,
            1,
            0
        ];
        return d[uint8(src - 1) * 8 + uint8(dst - 1)];
    }

    // Build a canonical path from src to dst (BFS on the adjacency graph).
    // Returns packed bytes8: region IDs in order, zero-padded.
    function _buildPath(uint8 src, uint8 dst) private pure returns (bytes8) {
        if (src == dst) {
            return bytes8(uint64(src) << 56);
        }
        // Adjacency list (1-indexed, 0 = end sentinel)
        // adj[r] = neighbors of region r (up to 3)
        uint8[3][9] memory adj = [
            [0, 0, 0], // 0: unused
            [2, 4, 0], // 1: Forest
            [1, 3, 0], // 2: Mountains
            [2, 4, 5], // 3: UnicornTown
            [1, 3, 6], // 4: WestFarms
            [3, 7, 0], // 5: EastFarms
            [4, 8, 0], // 6: WestDocks
            [5, 8, 0], // 7: EastDocks
            [6, 7, 0] // 8: DeepSea
        ];

        // BFS with parent tracking (max 8 nodes)
        uint8[9] memory parent;
        bool[9] memory visited;
        uint8[9] memory queue;
        uint256 head;
        uint256 tail;

        for (uint256 i = 0; i < 9; i++) {
            parent[i] = 0;
            visited[i] = false;
        }

        visited[src] = true;
        queue[tail++] = src;

        while (head < tail) {
            uint8 curr = queue[head++];
            if (curr == dst) break;
            for (uint256 ni = 0; ni < 3; ni++) {
                uint8 nb = adj[curr][ni];
                if (nb == 0) break;
                if (!visited[nb]) {
                    visited[nb] = true;
                    parent[nb] = curr;
                    queue[tail++] = nb;
                }
            }
        }

        // Reconstruct path backwards
        uint8[8] memory path;
        uint256 pathLen;
        uint8 cur = dst;
        while (cur != src) {
            path[pathLen++] = cur;
            cur = parent[cur];
        }
        path[pathLen++] = src;

        // Reverse into result
        bytes8 packed;
        uint64 byteShift = 56;
        for (uint256 i = pathLen; i > 0; i--) {
            packed = packed | bytes8(uint64(path[i - 1]) << byteShift);
            if (byteShift >= 8) byteShift -= 8;
        }
        return packed;
    }

    function _travelTicks(uint8 fromRegion, uint8 toRegion) private pure returns (uint8) {
        if (fromRegion == 0 || toRegion == 0) return 0; // NOOP region
        if (fromRegion == toRegion) return 0;
        if (fromRegion > 8 || toRegion > 8) return 0;
        return _distMatrix(fromRegion, toRegion);
    }

    function _addTicksClamped(uint64 tick, uint64 delta) private pure returns (uint64) {
        if (type(uint64).max - tick < delta) return type(uint64).max;
        return tick + delta;
    }

    // =========================================================================
    // INTERNAL SETTLEMENT
    // =========================================================================

    /// @dev Settle a single clansman's mission for the tick range [fromTick, toTick).
    ///      Handles all 6 mission lifecycle paths. Called from _settleClan and settleClansman.
    function _settleMissionForClansman(
        Clan storage clan,
        Clansman storage cs,
        uint32 clanId,
        uint64 fromTick,
        uint64 toTick
    ) internal {
        Mission storage m = _missions[cs.clansmanId];

        // Path 6: dead clansman — invalidate active mission if any
        if (cs.state == ClansmanState.DEAD) {
            if (m.active) {
                if (m.action == ActionType.DefendBase) {
                    _clearDefender(cs.clansmanId);
                }
                _refundUpgradeReservation(cs.clansmanId, m.action);
                m.active = false; // silent invalidation; dead clansman gets no MissionCompleted
            }
            return;
        }

        if (!m.active) return; // no active mission — nothing to settle

        bytes32 tickSeed;
        for (uint64 tick = fromTick; tick < toTick; tick++) {
            tickSeed = _tickSeeds[tick];

            // Path 1 → Path 2 transition: TRAVELING → ACTING at arrivalTick
            if (cs.state == ClansmanState.TRAVELING && tick >= m.arrivalTick) {
                cs.state = ClansmanState.ACTING;
                cs.currentRegion = m.targetRegion;
                emit WorkerArrived(clanId, cs.clansmanId, m.targetRegion, tick);

                if (m.action == ActionType.DefendBase) {
                    _registerDefender(m.targetRegion, clanId, cs.clansmanId);
                }
            }

            if (m.action == ActionType.DefendBase) continue; // persistent defender mission

            // Path 3: ACTING at/past settlesAtTick → resolve
            if (cs.state == ClansmanState.ACTING && tick >= m.settlesAtTick) {
                _resolveAction(clan, cs, m, clanId, tick, tickSeed);
                if (m.active && getActionDuration(m.action) > 0) {
                    m.settlesAtTick = _addTicksClamped(tick, getActionDuration(m.action));
                }
            }

            // If mission completed during this tick, stop iterating
            if (!m.active) break;
        }
    }

    /// @dev Lazy settlement of a clan forward to currentTick.
    ///      Mutates storage. Called before order submission and by public settleClan().
    function _settleClan(uint32 clanId) internal {
        Clan storage clan = _clans[clanId];
        if (clan.clanId == 0) return;

        uint64 curTick = _world.currentTick;
        uint64 fromTick = clan.lastSettledTick;
        if (fromTick >= curTick) return;

        // Cap ticks settled per call to prevent block gas limit issues
        if (curTick > fromTick + MAX_LAZY_SETTLE_BACKLOG) {
            curTick = fromTick + MAX_LAZY_SETTLE_BACKLOG;
        }

        uint32[] storage clansmanIds = _clanClansmanIds[clanId];

        // Settle tick by tick from fromTick to curTick - 1
        // (curTick is still open; we settle through the last closed tick)
        for (uint64 tick = fromTick; tick < curTick; tick++) {
            // 1. Apply upkeep for this tick
            _applyUpkeep(clan, tick);
            if (clan.clanState == ClanState.DEAD) break;

            // 2. Wheat plot regrow check (lazy, per tick)
            for (uint256 pi = 0; pi < 2; pi++) {
                WheatPlot storage plot = _wheatPlots[clanId][pi];
                if (plot.state == WheatPlotState.Regrowing && tick >= plot.regrowUntilTick) {
                    plot.state = WheatPlotState.Harvestable;
                    plot.remainingWheat = ClanWorldConstants.WHEAT_PLOT_STARTING_WHEAT;
                    plot.regrowUntilTick = 0;
                }
            }

            // 3. Advance each clansman (single-tick range: [tick, tick+1))
            for (uint256 i = 0; i < clansmanIds.length; i++) {
                Clansman storage cs = _clansmen[clansmanIds[i]];
                _settleMissionForClansman(clan, cs, clanId, tick, tick + 1);
            }
        }

        if (curTick > fromTick && !_isWinterActiveAt(curTick) && _isWinterActiveAt(curTick - 1)) {
            clan.coldDamage = 0;
        }

        clan.lastSettledTick = curTick;
        emit ClanSettled(clanId, curTick);
    }

    /// @dev Apply one tick of upkeep. Marks starvation if insufficient food and cold damage if winter wood is short.
    function _applyUpkeep(Clan storage clan, uint64 tick) internal {
        bool winter = _isWinterActiveAt(tick);
        if (!winter && tick > 0 && _isWinterActiveAt(tick - 1)) {
            clan.coldDamage = 0;
        }

        if (clan.livingClansmen == 0) return;

        uint256 wheatNeeded = uint256(clan.livingClansmen) * ClanWorldConstants.WHEAT_UPKEEP_PER_CLANSMAN;
        uint256 fishNeeded = uint256(clan.livingClansmen) * ClanWorldConstants.FISH_UPKEEP_PER_CLANSMAN;
        if (winter) {
            wheatNeeded = wheatNeeded * ClanWorldConstants.WINTER_UPKEEP_MULTIPLIER_BPS / 10000;
            fishNeeded = fishNeeded * ClanWorldConstants.WINTER_UPKEEP_MULTIPLIER_BPS / 10000;
        }

        uint256 spendableWheat = clan.vaultWheat > _reservedWheatByClan[clan.clanId]
            ? clan.vaultWheat - _reservedWheatByClan[clan.clanId]
            : 0;
        bool hadEnoughWheat = spendableWheat >= wheatNeeded;
        bool hadEnoughFish = clan.vaultFish >= fishNeeded;

        if (hadEnoughWheat) {
            clan.vaultWheat -= wheatNeeded;
        } else {
            clan.vaultWheat -= spendableWheat;
        }
        if (hadEnoughFish) {
            clan.vaultFish -= fishNeeded;
        } else {
            clan.vaultFish = 0;
        }

        bool starving = !hadEnoughWheat || !hadEnoughFish;
        if (starving && clan.starvationStartsAtTick == 0) {
            /// @dev Same-tick onset is canonical; see docs/planning/clanworld_v4_6_phase5_economy_alignment.md §5.2.
            ///      This also makes bandit-defense starvation effects apply on the upkeep-failure tick.
            clan.starvationStartsAtTick = tick;
            emit ClanStarvationChanged(clan.clanId, true, tick);
        } else if (!starving && clan.starvationStartsAtTick != 0) {
            clan.starvationStartsAtTick = 0;
            emit ClanStarvationChanged(clan.clanId, false, tick);
        }

        uint8 livingBeforeStarvation = clan.livingClansmen;
        if (winter && starving) {
            (, uint64 winterStartsAtTick,) = _winterWindowForTick(tick);
            uint64 effectiveStarvationStartsAtTick =
                clan.starvationStartsAtTick > winterStartsAtTick ? clan.starvationStartsAtTick : winterStartsAtTick;
            if (effectiveStarvationStartsAtTick < tick) {
                _killNextClansmanFromStarvation(clan, tick);
            }
        }
        if (clan.clanState == ClanState.DEAD) return;

        if (winter) {
            uint256 woodNeeded = ClanWorldConstants.WINTER_WOOD_BURN_PER_BASE + uint256(livingBeforeStarvation)
                * ClanWorldConstants.WINTER_WOOD_BURN_PER_CLANSMAN;
            if (clan.vaultWood >= woodNeeded) {
                clan.vaultWood -= woodNeeded;
            } else {
                uint256 woodShort = woodNeeded - clan.vaultWood;
                clan.vaultWood = 0;
                uint16 oldColdDamage = clan.coldDamage;
                if (clan.coldDamage < type(uint16).max) {
                    clan.coldDamage += 1;
                }
                emit ClanColdShortage(clan.clanId, tick, woodShort);
                _applyColdDamageConsequence(clan, tick, oldColdDamage);
            }
        }
    }

    function _applyColdDamageConsequence(Clan storage clan, uint64 tick, uint16 oldColdDamage) internal {
        uint16 newColdDamage = clan.coldDamage;
        if (newColdDamage == oldColdDamage) return;

        if (clan.wallLevel > 0) {
            if (
                newColdDamage / ClanWorldConstants.COLD_DAMAGE_PER_WALL_DEGRADATION
                    <= oldColdDamage / ClanWorldConstants.COLD_DAMAGE_PER_WALL_DEGRADATION
            ) return;

            clan.wallLevel--;
            emit WallDegradedByCold(clan.clanId, clan.wallLevel, tick);
            return;
        }

        if (
            newColdDamage / ClanWorldConstants.COLD_DAMAGE_PER_CLANSMAN_DEATH
                <= oldColdDamage / ClanWorldConstants.COLD_DAMAGE_PER_CLANSMAN_DEATH
        ) return;

        _killRandomClansmanFromCold(clan, tick, newColdDamage);
    }

    function _killRandomClansmanFromCold(Clan storage clan, uint64 tick, uint16 coldDamage) internal {
        if (clan.livingClansmen == 0) return;

        uint32[] storage csIds = _clanClansmanIds[clan.clanId];
        uint256 livingCount = 0;
        for (uint256 i = 0; i < csIds.length; i++) {
            if (_clansmen[csIds[i]].state != ClansmanState.DEAD) {
                livingCount++;
            }
        }
        if (livingCount == 0) return;

        uint256 pick = RNG.rngBounded(
            _tickSeeds[tick],
            RNG.DOMAIN_COLD_DAMAGE,
            uint256(keccak256(abi.encodePacked(clan.clanId, tick, coldDamage))),
            livingCount
        );

        uint256 seen = 0;
        for (uint256 i = 0; i < csIds.length; i++) {
            Clansman storage cs = _clansmen[csIds[i]];
            if (cs.state == ClansmanState.DEAD) continue;
            if (seen != pick) {
                seen++;
                continue;
            }

            _markClansmanDeadFromCold(clan, cs, tick);
            return;
        }
    }

    function _killNextClansmanFromStarvation(Clan storage clan, uint64 tick) internal {
        if (clan.livingClansmen == 0) return;

        uint32[] storage csIds = _clanClansmanIds[clan.clanId];
        for (uint256 i = 0; i < csIds.length; i++) {
            Clansman storage cs = _clansmen[csIds[i]];
            if (cs.state == ClansmanState.DEAD) continue;

            _markClansmanDead(clan, cs);
            if (clan.livingClansmen == 0) {
                _markClanDead(clan.clanId, "starvation", tick);
            }
            return;
        }
    }

    function _markClansmanDeadFromCold(Clan storage clan, Clansman storage cs, uint64 tick) internal {
        _markClansmanDead(clan, cs);

        emit ClansmanColdDeath(clan.clanId, cs.clansmanId, tick);
        if (clan.livingClansmen == 0) {
            _markClanDead(clan.clanId, "cold", tick);
        }
    }

    function _markClansmanDead(Clan storage clan, Clansman storage cs) internal {
        if (cs.state == ClansmanState.DEAD) return;

        cs.state = ClansmanState.DEAD;
        cs.cooldownEndsAtTs = 0;
        if (clan.livingClansmen > 0) {
            clan.livingClansmen--;
        }

        Mission storage m = _missions[cs.clansmanId];
        if (m.active) {
            if (m.action == ActionType.DefendBase) {
                _clearDefender(cs.clansmanId);
            }
            _refundUpgradeReservation(cs.clansmanId, m.action);
            m.active = false;
        }
    }

    function _markClanDead(uint32 clanId) internal {
        _markClanDead(clanId, "unknown", _world.currentTick, ClanWorldConstants.BANDIT_ID_NULL);
    }

    function _markClanDead(uint32 clanId, string memory reason, uint64 tick) internal {
        _markClanDead(clanId, reason, tick, ClanWorldConstants.BANDIT_ID_NULL);
    }

    function _markClanDead(uint32 clanId, string memory reason, uint64 tick, uint32 excludedBanditId) internal {
        Clan storage clan = _clans[clanId];
        if (clan.clanId == ClanWorldConstants.CLAN_ID_NULL || clan.clanState == ClanState.DEAD) return;

        uint8 baseRegion = clan.baseRegion;
        clan.clanState = ClanState.DEAD;
        clan.vaultWood = 0;
        clan.vaultWheat = 0;
        clan.vaultFish = 0;
        clan.vaultIron = 0;
        clan.starvationStartsAtTick = 0;
        clan.livingClansmen = 0;

        uint32[] storage csIds = _clanClansmanIds[clanId];
        for (uint256 i = 0; i < csIds.length; i++) {
            Clansman storage cs = _clansmen[csIds[i]];
            cs.state = ClansmanState.DEAD;
            cs.cooldownEndsAtTs = 0;
            Mission storage m = _missions[csIds[i]];
            if (m.active) {
                if (m.action == ActionType.DefendBase) {
                    _clearDefender(csIds[i]);
                }
                _refundUpgradeReservation(csIds[i], m.action);
                m.active = false;
            }
        }

        _releaseDefendersForDeadTarget(clanId, baseRegion);
        _abortBanditAttacksForDeadTarget(clanId, excludedBanditId, tick);

        emit ClanEliminated(clanId, tick);
        emit ClanDied(clanId, tick, reason);
    }

    function _releaseDefendersForDeadTarget(uint32 deadClanId, uint8 baseRegion) internal {
        for (uint256 i = 0; i < _allClanIds.length; i++) {
            uint32 defenderClanId = _allClanIds[i];
            if (defenderClanId == deadClanId) continue;

            uint32[] storage csIds = _clanClansmanIds[defenderClanId];
            for (uint256 j = 0; j < csIds.length; j++) {
                uint32 clansmanId = csIds[j];
                Mission storage mission = _missions[clansmanId];
                if (
                    mission.active && mission.action == ActionType.DefendBase && mission.targetClanId == deadClanId
                        && _clansmanDefendingRegion[clansmanId] == baseRegion
                ) {
                    _clearDefender(clansmanId);
                    mission.active = false;

                    Clansman storage defender = _clansmen[clansmanId];
                    if (defender.state != ClansmanState.DEAD) {
                        defender.state = ClansmanState.WAITING;
                    }
                }
            }
        }
    }

    function _abortBanditAttacksForDeadTarget(uint32 deadClanId, uint32 excludedBanditId, uint64 tick) internal {
        // Uses caller-provided tick for replay-determinism; matches closedTick from heartbeat context.
        for (uint8 region = ClanWorldConstants.REGION_FOREST; region <= ClanWorldConstants.REGION_DEEP_SEA; region++) {
            uint32[] storage regionBandits = _banditsByRegion[region];
            for (uint256 i = 0; i < regionBandits.length; i++) {
                uint32 banditId = regionBandits[i];
                if (banditId == excludedBanditId) continue;

                BanditTroop storage bandit = _bandits[banditId];
                if (bandit.state == BanditState.Attacking && bandit.targetClanId == deadClanId) {
                    _transitionBanditState(banditId, BanditState.Escaped);
                    emit BanditEscaped(banditId, tick);
                    emit BanditTargetDied(banditId, deadClanId, tick);
                }
            }
        }
    }

    /// @dev Check if a clan is currently starving (lazy read).
    function _isStarving(Clan storage clan) internal view returns (bool) {
        return clan.starvationStartsAtTick != 0 && clan.starvationStartsAtTick <= _world.currentTick;
    }

    /// @dev Resolve one tick of action for a clansman that is in ACTING state.
    function _resolveAction(
        Clan storage clan,
        Clansman storage cs,
        Mission storage m,
        uint32 clanId,
        uint64 tick,
        bytes32 tickSeed
    ) internal {
        bool starving = _isStarving(clan);
        ActionType action = m.action;

        if (action == ActionType.ChopWood) {
            _gatherWood(clan, cs, m, clanId, tick, starving, tickSeed);
        } else if (action == ActionType.MineIron) {
            _gatherIron(clan, cs, m, clanId, tick, starving, tickSeed);
        } else if (action == ActionType.FishDocks) {
            _gatherFishDocks(clan, cs, m, clanId, tick, starving, tickSeed);
        } else if (action == ActionType.FishDeepSea) {
            _gatherFishDeepSea(clan, cs, m, clanId, tick, starving, tickSeed);
        } else if (action == ActionType.HarvestWheat) {
            _gatherWheat(clan, cs, m, clanId, tick, starving);
        } else if (action == ActionType.DepositResources) {
            _doDeposit(clan, cs, m, clanId, tick);
        } else if (action == ActionType.WithdrawResources) {
            _doWithdrawResources(clan, cs, m, clanId, tick);
        } else if (action == ActionType.Wait) {
            // NOOP — worker stays ACTING (continuous), no transition needed
            // Wait mission is effectively persistent until interrupted
        } else if (action == ActionType.DefendBase) {
            // Persistent mission. Registration happens atomically at order submission.
        } else if (
            action == ActionType.UpgradeWall || action == ActionType.UpgradeBase || action == ActionType.UpgradeMonument
        ) {
            _doBuilding(clan, cs, m, clanId, tick, action);
        } else if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
            _completeMission(cs, m);
        }
    }

    // -------------------------------------------------------------------------
    // Gathering helpers
    // -------------------------------------------------------------------------

    function _gatherWood(
        Clan storage, // clan (unused — no clan-level mutation in wood gather)
        Clansman storage cs,
        Mission storage m,
        uint32 clanId,
        uint64 tick,
        bool starving,
        bytes32 tickSeed
    ) internal {
        uint256 remaining = ClanWorldConstants.WOOD_CAP - cs.carryWood;
        if (remaining == 0) {
            _completeMission(cs, m);
            return;
        }
        uint256 yield = ClanWorldConstants.WOOD_BASE_YIELD;
        // Crit roll: domain-separated RNG
        bytes32 critRng = keccak256(abi.encode("wood_crit", tickSeed, cs.clansmanId, m.nonce, tick));
        uint256 critRoll = uint256(critRng) % 10000;
        if (critRoll < ClanWorldConstants.WOOD_CRIT_BPS) {
            yield += ClanWorldConstants.WOOD_CRIT_BONUS;
        }
        if (starving) yield = yield / 2;
        if (yield > remaining) yield = remaining;
        cs.carryWood += yield;

        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.ChopWood, yield, 0, 0, 0, 0, tick);

        if (cs.carryWood >= ClanWorldConstants.WOOD_CAP) {
            _completeMission(cs, m);
        }
        // else continuous — worker stays ACTING
    }

    function _gatherIron(
        Clan storage clan,
        Clansman storage cs,
        Mission storage m,
        uint32 clanId,
        uint64 tick,
        bool starving,
        bytes32 tickSeed
    ) internal {
        uint256 remaining = ClanWorldConstants.IRON_CAP - cs.carryIron;
        if (remaining == 0) {
            _completeMission(cs, m);
            return;
        }
        uint256 yield = ClanWorldConstants.IRON_BASE_YIELD;
        if (starving) yield = yield / 2;
        if (yield > remaining) yield = remaining;
        cs.carryIron += yield;

        // Gold bonus roll — scoped to reduce stack depth
        uint256 goldBonus = _rollIronGoldBonus(clan, cs.clansmanId, m.nonce, tick, tickSeed);

        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.MineIron, 0, yield, 0, 0, goldBonus, tick);

        if (cs.carryIron >= ClanWorldConstants.IRON_CAP) {
            _completeMission(cs, m);
        }
    }

    function _rollIronGoldBonus(Clan storage clan, uint32 clansmanId, uint64 nonce, uint64 tick, bytes32 tickSeed)
        internal
        returns (uint256 goldBonus)
    {
        bytes32 goldRng = keccak256(abi.encode("iron_gold_bonus", tickSeed, clansmanId, nonce, tick));
        if (uint256(goldRng) % 10000 < ClanWorldConstants.GOLD_FROM_IRON_BPS) {
            goldBonus = ClanWorldConstants.GOLD_FROM_IRON_AMOUNT;
            clan.goldBalance += goldBonus;
        }
    }

    function _gatherFishDocks(
        Clan storage,
        Clansman storage cs,
        Mission storage m,
        uint32 clanId,
        uint64 tick,
        bool starving,
        bytes32 tickSeed
    ) internal {
        uint256 remaining = ClanWorldConstants.FISH_CAP - cs.carryFish;
        if (remaining == 0) {
            _completeMission(cs, m);
            return;
        }
        bytes32 fishRng = keccak256(abi.encode("fish_roll", tickSeed, cs.clansmanId, m.nonce, tick));
        uint256 fishRoll = uint256(fishRng) % 10000;
        uint256 yield = 0;
        if (fishRoll < ClanWorldConstants.FISH_DOCKS_BPS) {
            yield = 1e18;
        }
        if (starving) yield = yield / 2;
        if (yield > remaining) yield = remaining;
        if (yield > 0) {
            cs.carryFish += yield;
            emit ResourcesGathered(clanId, cs.clansmanId, ActionType.FishDocks, 0, 0, 0, yield, 0, tick);
        }
        if (cs.carryFish >= ClanWorldConstants.FISH_CAP) {
            _completeMission(cs, m);
        }
    }

    function _gatherFishDeepSea(
        Clan storage,
        Clansman storage cs,
        Mission storage m,
        uint32 clanId,
        uint64 tick,
        bool starving,
        bytes32 tickSeed
    ) internal {
        uint256 remaining = ClanWorldConstants.FISH_CAP - cs.carryFish;
        if (remaining == 0) {
            _completeMission(cs, m);
            return;
        }
        bytes32 fishRng = keccak256(abi.encode("fish_roll", tickSeed, cs.clansmanId, m.nonce, tick));
        uint256 fishRoll = uint256(fishRng) % 10000;
        uint256 yield = 0;
        if (fishRoll < ClanWorldConstants.FISH_DEEP_BPS) {
            yield = 1e18;
        }
        if (starving) yield = yield / 2;
        if (yield > remaining) yield = remaining;
        if (yield > 0) {
            cs.carryFish += yield;
            emit ResourcesGathered(clanId, cs.clansmanId, ActionType.FishDeepSea, 0, 0, 0, yield, 0, tick);
        }
        if (cs.carryFish >= ClanWorldConstants.FISH_CAP) {
            _completeMission(cs, m);
        }
    }

    function _gatherWheat(
        Clan storage,
        /* clan — unused but kept positional for callsite parity */
        Clansman storage cs,
        Mission storage m,
        uint32 clanId,
        uint64 tick,
        bool starving
    ) internal {
        uint256 remaining = ClanWorldConstants.WHEAT_CAP - cs.carryWheat;
        if (remaining == 0) {
            _completeMission(cs, m);
            return;
        }
        // Determine plot index from region
        uint8 region = m.targetRegion;
        uint256 plotIdx;
        if (region == ClanWorldConstants.REGION_WEST_FARMS) {
            plotIdx = 0;
        } else if (region == ClanWorldConstants.REGION_EAST_FARMS) {
            plotIdx = 1;
        } else {
            // Wrong region — complete (no harvest)
            _completeMission(cs, m);
            return;
        }

        WheatPlot storage plot = _wheatPlots[clanId][plotIdx];
        if (plot.state == WheatPlotState.WinterLocked) {
            // Winter-locked plots cannot be harvested; queued missions end with no yield.
            _completeMission(cs, m);
            return;
        }
        if (plot.state != WheatPlotState.Harvestable || plot.remainingWheat == 0) {
            // Plot not ready — worker waits
            _completeMission(cs, m);
            return;
        }

        uint256 yield = WHEAT_HARVEST_RATE;
        if (starving) yield = yield / 2;
        if (yield > remaining) yield = remaining;
        if (yield > plot.remainingWheat) yield = plot.remainingWheat;

        cs.carryWheat += yield;
        plot.remainingWheat -= yield;

        emit ResourcesGathered(clanId, cs.clansmanId, ActionType.HarvestWheat, 0, 0, yield, 0, 0, tick);

        if (plot.remainingWheat == 0) {
            plot.state = WheatPlotState.Regrowing;
            plot.regrowUntilTick = tick + ClanWorldConstants.WHEAT_PLOT_REGROW_TICKS;
        }

        if (cs.carryWheat >= ClanWorldConstants.WHEAT_CAP || plot.remainingWheat == 0) {
            _completeMission(cs, m);
        }
        // else continuous
    }

    function _doDeposit(Clan storage clan, Clansman storage cs, Mission storage m, uint32 clanId, uint64 tick)
        internal
    {
        // Must be at homebase region
        if (cs.currentRegion != clan.baseRegion) {
            _completeMission(cs, m);
            return;
        }
        bool hasAnything = cs.carryWood > 0 || cs.carryIron > 0 || cs.carryWheat > 0 || cs.carryFish > 0;
        if (!hasAnything) {
            _completeMission(cs, m);
            return;
        }

        uint256 w = cs.carryWood;
        uint256 ir = cs.carryIron;
        uint256 wh = cs.carryWheat;
        uint256 fi = cs.carryFish;

        clan.vaultWood += w;
        clan.vaultIron += ir;
        clan.vaultWheat += wh;
        clan.vaultFish += fi;

        cs.carryWood = 0;
        cs.carryIron = 0;
        cs.carryWheat = 0;
        cs.carryFish = 0;

        emit ResourcesDeposited(clanId, cs.clansmanId, w, ir, wh, fi, tick);
        _completeMission(cs, m);
    }

    function _doWithdrawResources(Clan storage clan, Clansman storage cs, Mission storage m, uint32 clanId, uint64 tick)
        internal
    {
        if (cs.currentRegion != clan.baseRegion) {
            _completeMission(cs, m);
            return;
        }

        WithdrawResourcesData memory req = m.withdrawResources;
        HeldUpgradeResources memory released;
        if (
            !_hasWithdrawRequest(req) || !_hasSpendableForWithdraw(clanId, clan, req, released)
                || !_hasCarryCapacityForWithdraw(cs, req)
        ) {
            _completeMission(cs, m);
            return;
        }

        clan.vaultWood -= req.wood;
        clan.vaultIron -= req.iron;
        clan.vaultWheat -= req.wheat;
        clan.vaultFish -= req.fish;

        cs.carryWood += req.wood;
        cs.carryIron += req.iron;
        cs.carryWheat += req.wheat;
        cs.carryFish += req.fish;

        emit ResourcesWithdrawn(clanId, cs.clansmanId, req.wood, req.iron, req.wheat, req.fish, tick);
        _completeMission(cs, m);
    }

    function _doBuilding(
        Clan storage clan,
        Clansman storage cs,
        Mission storage m,
        uint32 clanId,
        uint64 tick,
        ActionType action
    ) internal {
        // Must be at homebase
        if (cs.currentRegion != clan.baseRegion) {
            _completeMission(cs, m);
            return;
        }

        bool finished = true;
        if (action == ActionType.UpgradeWall) {
            finished = _settleWallUpgrade(clan, cs.clansmanId, m.nonce, clanId, tick);
        } else if (action == ActionType.UpgradeBase) {
            finished = _settleBaseUpgrade(clan, cs.clansmanId, m.nonce, clanId, tick);
        } else if (action == ActionType.UpgradeMonument) {
            finished = _settleMonumentUpgrade(clan, cs.clansmanId, m.nonce, clanId, tick);
        }

        if (finished) {
            _completeMission(cs, m);
        }
    }

    function _settleWallUpgrade(Clan storage clan, uint32 clansmanId, uint64 missionNonce, uint32 clanId, uint64 tick)
        internal
        returns (bool)
    {
        WallUpgradeReservation storage reservation = _wallUpgradeReservations[clansmanId];
        if (!reservation.active || reservation.clanId != clanId || reservation.missionNonce != missionNonce) {
            return true;
        }

        WallUpgradeReservation memory held = reservation;
        if (clan.wallLevel >= WALL_MAX_LEVEL) {
            _clearWallUpgradeReservation(clansmanId);
            return true;
        }
        if (held.fromLevel != clan.wallLevel) {
            if (held.fromLevel < clan.wallLevel) _refundWallUpgradeReservation(clansmanId);
            return false;
        }

        (uint256 woodCost, uint256 ironCost) = _wallUpgradeCost(clan.wallLevel);
        uint256 woodDebit = _min(held.woodCost, woodCost);
        uint256 ironDebit = _min(held.ironCost, ironCost);
        if (clan.vaultWood < woodDebit || clan.vaultIron < ironDebit) return false;

        _clearWallUpgradeReservation(clansmanId);
        clan.vaultWood -= woodDebit;
        clan.vaultIron -= ironDebit;

        uint8 old = clan.wallLevel;
        clan.wallLevel = old + 1;
        emit WallLevelChanged(clanId, old, clan.wallLevel, tick);
        return true;
    }

    function _settleBaseUpgrade(Clan storage clan, uint32 clansmanId, uint64 missionNonce, uint32 clanId, uint64 tick)
        internal
        returns (bool)
    {
        BaseUpgradeReservation storage reservation = _baseUpgradeReservations[clansmanId];
        if (!reservation.active || reservation.clanId != clanId || reservation.missionNonce != missionNonce) {
            return true;
        }

        BaseUpgradeReservation memory held = reservation;
        if (clan.baseLevel >= BASE_MAX_LEVEL) {
            _clearBaseUpgradeReservation(clansmanId);
            return true;
        }
        if (held.fromLevel != clan.baseLevel) {
            if (held.fromLevel < clan.baseLevel) _refundBaseUpgradeReservation(clansmanId);
            return false;
        }

        (uint256 woodCost, uint256 ironCost, uint256 wheatCost) = _baseUpgradeCost(clan.baseLevel);
        uint256 woodDebit = _min(held.woodCost, woodCost);
        uint256 ironDebit = _min(held.ironCost, ironCost);
        uint256 wheatDebit = _min(held.wheatCost, wheatCost);
        if (clan.vaultWood < woodDebit || clan.vaultIron < ironDebit || clan.vaultWheat < wheatDebit) return false;

        _clearBaseUpgradeReservation(clansmanId);
        clan.vaultWood -= woodDebit;
        clan.vaultIron -= ironDebit;
        clan.vaultWheat -= wheatDebit;

        uint8 old = clan.baseLevel;
        clan.baseLevel = old + 1;
        emit BaseLevelChanged(clanId, old, clan.baseLevel, tick);
        return true;
    }

    function _settleMonumentUpgrade(
        Clan storage clan,
        uint32 clansmanId,
        uint64 missionNonce,
        uint32 clanId,
        uint64 tick
    ) internal returns (bool) {
        MonumentUpgradeReservation storage reservation = _monumentUpgradeReservations[clansmanId];
        if (!reservation.active || reservation.clanId != clanId || reservation.missionNonce != missionNonce) {
            return true;
        }

        MonumentUpgradeReservation memory held = reservation;
        if (clan.monumentLevel >= MONUMENT_MAX_LEVEL) {
            _clearMonumentUpgradeReservation(clansmanId);
            return true;
        }
        if (held.fromLevel != clan.monumentLevel) {
            if (held.fromLevel < clan.monumentLevel) _refundMonumentUpgradeReservation(clansmanId);
            return false;
        }

        (uint256 woodCost, uint256 ironCost, uint256 wheatCost, uint256 blueprintCost) =
            _monumentUpgradeCost(clan.monumentLevel);
        uint256 woodDebit = _min(held.woodCost, woodCost);
        uint256 ironDebit = _min(held.ironCost, ironCost);
        uint256 wheatDebit = _min(held.wheatCost, wheatCost);
        uint256 blueprintDebit = _min(held.blueprintCost, blueprintCost);
        if (
            clan.vaultWood < woodDebit || clan.vaultIron < ironDebit || clan.vaultWheat < wheatDebit
                || clan.blueprintBalance < blueprintDebit
        ) return false;

        _clearMonumentUpgradeReservation(clansmanId);
        clan.vaultWood -= woodDebit;
        clan.vaultIron -= ironDebit;
        clan.vaultWheat -= wheatDebit;
        clan.blueprintBalance -= blueprintDebit;

        uint8 old = clan.monumentLevel;
        clan.monumentLevel = old + 1;
        _recordMonumentReachTick(clanId, clan.monumentLevel, tick);
        emit MonumentLevelChanged(clanId, old, clan.monumentLevel, tick);
        return true;
    }

    function _recordMonumentReachTick(uint32 clanId, uint8 newLevel, uint64 tick) internal {
        if (newLevel == 0) return;
        if (_monumentLevelReachedAt[clanId][newLevel] == 0) {
            _monumentLevelReachedAt[clanId][newLevel] = tick;
        }
    }

    /// @dev Complete a mission: set worker to WAITING, set cooldown, mark mission inactive, emit event.
    function _completeMission(Clansman storage cs, Mission storage m) internal {
        cs.state = ClansmanState.WAITING;
        cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
        m.active = false;
        emit MissionCompleted(_clans[cs.clanId].clanId, cs.clansmanId, m.nonce, m.action);
    }

    // -------------------------------------------------------------------------
    // View-only settlement simulation
    // -------------------------------------------------------------------------

    function _simulateSettleToTick(uint32 clanId, uint64 toTick)
        internal
        view
        returns (SettlementSimulation memory sim)
    {
        sim.clan = _clans[clanId];
        if (sim.clan.clanId == ClanWorldConstants.CLAN_ID_NULL) return sim;

        uint32[] storage clansmanIds = _clanClansmanIds[clanId];
        sim.clansmen = new Clansman[](clansmanIds.length);
        sim.missions = new Mission[](clansmanIds.length);
        sim.simWallReservationCleared = new bool[](clansmanIds.length);
        sim.simBaseReservationCleared = new bool[](clansmanIds.length);
        sim.simMonumentReservationCleared = new bool[](clansmanIds.length);
        for (uint256 i = 0; i < clansmanIds.length; i++) {
            uint32 clansmanId = clansmanIds[i];
            sim.clansmen[i] = _clansmen[clansmanId];
            sim.missions[i] = _missions[clansmanId];
        }
        sim.wheatPlots[0] = _wheatPlots[clanId][0];
        sim.wheatPlots[1] = _wheatPlots[clanId][1];
        sim.reservedWheat = _reservedWheatByClan[clanId];

        uint64 fromTick = sim.clan.lastSettledTick;
        if (fromTick >= toTick) return sim;

        for (uint64 tick = fromTick; tick < toTick; tick++) {
            _simulateApplyUpkeep(sim, tick);
            if (sim.clan.clanState == ClanState.DEAD) break;

            _simulateRegrowWheatPlots(sim, tick);

            for (uint256 i = 0; i < sim.clansmen.length; i++) {
                _simulateSettleMissionForClansman(sim, i, tick, tick + 1);
            }
        }

        if (toTick > fromTick && !_isWinterActiveAt(toTick) && _isWinterActiveAt(toTick - 1)) {
            sim.clan.coldDamage = 0;
        }

        sim.clan.lastSettledTick = toTick;
    }

    function _simulateApplyUpkeep(SettlementSimulation memory sim, uint64 tick) internal view {
        bool winter = _isWinterActiveAt(tick);
        if (!winter && tick > 0 && _isWinterActiveAt(tick - 1)) {
            sim.clan.coldDamage = 0;
        }

        if (sim.clan.livingClansmen == 0) return;

        uint256 wheatNeeded = uint256(sim.clan.livingClansmen) * ClanWorldConstants.WHEAT_UPKEEP_PER_CLANSMAN;
        uint256 fishNeeded = uint256(sim.clan.livingClansmen) * ClanWorldConstants.FISH_UPKEEP_PER_CLANSMAN;
        if (winter) {
            wheatNeeded = wheatNeeded * ClanWorldConstants.WINTER_UPKEEP_MULTIPLIER_BPS / 10000;
            fishNeeded = fishNeeded * ClanWorldConstants.WINTER_UPKEEP_MULTIPLIER_BPS / 10000;
        }

        uint256 spendableWheat = sim.clan.vaultWheat > sim.reservedWheat ? sim.clan.vaultWheat - sim.reservedWheat : 0;
        bool hadEnoughWheat = spendableWheat >= wheatNeeded;
        bool hadEnoughFish = sim.clan.vaultFish >= fishNeeded;

        if (hadEnoughWheat) {
            sim.clan.vaultWheat -= wheatNeeded;
        } else {
            sim.clan.vaultWheat -= spendableWheat;
        }
        sim.clan.vaultFish = hadEnoughFish ? sim.clan.vaultFish - fishNeeded : 0;

        bool starving = !hadEnoughWheat || !hadEnoughFish;
        if (starving && sim.clan.starvationStartsAtTick == 0) {
            sim.clan.starvationStartsAtTick = tick;
        } else if (!starving && sim.clan.starvationStartsAtTick != 0) {
            sim.clan.starvationStartsAtTick = 0;
        }

        uint8 livingBeforeStarvation = sim.clan.livingClansmen;
        if (winter && starving) {
            (, uint64 winterStartsAtTick,) = _winterWindowForTick(tick);
            uint64 effectiveStarvationStartsAtTick = sim.clan.starvationStartsAtTick > winterStartsAtTick
                ? sim.clan.starvationStartsAtTick
                : winterStartsAtTick;
            if (effectiveStarvationStartsAtTick < tick) {
                _simulateKillNextClansmanFromStarvation(sim);
            }
        }
        if (sim.clan.clanState == ClanState.DEAD) return;

        if (winter) {
            uint256 woodNeeded = ClanWorldConstants.WINTER_WOOD_BURN_PER_BASE + uint256(livingBeforeStarvation)
                * ClanWorldConstants.WINTER_WOOD_BURN_PER_CLANSMAN;
            if (sim.clan.vaultWood >= woodNeeded) {
                sim.clan.vaultWood -= woodNeeded;
            } else {
                sim.clan.vaultWood = 0;
                uint16 oldColdDamage = sim.clan.coldDamage;
                if (sim.clan.coldDamage < type(uint16).max) {
                    sim.clan.coldDamage += 1;
                }
                _simulateApplyColdDamageConsequence(sim, tick, oldColdDamage);
            }
        }
    }

    function _simulateApplyColdDamageConsequence(SettlementSimulation memory sim, uint64 tick, uint16 oldColdDamage)
        internal
        view
    {
        uint16 newColdDamage = sim.clan.coldDamage;
        if (newColdDamage == oldColdDamage) return;

        if (sim.clan.wallLevel > 0) {
            if (
                newColdDamage / ClanWorldConstants.COLD_DAMAGE_PER_WALL_DEGRADATION
                    <= oldColdDamage / ClanWorldConstants.COLD_DAMAGE_PER_WALL_DEGRADATION
            ) return;

            sim.clan.wallLevel--;
            return;
        }

        if (
            newColdDamage / ClanWorldConstants.COLD_DAMAGE_PER_CLANSMAN_DEATH
                <= oldColdDamage / ClanWorldConstants.COLD_DAMAGE_PER_CLANSMAN_DEATH
        ) return;

        _simulateKillRandomClansmanFromCold(sim, tick, newColdDamage);
    }

    function _simulateKillRandomClansmanFromCold(SettlementSimulation memory sim, uint64 tick, uint16 coldDamage)
        internal
        view
    {
        if (sim.clan.livingClansmen == 0) return;

        uint256 livingCount = 0;
        for (uint256 i = 0; i < sim.clansmen.length; i++) {
            if (sim.clansmen[i].state != ClansmanState.DEAD) {
                livingCount++;
            }
        }
        if (livingCount == 0) return;

        uint256 pick = RNG.rngBounded(
            _tickSeeds[tick],
            RNG.DOMAIN_COLD_DAMAGE,
            uint256(keccak256(abi.encodePacked(sim.clan.clanId, tick, coldDamage))),
            livingCount
        );

        uint256 seen = 0;
        for (uint256 i = 0; i < sim.clansmen.length; i++) {
            if (sim.clansmen[i].state == ClansmanState.DEAD) continue;
            if (seen != pick) {
                seen++;
                continue;
            }

            _simulateMarkClansmanDead(sim, i);
            if (sim.clan.livingClansmen == 0) {
                _simulateMarkClanDead(sim);
            }
            return;
        }
    }

    function _simulateKillNextClansmanFromStarvation(SettlementSimulation memory sim) internal pure {
        if (sim.clan.livingClansmen == 0) return;

        for (uint256 i = 0; i < sim.clansmen.length; i++) {
            if (sim.clansmen[i].state == ClansmanState.DEAD) continue;

            _simulateMarkClansmanDead(sim, i);
            if (sim.clan.livingClansmen == 0) {
                _simulateMarkClanDead(sim);
            }
            return;
        }
    }

    function _simulateMarkClansmanDead(SettlementSimulation memory sim, uint256 index) internal pure {
        if (sim.clansmen[index].state == ClansmanState.DEAD) return;

        sim.clansmen[index].state = ClansmanState.DEAD;
        sim.clansmen[index].cooldownEndsAtTs = 0;
        if (sim.clan.livingClansmen > 0) {
            sim.clan.livingClansmen--;
        }
        if (sim.missions[index].active) {
            sim.missions[index].active = false;
        }
    }

    function _simulateMarkClanDead(SettlementSimulation memory sim) internal pure {
        if (sim.clan.clanId == ClanWorldConstants.CLAN_ID_NULL || sim.clan.clanState == ClanState.DEAD) return;

        sim.clan.clanState = ClanState.DEAD;
        sim.clan.vaultWood = 0;
        sim.clan.vaultWheat = 0;
        sim.clan.vaultFish = 0;
        sim.clan.vaultIron = 0;
        sim.clan.starvationStartsAtTick = 0;
        sim.clan.livingClansmen = 0;

        for (uint256 i = 0; i < sim.clansmen.length; i++) {
            sim.clansmen[i].state = ClansmanState.DEAD;
            sim.clansmen[i].cooldownEndsAtTs = 0;
            if (sim.missions[i].active) {
                sim.missions[i].active = false;
            }
        }
    }

    function _simulateRegrowWheatPlots(SettlementSimulation memory sim, uint64 tick) internal pure {
        for (uint256 pi = 0; pi < 2; pi++) {
            WheatPlot memory plot = sim.wheatPlots[pi];
            if (plot.state == WheatPlotState.Regrowing && tick >= plot.regrowUntilTick) {
                plot.state = WheatPlotState.Harvestable;
                plot.remainingWheat = ClanWorldConstants.WHEAT_PLOT_STARTING_WHEAT;
                plot.regrowUntilTick = 0;
                sim.wheatPlots[pi] = plot;
            }
        }
    }

    function _simulateSettleMissionForClansman(
        SettlementSimulation memory sim,
        uint256 index,
        uint64 fromTick,
        uint64 toTick
    ) internal view {
        Clansman memory cs = sim.clansmen[index];
        Mission memory m = sim.missions[index];

        if (cs.state == ClansmanState.DEAD) {
            if (m.active) {
                m.active = false;
            }
            sim.missions[index] = m;
            return;
        }

        if (!m.active) return;

        for (uint64 tick = fromTick; tick < toTick; tick++) {
            bytes32 tickSeed = _tickSeeds[tick];

            if (cs.state == ClansmanState.TRAVELING && tick >= m.arrivalTick) {
                cs.state = ClansmanState.ACTING;
                cs.currentRegion = m.targetRegion;
            }

            if (m.action == ActionType.DefendBase) continue;

            if (cs.state == ClansmanState.ACTING && tick >= m.settlesAtTick) {
                (cs, m) = _simulateResolveAction(sim, cs, m, tick, tickSeed);
                if (m.active && getActionDuration(m.action) > 0) {
                    m.settlesAtTick = _addTicksClamped(tick, getActionDuration(m.action));
                }
            }

            if (!m.active) break;
        }

        sim.clansmen[index] = cs;
        sim.missions[index] = m;
    }

    function _simulateResolveAction(
        SettlementSimulation memory sim,
        Clansman memory cs,
        Mission memory m,
        uint64 tick,
        bytes32 tickSeed
    ) internal view returns (Clansman memory, Mission memory) {
        bool starving =
            sim.clan.starvationStartsAtTick != 0 && sim.clan.starvationStartsAtTick <= _world.currentTick;
        ActionType action = m.action;

        if (action == ActionType.ChopWood) {
            (cs, m) = _simulateGatherWood(cs, m, tick, starving, tickSeed);
        } else if (action == ActionType.MineIron) {
            (cs, m) = _simulateGatherIron(sim, cs, m, tick, starving, tickSeed);
        } else if (action == ActionType.FishDocks) {
            (cs, m) = _simulateGatherFish(cs, m, tick, starving, tickSeed, ClanWorldConstants.FISH_DOCKS_BPS);
        } else if (action == ActionType.FishDeepSea) {
            (cs, m) = _simulateGatherFish(cs, m, tick, starving, tickSeed, ClanWorldConstants.FISH_DEEP_BPS);
        } else if (action == ActionType.HarvestWheat) {
            (cs, m) = _simulateGatherWheat(sim, cs, m, tick, starving);
        } else if (action == ActionType.DepositResources) {
            (cs, m) = _simulateDoDeposit(sim, cs, m);
        } else if (action == ActionType.WithdrawResources) {
            (cs, m) = _simulateDoWithdrawResources(sim, cs, m);
        } else if (
            action == ActionType.UpgradeWall || action == ActionType.UpgradeBase || action == ActionType.UpgradeMonument
        ) {
            (cs, m) = _simulateDoBuilding(sim, cs, m, action, tick);
        } else if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
            (cs, m) = _simulateCompleteMission(cs, m);
        }

        return (cs, m);
    }

    function _simulateGatherWood(Clansman memory cs, Mission memory m, uint64 tick, bool starving, bytes32 tickSeed)
        internal
        view
        returns (Clansman memory, Mission memory)
    {
        uint256 remaining = ClanWorldConstants.WOOD_CAP - cs.carryWood;
        if (remaining == 0) return _simulateCompleteMission(cs, m);

        uint256 yield = ClanWorldConstants.WOOD_BASE_YIELD;
        bytes32 critRng = keccak256(abi.encode("wood_crit", tickSeed, cs.clansmanId, m.nonce, tick));
        if (uint256(critRng) % 10000 < ClanWorldConstants.WOOD_CRIT_BPS) {
            yield += ClanWorldConstants.WOOD_CRIT_BONUS;
        }
        if (starving) yield = yield / 2;
        if (yield > remaining) yield = remaining;
        cs.carryWood += yield;

        if (cs.carryWood >= ClanWorldConstants.WOOD_CAP) {
            return _simulateCompleteMission(cs, m);
        }
        return (cs, m);
    }

    function _simulateGatherIron(
        SettlementSimulation memory sim,
        Clansman memory cs,
        Mission memory m,
        uint64 tick,
        bool starving,
        bytes32 tickSeed
    ) internal view returns (Clansman memory, Mission memory) {
        uint256 remaining = ClanWorldConstants.IRON_CAP - cs.carryIron;
        if (remaining == 0) return _simulateCompleteMission(cs, m);

        uint256 yield = ClanWorldConstants.IRON_BASE_YIELD;
        if (starving) yield = yield / 2;
        if (yield > remaining) yield = remaining;
        cs.carryIron += yield;

        bytes32 goldRng = keccak256(abi.encode("iron_gold_bonus", tickSeed, cs.clansmanId, m.nonce, tick));
        if (uint256(goldRng) % 10000 < ClanWorldConstants.GOLD_FROM_IRON_BPS) {
            sim.clan.goldBalance += ClanWorldConstants.GOLD_FROM_IRON_AMOUNT;
        }

        if (cs.carryIron >= ClanWorldConstants.IRON_CAP) {
            return _simulateCompleteMission(cs, m);
        }
        return (cs, m);
    }

    function _simulateGatherFish(
        Clansman memory cs,
        Mission memory m,
        uint64 tick,
        bool starving,
        bytes32 tickSeed,
        uint256 successBps
    ) internal view returns (Clansman memory, Mission memory) {
        uint256 remaining = ClanWorldConstants.FISH_CAP - cs.carryFish;
        if (remaining == 0) return _simulateCompleteMission(cs, m);

        bytes32 fishRng = keccak256(abi.encode("fish_roll", tickSeed, cs.clansmanId, m.nonce, tick));
        uint256 yield = uint256(fishRng) % 10000 < successBps ? RESOURCE_UNIT : 0;
        if (starving) yield = yield / 2;
        if (yield > remaining) yield = remaining;
        if (yield > 0) {
            cs.carryFish += yield;
        }

        if (cs.carryFish >= ClanWorldConstants.FISH_CAP) {
            return _simulateCompleteMission(cs, m);
        }
        return (cs, m);
    }

    function _simulateGatherWheat(
        SettlementSimulation memory sim,
        Clansman memory cs,
        Mission memory m,
        uint64 tick,
        bool starving
    ) internal view returns (Clansman memory, Mission memory) {
        uint256 remaining = ClanWorldConstants.WHEAT_CAP - cs.carryWheat;
        if (remaining == 0) return _simulateCompleteMission(cs, m);

        uint256 plotIdx;
        if (m.targetRegion == ClanWorldConstants.REGION_WEST_FARMS) {
            plotIdx = 0;
        } else if (m.targetRegion == ClanWorldConstants.REGION_EAST_FARMS) {
            plotIdx = 1;
        } else {
            return _simulateCompleteMission(cs, m);
        }

        WheatPlot memory plot = sim.wheatPlots[plotIdx];
        if (plot.state != WheatPlotState.Harvestable || plot.remainingWheat == 0) {
            return _simulateCompleteMission(cs, m);
        }

        uint256 yield = WHEAT_HARVEST_RATE;
        if (starving) yield = yield / 2;
        if (yield > remaining) yield = remaining;
        if (yield > plot.remainingWheat) yield = plot.remainingWheat;

        cs.carryWheat += yield;
        plot.remainingWheat -= yield;

        if (plot.remainingWheat == 0) {
            plot.state = WheatPlotState.Regrowing;
            plot.regrowUntilTick = _addTicksClamped(tick, ClanWorldConstants.WHEAT_PLOT_REGROW_TICKS);
        }
        sim.wheatPlots[plotIdx] = plot;

        if (cs.carryWheat >= ClanWorldConstants.WHEAT_CAP || plot.remainingWheat == 0) {
            return _simulateCompleteMission(cs, m);
        }
        return (cs, m);
    }

    function _simulateDoDeposit(SettlementSimulation memory sim, Clansman memory cs, Mission memory m)
        internal
        view
        returns (Clansman memory, Mission memory)
    {
        if (cs.currentRegion != sim.clan.baseRegion) return _simulateCompleteMission(cs, m);

        bool hasAnything = cs.carryWood > 0 || cs.carryIron > 0 || cs.carryWheat > 0 || cs.carryFish > 0;
        if (!hasAnything) return _simulateCompleteMission(cs, m);

        sim.clan.vaultWood += cs.carryWood;
        sim.clan.vaultIron += cs.carryIron;
        sim.clan.vaultWheat += cs.carryWheat;
        sim.clan.vaultFish += cs.carryFish;

        cs.carryWood = 0;
        cs.carryIron = 0;
        cs.carryWheat = 0;
        cs.carryFish = 0;

        return _simulateCompleteMission(cs, m);
    }

    function _simulateDoWithdrawResources(SettlementSimulation memory sim, Clansman memory cs, Mission memory m)
        internal
        view
        returns (Clansman memory, Mission memory)
    {
        if (cs.currentRegion != sim.clan.baseRegion) return _simulateCompleteMission(cs, m);

        WithdrawResourcesData memory req = m.withdrawResources;
        if (!_hasWithdrawRequest(req)) return _simulateCompleteMission(cs, m);

        uint256 spendableWood =
            _spendableAfterReleasing(sim.clan.vaultWood, _reservedWoodByClan[sim.clan.clanId], 0);
        uint256 spendableIron =
            _spendableAfterReleasing(sim.clan.vaultIron, _reservedIronByClan[sim.clan.clanId], 0);
        uint256 spendableWheat = sim.clan.vaultWheat > sim.reservedWheat ? sim.clan.vaultWheat - sim.reservedWheat : 0;

        if (
            spendableWood < req.wood || spendableIron < req.iron || spendableWheat < req.wheat
                || sim.clan.vaultFish < req.fish
        ) return _simulateCompleteMission(cs, m);

        if (
            req.wood > _remainingCapacity(cs.carryWood, ClanWorldConstants.WOOD_CAP)
                || req.iron > _remainingCapacity(cs.carryIron, ClanWorldConstants.IRON_CAP)
                || req.wheat > _remainingCapacity(cs.carryWheat, ClanWorldConstants.WHEAT_CAP)
                || req.fish > _remainingCapacity(cs.carryFish, ClanWorldConstants.FISH_CAP)
        ) return _simulateCompleteMission(cs, m);

        sim.clan.vaultWood -= req.wood;
        sim.clan.vaultIron -= req.iron;
        sim.clan.vaultWheat -= req.wheat;
        sim.clan.vaultFish -= req.fish;

        cs.carryWood += req.wood;
        cs.carryIron += req.iron;
        cs.carryWheat += req.wheat;
        cs.carryFish += req.fish;

        return _simulateCompleteMission(cs, m);
    }

    function _simulateDoBuilding(
        SettlementSimulation memory sim,
        Clansman memory cs,
        Mission memory m,
        ActionType action,
        uint64 tick
    ) internal view returns (Clansman memory, Mission memory) {
        bool finished = true;
        if (cs.currentRegion == sim.clan.baseRegion) {
            if (action == ActionType.UpgradeWall) {
                finished = _simulateSettleWallUpgrade(sim, cs.clansmanId, m.nonce);
            } else if (action == ActionType.UpgradeBase) {
                finished = _simulateSettleBaseUpgrade(sim, cs.clansmanId, m.nonce);
            } else if (action == ActionType.UpgradeMonument) {
                finished = _simulateSettleMonumentUpgrade(sim, cs.clansmanId, m.nonce, tick);
            }
        }
        if (finished) return _simulateCompleteMission(cs, m);
        return (cs, m);
    }

    function _simulateSettleWallUpgrade(SettlementSimulation memory sim, uint32 clansmanId, uint64 missionNonce)
        internal
        view
        returns (bool)
    {
        if (_simUpgradeReservationCleared(sim, clansmanId, ActionType.UpgradeWall)) return true;
        WallUpgradeReservation memory held = _wallUpgradeReservations[clansmanId];
        if (!held.active || held.clanId != sim.clan.clanId || held.missionNonce != missionNonce) return true;
        if (sim.clan.wallLevel >= WALL_MAX_LEVEL) return true;
        if (held.fromLevel != sim.clan.wallLevel) {
            if (held.fromLevel < sim.clan.wallLevel) {
                _simClearUpgradeReservation(sim, clansmanId, ActionType.UpgradeWall);
            }
            return false;
        }

        (uint256 woodCost, uint256 ironCost) = _wallUpgradeCost(sim.clan.wallLevel);
        uint256 woodDebit = _min(held.woodCost, woodCost);
        uint256 ironDebit = _min(held.ironCost, ironCost);
        if (sim.clan.vaultWood < woodDebit || sim.clan.vaultIron < ironDebit) return false;

        sim.clan.vaultWood -= woodDebit;
        sim.clan.vaultIron -= ironDebit;
        sim.clan.wallLevel += 1;
        return true;
    }

    function _simulateSettleBaseUpgrade(SettlementSimulation memory sim, uint32 clansmanId, uint64 missionNonce)
        internal
        view
        returns (bool)
    {
        if (_simUpgradeReservationCleared(sim, clansmanId, ActionType.UpgradeBase)) return true;
        BaseUpgradeReservation memory held = _baseUpgradeReservations[clansmanId];
        if (!held.active || held.clanId != sim.clan.clanId || held.missionNonce != missionNonce) return true;
        if (sim.clan.baseLevel >= BASE_MAX_LEVEL) return true;
        if (held.fromLevel != sim.clan.baseLevel) {
            if (held.fromLevel < sim.clan.baseLevel) {
                _simClearUpgradeReservation(sim, clansmanId, ActionType.UpgradeBase);
                if (sim.reservedWheat >= held.wheatCost) sim.reservedWheat -= held.wheatCost;
                else sim.reservedWheat = 0;
            }
            return false;
        }

        (uint256 woodCost, uint256 ironCost, uint256 wheatCost) = _baseUpgradeCost(sim.clan.baseLevel);
        uint256 woodDebit = _min(held.woodCost, woodCost);
        uint256 ironDebit = _min(held.ironCost, ironCost);
        uint256 wheatDebit = _min(held.wheatCost, wheatCost);
        if (sim.clan.vaultWood < woodDebit || sim.clan.vaultIron < ironDebit || sim.clan.vaultWheat < wheatDebit) {
            return false;
        }

        sim.clan.vaultWood -= woodDebit;
        sim.clan.vaultIron -= ironDebit;
        sim.clan.vaultWheat -= wheatDebit;
        if (sim.reservedWheat >= wheatDebit) sim.reservedWheat -= wheatDebit;
        else sim.reservedWheat = 0;
        sim.clan.baseLevel += 1;
        return true;
    }

    function _simulateSettleMonumentUpgrade(
        SettlementSimulation memory sim,
        uint32 clansmanId,
        uint64 missionNonce,
        uint64 tick
    ) internal view returns (bool) {
        if (_simUpgradeReservationCleared(sim, clansmanId, ActionType.UpgradeMonument)) {
            return true;
        }
        MonumentUpgradeReservation memory held = _monumentUpgradeReservations[clansmanId];
        if (!held.active || held.clanId != sim.clan.clanId || held.missionNonce != missionNonce) return true;
        if (sim.clan.monumentLevel >= MONUMENT_MAX_LEVEL) return true;
        if (held.fromLevel != sim.clan.monumentLevel) {
            if (held.fromLevel < sim.clan.monumentLevel) {
                _simClearUpgradeReservation(sim, clansmanId, ActionType.UpgradeMonument);
                if (sim.reservedWheat >= held.wheatCost) sim.reservedWheat -= held.wheatCost;
                else sim.reservedWheat = 0;
            }
            return false;
        }

        (uint256 woodCost, uint256 ironCost, uint256 wheatCost, uint256 blueprintCost) =
            _monumentUpgradeCost(sim.clan.monumentLevel);
        uint256 woodDebit = _min(held.woodCost, woodCost);
        uint256 ironDebit = _min(held.ironCost, ironCost);
        uint256 wheatDebit = _min(held.wheatCost, wheatCost);
        uint256 blueprintDebit = _min(held.blueprintCost, blueprintCost);
        if (
            sim.clan.vaultWood < woodDebit || sim.clan.vaultIron < ironDebit || sim.clan.vaultWheat < wheatDebit
                || sim.clan.blueprintBalance < blueprintDebit
        ) return false;

        sim.clan.vaultWood -= woodDebit;
        sim.clan.vaultIron -= ironDebit;
        sim.clan.vaultWheat -= wheatDebit;
        sim.clan.blueprintBalance -= blueprintDebit;
        if (sim.reservedWheat >= wheatDebit) sim.reservedWheat -= wheatDebit;
        else sim.reservedWheat = 0;
        sim.clan.monumentLevel += 1;
        sim.simMonumentReachedAt[sim.clan.monumentLevel] = tick;
        return true;
    }

    function _simUpgradeReservationCleared(SettlementSimulation memory sim, uint32 clansmanId, ActionType action)
        internal
        pure
        returns (bool)
    {
        (uint256 index, bool found) = _simClansmanIndex(sim, clansmanId);
        if (!found) return false;
        if (action == ActionType.UpgradeWall) return sim.simWallReservationCleared[index];
        if (action == ActionType.UpgradeBase) return sim.simBaseReservationCleared[index];
        if (action == ActionType.UpgradeMonument) return sim.simMonumentReservationCleared[index];
        return false;
    }

    function _simClearUpgradeReservation(SettlementSimulation memory sim, uint32 clansmanId, ActionType action)
        internal
        pure
    {
        (uint256 index, bool found) = _simClansmanIndex(sim, clansmanId);
        if (!found) return;
        if (action == ActionType.UpgradeWall) {
            sim.simWallReservationCleared[index] = true;
        } else if (action == ActionType.UpgradeBase) {
            sim.simBaseReservationCleared[index] = true;
        } else if (action == ActionType.UpgradeMonument) {
            sim.simMonumentReservationCleared[index] = true;
        }
    }

    function _simClansmanIndex(SettlementSimulation memory sim, uint32 clansmanId)
        internal
        pure
        returns (uint256, bool)
    {
        for (uint256 i = 0; i < sim.clansmen.length; i++) {
            if (sim.clansmen[i].clansmanId == clansmanId) return (i, true);
        }
        return (0, false);
    }

    function _simulateCompleteMission(Clansman memory cs, Mission memory m)
        internal
        view
        returns (Clansman memory, Mission memory)
    {
        cs.state = ClansmanState.WAITING;
        cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
        m.active = false;
        return (cs, m);
    }

    // =========================================================================
    // BANDIT STATE MACHINE
    // =========================================================================

    function _spawnBandit(uint8 region, uint32 strength) internal returns (uint32 id) {
        return _spawnBandit(region, _tierForBanditAttackPower(strength), strength);
    }

    function _spawnBandit(uint8 region, uint8 tier, uint32 strength) internal returns (uint32 id) {
        require(
            region >= ClanWorldConstants.REGION_FOREST && region <= ClanWorldConstants.REGION_DEEP_SEA,
            "ClanWorld: invalid bandit region"
        );
        require(strength > 0, "ClanWorld: invalid bandit strength");

        id = _nextBanditId++;
        _bandits[id] = BanditTroop({
            id: id,
            region: region,
            state: BanditState.Spawned,
            targetClanId: 0,
            tickEnteredState: _world.currentTick,
            strength: strength,
            tier: tier,
            attackAttemptsMade: 0,
            carryWood: 0,
            carryIron: 0,
            carryWheat: 0,
            carryFish: 0,
            carryGold: 0
        });
        _banditsByRegion[region].push(id);
        _activeBanditCount += 1;

        BanditSpawnState storage spawnState = _banditSpawnByRegion[region];
        spawnState.lastSpawnTick = _world.currentTick;
        spawnState.probabilityAccum = 0;

        if (_world.activeBanditId == ClanWorldConstants.BANDIT_ID_NULL) {
            _world.activeBanditId = id;
        }

        emit BanditSpawned(id, region, tier, _banditStrengthForLegacyEvent(strength));
    }

    function _transitionBanditToAttacking(uint32 id, uint32 targetClanId) internal {
        require(targetClanId != ClanWorldConstants.CLAN_ID_NULL, "ClanWorld: invalid bandit target");
        _bandits[id].targetClanId = targetClanId;
        _transitionBanditState(id, BanditState.Attacking);
    }

    function _transitionBanditState(uint32 id, BanditState newState) internal {
        BanditTroop storage bandit = _bandits[id];
        require(bandit.id != ClanWorldConstants.BANDIT_ID_NULL, "ClanWorld: bandit not found");
        require(newState != BanditState.None, "ClanWorld: invalid bandit transition");

        BanditState oldState = bandit.state;
        require(_isValidBanditTransition(bandit, newState), "ClanWorld: invalid bandit transition");

        if (newState == BanditState.Defeated) {
            emit BanditStateChanged(id, oldState, newState, bandit.region, _world.currentTick);
            _deleteBandit(id);
            return;
        }

        bandit.state = newState;
        bandit.tickEnteredState = _world.currentTick;
        if (newState != BanditState.Attacking) {
            bandit.targetClanId = ClanWorldConstants.CLAN_ID_NULL;
        }

        emit BanditStateChanged(id, oldState, newState, bandit.region, _world.currentTick);

        if (oldState == BanditState.Resting && newState == BanditState.Camped) {
            _moveBanditToRampageNextRegion(id);
        }
    }

    function _isValidBanditTransition(BanditTroop storage bandit, BanditState newState) internal view returns (bool) {
        if (bandit.state == BanditState.Spawned) return _canBanditLeaveSpawned(bandit, newState);
        if (bandit.state == BanditState.Camped) return _canBanditLeaveCamped(bandit, newState);
        if (bandit.state == BanditState.Attacking) return _canBanditLeaveAttacking(newState);
        if (bandit.state == BanditState.Escaped) return _canBanditLeaveEscaped(newState);
        if (bandit.state == BanditState.Resting) return _canBanditLeaveResting(bandit, newState);
        return false;
    }

    function _canBanditLeaveSpawned(BanditTroop storage bandit, BanditState newState) internal view returns (bool) {
        return newState == BanditState.Escaped
            || (newState == BanditState.Camped && _world.currentTick >= bandit.tickEnteredState + 1);
    }

    function _canBanditLeaveCamped(BanditTroop storage bandit, BanditState newState) internal view returns (bool) {
        return newState == BanditState.Escaped || newState == BanditState.Resting
            || (newState == BanditState.Attacking
                && bandit.targetClanId != ClanWorldConstants.CLAN_ID_NULL
                && _world.currentTick >= bandit.tickEnteredState + ClanWorldConstants.BANDIT_CAMP_TICKS);
    }

    function _canBanditLeaveAttacking(BanditState newState) internal pure returns (bool) {
        return newState == BanditState.Defeated || newState == BanditState.Escaped || newState == BanditState.Resting;
    }

    function _canBanditLeaveEscaped(BanditState newState) internal pure returns (bool) {
        return newState == BanditState.Resting;
    }

    function _canBanditLeaveResting(BanditTroop storage bandit, BanditState newState) internal view returns (bool) {
        return newState == BanditState.Escaped
            || (newState == BanditState.Camped
                && _world.currentTick >= bandit.tickEnteredState + ClanWorldConstants.BANDIT_REST_TICKS);
    }

    function _moveBanditToRampageNextRegion(uint32 id) internal {
        BanditTroop storage bandit = _bandits[id];
        uint8 fromRegion = bandit.region;
        uint8 toRegion = _nextRampageRegion(fromRegion);
        if (fromRegion == toRegion) {
            return;
        }

        uint32[] storage fromBandits = _banditsByRegion[fromRegion];
        for (uint256 i = 0; i < fromBandits.length; i++) {
            if (fromBandits[i] == id) {
                fromBandits[i] = fromBandits[fromBandits.length - 1];
                fromBandits.pop();
                break;
            }
        }

        bandit.region = toRegion;
        _banditsByRegion[toRegion].push(id);
        emit BanditMoved(id, fromRegion, toRegion, _world.currentTick);

        _eagerSettleBanditCandidateRegion(toRegion);
    }

    function _nextRampageRegion(uint8 currentRegion) internal pure returns (uint8) {
        if (currentRegion == ClanWorldConstants.REGION_FOREST) return ClanWorldConstants.REGION_MOUNTAINS;
        if (currentRegion == ClanWorldConstants.REGION_MOUNTAINS) return ClanWorldConstants.REGION_EAST_FARMS;
        if (currentRegion == ClanWorldConstants.REGION_EAST_FARMS) return ClanWorldConstants.REGION_EAST_DOCKS;
        if (currentRegion == ClanWorldConstants.REGION_EAST_DOCKS) return ClanWorldConstants.REGION_WEST_DOCKS;
        if (currentRegion == ClanWorldConstants.REGION_WEST_DOCKS) return ClanWorldConstants.REGION_WEST_FARMS;
        return ClanWorldConstants.REGION_FOREST;
    }

    function _deleteBandit(uint32 id) internal {
        BanditTroop storage bandit = _bandits[id];
        uint8 region = bandit.region;
        uint32[] storage regionBandits = _banditsByRegion[region];
        for (uint256 i = 0; i < regionBandits.length; i++) {
            if (regionBandits[i] == id) {
                regionBandits[i] = regionBandits[regionBandits.length - 1];
                regionBandits.pop();
                break;
            }
        }

        delete _bandits[id];
        if (_activeBanditCount > 0) {
            _activeBanditCount -= 1;
        }
        if (_world.activeBanditId == id) {
            _world.activeBanditId = _findOldestActiveBandit();
        }
    }

    function _findOldestActiveBandit() internal view returns (uint32 oldestBanditId) {
        // V1 caps live troops at MAX_TOTAL_BANDITS = 1, so scanning the region
        // indexes is bounded even though storage mappings cannot be enumerated.
        for (uint8 region = ClanWorldConstants.REGION_FOREST; region <= ClanWorldConstants.REGION_DEEP_SEA; region++) {
            uint32[] storage regionBandits = _banditsByRegion[region];
            for (uint256 i = 0; i < regionBandits.length; i++) {
                uint32 candidateId = regionBandits[i];
                BanditTroop storage candidate = _bandits[candidateId];
                if (candidate.id == ClanWorldConstants.BANDIT_ID_NULL || candidate.state == BanditState.None) {
                    continue;
                }
                if (oldestBanditId == ClanWorldConstants.BANDIT_ID_NULL || candidateId < oldestBanditId) {
                    oldestBanditId = candidateId;
                }
            }
        }
    }

    function _advanceBanditStates(uint64 closedTick) internal {
        require(_world.currentTick == closedTick, "ClanWorld: bandit advance tick mismatch");
        for (uint8 region = ClanWorldConstants.REGION_FOREST; region <= ClanWorldConstants.REGION_DEEP_SEA; region++) {
            uint32[] storage regionBandits = _banditsByRegion[region];
            uint256 i = 0;
            while (i < regionBandits.length) {
                uint32 banditId = regionBandits[i];
                BanditTroop storage bandit = _bandits[banditId];
                uint8 regionBefore = bandit.region;
                if (bandit.state == BanditState.Spawned && closedTick > bandit.tickEnteredState) {
                    _transitionBanditState(banditId, BanditState.Camped);
                } else if (
                    bandit.state == BanditState.Camped
                        && closedTick >= bandit.tickEnteredState + ClanWorldConstants.BANDIT_CAMP_TICKS
                ) {
                    uint32 targetClanId = _pickBanditAttackTarget(bandit);
                    if (targetClanId == ClanWorldConstants.CLAN_ID_NULL) {
                        if (_recordBanditAttackAttempt(banditId) >= ClanWorldConstants.BANDIT_MAX_ATTACK_ATTEMPTS) {
                            _terminalEscapeBandit(banditId, closedTick);
                            continue;
                        }
                        _transitionBanditState(banditId, BanditState.Resting);
                    } else {
                        _transitionBanditToAttacking(banditId, targetClanId);
                    }
                } else if (
                    bandit.state == BanditState.Escaped
                        && closedTick >= bandit.tickEnteredState + ClanWorldConstants.BANDIT_REST_TICKS
                ) {
                    _transitionBanditState(banditId, BanditState.Resting);
                } else if (
                    bandit.state == BanditState.Resting
                        && closedTick >= bandit.tickEnteredState + ClanWorldConstants.BANDIT_REST_TICKS
                ) {
                    _transitionBanditState(banditId, BanditState.Camped);
                }

                if (_bandits[banditId].id == ClanWorldConstants.BANDIT_ID_NULL) {
                    continue;
                }
                if (regionBefore != _bandits[banditId].region) {
                    continue;
                }
                i++;
            }
        }
    }

    function _pickBanditAttackTarget(BanditTroop storage bandit) internal view returns (uint32 targetClanId) {
        uint256 bestLootValue;

        for (uint256 i = 0; i < _allClanIds.length; i++) {
            uint32 clanId = _allClanIds[i];
            Clan storage clan = _clans[clanId];
            if (clan.clanState == ClanState.DEAD || clan.baseRegion != bandit.region || clan.livingClansmen == 0) {
                continue;
            }

            uint256 lootValue = _lootValueRaw(clan);
            if (targetClanId == ClanWorldConstants.CLAN_ID_NULL || lootValue > bestLootValue) {
                bestLootValue = lootValue;
                targetClanId = clanId;
            } else if (lootValue == bestLootValue && clanId < targetClanId) {
                targetClanId = clanId;
            }
        }
    }

    function _recordBanditAttackAttempt(uint32 banditId) internal returns (uint8 attemptsMade) {
        BanditTroop storage bandit = _bandits[banditId];
        if (bandit.id == ClanWorldConstants.BANDIT_ID_NULL) {
            return 0;
        }
        attemptsMade = bandit.attackAttemptsMade + 1;
        bandit.attackAttemptsMade = attemptsMade;
    }

    function _terminalEscapeBandit(uint32 banditId, uint64 closedTick) internal {
        BanditTroop storage bandit = _bandits[banditId];
        if (bandit.id == ClanWorldConstants.BANDIT_ID_NULL) {
            return;
        }

        BanditState oldState = bandit.state;
        emit BanditStateChanged(banditId, oldState, BanditState.Escaped, bandit.region, closedTick);
        _burnBanditCarry(banditId);
        emit BanditEscaped(banditId, closedTick);
        _deleteBandit(banditId);
    }

    function _banditStrengthForLegacyEvent(uint32 strength) internal pure returns (uint16) {
        if (strength > type(uint16).max) return type(uint16).max;
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(strength);
    }

    function _resolveAttackingBandits(uint64 closedTick) internal {
        for (uint8 region = ClanWorldConstants.REGION_FOREST; region <= ClanWorldConstants.REGION_DEEP_SEA; region++) {
            uint32[] storage regionBandits = _banditsByRegion[region];
            uint256 i = 0;
            while (i < regionBandits.length) {
                uint32 banditId = regionBandits[i];
                BanditTroop storage bandit = _bandits[banditId];
                bool shouldResolve = bandit.state == BanditState.Attacking && bandit.tickEnteredState == closedTick;
                if (shouldResolve) {
                    _resolveBanditAttack(banditId, closedTick);
                    if (_bandits[banditId].id == ClanWorldConstants.BANDIT_ID_NULL) {
                        continue;
                    }
                }
                i++;
            }
        }
    }

    function _resolveBanditAttack(uint32 banditId, uint64 closedTick) internal {
        require(_world.currentTick == closedTick, "ClanWorld: bandit attack tick mismatch");

        BanditTroop storage bandit = _bandits[banditId];
        if (bandit.id == ClanWorldConstants.BANDIT_ID_NULL || bandit.state != BanditState.Attacking) {
            return;
        }
        if (bandit.tickEnteredState != closedTick) {
            return;
        }

        uint32 targetClanId = bandit.targetClanId;
        Clan storage targetClan = _clans[targetClanId];
        if (targetClan.clanId == ClanWorldConstants.CLAN_ID_NULL || targetClan.clanState == ClanState.DEAD) {
            _transitionBanditState(banditId, BanditState.Escaped);
            emit BanditEscaped(banditId, closedTick);
            return;
        }

        _settleClan(targetClanId);
        if (bandit.state != BanditState.Attacking || bandit.targetClanId != targetClanId) {
            return;
        }
        if (targetClan.clanState == ClanState.DEAD) {
            _transitionBanditState(banditId, BanditState.Escaped);
            emit BanditEscaped(banditId, closedTick);
            return;
        }
        if (targetClan.lastSettledTick < _world.currentTick) {
            _transitionBanditState(banditId, BanditState.Resting);
            return;
        }

        _eagerSettleActiveDefendersForBase(targetClanId, targetClan.baseRegion);
        if (
            bandit.state != BanditState.Attacking || bandit.targetClanId != targetClanId
                || targetClan.clanState == ClanState.DEAD
        ) {
            return;
        }

        bytes32 tickSeed = _world.currentTickSeed;
        uint32 banditAttackPower = bandit.strength;
        uint32 totalClansmanDefense = _totalBanditClansmanDefense(targetClanId);
        bool defeated = uint256(totalClansmanDefense) >= uint256(banditAttackPower) * 2;

        uint32 wallDamage;
        uint32 baseAbsorbed;
        uint32 clansmanDamageAbsorbed;
        uint256 stolenWood;
        uint256 stolenIron;
        uint256 stolenWheat;
        uint256 stolenFish;
        if (!defeated) {
            (stolenWood, stolenIron, stolenWheat, stolenFish) = _stealBanditVaultLoot(bandit, targetClan);
            uint32 incomingDamage =
                banditAttackPower > totalClansmanDefense ? banditAttackPower - totalClansmanDefense : 0;
            (incomingDamage, wallDamage) = _applyBanditWallDamage(targetClan, targetClanId, banditId, incomingDamage);
            (incomingDamage, baseAbsorbed) = _applyBanditBaseDefense(targetClan, incomingDamage);
            clansmanDamageAbsorbed =
                _applyBanditClansmanCasualties(targetClan, targetClanId, banditId, incomingDamage, tickSeed);
        }

        uint32 totalDefense = totalClansmanDefense + wallDamage + baseAbsorbed + clansmanDamageAbsorbed;
        emit BanditAttackResolved(
            banditId,
            targetClanId,
            defeated,
            _uint16Clamp(banditAttackPower),
            _uint16Clamp(totalDefense),
            targetClan.wallLevel,
            stolenWood,
            stolenIron,
            stolenWheat,
            stolenFish,
            closedTick
        );

        if (defeated) {
            emit BanditDefeated(banditId, targetClanId, closedTick);
            _distributeBanditLootToDefendingClans(banditId, targetClanId);
            targetClan.blueprintBalance += BLUEPRINT_UNIT;
            emit BlueprintEarned(targetClanId, banditId, BLUEPRINT_UNIT, closedTick);
            _transitionBanditState(banditId, BanditState.Defeated);
        } else {
            if (_recordBanditAttackAttempt(banditId) >= ClanWorldConstants.BANDIT_MAX_ATTACK_ATTEMPTS) {
                _terminalEscapeBandit(banditId, closedTick);
            } else {
                _transitionBanditState(banditId, BanditState.Resting);
            }
        }
    }

    function _distributeBanditLootToDefendingClans(uint32 banditId, uint32 targetClanId) internal {
        BanditTroop storage bandit = _bandits[banditId];
        DefenseContribution[] memory contributions = _banditDefenseContributions(targetClanId);
        uint256 nDefenders = contributions.length;
        uint32[] memory rewardedClanIds = new uint32[](nDefenders);

        uint256 dropWood = _banditLootDrop(bandit.carryWood);
        uint256 dropIron = _banditLootDrop(bandit.carryIron);
        uint256 dropWheat = _banditLootDrop(bandit.carryWheat);
        uint256 dropFish = _banditLootDrop(bandit.carryFish);
        uint256 dropGold = _banditLootDrop(bandit.carryGold);

        uint256 perWood;
        uint256 perIron;
        uint256 perWheat;
        uint256 perFish;
        uint256 perGold;
        uint256 distributedWood;
        uint256 distributedIron;
        uint256 distributedWheat;
        uint256 distributedFish;
        uint256 distributedGold;
        if (nDefenders > 0) {
            perWood = _perDefenderBanditLootShare(dropWood, nDefenders);
            perIron = _perDefenderBanditLootShare(dropIron, nDefenders);
            perWheat = _perDefenderBanditLootShare(dropWheat, nDefenders);
            perFish = _perDefenderBanditLootShare(dropFish, nDefenders);
            perGold = _perDefenderBanditLootShare(dropGold, nDefenders);

            for (uint256 i = 0; i < contributions.length; i++) {
                uint32 clansmanId = contributions[i].clansmanId;
                uint32 clanId = contributions[i].clanId;
                rewardedClanIds[i] = clanId;

                Clansman storage defender = _clansmen[clansmanId];
                uint256 addedWood = _addClansmanCarryCapped(defender.carryWood, perWood, ClanWorldConstants.WOOD_CAP);
                uint256 addedIron = _addClansmanCarryCapped(defender.carryIron, perIron, ClanWorldConstants.IRON_CAP);
                uint256 addedWheat =
                    _addClansmanCarryCapped(defender.carryWheat, perWheat, ClanWorldConstants.WHEAT_CAP);
                uint256 addedFish = _addClansmanCarryCapped(defender.carryFish, perFish, ClanWorldConstants.FISH_CAP);

                defender.carryWood += addedWood;
                defender.carryIron += addedIron;
                defender.carryWheat += addedWheat;
                defender.carryFish += addedFish;
                _clans[clanId].goldBalance += perGold;

                distributedWood += addedWood;
                distributedIron += addedIron;
                distributedWheat += addedWheat;
                distributedFish += addedFish;
                distributedGold += perGold;

                emit LootDistributedToDefender(
                    banditId, clanId, clansmanId, addedWood, addedIron, addedWheat, addedFish
                );
            }
        }

        emit LootDistributed(
            banditId,
            rewardedClanIds,
            perWood,
            perWheat,
            perFish,
            perIron,
            perGold,
            bandit.carryWood - distributedWood,
            bandit.carryWheat - distributedWheat,
            bandit.carryFish - distributedFish,
            bandit.carryIron - distributedIron,
            bandit.carryGold - distributedGold
        );
    }

    function _burnBanditCarry(uint32 banditId) internal {
        BanditTroop storage bandit = _bandits[banditId];
        uint32[] memory rewardedClanIds = new uint32[](0);
        emit LootDistributed(
            banditId,
            rewardedClanIds,
            0,
            0,
            0,
            0,
            0,
            bandit.carryWood,
            bandit.carryWheat,
            bandit.carryFish,
            bandit.carryIron,
            bandit.carryGold
        );
    }

    function _stealBanditVaultLoot(BanditTroop storage bandit, Clan storage targetClan)
        internal
        returns (uint256 stolenWood, uint256 stolenIron, uint256 stolenWheat, uint256 stolenFish)
    {
        stolenWood = _banditStealAmount(targetClan.vaultWood);
        stolenIron = _banditStealAmount(targetClan.vaultIron);
        stolenWheat = _banditStealAmount(targetClan.vaultWheat);
        stolenFish = _banditStealAmount(targetClan.vaultFish);

        targetClan.vaultWood -= stolenWood;
        targetClan.vaultIron -= stolenIron;
        targetClan.vaultWheat -= stolenWheat;
        targetClan.vaultFish -= stolenFish;

        bandit.carryWood += stolenWood;
        bandit.carryIron += stolenIron;
        bandit.carryWheat += stolenWheat;
        bandit.carryFish += stolenFish;
    }

    function _banditStealAmount(uint256 vaultAmount) internal pure returns (uint256) {
        return (vaultAmount * ClanWorldConstants.BANDIT_BASE_STEAL_BPS) / 10000;
    }

    function _banditLootDrop(uint256 carryAmount) internal pure returns (uint256) {
        return (carryAmount * ClanWorldConstants.BANDIT_DROP_TO_DEFENDERS_BPS) / 10000;
    }

    function _perDefenderBanditLootShare(uint256 loot, uint256 nDefenders) internal pure returns (uint256) {
        if (nDefenders == 1) {
            return loot;
        }
        return ((loot / RESOURCE_UNIT) / nDefenders) * RESOURCE_UNIT;
    }

    function _addClansmanCarryCapped(uint256 currentCarry, uint256 amount, uint256 carryCap)
        internal
        pure
        returns (uint256)
    {
        if (currentCarry >= carryCap) return 0;
        uint256 remaining = carryCap - currentCarry;
        return amount < remaining ? amount : remaining;
    }

    function _activeDefendingClanIds(uint32 targetClanId) internal view returns (uint32[] memory clanIds) {
        uint8 targetRegion = _clans[targetClanId].baseRegion;
        uint32[] storage defendingClans = _defendingClansByRegion[targetRegion];
        uint256 count;

        for (uint256 i = 0; i < defendingClans.length; i++) {
            if (_clanHasActiveDefenderForTarget(defendingClans[i], targetClanId, targetRegion)) {
                count++;
            }
        }

        clanIds = new uint32[](count);
        uint256 out;
        for (uint256 i = 0; i < defendingClans.length; i++) {
            uint32 defenderClanId = defendingClans[i];
            if (_clanHasActiveDefenderForTarget(defenderClanId, targetClanId, targetRegion)) {
                clanIds[out++] = defenderClanId;
            }
        }
    }

    function _banditDefenseContributions(uint32 targetClanId)
        internal
        view
        returns (DefenseContribution[] memory contributions)
    {
        uint256 count = _countBanditDefenseContributions(targetClanId);
        contributions = new DefenseContribution[](count);
        uint256 out;

        uint8 targetRegion = _clans[targetClanId].baseRegion;
        uint32[] storage defendingClans = _defendingClansByRegion[targetRegion];
        for (uint256 i = 0; i < defendingClans.length; i++) {
            uint32 defenderClanId = defendingClans[i];
            Clan storage defenderClan = _clans[defenderClanId];
            if (defenderClan.clanState == ClanState.DEAD || _isStarving(defenderClan)) {
                continue;
            }

            uint32[] storage clansmanIds = _clanClansmanIds[defenderClanId];
            for (uint256 j = 0; j < clansmanIds.length; j++) {
                uint32 clansmanId = clansmanIds[j];
                Clansman storage cs = _clansmen[clansmanId];
                Mission storage mission = _missions[clansmanId];
                if (_isExplicitBanditDefender(cs, mission, targetClanId, targetRegion)) {
                    contributions[out++] = DefenseContribution({
                        clansmanId: clansmanId, clanId: defenderClanId, defensePoints: uint16(DEFEND_BASE_DEFENSE)
                    });
                }
            }
        }

        Clan storage targetClan = _clans[targetClanId];
        if (targetClan.clanState != ClanState.DEAD && !_isStarving(targetClan)) {
            uint32[] storage targetClansmen = _clanClansmanIds[targetClanId];
            for (uint256 i = 0; i < targetClansmen.length; i++) {
                uint32 clansmanId = targetClansmen[i];
                Clansman storage cs = _clansmen[clansmanId];
                if (cs.state == ClansmanState.WAITING && cs.currentRegion == targetRegion) {
                    contributions[out++] = DefenseContribution({
                        clansmanId: clansmanId, clanId: targetClanId, defensePoints: uint16(WAITING_HOME_DEFENSE)
                    });
                }
            }
        }
    }

    function _countBanditDefenseContributions(uint32 targetClanId) internal view returns (uint256 count) {
        uint8 targetRegion = _clans[targetClanId].baseRegion;
        uint32[] storage defendingClans = _defendingClansByRegion[targetRegion];
        for (uint256 i = 0; i < defendingClans.length; i++) {
            uint32 defenderClanId = defendingClans[i];
            Clan storage defenderClan = _clans[defenderClanId];
            if (defenderClan.clanState == ClanState.DEAD || _isStarving(defenderClan)) {
                continue;
            }

            uint32[] storage clansmanIds = _clanClansmanIds[defenderClanId];
            for (uint256 j = 0; j < clansmanIds.length; j++) {
                Clansman storage cs = _clansmen[clansmanIds[j]];
                Mission storage mission = _missions[clansmanIds[j]];
                if (_isExplicitBanditDefender(cs, mission, targetClanId, targetRegion)) {
                    count++;
                }
            }
        }

        Clan storage targetClan = _clans[targetClanId];
        if (targetClan.clanState == ClanState.DEAD || _isStarving(targetClan)) {
            return count;
        }

        uint32[] storage targetClansmen = _clanClansmanIds[targetClanId];
        for (uint256 i = 0; i < targetClansmen.length; i++) {
            Clansman storage cs = _clansmen[targetClansmen[i]];
            if (cs.state == ClansmanState.WAITING && cs.currentRegion == targetRegion) {
                count++;
            }
        }
    }

    function _clanHasActiveDefenderForTarget(uint32 defenderClanId, uint32 targetClanId, uint8 targetRegion)
        internal
        view
        returns (bool)
    {
        Clan storage defenderClan = _clans[defenderClanId];
        if (defenderClan.clanState == ClanState.DEAD || _isStarving(defenderClan)) {
            return false;
        }

        uint32[] storage clansmanIds = _clanClansmanIds[defenderClanId];
        for (uint256 i = 0; i < clansmanIds.length; i++) {
            uint32 clansmanId = clansmanIds[i];
            Clansman storage cs = _clansmen[clansmanId];
            Mission storage mission = _missions[clansmanId];
            if (_isExplicitBanditDefender(cs, mission, targetClanId, targetRegion)) {
                return true;
            }
        }
        return false;
    }

    function _isExplicitBanditDefender(
        Clansman storage cs,
        Mission storage mission,
        uint32 targetClanId,
        uint8 targetRegion
    ) internal view returns (bool) {
        return cs.state == ClansmanState.ACTING && cs.currentRegion == targetRegion && mission.active
            && mission.action == ActionType.DefendBase && mission.targetClanId == targetClanId;
    }

    function _totalBanditClansmanDefense(uint32 targetClanId) internal view returns (uint32 totalDefense) {
        DefenseContribution[] memory contributions = _banditDefenseContributions(targetClanId);
        for (uint256 i = 0; i < contributions.length; i++) {
            totalDefense += contributions[i].defensePoints;
        }
    }

    function _applyBanditWallDamage(Clan storage clan, uint32 clanId, uint32 banditId, uint32 incomingDamage)
        internal
        returns (uint32 remainingDamage, uint32 wallDamage)
    {
        remainingDamage = incomingDamage;
        if (remainingDamage == 0 || clan.wallLevel == 0) {
            return (remainingDamage, 0);
        }

        wallDamage = remainingDamage < WALL_HP_PER_LEVEL ? remainingDamage : WALL_HP_PER_LEVEL;
        remainingDamage -= wallDamage;
        if (wallDamage >= WALL_HP_PER_LEVEL) {
            if (clan.wallLevel > 0) {
                clan.wallLevel--;
            }
            emit WallDamagedByBandit(clanId, clan.wallLevel, banditId);
        }
    }

    function _applyBanditBaseDefense(Clan storage clan, uint32 incomingDamage)
        internal
        view
        returns (uint32 remainingDamage, uint32 baseAbsorbed)
    {
        remainingDamage = incomingDamage;
        if (remainingDamage == 0 || clan.baseLevel == 0) {
            return (remainingDamage, 0);
        }

        uint32 baseDefense = uint32(clan.baseLevel) * BASE_HP_PER_LEVEL;
        baseAbsorbed = remainingDamage < baseDefense ? remainingDamage : baseDefense;
        remainingDamage -= baseAbsorbed;
    }

    function _applyBanditClansmanCasualties(
        Clan storage clan,
        uint32 clanId,
        uint32 banditId,
        uint32 incomingDamage,
        bytes32 tickSeed
    ) internal returns (uint32 damageAbsorbed) {
        uint32 remainingDamage = incomingDamage;
        uint32 killIndex = 0;
        while (remainingDamage > 0) {
            uint32 victimId = _pickBanditClansmanVictim(clanId, banditId, killIndex, tickSeed);
            if (victimId == 0) {
                break;
            }

            Clansman storage victim = _clansmen[victimId];
            _markClansmanDead(clan, victim);

            uint32 absorbed = remainingDamage < CLANSMAN_HP ? remainingDamage : CLANSMAN_HP;
            damageAbsorbed += absorbed;
            remainingDamage -= absorbed;
            emit ClansmanKilledByBandit(clanId, victimId, banditId);
            killIndex++;

            if (clan.livingClansmen == 0) {
                _markClanDead(clanId, "bandit", _world.currentTick, banditId);
                break;
            }
        }
    }

    function _pickBanditClansmanVictim(uint32 clanId, uint32 banditId, uint32 killIndex, bytes32 tickSeed)
        internal
        view
        returns (uint32 victimId)
    {
        uint32[] storage clansmanIds = _clanClansmanIds[clanId];
        uint256 livingCount;
        for (uint256 i = 0; i < clansmanIds.length; i++) {
            if (_clansmen[clansmanIds[i]].state != ClansmanState.DEAD) {
                livingCount++;
            }
        }
        if (livingCount == 0) {
            return 0;
        }

        uint256 pick =
            uint256(keccak256(abi.encode("bandit_clansman_kill", tickSeed, banditId, clanId, killIndex))) % livingCount;
        uint256 seen;
        for (uint256 i = 0; i < clansmanIds.length; i++) {
            uint32 candidateId = clansmanIds[i];
            if (_clansmen[candidateId].state == ClansmanState.DEAD) {
                continue;
            }
            if (seen == pick) {
                return candidateId;
            }
            seen++;
        }
    }

    function _clansmanDefenseDamageRoll(bytes32 tickSeed, uint32 banditId, uint32 clansmanId)
        internal
        pure
        returns (uint32)
    {
        return uint32(
            uint256(keccak256(abi.encode("clansman_defense", tickSeed, banditId, clansmanId)))
                % (CLANSMAN_MAX_DEFENSE_DAMAGE + 1)
        );
    }

    function _uint16Clamp(uint32 value) internal pure returns (uint16) {
        if (value > type(uint16).max) return type(uint16).max;
        return uint16(value);
    }

    function _evaluateBanditSpawns(bytes32 tickSeed) internal {
        uint256[] memory regionWeights = _banditSpawnRegionWeights();
        if (_activeBanditCount >= MAX_TOTAL_BANDITS) {
            _refreshBanditSpawnWorldPreview(regionWeights);
            return;
        }

        uint256[] memory candidateWeights = new uint256[](8);
        for (uint8 region = ClanWorldConstants.REGION_FOREST; region <= ClanWorldConstants.REGION_DEEP_SEA; region++) {
            uint256 weight = regionWeights[region - 1];
            if (weight == 0 || _banditsByRegion[region].length >= MAX_BANDITS_PER_REGION) {
                continue;
            }

            BanditSpawnState storage spawnState = _banditSpawnByRegion[region];
            if (_world.currentTick < spawnState.lastSpawnTick + MIN_SPAWN_COOLDOWN_TICKS) {
                continue;
            }

            spawnState.probabilityAccum = _incrementBanditSpawnProbability(spawnState.probabilityAccum);
            if (_banditSpawnRollPasses(tickSeed, region, spawnState.probabilityAccum)) {
                candidateWeights[region - 1] = weight;
            }
        }

        uint8 selectedRegion = _selectBanditSpawnRegion(tickSeed, candidateWeights);
        if (selectedRegion != ClanWorldConstants.REGION_NOOP) {
            // _spawnBandit resets only the selected region's accumulator; other
            // eligible regions retain their accumulated pressure for later ticks.
            uint8 tier = _banditSpawnTier(tickSeed, selectedRegion);
            _spawnBandit(selectedRegion, tier, getBanditAttackPower(tier));
        }

        _refreshBanditSpawnWorldPreview(regionWeights);
    }

    function _incrementBanditSpawnProbability(uint16 probabilityAccum) internal pure returns (uint16) {
        uint256 next = uint256(probabilityAccum) + BANDIT_SPAWN_PROBABILITY_INCREMENT_BPS;
        if (next > BANDIT_SPAWN_MAX_PROBABILITY_BPS) {
            return BANDIT_SPAWN_MAX_PROBABILITY_BPS;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(next);
    }

    function _banditSpawnRollPasses(bytes32 tickSeed, uint8 region, uint16 probabilityAccum)
        internal
        pure
        returns (bool)
    {
        return _banditSpawnRoll(tickSeed, region) < uint256(probabilityAccum);
    }

    function _banditSpawnRoll(bytes32 tickSeed, uint8 region) internal pure returns (uint256) {
        uint256 nonce = uint256(keccak256(abi.encodePacked("bandit_spawn", region)));
        return RNG.rngBounded(tickSeed, DOMAIN_BANDIT_SPAWN, nonce, 10000);
    }

    function _selectBanditSpawnRegion(bytes32 tickSeed, uint256[] memory weights) internal pure returns (uint8) {
        uint256 selected = RNG.rngWeightedPick(
            tickSeed, DOMAIN_BANDIT_SPAWN, uint256(keccak256(abi.encodePacked("bandit_spawn_region"))), weights
        );
        if (weights.length == 0 || weights[selected] == 0) {
            return ClanWorldConstants.REGION_NOOP;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(selected + 1);
    }

    function _banditSpawnTier(bytes32 tickSeed, uint8 region) internal pure returns (uint8) {
        uint256 nonce = uint256(keccak256(abi.encodePacked("bandit_spawn_tier", region)));
        uint256 roll = RNG.rngBounded(tickSeed, DOMAIN_BANDIT_SPAWN, nonce, BANDIT_TIER_COUNT);
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(roll + 1);
    }

    function getBanditAttackPower(uint8 tier) internal pure returns (uint16) {
        if (tier == 1) return 30;
        if (tier == 2) return 45;
        if (tier == 3) return 60;
        if (tier == 4) return 80;
        if (tier == 5) return 95;
        return 0;
    }

    function _tierForBanditAttackPower(uint32 attackPower) internal pure returns (uint8) {
        if (attackPower == 30) return 1;
        if (attackPower == 45) return 2;
        if (attackPower == 60) return 3;
        if (attackPower == 80) return 4;
        if (attackPower == 95) return 5;
        return 0;
    }

    function _eagerSettleForBandits(uint64 closedTick) internal {
        require(_world.currentTick == closedTick, "ClanWorld: eager settle tick mismatch");
        if (_activeBanditCount >= MAX_TOTAL_BANDITS) return;

        uint256[] memory regionWeights = _banditSpawnRegionWeights();
        for (uint8 region = ClanWorldConstants.REGION_FOREST; region <= ClanWorldConstants.REGION_DEEP_SEA; region++) {
            if (!_isBanditSpawnRegionCandidate(regionWeights, region)) {
                continue;
            }
            _eagerSettleBanditCandidateRegion(region);
        }
    }

    function _isBanditSpawnRegionCandidate(uint256[] memory regionWeights, uint8 region) internal view returns (bool) {
        if (regionWeights[region - 1] == 0 || _banditsByRegion[region].length >= MAX_BANDITS_PER_REGION) {
            return false;
        }

        BanditSpawnState storage spawnState = _banditSpawnByRegion[region];
        if (_world.currentTick < spawnState.lastSpawnTick + MIN_SPAWN_COOLDOWN_TICKS) {
            return false;
        }

        uint16 nextProbability = _incrementBanditSpawnProbability(spawnState.probabilityAccum);
        return _banditSpawnRollPasses(_world.currentTickSeed, region, nextProbability);
    }

    function _eagerSettleBanditCandidateRegion(uint8 region) internal {
        uint256 clanScanCount = _allClanIds.length < MAX_BANDIT_EAGER_SETTLE_BASE_SCAN_PER_REGION
            ? _allClanIds.length
            : MAX_BANDIT_EAGER_SETTLE_BASE_SCAN_PER_REGION;

        for (uint256 i = 0; i < clanScanCount; i++) {
            uint32 clanId = _allClanIds[i];
            Clan storage clan = _clans[clanId];
            if (clan.clanState == ClanState.DEAD || clan.baseRegion != region) {
                continue;
            }

            _settleClan(clanId);
            _eagerSettleActiveDefendersForBase(clanId, region);
        }
    }

    function _eagerSettleActiveDefendersForBase(uint32 targetClanId, uint8 region) internal {
        uint32[] storage defendingClans = _defendingClansByRegion[region];
        uint256 defendingClanScanCount = defendingClans.length < MAX_BANDIT_EAGER_SETTLE_DEFENDING_CLANS_PER_REGION
            ? defendingClans.length
            : MAX_BANDIT_EAGER_SETTLE_DEFENDING_CLANS_PER_REGION;
        uint256 defendersScanned;

        for (uint256 i = 0; i < defendingClanScanCount; i++) {
            uint32 defenderClanId = defendingClans[i];
            uint32[] storage clansmanIds = _clanClansmanIds[defenderClanId];

            for (
                uint256 j = 0;
                j < clansmanIds.length && defendersScanned < MAX_BANDIT_EAGER_SETTLE_DEFENDER_SCAN_PER_REGION;
                j++
            ) {
                defendersScanned += 1;
                Mission storage mission = _missions[clansmanIds[j]];
                if (mission.active && mission.action == ActionType.DefendBase && mission.targetClanId == targetClanId) {
                    _settleClan(defenderClanId);
                    break;
                }
            }

            if (defendersScanned >= MAX_BANDIT_EAGER_SETTLE_DEFENDER_SCAN_PER_REGION) {
                break;
            }
        }
    }

    function _banditSpawnRegionWeights() internal view returns (uint256[] memory weights) {
        weights = new uint256[](8);
        uint256 clanCount = _allClanIds.length;
        if (clanCount == 0) {
            return weights;
        }

        uint256 scanCount = clanCount < MAX_BANDIT_SPAWN_SCAN_PER_REGION ? clanCount : MAX_BANDIT_SPAWN_SCAN_PER_REGION;
        uint256 startIndex = uint256(_world.currentTick) % clanCount;
        uint256 clansmenScanned;
        for (uint256 i = 0; i < scanCount; i++) {
            Clan storage clan = _clans[_allClanIds[(startIndex + i) % clanCount]];
            if (clan.clanState == ClanState.DEAD) {
                continue;
            }

            if (
                clan.baseRegion >= ClanWorldConstants.REGION_FOREST
                    && clan.baseRegion <= ClanWorldConstants.REGION_DEEP_SEA
            ) {
                weights[clan.baseRegion - 1] += 100 + (_lootValueRaw(clan) / 1e18);
            }

            uint32[] storage clansmanIds = _clanClansmanIds[clan.clanId];
            for (
                uint256 j = 0;
                j < clansmanIds.length && clansmenScanned < MAX_BANDIT_SPAWN_CLANSMEN_SCAN_PER_REGION;
                j++
            ) {
                clansmenScanned += 1;
                Clansman storage cs = _clansmen[clansmanIds[j]];
                if (
                    cs.state != ClansmanState.DEAD && cs.currentRegion >= ClanWorldConstants.REGION_FOREST
                        && cs.currentRegion <= ClanWorldConstants.REGION_DEEP_SEA
                ) {
                    weights[cs.currentRegion - 1] += 25;
                }
            }
        }
    }

    function _refreshBanditSpawnWorldPreview(uint256[] memory regionWeights) internal {
        uint64 nextEligibleTick = type(uint64).max;
        uint16 maxChance = 0;

        for (uint8 region = ClanWorldConstants.REGION_FOREST; region <= ClanWorldConstants.REGION_DEEP_SEA; region++) {
            BanditSpawnState storage spawnState = _banditSpawnByRegion[region];
            uint64 eligibleTick = spawnState.lastSpawnTick + MIN_SPAWN_COOLDOWN_TICKS;
            if (
                _activeBanditCount < MAX_TOTAL_BANDITS && regionWeights[region - 1] > 0
                    && _banditsByRegion[region].length < MAX_BANDITS_PER_REGION && eligibleTick < nextEligibleTick
            ) {
                nextEligibleTick = eligibleTick;
            }
            if (spawnState.probabilityAccum > maxChance) {
                maxChance = spawnState.probabilityAccum;
            }
        }

        _world.nextBanditSpawnEligibleTick = nextEligibleTick == type(uint64).max ? 0 : nextEligibleTick;
        _world.currentBanditSpawnChanceBps = maxChance;
    }

    // =========================================================================
    // WORLD PROGRESSION
    // =========================================================================

    /// @notice Permissionless heartbeat. Closes the current tick, advances tick counter.
    ///         Execution order per spec §4.2 (CEI-safe):
    ///         CEI guard: nextHeartbeatAtTs written first to close reentrancy window.
    ///         1. Settle missions completing this tick.
    ///         2. Execute scheduled market actions for closedTick (external calls).
    ///         3. Eager-settle bases and defenders in bandit spawn-candidate regions.
    ///         4. Advance bandit timers for the closed tick.
    ///         5. Resolve closed-tick bandit attacks and deaths.
    ///         6. Spawn new bandits if spawn conditions are met.
    ///         7. Resolve world events (season boundary, winter transitions).
    ///         8. Increment tick and publish the next tick seed atomically.
    function heartbeat() external override nonReentrant {
        require(block.timestamp >= _world.nextHeartbeatAtTs, "ClanWorld: heartbeat rate limited");

        uint64 closedTick = _world.currentTick;
        bytes32 closedTickSeed = _world.currentTickSeed;

        // CEI: update rate-limit guard before any external calls
        _world.nextHeartbeatAtTs = uint64(block.timestamp) + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS;

        // Step 1: Settle missions that complete this tick (settlesAtTick == closedTick).
        // Bounded by 12-clan cap x 4 clansmen = 48 max iterations.
        _settleCompletingMissions(closedTick);

        // Step 2: Execute scheduled market actions for closedTick (may make external calls).
        _executeScheduledMarketActions(closedTick);

        // Step 3: Eager-settle bases and active defenders in bandit spawn-candidate regions.
        _eagerSettleForBandits(closedTick);

        // Step 4: Advance deterministic bandit timers for the closed tick.
        _advanceBanditStates(closedTick);

        // Step 5: Resolve deterministic bandit attacks for the closed tick.
        _resolveAttackingBandits(closedTick);

        // Step 6: Evaluate deterministic bandit spawns for the closed tick.
        _evaluateBanditSpawns(closedTickSeed);

        // Step 7: Resolve world events (season boundary, winter transitions).
        _resolveWorldEvents(closedTick);

        // Step 8: Increment tick and publish the opened tick seed as one visible state transition.
        uint64 newTick = closedTick + 1;
        bytes32 newSeed = keccak256(abi.encode(block.prevrandao, closedTickSeed, closedTick));
        _world.currentTick = newTick;
        _tickSeeds[newTick] = newSeed;
        _world.currentTickSeed = newSeed;
        _world.nextHeartbeatAtTick = newTick + 1;

        emit TickAdvanced(closedTick, newTick, newSeed);
    }

    /// @dev Settle missions that complete exactly at `tick` (settlesAtTick == tick).
    ///      Called from heartbeat before market execution and tick increment.
    ///      Bounded by 12-clan cap x 4 clansmen = 48 max iterations.
    function _settleCompletingMissions(uint64 tick) internal {
        for (uint256 i = 0; i < _allClanIds.length; i++) {
            uint32 clanId = _allClanIds[i];
            Clan storage clan = _clans[clanId];
            if (clan.clanState == ClanState.DEAD) continue;

            uint32[] storage csIds = _clanClansmanIds[clanId];
            for (uint256 j = 0; j < csIds.length; j++) {
                Clansman storage cs = _clansmen[csIds[j]];
                if (cs.state == ClansmanState.DEAD) continue;

                Mission storage m = _missions[cs.clansmanId];
                if (!m.active) continue;
                if (m.settlesAtTick != tick) continue; // not due this tick

                // Settle this mission using the single-tick range [tick, tick+1).
                _settleMissionForClansman(clan, cs, clanId, tick, tick + 1);
            }
        }
    }

    /// @dev Resolve world events for the tick that was just closed.
    ///      Uses closedTick+1 as the equivalent of the old `newTick` for transition checks.
    function _resolveWorldEvents(uint64 closedTick) internal {
        uint64 newTick = closedTick + 1;

        // --- season boundary ---
        if (newTick >= _world.seasonEndTick) {
            _world.currentSeasonNumber += 1;
            _world.seasonStartTick = _world.seasonEndTick;
            _world.seasonEndTick = _world.seasonStartTick + ClanWorldConstants.SEASON_DURATION_TICKS;
        }

        // --- winter transitions (timer only; mechanics = Phase 10) ---
        bool wasWinter = _isWinterActiveAt(closedTick);
        bool nowWinter = _isWinterActiveAt(newTick);
        if (!wasWinter && nowWinter) {
            _lockWheatPlotsForWinter();
            emit WinterStarted(_winterEventTick(newTick));
        }
        if (wasWinter && !nowWinter) {
            _restartWheatPlotsAfterWinter(newTick);
            emit WinterEnded(_winterEventTick(newTick));
        }
    }

    function _lockWheatPlotsForWinter() internal {
        uint256 transitions;
        for (uint256 i = 0; i < _allClanIds.length; i++) {
            uint32 clanId = _allClanIds[i];
            for (uint256 pi = 0; pi < 2; pi++) {
                require(transitions < MAX_CROP_TRANSITION_PER_TICK, "ClanWorld: crop transition cap");
                WheatPlot storage plot = _wheatPlots[clanId][pi];
                plot.state = WheatPlotState.WinterLocked;
                plot.remainingWheat = 0;
                plot.regrowUntilTick = 0;
                transitions++;
            }
        }
    }

    function _restartWheatPlotsAfterWinter(uint64 currentTick) internal {
        uint256 transitions;
        for (uint256 i = 0; i < _allClanIds.length; i++) {
            uint32 clanId = _allClanIds[i];
            for (uint256 pi = 0; pi < 2; pi++) {
                require(transitions < MAX_CROP_TRANSITION_PER_TICK, "ClanWorld: crop transition cap");
                WheatPlot storage plot = _wheatPlots[clanId][pi];
                if (plot.state == WheatPlotState.WinterLocked) {
                    plot.state = WheatPlotState.Regrowing;
                    plot.remainingWheat = 0;
                    plot.regrowUntilTick = currentTick + ClanWorldConstants.WHEAT_PLOT_REGROW_TICKS;
                }
                transitions++;
            }
        }
    }

    function _winterEventTick(uint64 tick) internal pure returns (uint64) {
        return tick;
    }

    function _isWinterActiveAt(uint64 tick) internal pure returns (bool) {
        if (tick < ClanWorldConstants.WINTER_START_TICK) {
            return false;
        }
        uint64 elapsed = tick - ClanWorldConstants.WINTER_START_TICK;
        return elapsed % ClanWorldConstants.WINTER_PERIOD_TICKS < ClanWorldConstants.WINTER_DURATION_TICKS;
    }

    function _winterWindowForTick(uint64 tick)
        internal
        pure
        returns (bool active, uint64 startsAtTick, uint64 endsAtTick)
    {
        if (tick < ClanWorldConstants.WINTER_START_TICK) {
            startsAtTick = ClanWorldConstants.WINTER_START_TICK;
            endsAtTick = ClanWorldConstants.WINTER_START_TICK + ClanWorldConstants.WINTER_DURATION_TICKS;
            return (false, startsAtTick, endsAtTick);
        }

        uint64 elapsed = tick - ClanWorldConstants.WINTER_START_TICK;
        uint64 cycleIndex = elapsed / ClanWorldConstants.WINTER_PERIOD_TICKS;
        uint64 cycleStart = ClanWorldConstants.WINTER_START_TICK + cycleIndex * ClanWorldConstants.WINTER_PERIOD_TICKS;
        active = elapsed % ClanWorldConstants.WINTER_PERIOD_TICKS < ClanWorldConstants.WINTER_DURATION_TICKS;
        startsAtTick = active ? cycleStart : cycleStart + ClanWorldConstants.WINTER_PERIOD_TICKS;
        endsAtTick = startsAtTick + ClanWorldConstants.WINTER_DURATION_TICKS;
    }

    function _worldStateView() internal view returns (WorldState memory ws) {
        ws.currentTick = _world.currentTick;
        ws.seasonStartTick = _world.seasonStartTick;
        ws.seasonEndTick = _world.seasonEndTick;
        ws.seasonFinalized = _world.seasonFinalized;
        ws.currentSeasonNumber = _world.currentSeasonNumber;
        ws.nextHeartbeatAtTick = _world.nextHeartbeatAtTick;
        ws.nextHeartbeatAtTs = _world.nextHeartbeatAtTs;
        ws.nextBanditSpawnEligibleTick = _world.nextBanditSpawnEligibleTick;
        ws.currentBanditSpawnChanceBps = _world.currentBanditSpawnChanceBps;
        ws.currentTickSeed = _world.currentTickSeed;
        ws.activeBanditId = _world.activeBanditId;
        ws.nextCommitSequence = _world.nextCommitSequence;
        (ws.winterActive, ws.winterStartsAtTick, ws.winterEndsAtTick) = _winterWindowForTick(_world.currentTick);
    }

    /// @notice Public settlement trigger — lazily settle a clan.
    function settleClan(uint32 clanId) external override nonReentrant {
        _settleClan(clanId);
    }

    /// @notice Lazily settle a single clansman's mission to current tick. Idempotent.
    ///         Internally settles the entire clan (including upkeep) to guarantee
    ///         correct ordering and prevent double-settlement. Callers may call this
    ///         or settleClan interchangeably; both are safe and idempotent.
    function settleClansman(uint32 clansmanId) external override nonReentrant {
        Clansman storage cs = _clansmen[clansmanId];
        if (cs.clansmanId == 0) return;
        _settleClan(cs.clanId);
    }

    /// @notice Finalize season. Phase 1 stub.
    function finalizeSeason() external override {
        // TODO Phase 3
    }

    // =========================================================================
    // CLAN LIFECYCLE
    // =========================================================================

    /// @notice Mint a new clan and spawn its homebase.
    function mintClan(address to) external override nonReentrant returns (uint32 clanId, uint256 iftTokenId) {
        require(to != address(0), "ClanWorld: zero address");
        require(_allClanIds.length < MAX_CLANS, "ClanWorld: max clans");
        clanId = _nextClanId++;
        iftTokenId = uint256(clanId); // Phase 1 placeholder; real iNFT is Phase 7

        // Assign homebase region: valid spawn regions are 1,2,4,5,6,7 (not 3=UnicornTown, not 8=DeepSea)
        uint8[6] memory spawnRegions = [
            ClanWorldConstants.REGION_FOREST,
            ClanWorldConstants.REGION_MOUNTAINS,
            ClanWorldConstants.REGION_WEST_FARMS,
            ClanWorldConstants.REGION_EAST_FARMS,
            ClanWorldConstants.REGION_WEST_DOCKS,
            ClanWorldConstants.REGION_EAST_DOCKS
        ];
        uint8 baseRegion = spawnRegions[(clanId - 1) % 6];

        // Create clan
        Clan storage clan = _clans[clanId];
        clan.clanId = clanId;
        clan.iftTokenId = iftTokenId;
        clan.owner = to;
        clan.clanState = ClanState.ACTIVE;
        clan.baseRegion = baseRegion;
        clan.baseLevel = 1;
        clan.wallLevel = 0;
        clan.monumentLevel = 0;
        clan.livingClansmen = 4;
        clan.lastSettledTick = _world.currentTick;
        clan.starvationStartsAtTick = 0;
        clan.coldDamage = 0;
        clan.goldBalance = 3e18; // starter gold per v4 spec §12.5
        clan.blueprintBalance = 0;
        // Starting vault per v4 spec §12.4
        clan.vaultWood = 20e18;
        clan.vaultIron = 0;
        clan.vaultWheat = 20e18;
        clan.vaultFish = 2e18;

        WheatPlotState startingPlotState =
            _isWinterActiveAt(_world.currentTick) ? WheatPlotState.WinterLocked : WheatPlotState.Harvestable;
        uint256 startingWheat =
            startingPlotState == WheatPlotState.WinterLocked ? 0 : ClanWorldConstants.WHEAT_PLOT_STARTING_WHEAT;

        // Wheat plots
        _wheatPlots[clanId][0] = WheatPlot({
            state: startingPlotState,
            region: ClanWorldConstants.REGION_WEST_FARMS,
            remainingWheat: startingWheat,
            regrowUntilTick: 0
        });
        _wheatPlots[clanId][1] = WheatPlot({
            state: startingPlotState,
            region: ClanWorldConstants.REGION_EAST_FARMS,
            remainingWheat: startingWheat,
            regrowUntilTick: 0
        });

        // Create 4 clansmen
        for (uint256 i = 0; i < 4; i++) {
            uint32 clansmanId = _nextClansmanId++;
            Clansman storage cs = _clansmen[clansmanId];
            cs.clansmanId = clansmanId;
            cs.clanId = clanId;
            cs.state = ClansmanState.WAITING;
            cs.currentRegion = baseRegion;
            cs.cooldownEndsAtTs = 0;
            cs.lastMissionNonce = 0;
            cs.carryWood = 0;
            cs.carryIron = 0;
            cs.carryWheat = 0;
            cs.carryFish = 0;
            _clanClansmanIds[clanId].push(clansmanId);
        }

        _allClanIds.push(clanId);

        emit ClanSpawned(clanId, to, iftTokenId, baseRegion, _world.currentTick);
        return (clanId, iftTokenId);
    }

    /// @notice Submit one or more orders for a clan's clansmen. Per-order failures don't revert.
    function submitClanOrders(uint32 clanId, ClanOrder[] calldata orders)
        external
        override
        nonReentrant
        returns (OrderResult[] memory results)
    {
        Clan storage clan = _clans[clanId];
        require(clan.clanId != 0, "ClanWorld: clan not found");
        require(clan.owner == msg.sender, "ClanWorld: not clan owner");
        require(clan.clanState == ClanState.ACTIVE, "ClanWorld: clan dead");

        // Guard: if clan is more than 200 ticks behind, caller must call settleClan() first
        // (_settleClan caps at 200 ticks per call; submitting into a partially-settled clan corrupts invariants)
        {
            uint64 lastSettled = _clans[clanId].lastSettledTick;
            if (_world.currentTick > lastSettled + MAX_LAZY_SETTLE_BACKLOG) {
                results = new OrderResult[](orders.length);
                for (uint256 i = 0; i < orders.length; i++) {
                    results[i] = OrderResult({
                        clansmanId: orders[i].clansmanId,
                        status: StatusCode.ERR_MUST_SETTLE_FIRST,
                        cooldownEndsAtTs: 0,
                        missionNonce: 0,
                        marketMode: MarketExecutionMode.None
                    });
                }
                return results;
            }
        }

        // Lazy settle before processing orders
        _settleClan(clanId);

        results = new OrderResult[](orders.length);
        if (clan.clanState == ClanState.DEAD) {
            for (uint256 i = 0; i < orders.length; i++) {
                results[i] = OrderResult({
                    clansmanId: orders[i].clansmanId,
                    status: StatusCode.ERR_CLAN_DEAD,
                    cooldownEndsAtTs: 0,
                    missionNonce: 0,
                    marketMode: MarketExecutionMode.None
                });
            }
            return results;
        }

        for (uint256 i = 0; i < orders.length; i++) {
            results[i] = _processOrder(clanId, clan, orders[i]);
        }

        return results;
    }

    struct OrderCtx {
        uint8 gotoRegion;
        uint8 fromRegion;
        bool isNoop;
        uint8 travelTicks;
        uint64 arrivalTick;
        uint64 newNonce;
        uint32 targetClanId;
        bool wasActive;
        uint64 oldNonce;
    }

    function _processOrder(uint32 clanId, Clan storage clan, ClanOrder calldata order)
        internal
        returns (OrderResult memory result)
    {
        result.clansmanId = order.clansmanId;

        // Validate clansman
        Clansman storage cs = _clansmen[order.clansmanId];
        if (cs.clansmanId == 0 || cs.clanId != clanId) {
            result.status = StatusCode.ERR_INVALID_CLANSMAN;
            return result;
        }
        if (cs.state == ClansmanState.DEAD) {
            result.status = StatusCode.ERR_CLANSMAN_DEAD;
            return result;
        }

        if (order.action == ActionType.DefendBase) {
            StatusCode defendErr = _validateDefendBaseOrder(clan, order, order.gotoRegion);
            if (defendErr != StatusCode.OK) {
                result.status = defendErr;
                return result;
            }

            uint32 defendTargetClanId = order.targetClanId == 0 ? clanId : order.targetClanId;
            Mission storage currentM = _missions[order.clansmanId];
            if (
                currentM.active && currentM.action == ActionType.DefendBase && currentM.targetRegion == order.gotoRegion
                    && currentM.targetClanId == defendTargetClanId
            ) {
                result.status = StatusCode.OK;
                result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
                result.missionNonce = currentM.nonce;
                return result;
            }
        }

        bool isMarketAction = order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell;

        // Cooldown check. Market orders may still fall back to the scheduled path;
        // only the immediate path requires the worker to be off cooldown.
        if (block.timestamp < cs.cooldownEndsAtTs) {
            result.status = StatusCode.ERR_COOLDOWN_ACTIVE;
            result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
            result.missionNonce = cs.lastMissionNonce;
            return result;
        }

        OrderCtx memory ctx;
        ctx.fromRegion = cs.currentRegion;
        ctx.gotoRegion = order.gotoRegion;
        ctx.targetClanId =
            order.action == ActionType.DefendBase && order.targetClanId == 0 ? clanId : order.targetClanId;

        // NOOP bypass: treat 0 as "stay here"; DefendBase requires the defended base region.
        ctx.isNoop = order.action != ActionType.DefendBase
            && (ctx.gotoRegion == ClanWorldConstants.REGION_NOOP || ctx.gotoRegion == ctx.fromRegion);
        if (ctx.isNoop) {
            ctx.gotoRegion = ctx.fromRegion;
        }

        // Validate target region (1-8 or 0=noop)
        if (ctx.gotoRegion > 8) {
            result.status = StatusCode.ERR_INVALID_REGION;
            return result;
        }

        // Validate action
        StatusCode actionErr = _validateAction(clan, cs, order, ctx.gotoRegion);
        if (actionErr != StatusCode.OK) {
            result.status = actionErr;
            return result;
        }

        if (
            isMarketAction && ctx.fromRegion == ClanWorldConstants.REGION_UNICORN_TOWN
                && cs.state == ClansmanState.WAITING && block.timestamp >= cs.cooldownEndsAtTs
        ) {
            ctx.newNonce = cs.lastMissionNonce + 1;
            cs.lastMissionNonce = ctx.newNonce;

            StatusCode marketStatus = _executeImmediateMarket(clanId, order, cs.clansmanId);

            if (marketStatus == StatusCode.OK) {
                cs.state = ClansmanState.WAITING;
                cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
            }
            _clearDefender(cs.clansmanId);

            result.status = marketStatus;
            result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
            result.missionNonce = ctx.newNonce;
            result.marketMode = MarketExecutionMode.Immediate;
            return result;
        }

        // Capture existing mission state
        Mission storage existingM = _missions[order.clansmanId];
        ctx.wasActive = existingM.active;
        ctx.oldNonce = existingM.nonce;

        // Compute travel from the clansman's current region to the order target.
        ctx.travelTicks = _travelTicks(ctx.fromRegion, ctx.gotoRegion);
        ctx.arrivalTick = _addTicksClamped(_world.currentTick, uint64(ctx.travelTicks));

        // New nonce
        ctx.newNonce = cs.lastMissionNonce + 1;
        cs.lastMissionNonce = ctx.newNonce;

        if (ctx.wasActive) {
            _refundUpgradeReservation(order.clansmanId, existingM.action);
        }

        if (order.action == ActionType.UpgradeWall) {
            _reserveWallUpgrade(clan, clanId, order.clansmanId, ctx.newNonce);
        }
        if (order.action == ActionType.UpgradeBase) {
            _reserveBaseUpgrade(clan, clanId, order.clansmanId, ctx.newNonce);
        }
        if (order.action == ActionType.UpgradeMonument) {
            _reserveMonumentUpgrade(clan, clanId, order.clansmanId, ctx.newNonce);
        }

        // Install mission via helper to keep stack shallow
        _installMission(existingM, order, cs, ctx);

        // Update clansman state
        if (ctx.travelTicks > 0) {
            cs.state = ClansmanState.TRAVELING;
        } else {
            // NOOP / same-region: no traveling state per v4.3 §A
            cs.state = ClansmanState.ACTING;
            cs.currentRegion = ctx.gotoRegion;
        }

        // Start cooldown
        cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;

        _clearDefender(cs.clansmanId);

        if (order.action == ActionType.DefendBase && ctx.travelTicks == 0) {
            _registerDefender(ctx.gotoRegion, clanId, cs.clansmanId);
        }

        if (ctx.wasActive) {
            emit MissionInterrupted(clanId, order.clansmanId, ctx.oldNonce, ctx.newNonce);
        }

        emit MissionAssigned(
            clanId,
            order.clansmanId,
            ctx.newNonce,
            order.action,
            ctx.fromRegion,
            ctx.gotoRegion,
            _world.currentTick,
            ctx.arrivalTick
        );

        result.status = StatusCode.OK;
        result.cooldownEndsAtTs = cs.cooldownEndsAtTs;
        result.missionNonce = ctx.newNonce;
        result.marketMode = isMarketAction ? MarketExecutionMode.Scheduled : MarketExecutionMode.None;
        if (isMarketAction) {
            _enqueueScheduledMarketAction(clanId, cs.clansmanId, existingM);
        }
        return result;
    }

    function _installMission(Mission storage m, ClanOrder calldata order, Clansman storage cs, OrderCtx memory ctx)
        internal
    {
        m.active = true;
        m.nonce = ctx.newNonce;
        m.clansmanId = cs.clansmanId;
        m.submittedAtTick = _world.currentTick;
        m.executesAtTick = ctx.arrivalTick;
        m.settlesAtTick = order.action == ActionType.DefendBase
            ? type(uint64).max
            : (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell)
                ? ctx.arrivalTick
                : _addTicksClamped(ctx.arrivalTick, getActionDuration(order.action));
        m.startRegion = ctx.fromRegion;
        m.targetRegion = ctx.gotoRegion;
        m.action = order.action;
        m.startTick = _world.currentTick;
        m.arrivalTick = ctx.arrivalTick;
        m.actionStartTick = ctx.arrivalTick;
        m.missionSeed = keccak256(abi.encode(_world.currentTickSeed, cs.clansmanId, ctx.newNonce));
        m.marketMode = (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell)
            ? MarketExecutionMode.Scheduled
            : MarketExecutionMode.None;
        m.targetClanId = ctx.targetClanId;
        m.marketToken = order.marketToken;
        m.marketAmount = order.marketAmount;
        m.maxGoldIn = order.maxGoldIn;
        m.withdrawResources = order.withdrawResources;

        if (m.marketMode == MarketExecutionMode.Scheduled) {
            _marketMissionCommitSequence[cs.clansmanId] = _world.nextCommitSequence++;
        } else {
            delete _marketMissionCommitSequence[cs.clansmanId];
        }
    }

    function _enqueueScheduledMarketAction(uint32 clanId, uint32 clansmanId, Mission storage m) internal {
        uint64 executeAtTick = m.settlesAtTick;
        ScheduledMarketAction memory sma = ScheduledMarketAction({
            executeAtTick: executeAtTick,
            commitSequence: _marketMissionCommitSequence[clansmanId],
            missionNonce: m.nonce,
            clanId: clanId,
            clansmanId: clansmanId,
            action: m.action,
            marketToken: m.marketToken,
            marketAmount: m.marketAmount,
            maxGoldIn: m.maxGoldIn
        });
        _scheduledMarketActions[executeAtTick].push(sma);
        emit ScheduledMarketActionCommitted(
            executeAtTick, sma.commitSequence, clanId, clansmanId, m.action, m.marketToken, m.marketAmount, m.maxGoldIn
        );
    }

    function _registerDefender(uint8 region, uint32 clanId, uint32 clansmanId) internal {
        if (_clansmanDefendingRegion[clansmanId] == region) return;
        _clearDefender(clansmanId);

        if (_defenderCountByRegionClan[region][clanId] == 0) {
            _defendingClansByRegion[region].push(clanId);
        }
        _defenderCountByRegionClan[region][clanId]++;
        _clansmanDefendingRegion[clansmanId] = region;
    }

    function _clearDefender(uint32 clansmanId) internal {
        uint8 region = _clansmanDefendingRegion[clansmanId];
        if (region == 0) return;

        uint32 clanId = _clansmen[clansmanId].clanId;
        uint256 count = _defenderCountByRegionClan[region][clanId];
        if (count > 1) {
            _defenderCountByRegionClan[region][clanId] = count - 1;
        } else {
            delete _defenderCountByRegionClan[region][clanId];
            uint32[] storage clans = _defendingClansByRegion[region];
            for (uint256 i = 0; i < clans.length; i++) {
                if (clans[i] == clanId) {
                    clans[i] = clans[clans.length - 1];
                    clans.pop();
                    break;
                }
            }
        }

        delete _clansmanDefendingRegion[clansmanId];
    }

    // =========================================================================
    // MARKET EXECUTION (Phase 6)
    // =========================================================================

    /// @dev Execute the full scheduled market queue for the given tick, then delete it.
    function _executeScheduledMarketActions(uint64 tick) internal {
        ScheduledMarketAction[] storage actions = _scheduledMarketActions[tick];
        uint256 len = actions.length;
        if (len == 0) return;

        _sortScheduledMarketActionsByCommitSequence(actions);

        for (uint256 i = 0; i < len; i++) {
            ScheduledMarketAction storage sma = actions[i];

            // Validate clansman still belongs to the clan
            Clansman storage cs = _clansmen[sma.clansmanId];
            if (cs.clanId != sma.clanId || cs.state == ClansmanState.DEAD) {
                _emitMarketActionFailed(
                    sma.clanId,
                    sma.clansmanId,
                    sma.action,
                    MarketExecutionMode.Scheduled,
                    StatusCode.ERR_INVALID_CLANSMAN,
                    tick
                );
                continue;
            }

            // Guard: clansman was re-tasked if mission action no longer matches the queued type.
            // Note: _completeMission sets m.active=false during settlement (by design), so we
            // cannot use m.active as a validity signal here — check action type and nonce.
            Mission storage m = _missions[sma.clansmanId];
            if (m.action != sma.action || m.nonce != sma.missionNonce) {
                _emitMarketActionFailed(
                    sma.clanId,
                    sma.clansmanId,
                    sma.action,
                    MarketExecutionMode.Scheduled,
                    StatusCode.ERR_INVALID_ACTION,
                    tick
                );
                continue;
            }

            if (sma.action == ActionType.MarketSell) {
                try this._executeMarketSellExternal(
                    tick, sma.clanId, sma.clansmanId, sma.marketToken, sma.marketAmount
                ) returns (
                    StatusCode marketStatus
                ) {
                    if (marketStatus != StatusCode.OK) {
                        _handleMarketFailure(
                            sma.clanId, sma.clansmanId, sma.action, MarketExecutionMode.Scheduled, marketStatus, tick
                        );
                    }
                } catch {
                    _handleMarketFailure(
                        sma.clanId,
                        sma.clansmanId,
                        sma.action,
                        MarketExecutionMode.Scheduled,
                        StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
                        tick
                    );
                }
            } else if (sma.action == ActionType.MarketBuy) {
                try this._executeMarketBuyExternal(
                    tick, sma.clanId, sma.clansmanId, sma.marketToken, sma.marketAmount, sma.maxGoldIn
                ) returns (
                    StatusCode marketStatus
                ) {
                    if (marketStatus != StatusCode.OK) {
                        _handleMarketFailure(
                            sma.clanId, sma.clansmanId, sma.action, MarketExecutionMode.Scheduled, marketStatus, tick
                        );
                    }
                } catch {
                    _handleMarketFailure(
                        sma.clanId,
                        sma.clansmanId,
                        sma.action,
                        MarketExecutionMode.Scheduled,
                        StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
                        tick
                    );
                }
            }
        }

        delete _scheduledMarketActions[tick];
    }

    function _sortScheduledMarketActionsByCommitSequence(ScheduledMarketAction[] storage actions) internal {
        uint256 len = actions.length;
        if (len <= 1) return;
        ScheduledMarketAction[] memory arr = new ScheduledMarketAction[](len);
        for (uint256 i = 0; i < len; i++) {
            arr[i] = actions[i];
        }
        for (uint256 i = 1; i < len; i++) {
            ScheduledMarketAction memory key = arr[i];
            uint256 j = i;
            while (j > 0 && arr[j - 1].commitSequence > key.commitSequence) {
                arr[j] = arr[j - 1];
                j--;
            }
            arr[j] = key;
        }
        for (uint256 i = 0; i < len; i++) {
            actions[i] = arr[i];
        }
    }

    /// @dev External wrapper for _executeMarketSell — enables try/catch from heartbeat loop.
    function _executeMarketSellExternal(
        uint64 closedTick,
        uint32 clanId,
        uint32 clansmanId,
        address token,
        uint256 amount
    ) external returns (StatusCode) {
        require(msg.sender == address(this), "ClanWorld: internal only");
        return _executeMarketSell(closedTick, clanId, clansmanId, token, amount);
    }

    /// @dev External wrapper for _executeMarketBuy — enables try/catch from heartbeat loop.
    function _executeMarketBuyExternal(
        uint64 closedTick,
        uint32 clanId,
        uint32 clansmanId,
        address token,
        uint256 amountOut,
        uint256 maxGoldIn
    ) external returns (StatusCode) {
        require(msg.sender == address(this), "ClanWorld: internal only");
        return _executeMarketBuy(closedTick, clanId, clansmanId, token, amountOut, maxGoldIn);
    }

    /// @dev Map a resource token address to its pool address.
    function _poolFor(address token) internal view returns (address pool) {
        if (token == _treasury.woodToken) return _treasury.woodGoldPool;
        if (token == _treasury.ironToken) return _treasury.ironGoldPool;
        if (token == _treasury.wheatToken) return _treasury.wheatGoldPool;
        if (token == _treasury.fishToken) return _treasury.fishGoldPool;
        return address(0);
    }

    /// @dev Map a market token address to the canonical uint8 resource id used by market events.
    function _marketResourceForToken(address token) internal view returns (uint8) {
        if (token == _treasury.woodToken) return uint8(ResourceType.Wood);
        if (token == _treasury.ironToken) return uint8(ResourceType.Iron);
        if (token == _treasury.wheatToken) return uint8(ResourceType.Wheat);
        if (token == _treasury.fishToken) return uint8(ResourceType.Fish);
        if (token == _treasury.goldToken) return ClanWorldConstants.RESOURCE_GOLD;
        revert("ClanWorld: invalid market resource");
    }

    function _emitMarketActionFailed(
        uint32 clanId,
        uint32 clansmanId,
        ActionType action,
        MarketExecutionMode mode,
        StatusCode reason,
        uint64 tick
    ) internal {
        emit MarketActionFailed(clanId, clansmanId, action, mode, reason, tick);
    }

    /// @dev Add an amount of a resource token to the clan vault.
    function _addToVault(Clan storage clan, address token, uint256 amount) internal {
        if (token == _treasury.woodToken) {
            clan.vaultWood += amount;
            return;
        }
        if (token == _treasury.ironToken) {
            clan.vaultIron += amount;
            return;
        }
        if (token == _treasury.wheatToken) {
            clan.vaultWheat += amount;
            return;
        }
        if (token == _treasury.fishToken) {
            clan.vaultFish += amount;
            return;
        }
    }

    /// @dev Deduct an amount of a spendable resource token from the clan vault. Returns false if insufficient.
    function _deductFromVault(uint32 clanId, Clan storage clan, address token, uint256 amount) internal returns (bool) {
        if (token == _treasury.woodToken) {
            if (_spendableAfterReleasing(clan.vaultWood, _reservedWoodByClan[clanId], 0) < amount) return false;
            clan.vaultWood -= amount;
            return true;
        }
        if (token == _treasury.ironToken) {
            if (_spendableAfterReleasing(clan.vaultIron, _reservedIronByClan[clanId], 0) < amount) return false;
            clan.vaultIron -= amount;
            return true;
        }
        if (token == _treasury.wheatToken) {
            if (_spendableAfterReleasing(clan.vaultWheat, _reservedWheatByClan[clanId], 0) < amount) return false;
            clan.vaultWheat -= amount;
            return true;
        }
        if (token == _treasury.fishToken) {
            if (clan.vaultFish < amount) return false;
            clan.vaultFish -= amount;
            return true;
        }
        return false;
    }

    function _spendableVaultResource(uint32 clanId, Clan storage clan, ResourceType resource)
        internal
        view
        returns (uint256)
    {
        if (resource == ResourceType.Wood) {
            return _spendableAfterReleasing(clan.vaultWood, _reservedWoodByClan[clanId], 0);
        }
        if (resource == ResourceType.Iron) {
            return _spendableAfterReleasing(clan.vaultIron, _reservedIronByClan[clanId], 0);
        }
        if (resource == ResourceType.Wheat) {
            return _spendableAfterReleasing(clan.vaultWheat, _reservedWheatByClan[clanId], 0);
        }
        if (resource == ResourceType.Fish) {
            return clan.vaultFish;
        }
        return 0;
    }

    function _deductVaultResource(uint32 clanId, Clan storage clan, ResourceType resource, uint256 amount)
        internal
        returns (bool)
    {
        if (_spendableVaultResource(clanId, clan, resource) < amount) return false;
        if (resource == ResourceType.Wood) {
            clan.vaultWood -= amount;
            return true;
        }
        if (resource == ResourceType.Iron) {
            clan.vaultIron -= amount;
            return true;
        }
        if (resource == ResourceType.Wheat) {
            clan.vaultWheat -= amount;
            return true;
        }
        if (resource == ResourceType.Fish) {
            clan.vaultFish -= amount;
            return true;
        }
        return false;
    }

    function _spendableBlueprint(uint32 clanId, Clan storage clan) internal view returns (uint256) {
        return _spendableAfterReleasing(clan.blueprintBalance, _reservedBlueprintByClan[clanId], 0);
    }

    function _deductBlueprint(uint32 clanId, Clan storage clan, uint256 amount) internal returns (bool) {
        if (_spendableBlueprint(clanId, clan) < amount) return false;
        clan.blueprintBalance -= amount;
        return true;
    }

    function _hasCarryBalance(Clansman storage cs, address token, uint256 amount) internal view returns (bool) {
        if (token == _treasury.woodToken) return cs.carryWood >= amount;
        if (token == _treasury.ironToken) return cs.carryIron >= amount;
        if (token == _treasury.wheatToken) return cs.carryWheat >= amount;
        if (token == _treasury.fishToken) return cs.carryFish >= amount;
        return false;
    }

    function _deductFromCarry(Clansman storage cs, address token, uint256 amount) internal returns (bool) {
        if (token == _treasury.woodToken) {
            if (cs.carryWood < amount) return false;
            cs.carryWood -= amount;
            return true;
        }
        if (token == _treasury.ironToken) {
            if (cs.carryIron < amount) return false;
            cs.carryIron -= amount;
            return true;
        }
        if (token == _treasury.wheatToken) {
            if (cs.carryWheat < amount) return false;
            cs.carryWheat -= amount;
            return true;
        }
        if (token == _treasury.fishToken) {
            if (cs.carryFish < amount) return false;
            cs.carryFish -= amount;
            return true;
        }
        return false;
    }

    function _addToCarry(Clansman storage cs, address token, uint256 amount) internal {
        if (token == _treasury.woodToken) {
            cs.carryWood += amount;
            return;
        }
        if (token == _treasury.ironToken) {
            cs.carryIron += amount;
            return;
        }
        if (token == _treasury.wheatToken) {
            cs.carryWheat += amount;
            return;
        }
        if (token == _treasury.fishToken) {
            cs.carryFish += amount;
            return;
        }
    }

    /// @dev Check a clan vault balance without mutating storage.
    function _hasVaultBalance(Clan storage clan, address token, uint256 amount) internal view returns (bool) {
        if (token == _treasury.woodToken) return clan.vaultWood >= amount;
        if (token == _treasury.ironToken) return clan.vaultIron >= amount;
        if (token == _treasury.wheatToken) return clan.vaultWheat >= amount;
        if (token == _treasury.fishToken) return clan.vaultFish >= amount;
        return false;
    }

    function _hasWithdrawRequest(WithdrawResourcesData memory req) internal pure returns (bool) {
        return req.wood > 0 || req.iron > 0 || req.wheat > 0 || req.fish > 0;
    }

    function _hasSpendableForWithdraw(
        uint32 clanId,
        Clan storage clan,
        WithdrawResourcesData memory req,
        HeldUpgradeResources memory released
    ) internal view returns (bool) {
        if (_spendableAfterReleasing(clan.vaultWood, _reservedWoodByClan[clanId], released.wood) < req.wood) {
            return false;
        }
        if (_spendableAfterReleasing(clan.vaultIron, _reservedIronByClan[clanId], released.iron) < req.iron) {
            return false;
        }
        if (_spendableAfterReleasing(clan.vaultWheat, _reservedWheatByClan[clanId], released.wheat) < req.wheat) {
            return false;
        }
        if (clan.vaultFish < req.fish) return false;
        return true;
    }

    function _hasCarryCapacityForWithdraw(Clansman storage cs, WithdrawResourcesData memory req)
        internal
        view
        returns (bool)
    {
        return req.wood <= _remainingCapacity(cs.carryWood, ClanWorldConstants.WOOD_CAP)
            && req.iron <= _remainingCapacity(cs.carryIron, ClanWorldConstants.IRON_CAP)
            && req.wheat <= _remainingCapacity(cs.carryWheat, ClanWorldConstants.WHEAT_CAP)
            && req.fish <= _remainingCapacity(cs.carryFish, ClanWorldConstants.FISH_CAP);
    }

    function _remainingCapacity(uint256 carried, uint256 cap) internal pure returns (uint256) {
        if (carried >= cap) return 0;
        return cap - carried;
    }

    function _handleMarketFailure(
        uint32 clanId,
        uint32 clansmanId,
        ActionType action,
        MarketExecutionMode mode,
        StatusCode reason,
        uint64 tick
    ) internal returns (StatusCode) {
        Clansman storage cs = _clansmen[clansmanId];
        if (cs.clansmanId != 0 && cs.state != ClansmanState.DEAD) {
            cs.state = ClansmanState.WAITING;
            cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
        }
        _emitMarketActionFailed(clanId, clansmanId, action, mode, reason, tick);
        return reason;
    }

    function _remainingCarryForToken(Clansman storage cs, address token) internal view returns (uint256) {
        uint256 carried;
        uint256 cap;
        if (token == _treasury.woodToken) {
            carried = cs.carryWood;
            cap = ClanWorldConstants.WOOD_CAP;
        } else if (token == _treasury.ironToken) {
            carried = cs.carryIron;
            cap = ClanWorldConstants.IRON_CAP;
        } else if (token == _treasury.wheatToken) {
            carried = cs.carryWheat;
            cap = ClanWorldConstants.WHEAT_CAP;
        } else if (token == _treasury.fishToken) {
            carried = cs.carryFish;
            cap = ClanWorldConstants.FISH_CAP;
        } else {
            return 0;
        }

        if (carried >= cap) return 0;
        return cap - carried;
    }

    function _executeImmediateMarket(uint32 clanId, ClanOrder calldata order, uint32 clansmanId)
        internal
        returns (StatusCode)
    {
        if (order.action == ActionType.MarketSell) {
            return _executeImmediateMarketSell(clanId, clansmanId, order.marketToken, order.marketAmount);
        }
        return _executeImmediateMarketBuy(clanId, clansmanId, order.marketToken, order.marketAmount, order.maxGoldIn);
    }

    function _executeImmediateMarketSell(uint32 clanId, uint32 clansmanId, address token, uint256 amount)
        internal
        returns (StatusCode)
    {
        if (!_treasury.poolsSeeded) {
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketSell,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN,
                _world.currentTick
            );
        }
        address poolAddr = _poolFor(token);
        if (poolAddr == address(0)) {
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketSell,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN,
                _world.currentTick
            );
        }

        Clan storage clan = _clans[clanId];
        Clansman storage cs = _clansmen[clansmanId];
        if (!_hasCarryBalance(cs, token, amount)) {
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketSell,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_MISSING_RESOURCES,
                _world.currentTick
            );
        }

        // CEI: deduct carry before external call
        if (!_deductFromCarry(cs, token, amount)) {
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketSell,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_MISSING_RESOURCES,
                _world.currentTick
            );
        }

        try StubPool(poolAddr).swapExactInForOut(amount, 0) returns (uint256 goldOut) {
            clan.goldBalance += goldOut;
            emit ImmediateMarketActionExecuted(
                clanId,
                clansmanId,
                ActionType.MarketSell,
                _marketResourceForToken(token),
                amount,
                ClanWorldConstants.RESOURCE_GOLD,
                goldOut,
                _world.currentTick
            );
            return StatusCode.OK;
        } catch {
            _addToCarry(cs, token, amount); // restore carry on swap failure
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketSell,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
                _world.currentTick
            );
        }
    }

    function _executeImmediateMarketBuy(
        uint32 clanId,
        uint32 clansmanId,
        address token,
        uint256 amountOut,
        uint256 maxGoldIn
    ) internal returns (StatusCode) {
        if (!_treasury.poolsSeeded) {
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketBuy,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN,
                _world.currentTick
            );
        }
        address poolAddr = _poolFor(token);
        if (poolAddr == address(0)) {
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketBuy,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN,
                _world.currentTick
            );
        }

        Clansman storage cs = _clansmen[clansmanId];
        if (amountOut > _remainingCarryForToken(cs, token)) {
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketBuy,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_CARRY_FULL,
                _world.currentTick
            );
        }

        uint256 goldIn;
        try StubPool(poolAddr).getAmountInForExactOut(amountOut) returns (uint256 quotedGoldIn) {
            goldIn = quotedGoldIn;
        } catch {
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketBuy,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
                _world.currentTick
            );
        }

        Clan storage clan = _clans[clanId];
        if (goldIn > maxGoldIn) {
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketBuy,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_MAX_GOLD_IN_EXCEEDED,
                _world.currentTick
            );
        }
        if (clan.goldBalance < goldIn) {
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketBuy,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_NOT_ENOUGH_GOLD,
                _world.currentTick
            );
        }

        try StubPool(poolAddr).swapExactOutForInWithMaxIn(amountOut, maxGoldIn) returns (uint256 actualGoldIn) {
            clan.goldBalance -= actualGoldIn;
            _addToCarry(cs, token, amountOut);
            emit ImmediateMarketActionExecuted(
                clanId,
                clansmanId,
                ActionType.MarketBuy,
                ClanWorldConstants.RESOURCE_GOLD,
                actualGoldIn,
                _marketResourceForToken(token),
                amountOut,
                _world.currentTick
            );
            return StatusCode.OK;
        } catch {
            return _handleMarketFailure(
                clanId,
                clansmanId,
                ActionType.MarketBuy,
                MarketExecutionMode.Immediate,
                StatusCode.ERR_LIQUIDITY_INSUFFICIENT,
                _world.currentTick
            );
        }
    }

    /// @dev Execute a scheduled market sell: deduct resource from carry, credit clan gold.
    function _executeMarketSell(uint64 closedTick, uint32 clanId, uint32 clansmanId, address token, uint256 amount)
        internal
        returns (StatusCode)
    {
        if (!_treasury.poolsSeeded) {
            return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
        }
        address poolAddr = _poolFor(token);
        if (poolAddr == address(0)) {
            return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
        }

        Clan storage clan = _clans[clanId];
        Clansman storage cs = _clansmen[clansmanId];
        if (!_deductFromCarry(cs, token, amount)) {
            return StatusCode.ERR_MISSING_RESOURCES;
        }

        uint256 goldOut = StubPool(poolAddr).sellResource(amount);
        clan.goldBalance += goldOut;

        emit ScheduledMarketActionExecuted(
            clanId,
            clansmanId,
            ActionType.MarketSell,
            _marketResourceForToken(token),
            amount,
            ClanWorldConstants.RESOURCE_GOLD,
            goldOut,
            closedTick
        );
        return StatusCode.OK;
    }

    /// @dev Execute a scheduled market buy: deduct clan gold, credit resource to carry.
    function _executeMarketBuy(
        uint64 closedTick,
        uint32 clanId,
        uint32 clansmanId,
        address token,
        uint256 amountOut,
        uint256 maxGoldIn
    ) internal returns (StatusCode) {
        if (!_treasury.poolsSeeded) {
            return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
        }
        address poolAddr = _poolFor(token);
        if (poolAddr == address(0)) {
            return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
        }

        Clansman storage cs = _clansmen[clansmanId];
        if (amountOut > _remainingCarryForToken(cs, token)) {
            return StatusCode.ERR_CARRY_FULL;
        }

        uint256 goldIn;
        try StubPool(poolAddr).quoteBuy(amountOut) returns (uint256 quotedGoldIn) {
            goldIn = quotedGoldIn;
        } catch {
            return StatusCode.ERR_LIQUIDITY_INSUFFICIENT;
        }

        Clan storage clan = _clans[clanId];

        if (goldIn > maxGoldIn) {
            return StatusCode.ERR_MAX_GOLD_IN_EXCEEDED;
        }
        if (clan.goldBalance < goldIn) {
            return StatusCode.ERR_NOT_ENOUGH_GOLD;
        }

        uint256 actualGoldIn;
        try StubPool(poolAddr).swapExactOutForInWithMaxIn(amountOut, maxGoldIn) returns (uint256 spentGold) {
            actualGoldIn = spentGold;
        } catch {
            return StatusCode.ERR_LIQUIDITY_INSUFFICIENT;
        }

        clan.goldBalance -= actualGoldIn;
        _addToCarry(cs, token, amountOut);

        emit ScheduledMarketActionExecuted(
            clanId,
            clansmanId,
            ActionType.MarketBuy,
            ClanWorldConstants.RESOURCE_GOLD,
            actualGoldIn,
            _marketResourceForToken(token),
            amountOut,
            closedTick
        );
        return StatusCode.OK;
    }

    function _validateAction(Clan storage clan, Clansman storage cs, ClanOrder calldata order, uint8 gotoRegion)
        internal
        view
        returns (StatusCode)
    {
        ActionType action = order.action;

        if (action == ActionType.None) return StatusCode.ERR_INVALID_ACTION;

        // DepositResources / WithdrawResources: must go to homebase
        if (action == ActionType.DepositResources) {
            if (gotoRegion != clan.baseRegion) return StatusCode.ERR_NOT_AT_HOMEBASE;
        }
        if (action == ActionType.WithdrawResources) {
            if (gotoRegion != clan.baseRegion) return StatusCode.ERR_NOT_AT_HOMEBASE;
            WithdrawResourcesData memory req = order.withdrawResources;
            if (!_hasWithdrawRequest(req)) return StatusCode.ERR_EMPTY_CARGO;
            HeldUpgradeResources memory released = _releasedUpgradeResources(clan.clanId, cs.clansmanId);
            if (!_hasSpendableForWithdraw(clan.clanId, clan, req, released)) {
                return StatusCode.ERR_MISSING_RESOURCES;
            }
            if (!_hasCarryCapacityForWithdraw(cs, req)) return StatusCode.ERR_CARRY_FULL;
        }

        // UpgradeWall / UpgradeBase / UpgradeMonument: must go to homebase
        if (
            action == ActionType.UpgradeWall || action == ActionType.UpgradeBase || action == ActionType.UpgradeMonument
        ) {
            if (gotoRegion != clan.baseRegion) return StatusCode.ERR_NOT_AT_HOMEBASE;
        }

        if (action == ActionType.UpgradeWall) {
            return _validateUpgradeWallOrder(clan, cs.clansmanId);
        }
        if (action == ActionType.UpgradeBase) {
            return _validateUpgradeBaseOrder(clan, cs.clansmanId);
        }
        if (action == ActionType.UpgradeMonument) {
            return _validateUpgradeMonumentOrder(clan, cs.clansmanId);
        }

        // ChopWood: must go to Forest
        if (action == ActionType.ChopWood) {
            if (gotoRegion != ClanWorldConstants.REGION_FOREST) return StatusCode.ERR_INVALID_REGION;
        }
        // MineIron: must go to Mountains
        if (action == ActionType.MineIron) {
            if (gotoRegion != ClanWorldConstants.REGION_MOUNTAINS) return StatusCode.ERR_INVALID_REGION;
        }
        // FishDocks: must go to WestDocks or EastDocks
        if (action == ActionType.FishDocks) {
            if (
                gotoRegion != ClanWorldConstants.REGION_WEST_DOCKS && gotoRegion != ClanWorldConstants.REGION_EAST_DOCKS
            ) {
                return StatusCode.ERR_INVALID_REGION;
            }
        }
        // FishDeepSea: must go to DeepSea
        if (action == ActionType.FishDeepSea) {
            if (gotoRegion != ClanWorldConstants.REGION_DEEP_SEA) return StatusCode.ERR_INVALID_REGION;
        }
        // HarvestWheat: must go to WestFarms or EastFarms
        if (action == ActionType.HarvestWheat) {
            if (
                gotoRegion != ClanWorldConstants.REGION_WEST_FARMS && gotoRegion != ClanWorldConstants.REGION_EAST_FARMS
            ) {
                return StatusCode.ERR_INVALID_REGION;
            }
            if (_isWinterActiveAt(_world.currentTick)) {
                return StatusCode.ERR_WINTER_LOCKED;
            }
        }

        if (action == ActionType.DefendBase) {
            return _validateDefendBaseOrder(clan, order, gotoRegion);
        }

        // MarketBuy/MarketSell: must target Unicorn Town
        if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
            if (_treasury.woodToken == address(0)) return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
            if (gotoRegion != ClanWorldConstants.REGION_UNICORN_TOWN) {
                return StatusCode.ERR_INVALID_REGION;
            }
            if (order.marketAmount == 0) return StatusCode.ERR_MARKET_ZERO_AMOUNT;
            // Validate token is a supported resource token (not gold itself)
            address tok = order.marketToken;
            if (tok == address(0) || tok == _treasury.goldToken) {
                return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
            }
            if (
                tok != _treasury.woodToken && tok != _treasury.ironToken && tok != _treasury.wheatToken
                    && tok != _treasury.fishToken
            ) {
                return StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN;
            }
            // MarketBuy uses maxGoldIn as its explicit slippage bound; zero would mean no protection.
            if (action == ActionType.MarketBuy && order.maxGoldIn == 0) {
                return StatusCode.ERR_SLIPPAGE_REQUIRED;
            }
            // Over-capacity buys are rejected at submission; no partial fills or overflow refunds.
            if (action == ActionType.MarketBuy && order.marketAmount > _remainingCarryForToken(cs, tok)) {
                return StatusCode.ERR_CARRY_FULL;
            }
            if (action == ActionType.MarketSell && !_hasCarryBalance(cs, tok, order.marketAmount)) {
                return StatusCode.ERR_MISSING_RESOURCES;
            }
            // Immediate market orders execute during submitClanOrders when the
            // worker is waiting in Unicorn Town and off cooldown. Other valid
            // market orders enqueue when the scheduled mission resolves.
            if (cs.currentRegion == ClanWorldConstants.REGION_UNICORN_TOWN && cs.state == ClansmanState.WAITING) {
                // Already at Unicorn Town — immediate if off cooldown, scheduled otherwise.
            }
        }

        cs; // suppress unused warning
        return StatusCode.OK;
    }

    function _validateDefendBaseOrder(Clan storage clan, ClanOrder calldata order, uint8 gotoRegion)
        internal
        view
        returns (StatusCode)
    {
        uint32 targetClanId = order.targetClanId == 0 ? clan.clanId : order.targetClanId;
        Clan storage targetClan = _clans[targetClanId];
        if (targetClan.clanId == ClanWorldConstants.CLAN_ID_NULL || targetClan.clanState == ClanState.DEAD) {
            return StatusCode.ERR_INVALID_TARGET;
        }
        if (gotoRegion != targetClan.baseRegion) return StatusCode.ERR_INVALID_REGION;
        return StatusCode.OK;
    }

    function _validateUpgradeWallOrder(Clan storage clan, uint32 clansmanId) internal view returns (StatusCode) {
        uint8 pendingUpgrades = _pendingWallUpgradesByClan[clan.clanId];
        HeldUpgradeResources memory released = _releasedUpgradeResources(clan.clanId, clansmanId);

        WallUpgradeReservation storage existing = _wallUpgradeReservations[clansmanId];
        if (existing.active && existing.clanId == clan.clanId) {
            pendingUpgrades -= 1;
        }

        uint256 availableWood =
            _spendableAfterReleasing(clan.vaultWood, _reservedWoodByClan[clan.clanId], released.wood);
        uint256 availableIron =
            _spendableAfterReleasing(clan.vaultIron, _reservedIronByClan[clan.clanId], released.iron);

        uint8 plannedCurrentLevel = clan.wallLevel + pendingUpgrades;
        if (plannedCurrentLevel >= WALL_MAX_LEVEL) return StatusCode.ERR_INVALID_ACTION;

        (uint256 woodCost, uint256 ironCost) = _wallUpgradeCost(plannedCurrentLevel);
        if (availableWood < woodCost || availableIron < ironCost) return StatusCode.ERR_MISSING_RESOURCES;

        return StatusCode.OK;
    }

    function _reserveWallUpgrade(Clan storage clan, uint32 clanId, uint32 clansmanId, uint64 missionNonce) internal {
        uint8 plannedCurrentLevel = clan.wallLevel + _pendingWallUpgradesByClan[clanId];
        (uint256 woodCost, uint256 ironCost) = _wallUpgradeCost(plannedCurrentLevel);

        _pendingWallUpgradesByClan[clanId] += 1;
        _reservedWoodByClan[clanId] += woodCost;
        _reservedIronByClan[clanId] += ironCost;

        _wallUpgradeReservations[clansmanId] = WallUpgradeReservation({
            active: true,
            clanId: clanId,
            missionNonce: missionNonce,
            fromLevel: plannedCurrentLevel,
            toLevel: plannedCurrentLevel + 1,
            woodCost: woodCost,
            ironCost: ironCost
        });
    }

    function _refundWallUpgradeReservation(uint32 clansmanId) internal {
        _clearWallUpgradeReservation(clansmanId);
    }

    function _clearWallUpgradeReservation(uint32 clansmanId) internal {
        WallUpgradeReservation storage reservation = _wallUpgradeReservations[clansmanId];
        if (!reservation.active) return;

        uint32 clanId = reservation.clanId;
        if (_pendingWallUpgradesByClan[clanId] > 0) {
            _pendingWallUpgradesByClan[clanId] -= 1;
        }
        _reservedWoodByClan[clanId] = _subtractHeld(_reservedWoodByClan[clanId], reservation.woodCost);
        _reservedIronByClan[clanId] = _subtractHeld(_reservedIronByClan[clanId], reservation.ironCost);

        delete _wallUpgradeReservations[clansmanId];
    }

    function _validateUpgradeBaseOrder(Clan storage clan, uint32 clansmanId) internal view returns (StatusCode) {
        uint8 pendingUpgrades = _pendingBaseUpgradesByClan[clan.clanId];
        HeldUpgradeResources memory released = _releasedUpgradeResources(clan.clanId, clansmanId);

        BaseUpgradeReservation storage existing = _baseUpgradeReservations[clansmanId];
        if (existing.active && existing.clanId == clan.clanId) {
            pendingUpgrades -= 1;
        }

        uint256 availableWood =
            _spendableAfterReleasing(clan.vaultWood, _reservedWoodByClan[clan.clanId], released.wood);
        uint256 availableIron =
            _spendableAfterReleasing(clan.vaultIron, _reservedIronByClan[clan.clanId], released.iron);
        uint256 availableWheat =
            _spendableAfterReleasing(clan.vaultWheat, _reservedWheatByClan[clan.clanId], released.wheat);

        uint8 plannedCurrentLevel = clan.baseLevel + pendingUpgrades;
        if (plannedCurrentLevel >= BASE_MAX_LEVEL) return StatusCode.ERR_INVALID_ACTION;

        (uint256 woodCost, uint256 ironCost, uint256 wheatCost) = _baseUpgradeCost(plannedCurrentLevel);
        if (availableWood < woodCost || availableIron < ironCost || availableWheat < wheatCost) {
            return StatusCode.ERR_MISSING_RESOURCES;
        }

        return StatusCode.OK;
    }

    function _reserveBaseUpgrade(Clan storage clan, uint32 clanId, uint32 clansmanId, uint64 missionNonce) internal {
        uint8 plannedCurrentLevel = clan.baseLevel + _pendingBaseUpgradesByClan[clanId];
        (uint256 woodCost, uint256 ironCost, uint256 wheatCost) = _baseUpgradeCost(plannedCurrentLevel);

        _pendingBaseUpgradesByClan[clanId] += 1;
        _reservedWoodByClan[clanId] += woodCost;
        _reservedIronByClan[clanId] += ironCost;
        _reservedWheatByClan[clanId] += wheatCost;

        _baseUpgradeReservations[clansmanId] = BaseUpgradeReservation({
            active: true,
            clanId: clanId,
            missionNonce: missionNonce,
            fromLevel: plannedCurrentLevel,
            toLevel: plannedCurrentLevel + 1,
            woodCost: woodCost,
            ironCost: ironCost,
            wheatCost: wheatCost
        });
    }

    function _refundBaseUpgradeReservation(uint32 clansmanId) internal {
        _clearBaseUpgradeReservation(clansmanId);
    }

    function _clearBaseUpgradeReservation(uint32 clansmanId) internal {
        BaseUpgradeReservation storage reservation = _baseUpgradeReservations[clansmanId];
        if (!reservation.active) return;

        uint32 clanId = reservation.clanId;
        if (_pendingBaseUpgradesByClan[clanId] > 0) {
            _pendingBaseUpgradesByClan[clanId] -= 1;
        }
        _reservedWoodByClan[clanId] = _subtractHeld(_reservedWoodByClan[clanId], reservation.woodCost);
        _reservedIronByClan[clanId] = _subtractHeld(_reservedIronByClan[clanId], reservation.ironCost);
        _reservedWheatByClan[clanId] = _subtractHeld(_reservedWheatByClan[clanId], reservation.wheatCost);

        delete _baseUpgradeReservations[clansmanId];
    }

    function _validateUpgradeMonumentOrder(Clan storage clan, uint32 clansmanId) internal view returns (StatusCode) {
        uint8 pendingUpgrades = _pendingMonumentUpgradesByClan[clan.clanId];
        HeldUpgradeResources memory released = _releasedUpgradeResources(clan.clanId, clansmanId);

        MonumentUpgradeReservation storage existing = _monumentUpgradeReservations[clansmanId];
        if (existing.active && existing.clanId == clan.clanId) {
            pendingUpgrades -= 1;
        }

        uint256 availableWood =
            _spendableAfterReleasing(clan.vaultWood, _reservedWoodByClan[clan.clanId], released.wood);
        uint256 availableIron =
            _spendableAfterReleasing(clan.vaultIron, _reservedIronByClan[clan.clanId], released.iron);
        uint256 availableWheat =
            _spendableAfterReleasing(clan.vaultWheat, _reservedWheatByClan[clan.clanId], released.wheat);
        uint256 availableBlueprint =
            _spendableAfterReleasing(clan.blueprintBalance, _reservedBlueprintByClan[clan.clanId], released.blueprint);

        uint8 plannedCurrentLevel = clan.monumentLevel + pendingUpgrades;
        if (plannedCurrentLevel >= MONUMENT_MAX_LEVEL) return StatusCode.ERR_INVALID_ACTION;

        (uint256 woodCost, uint256 ironCost, uint256 wheatCost, uint256 blueprintCost) =
            _monumentUpgradeCost(plannedCurrentLevel);
        if (
            availableWood < woodCost || availableIron < ironCost || availableWheat < wheatCost
                || availableBlueprint < blueprintCost
        ) {
            return StatusCode.ERR_MISSING_RESOURCES;
        }

        return StatusCode.OK;
    }

    function _reserveMonumentUpgrade(Clan storage clan, uint32 clanId, uint32 clansmanId, uint64 missionNonce)
        internal
    {
        uint8 plannedCurrentLevel = clan.monumentLevel + _pendingMonumentUpgradesByClan[clanId];
        (uint256 woodCost, uint256 ironCost, uint256 wheatCost, uint256 blueprintCost) =
            _monumentUpgradeCost(plannedCurrentLevel);

        _pendingMonumentUpgradesByClan[clanId] += 1;
        _reservedWoodByClan[clanId] += woodCost;
        _reservedIronByClan[clanId] += ironCost;
        _reservedWheatByClan[clanId] += wheatCost;
        _reservedBlueprintByClan[clanId] += blueprintCost;

        _monumentUpgradeReservations[clansmanId] = MonumentUpgradeReservation({
            active: true,
            clanId: clanId,
            missionNonce: missionNonce,
            fromLevel: plannedCurrentLevel,
            toLevel: plannedCurrentLevel + 1,
            woodCost: woodCost,
            ironCost: ironCost,
            wheatCost: wheatCost,
            blueprintCost: blueprintCost
        });
    }

    function _refundMonumentUpgradeReservation(uint32 clansmanId) internal {
        _clearMonumentUpgradeReservation(clansmanId);
    }

    function _clearMonumentUpgradeReservation(uint32 clansmanId) internal {
        MonumentUpgradeReservation storage reservation = _monumentUpgradeReservations[clansmanId];
        if (!reservation.active) return;

        uint32 clanId = reservation.clanId;
        if (_pendingMonumentUpgradesByClan[clanId] > 0) {
            _pendingMonumentUpgradesByClan[clanId] -= 1;
        }
        _reservedWoodByClan[clanId] = _subtractHeld(_reservedWoodByClan[clanId], reservation.woodCost);
        _reservedIronByClan[clanId] = _subtractHeld(_reservedIronByClan[clanId], reservation.ironCost);
        _reservedWheatByClan[clanId] = _subtractHeld(_reservedWheatByClan[clanId], reservation.wheatCost);
        _reservedBlueprintByClan[clanId] = _subtractHeld(_reservedBlueprintByClan[clanId], reservation.blueprintCost);

        delete _monumentUpgradeReservations[clansmanId];
    }

    function _refundUpgradeReservation(uint32 clansmanId, ActionType action) internal {
        if (action == ActionType.UpgradeWall) {
            _refundWallUpgradeReservation(clansmanId);
        } else if (action == ActionType.UpgradeBase) {
            _refundBaseUpgradeReservation(clansmanId);
        } else if (action == ActionType.UpgradeMonument) {
            _refundMonumentUpgradeReservation(clansmanId);
        }
    }

    function _releasedUpgradeResources(uint32 clanId, uint32 clansmanId)
        internal
        view
        returns (HeldUpgradeResources memory released)
    {
        WallUpgradeReservation storage wall = _wallUpgradeReservations[clansmanId];
        if (wall.active && wall.clanId == clanId) {
            released.wood += wall.woodCost;
            released.iron += wall.ironCost;
        }

        BaseUpgradeReservation storage base = _baseUpgradeReservations[clansmanId];
        if (base.active && base.clanId == clanId) {
            released.wood += base.woodCost;
            released.iron += base.ironCost;
            released.wheat += base.wheatCost;
        }

        MonumentUpgradeReservation storage monument = _monumentUpgradeReservations[clansmanId];
        if (monument.active && monument.clanId == clanId) {
            released.wood += monument.woodCost;
            released.iron += monument.ironCost;
            released.wheat += monument.wheatCost;
            released.blueprint += monument.blueprintCost;
        }
    }

    function _spendableAfterReleasing(uint256 vault, uint256 reserved, uint256 released)
        internal
        pure
        returns (uint256)
    {
        uint256 adjustedReserved = _subtractHeld(reserved, released);
        if (vault <= adjustedReserved) return 0;
        return vault - adjustedReserved;
    }

    function _subtractHeld(uint256 held, uint256 amount) internal pure returns (uint256) {
        return held > amount ? held - amount : 0;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // =========================================================================
    // TREASURY / POOL SEEDING
    // =========================================================================

    /// @notice One-time treasury initialization: register token and pool addresses.
    ///         Must be called before seedPools. Callable only once.
    function initTreasury(address[6] calldata tokens, address[4] calldata pools) external override nonReentrant {
        require(!_treasury.poolsSeeded && _treasury.woodToken == address(0), "ClanWorld: treasury already init");
        require(msg.sender == _treasury.treasuryOwner, "ClanWorld: not owner");

        _treasury.woodToken = tokens[0];
        _treasury.ironToken = tokens[1];
        _treasury.wheatToken = tokens[2];
        _treasury.fishToken = tokens[3];
        _treasury.goldToken = tokens[4];
        _treasury.blueprintToken = tokens[5];

        _treasury.woodGoldPool = pools[0];
        _treasury.wheatGoldPool = pools[1];
        _treasury.fishGoldPool = pools[2];
        _treasury.ironGoldPool = pools[3];
    }

    /// @notice Owner-only. Seeds the four Unicorn Town AMM pools.
    function seedPools(PoolSeedConfig calldata cfg) external override nonReentrant {
        require(msg.sender == _treasury.treasuryOwner, "ClanWorld: not owner");
        require(!_treasury.poolsSeeded, "ClanWorld: pools already seeded");
        require(_treasury.woodToken != address(0), "ClanWorld: treasury not init");

        _transferSeed(_treasury.woodToken, _treasury.woodGoldPool, cfg.woodSeed);
        _transferSeed(_treasury.goldToken, _treasury.woodGoldPool, cfg.goldSeedForWood);
        _transferSeed(_treasury.wheatToken, _treasury.wheatGoldPool, cfg.wheatSeed);
        _transferSeed(_treasury.goldToken, _treasury.wheatGoldPool, cfg.goldSeedForWheat);
        _transferSeed(_treasury.fishToken, _treasury.fishGoldPool, cfg.fishSeed);
        _transferSeed(_treasury.goldToken, _treasury.fishGoldPool, cfg.goldSeedForFish);
        _transferSeed(_treasury.ironToken, _treasury.ironGoldPool, cfg.ironSeed);
        _transferSeed(_treasury.goldToken, _treasury.ironGoldPool, cfg.goldSeedForIron);

        StubPool(_treasury.woodGoldPool).seed(cfg.woodSeed, cfg.goldSeedForWood);
        StubPool(_treasury.wheatGoldPool).seed(cfg.wheatSeed, cfg.goldSeedForWheat);
        StubPool(_treasury.fishGoldPool).seed(cfg.fishSeed, cfg.goldSeedForFish);
        StubPool(_treasury.ironGoldPool).seed(cfg.ironSeed, cfg.goldSeedForIron);

        _treasury.poolsSeeded = true;

        emit PoolsSeeded(
            _treasury.woodGoldPool, _treasury.wheatGoldPool, _treasury.fishGoldPool, _treasury.ironGoldPool
        );
    }

    function _transferSeed(address token, address pool, uint256 amount) internal {
        require(token != address(0) && pool != address(0), "ClanWorld: treasury not init");
        require(MinimalERC20(token).transferFrom(msg.sender, pool, amount), "ClanWorld: seed transfer failed");
    }

    // =========================================================================
    // CLAN OWNERSHIP TRANSFER
    // =========================================================================

    /// @notice Transfer clan ownership to a new address. Increments ownerNonce.
    function transferClanOwnership(uint32 clanId, address newOwner) external override nonReentrant {
        Clan storage clan = _clans[clanId];
        require(clan.clanId != 0, "ClanWorld: clan not found");
        require(clan.owner == msg.sender, "ClanWorld: not clan owner");
        require(newOwner != address(0), "ClanWorld: zero address");
        require(newOwner != clan.owner, "ClanWorld: same owner");
        _settleClan(clanId);
        require(clan.clanState != ClanState.DEAD, "ClanWorld: clan dead");
        address oldOwner = clan.owner;
        clan.owner = newOwner;
        clan.ownerNonce++;
        emit ClanOwnershipTransferred(clanId, oldOwner, newOwner, clan.ownerNonce);
    }

    // =========================================================================
    // OTC TRANSFERS
    // =========================================================================

    function _requireTransferSettlementComplete(Clan storage fromClan, Clan storage toClan) private view {
        require(
            fromClan.lastSettledTick == _world.currentTick && toClan.lastSettledTick == _world.currentTick,
            "ERR_MUST_SETTLE_FIRST"
        );
    }

    /// @notice Transfer gold from one clan to another. Caller must be owner of fromClan.
    function transferGold(uint32 fromClanId, uint32 toClanId, uint256 amount) external override nonReentrant {
        require(amount > 0, "ClanWorld: zero amount");
        require(fromClanId != toClanId, "ClanWorld: same clan");

        Clan storage fromClan = _clans[fromClanId];
        Clan storage toClan = _clans[toClanId];

        require(fromClan.clanId != 0, "ClanWorld: from clan not found");
        require(fromClan.owner == msg.sender, "ClanWorld: not clan owner");
        require(toClan.clanId != 0, "ClanWorld: to clan not found");

        _settleClan(fromClanId);
        _settleClan(toClanId);

        _requireTransferSettlementComplete(fromClan, toClan);
        require(fromClan.clanState != ClanState.DEAD, "ClanWorld: clan dead");
        require(fromClan.goldBalance >= amount, "ClanWorld: insufficient gold");

        fromClan.goldBalance -= amount;
        toClan.goldBalance += amount;

        emit GoldTransferred(fromClanId, toClanId, amount, _world.currentTick);
    }

    /// @notice Transfer a vault resource from one clan to another. Caller must be owner of fromClan.
    function transferVaultResource(uint32 fromClanId, uint32 toClanId, ResourceType resource, uint256 amount)
        external
        override
        nonReentrant
    {
        require(amount > 0, "ClanWorld: zero amount");
        require(fromClanId != toClanId, "ClanWorld: same clan");

        Clan storage fromClan = _clans[fromClanId];
        Clan storage toClan = _clans[toClanId];

        require(fromClan.clanId != 0, "ClanWorld: from clan not found");
        require(fromClan.owner == msg.sender, "ClanWorld: not clan owner");
        require(toClan.clanId != 0, "ClanWorld: to clan not found");

        _settleClan(fromClanId);
        _settleClan(toClanId);

        _requireTransferSettlementComplete(fromClan, toClan);
        require(fromClan.clanState != ClanState.DEAD, "ClanWorld: clan dead");
        if (resource == ResourceType.Wood) {
            require(_deductVaultResource(fromClanId, fromClan, resource, amount), "ClanWorld: insufficient wood");
            toClan.vaultWood += amount;
        } else if (resource == ResourceType.Iron) {
            require(_deductVaultResource(fromClanId, fromClan, resource, amount), "ClanWorld: insufficient iron");
            toClan.vaultIron += amount;
        } else if (resource == ResourceType.Wheat) {
            require(_deductVaultResource(fromClanId, fromClan, resource, amount), "ClanWorld: insufficient wheat");
            toClan.vaultWheat += amount;
        } else if (resource == ResourceType.Fish) {
            require(_deductVaultResource(fromClanId, fromClan, resource, amount), "ClanWorld: insufficient fish");
            toClan.vaultFish += amount;
        } else {
            revert("ClanWorld: invalid resource");
        }

        emit VaultResourceTransferred(fromClanId, toClanId, resource, amount, _world.currentTick);
    }

    /// @notice Transfer blueprints from one clan to another. Caller must be owner of fromClan.
    function transferBlueprint(uint32 fromClanId, uint32 toClanId, uint256 amount) external override nonReentrant {
        require(amount > 0, "ClanWorld: zero amount");
        require(fromClanId != toClanId, "ClanWorld: same clan");

        Clan storage fromClan = _clans[fromClanId];
        Clan storage toClan = _clans[toClanId];

        require(fromClan.clanId != 0, "ClanWorld: from clan not found");
        require(fromClan.owner == msg.sender, "ClanWorld: not clan owner");
        require(toClan.clanId != 0, "ClanWorld: to clan not found");

        _settleClan(fromClanId);
        _settleClan(toClanId);

        _requireTransferSettlementComplete(fromClan, toClan);
        require(fromClan.clanState != ClanState.DEAD, "ClanWorld: clan dead");
        require(_deductBlueprint(fromClanId, fromClan, amount), "ClanWorld: insufficient blueprints");

        toClan.blueprintBalance += amount;

        emit BlueprintTransferred(fromClanId, toClanId, amount, _world.currentTick);
    }

    /// @notice Transfer a bundle of resources atomically. Caller must be owner of fromClan.
    ///         At least one component must be non-zero. Component debits and credits are atomic after settlement.
    function transferBundle(
        uint32 fromClanId,
        uint32 toClanId,
        uint256 gold,
        uint256 blueprint,
        uint256 wood,
        uint256 iron,
        uint256 wheat,
        uint256 fish
    ) external override nonReentrant {
        require(gold > 0 || blueprint > 0 || wood > 0 || iron > 0 || wheat > 0 || fish > 0, "ClanWorld: empty bundle");
        require(fromClanId != toClanId, "ClanWorld: same clan");

        Clan storage fromClan = _clans[fromClanId];
        Clan storage toClan = _clans[toClanId];

        require(fromClan.clanId != 0, "ClanWorld: from clan not found");
        require(fromClan.owner == msg.sender, "ClanWorld: not clan owner");
        require(toClan.clanId != 0, "ClanWorld: to clan not found");

        _settleClan(fromClanId);
        _settleClan(toClanId);

        _requireTransferSettlementComplete(fromClan, toClan);
        require(fromClan.clanState != ClanState.DEAD, "ClanWorld: clan dead");
        // All balance checks before any mutation (atomic)
        if (gold > 0) require(fromClan.goldBalance >= gold, "ClanWorld: insufficient gold");
        if (blueprint > 0) {
            require(_spendableBlueprint(fromClanId, fromClan) >= blueprint, "ClanWorld: insufficient blueprints");
        }
        if (wood > 0) {
            require(
                _spendableVaultResource(fromClanId, fromClan, ResourceType.Wood) >= wood,
                "ClanWorld: insufficient wood"
            );
        }
        if (iron > 0) {
            require(
                _spendableVaultResource(fromClanId, fromClan, ResourceType.Iron) >= iron,
                "ClanWorld: insufficient iron"
            );
        }
        if (wheat > 0) {
            require(
                _spendableVaultResource(fromClanId, fromClan, ResourceType.Wheat) >= wheat,
                "ClanWorld: insufficient wheat"
            );
        }
        if (fish > 0) {
            require(
                _spendableVaultResource(fromClanId, fromClan, ResourceType.Fish) >= fish,
                "ClanWorld: insufficient fish"
            );
        }

        // Apply debits
        if (gold > 0) fromClan.goldBalance -= gold;
        if (blueprint > 0) {
            require(_deductBlueprint(fromClanId, fromClan, blueprint), "ClanWorld: insufficient blueprints");
        }
        if (wood > 0) {
            require(_deductVaultResource(fromClanId, fromClan, ResourceType.Wood, wood), "ClanWorld: insufficient wood");
        }
        if (iron > 0) {
            require(_deductVaultResource(fromClanId, fromClan, ResourceType.Iron, iron), "ClanWorld: insufficient iron");
        }
        if (wheat > 0) {
            require(_deductVaultResource(fromClanId, fromClan, ResourceType.Wheat, wheat), "ClanWorld: insufficient wheat");
        }
        if (fish > 0) {
            require(_deductVaultResource(fromClanId, fromClan, ResourceType.Fish, fish), "ClanWorld: insufficient fish");
        }

        // Apply credits
        if (gold > 0) toClan.goldBalance += gold;
        if (blueprint > 0) toClan.blueprintBalance += blueprint;
        if (wood > 0) toClan.vaultWood += wood;
        if (iron > 0) toClan.vaultIron += iron;
        if (wheat > 0) toClan.vaultWheat += wheat;
        if (fish > 0) toClan.vaultFish += fish;

        // Emit per-component events
        if (gold > 0) emit GoldTransferred(fromClanId, toClanId, gold, _world.currentTick);
        if (blueprint > 0) emit BlueprintTransferred(fromClanId, toClanId, blueprint, _world.currentTick);
        if (wood > 0) emit VaultResourceTransferred(fromClanId, toClanId, ResourceType.Wood, wood, _world.currentTick);
        if (iron > 0) emit VaultResourceTransferred(fromClanId, toClanId, ResourceType.Iron, iron, _world.currentTick);
        if (wheat > 0) {
            emit VaultResourceTransferred(fromClanId, toClanId, ResourceType.Wheat, wheat, _world.currentTick);
        }
        if (fish > 0) emit VaultResourceTransferred(fromClanId, toClanId, ResourceType.Fish, fish, _world.currentTick);
    }

    // =========================================================================
    // RAW READ GETTERS
    // =========================================================================

    function getWorldState() external view override returns (WorldState memory) {
        return _worldStateView();
    }

    function getTreasuryState() external view override returns (TreasuryState memory) {
        return _treasury;
    }

    function getResourceToken(uint8 resourceType) external view override returns (address) {
        if (resourceType == uint8(ResourceType.Wood)) return _treasury.woodToken;
        if (resourceType == uint8(ResourceType.Iron)) return _treasury.ironToken;
        if (resourceType == uint8(ResourceType.Wheat)) return _treasury.wheatToken;
        if (resourceType == uint8(ResourceType.Fish)) return _treasury.fishToken;
        revert("ClanWorld: invalid resource");
    }

    function getPool(uint8 resourceType) external view override returns (address) {
        return _poolForResourceType(resourceType);
    }

    function getPrice(uint8 resourceType, uint256 amountIn) external view override returns (uint256 amountOut) {
        amountOut = StubPool(_poolForResourceType(resourceType)).getAmountOutForExactIn(amountIn);
    }

    function _poolForResourceType(uint8 resourceType) internal view returns (address) {
        if (resourceType == uint8(ResourceType.Wood)) return _treasury.woodGoldPool;
        if (resourceType == uint8(ResourceType.Iron)) return _treasury.ironGoldPool;
        if (resourceType == uint8(ResourceType.Wheat)) return _treasury.wheatGoldPool;
        if (resourceType == uint8(ResourceType.Fish)) return _treasury.fishGoldPool;
        revert("ClanWorld: invalid resource");
    }

    function getClan(uint32 clanId) external view override returns (Clan memory) {
        return _clans[clanId];
    }

    function getClansman(uint32 clansmanId) external view override returns (Clansman memory) {
        return _clansmen[clansmanId];
    }

    function getActiveMission(uint32 clansmanId) external view override returns (Mission memory) {
        return _missions[clansmanId];
    }

    function getMissionTiming(uint32 clanId, uint32 clansmanId)
        external
        view
        override
        returns (uint64 submitted, uint64 executes, uint64 settles)
    {
        Mission memory m = _missions[clansmanId];
        if (!m.active || _clansmen[clansmanId].clanId != clanId) {
            return (0, 0, 0);
        }
        return (m.submittedAtTick, m.executesAtTick, m.settlesAtTick);
    }

    function isWinter() external view override returns (bool) {
        return _isWinterActiveAt(_world.currentTick);
    }

    function getWallUpgradeCost(uint8 currentLevel) public pure override returns (uint256 wood, uint256 iron) {
        return _wallUpgradeCost(currentLevel);
    }

    function getBaseUpgradeCost(uint8 currentLevel)
        public
        pure
        override
        returns (uint256 wood, uint256 iron, uint256 wheat)
    {
        return _baseUpgradeCost(currentLevel);
    }

    function getMonumentUpgradeCost(uint8 currentLevel)
        public
        pure
        override
        returns (uint256 wood, uint256 iron, uint256 wheat, uint256 blueprint)
    {
        return _monumentUpgradeCost(currentLevel);
    }

    function _wallUpgradeCost(uint8 currentLevel) internal pure returns (uint256 wood, uint256 iron) {
        if (currentLevel == 0) return (20e18, 0);
        if (currentLevel == 1) return (35e18, 0);
        if (currentLevel == 2) return (30e18, 5e18);
        if (currentLevel == 3) return (40e18, 10e18);
        if (currentLevel == 4) return (50e18, 15e18);
        return (0, 0);
    }

    function _baseUpgradeCost(uint8 currentLevel) internal pure returns (uint256 wood, uint256 iron, uint256 wheat) {
        if (currentLevel == 1) return (40e18, 0, 20e18);
        if (currentLevel == 2) return (60e18, 5e18, 30e18);
        if (currentLevel == 3) return (80e18, 10e18, 40e18);
        if (currentLevel == 4) return (100e18, 15e18, 50e18);
        return (0, 0, 0);
    }

    function _monumentUpgradeCost(uint8 currentLevel)
        internal
        pure
        returns (uint256 wood, uint256 iron, uint256 wheat, uint256 blueprint)
    {
        if (currentLevel == 0) return (30e18, 0, 20e18, 0);
        if (currentLevel == 1) return (50e18, 0, 30e18, 0);
        if (currentLevel == 2) return (70e18, 5e18, 40e18, 0);
        if (currentLevel == 3) return (90e18, 10e18, 50e18, 0);
        if (currentLevel == 4) return (120e18, 15e18, 60e18, 0);
        if (currentLevel == 5) return (150e18, 20e18, 80e18, 0);
        if (currentLevel >= 6 && currentLevel < MONUMENT_MAX_LEVEL) return (200e18, 25e18, 100e18, 1e18);
        return (0, 0, 0, 0);
    }

    function getActionDuration(ActionType action) public pure override returns (uint64) {
        if (
            action == ActionType.ChopWood || action == ActionType.MineIron || action == ActionType.FishDocks
                || action == ActionType.FishDeepSea || action == ActionType.HarvestWheat
        ) {
            return 4;
        }

        if (action == ActionType.DepositResources || action == ActionType.WithdrawResources) {
            return DEPOSIT_DURATION_TICKS;
        }

        if (
            action == ActionType.UpgradeWall || action == ActionType.UpgradeBase || action == ActionType.UpgradeMonument
        ) {
            return BUILDING_DURATION_TICKS;
        }

        if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
            return 1;
        }

        return 0;
    }

    function getTravelTicks(uint8 fromRegion, uint8 toRegion) external pure override returns (uint64) {
        return uint64(_travelTicks(fromRegion, toRegion));
    }

    function getBandit(uint32 banditId) public view override returns (BanditTroop memory) {
        BanditTroop memory bandit = _bandits[banditId];
        if (bandit.id == ClanWorldConstants.BANDIT_ID_NULL || bandit.state == BanditState.None) {
            return BanditTroop({
                id: 0,
                region: 0,
                state: BanditState.None,
                targetClanId: 0,
                tickEnteredState: 0,
                strength: 0,
                tier: 0,
                attackAttemptsMade: 0,
                carryWood: 0,
                carryIron: 0,
                carryWheat: 0,
                carryFish: 0,
                carryGold: 0
            });
        }
        return bandit;
    }

    function getBanditTroop(uint32 banditId) external view override returns (BanditTroop memory) {
        return getBandit(banditId);
    }

    function getBanditsInRegion(uint8 region) external view override returns (uint32[] memory) {
        return _banditsByRegion[region];
    }

    function getWheatPlots(uint32 clanId)
        external
        view
        override
        returns (WheatPlot memory west, WheatPlot memory east)
    {
        west = _wheatPlots[clanId][0];
        east = _wheatPlots[clanId][1];
    }

    function getScheduledMarketActionsForTick(uint64 tick)
        external
        view
        override
        returns (ScheduledMarketAction[] memory)
    {
        return _scheduledMarketActions[tick];
    }

    function getActiveDefenders(uint32 targetClanId) external view override returns (uint32[] memory clansmanIds) {
        uint32[] storage defendingClans = _defendingClansByRegion[_clans[targetClanId].baseRegion];
        uint256 count = 0;

        for (uint256 i = 0; i < defendingClans.length; i++) {
            uint32[] storage clanClansmen = _clanClansmanIds[defendingClans[i]];
            for (uint256 j = 0; j < clanClansmen.length; j++) {
                Mission storage mission = _missions[clanClansmen[j]];
                if (mission.active && mission.action == ActionType.DefendBase && mission.targetClanId == targetClanId) {
                    count++;
                }
            }
        }

        clansmanIds = new uint32[](count);
        uint256 out = 0;
        for (uint256 i = 0; i < defendingClans.length; i++) {
            uint32[] storage clanClansmen = _clanClansmanIds[defendingClans[i]];
            for (uint256 j = 0; j < clanClansmen.length; j++) {
                uint32 clansmanId = clanClansmen[j];
                Mission storage mission = _missions[clansmanId];
                if (mission.active && mission.action == ActionType.DefendBase && mission.targetClanId == targetClanId) {
                    clansmanIds[out++] = clansmanId;
                }
            }
        }
    }

    function getDefendingClans(uint8 region) external view override returns (uint32[] memory) {
        return _defendingClansByRegion[region];
    }

    // =========================================================================
    // DERIVED READ GETTERS (read-only, no storage mutation)
    // =========================================================================

    function getDerivedClanState(uint32 clanId) external view override returns (DerivedClanState memory) {
        SettlementSimulation memory sim = _simulateSettleToTick(clanId, _world.currentTick);
        return _derivedClanStateFromSimulation(sim.clan);
    }

    function getDerivedClansmanState(uint32 clansmanId) external view override returns (DerivedClansmanState memory) {
        Clansman memory cs = _clansmen[clansmanId];
        if (cs.clansmanId == 0) {
            Mission memory emptyMission;
            return DerivedClansmanState({
                clansman: cs, activeMission: emptyMission, effectiveRegion: 0, derivedAtTick: _world.currentTick
            });
        }

        SettlementSimulation memory sim = _simulateSettleToTick(cs.clanId, _world.currentTick);
        (bool found, uint256 index) = _findSimulatedClansman(sim, clansmanId);
        if (found) {
            cs = sim.clansmen[index];
            Mission memory m = sim.missions[index];
            return DerivedClansmanState({
                clansman: cs,
                activeMission: m,
                effectiveRegion: _effectiveRegion(cs, m, _world.currentTick),
                derivedAtTick: _world.currentTick
            });
        }

        Mission memory fallbackMission = _missions[clansmanId];
        return DerivedClansmanState({
            clansman: cs,
            activeMission: fallbackMission,
            effectiveRegion: _effectiveRegion(cs, fallbackMission, _world.currentTick),
            derivedAtTick: _world.currentTick
        });
    }

    function getBanditTargetPreview(uint32 banditId) external view override returns (uint32) {
        return _bandits[banditId].targetClanId;
    }

    function quoteTravel(uint8 srcRegion, uint8 dstRegion)
        external
        pure
        override
        returns (uint8 travelTicks, bytes8 path)
    {
        if (srcRegion > 8 || dstRegion > 8) {
            return (0, bytes8(0));
        }
        if (srcRegion == dstRegion || srcRegion == 0 || dstRegion == 0) {
            travelTicks = 0;
            path = bytes8(uint64(srcRegion) << 56);
            return (travelTicks, path);
        }
        travelTicks = _travelTicks(srcRegion, dstRegion);
        path = _buildPath(srcRegion, dstRegion);
    }

    function quoteLootValueRaw(uint32 clanId) external view override returns (uint256) {
        return _lootValueRaw(_clans[clanId]);
    }

    function quoteLootValueSettled(uint32 clanId) external view override returns (uint256) {
        SettlementSimulation memory sim = _simulateSettleToTick(clanId, _world.currentTick);
        // memory struct — inline to avoid ambiguity with the storage overload below
        return sim.clan.vaultWood + sim.clan.vaultWheat + sim.clan.vaultFish * 2 + sim.clan.vaultIron * 4;
    }

    function getClanScore(uint32 clanId)
        external
        view
        override
        returns (uint256 score, uint64 monumentReachedAtTick, uint8 monumentLevel)
    {
        return _getClanScore(clanId);
    }

    function getRankings() external view override returns (uint32[] memory clanIdsRanked, uint256[] memory scores) {
        uint256 scanCount = _allClanIds.length;
        if (scanCount > MAX_CLAN_SCAN_FOR_RANKING) {
            scanCount = MAX_CLAN_SCAN_FOR_RANKING;
        }

        uint32[] memory tempClanIds = new uint32[](scanCount);
        uint256[] memory tempScores = new uint256[](scanCount);
        uint256 liveCount;

        for (uint256 i = 0; i < scanCount; i++) {
            uint32 clanId = _allClanIds[i];
            SettlementSimulation memory sim = _simulateSettleToTick(clanId, _world.currentTick);
            if (sim.clan.clanState != ClanState.ACTIVE) continue;

            (uint256 score,,) = _getClanScoreFromSimulation(clanId, sim);
            tempClanIds[liveCount] = clanId;
            tempScores[liveCount] = score;
            liveCount++;
        }

        for (uint256 i = 1; i < liveCount; i++) {
            uint32 keyClanId = tempClanIds[i];
            uint256 keyScore = tempScores[i];
            uint256 j = i;
            while (j > 0 && _rankingComesAfter(tempClanIds[j - 1], tempScores[j - 1], keyClanId, keyScore)) {
                tempClanIds[j] = tempClanIds[j - 1];
                tempScores[j] = tempScores[j - 1];
                j--;
            }
            tempClanIds[j] = keyClanId;
            tempScores[j] = keyScore;
        }

        clanIdsRanked = new uint32[](liveCount);
        scores = new uint256[](liveCount);
        for (uint256 i = 0; i < liveCount; i++) {
            clanIdsRanked[i] = tempClanIds[i];
            scores[i] = tempScores[i];
        }
    }

    function _lootValueRaw(Clan memory clan) internal pure returns (uint256) {
        return _lootValueFromClanMemory(clan);
    }

    function _lootValueFromClanMemory(Clan memory clan) internal pure returns (uint256) {
        return clan.vaultWood + clan.vaultWheat + clan.vaultFish * 2 + clan.vaultIron * 4;
    }

    function _getClanScore(uint32 clanId)
        internal
        view
        returns (uint256 score, uint64 monumentReachedAtTick, uint8 monumentLevel)
    {
        SettlementSimulation memory sim = _simulateSettleToTick(clanId, _world.currentTick);
        return _getClanScoreFromSimulation(clanId, sim);
    }

    function _getClanScoreFromSimulation(uint32 clanId, SettlementSimulation memory sim)
        internal
        view
        returns (uint256 score, uint64 monumentReachedAtTick, uint8 monumentLevel)
    {
        monumentLevel = sim.clan.monumentLevel;
        if (monumentLevel > 0) {
            monumentReachedAtTick = _monumentLevelReachedAt[clanId][monumentLevel];
            if (monumentReachedAtTick == 0) {
                monumentReachedAtTick = sim.simMonumentReachedAt[monumentLevel];
            }
        }

        return _packClanScore(sim.clan, monumentReachedAtTick, monumentLevel);
    }

    function _getClanScoreFromClan(uint32 clanId, Clan memory clan)
        internal
        view
        returns (uint256 score, uint64 monumentReachedAtTick, uint8 monumentLevel)
    {
        monumentLevel = clan.monumentLevel;
        if (monumentLevel > 0) {
            monumentReachedAtTick = _monumentLevelReachedAt[clanId][monumentLevel];
        }

        return _packClanScore(clan, monumentReachedAtTick, monumentLevel);
    }

    function _packClanScore(Clan memory clan, uint64 monumentReachedAtTick, uint8 monumentLevel)
        internal
        pure
        returns (uint256 score, uint64, uint8)
    {
        uint256 lootValue = _lootValueFromClanMemory(clan);
        uint256 maxLootComponent = (uint256(1) << 176) - 1;
        if (lootValue > maxLootComponent) {
            lootValue = maxLootComponent;
        }

        uint256 timeComponent;
        if (monumentLevel > 0) {
            timeComponent = uint256(type(uint64).max) - uint256(monumentReachedAtTick);
        }

        score = (uint256(monumentLevel) << 248) | (timeComponent << 184) | (lootValue << 8) | clan.wallLevel;
        return (score, monumentReachedAtTick, monumentLevel);
    }

    function _rankingComesAfter(uint32 leftClanId, uint256 leftScore, uint32 rightClanId, uint256 rightScore)
        internal
        pure
        returns (bool)
    {
        if (leftScore != rightScore) {
            return leftScore < rightScore;
        }
        return leftClanId > rightClanId;
    }

    function _derivedClanStateFromSimulation(Clan memory clan) internal view returns (DerivedClanState memory) {
        bool starving = clan.starvationStartsAtTick != 0 && clan.starvationStartsAtTick <= _world.currentTick;
        // memory struct — inline to avoid ambiguity with the storage overload of _lootValueRaw
        uint256 lootValue = clan.vaultWood + clan.vaultWheat + clan.vaultFish * 2 + clan.vaultIron * 4;
        return
            DerivedClanState({
                clan: clan, isStarving: starving, lootValue: lootValue, derivedAtTick: _world.currentTick
            });
    }

    function _findSimulatedClansman(SettlementSimulation memory sim, uint32 clansmanId)
        internal
        pure
        returns (bool found, uint256 index)
    {
        for (uint256 i = 0; i < sim.clansmen.length; i++) {
            if (sim.clansmen[i].clansmanId == clansmanId) {
                return (true, i);
            }
        }
    }

    function _effectiveRegion(Clansman memory cs, Mission memory m, uint64 tick) internal pure returns (uint8) {
        if (cs.state == ClansmanState.TRAVELING && m.active) {
            return tick >= m.arrivalTick ? m.targetRegion : m.startRegion;
        }
        return cs.currentRegion;
    }

    // =========================================================================
    // UI INDEXER AGGREGATOR GETTERS
    // =========================================================================

    /// @dev Leaderboard loot values reflect vault contents only (last-settled state).
    ///      Carry amounts not included. Full view-only settlement deferred.
    ///      View function — no gas cost for off-chain indexer/UI reads.
    ///      Iterates all clans. Canonical game cap: ≤12 clans, ≤4 clansmen each = ≤48 iterations.
    function getWorldSnapshot() external view override returns (WorldSnapshot memory) {
        LeaderboardEntry[] memory lb = new LeaderboardEntry[](_allClanIds.length);
        for (uint256 i = 0; i < _allClanIds.length; i++) {
            uint32 cid = _allClanIds[i];
            Clan storage clan = _clans[cid];
            lb[i] = LeaderboardEntry({
                clanId: cid,
                owner: clan.owner,
                monumentLevel: clan.monumentLevel,
                baseLevel: clan.baseLevel,
                wallLevel: clan.wallLevel,
                livingClansmen: clan.livingClansmen,
                state: clan.clanState,
                lootValue: _lootValueRaw(clan)
            });
        }

        WorldState memory ws = _worldStateView();
        return WorldSnapshot({
            currentTick: ws.currentTick,
            seasonStartTick: ws.seasonStartTick,
            seasonEndTick: ws.seasonEndTick,
            seasonFinalized: ws.seasonFinalized,
            currentSeasonNumber: ws.currentSeasonNumber,
            nextHeartbeatAtTick: ws.nextHeartbeatAtTick,
            winterActive: ws.winterActive,
            winterStartsAtTick: ws.winterStartsAtTick,
            winterEndsAtTick: ws.winterEndsAtTick,
            activeBanditId: ws.activeBanditId,
            currentTickSeed: ws.currentTickSeed,
            leaderboard: lb
        });
    }

    function getClanFullView(uint32 clanId) external view override returns (ClanFullView memory) {
        SettlementSimulation memory sim = _simulateSettleToTick(clanId, _world.currentTick);
        DerivedClanState memory derivedClan = _derivedClanStateFromSimulation(sim.clan);

        ClansmanFullView[] memory clansmen = new ClansmanFullView[](sim.clansmen.length);
        for (uint256 i = 0; i < sim.clansmen.length; i++) {
            Clansman memory cs = sim.clansmen[i];
            Mission memory m = sim.missions[i];
            DerivedClansmanState memory dcs = DerivedClansmanState({
                clansman: cs,
                activeMission: m,
                effectiveRegion: _effectiveRegion(cs, m, _world.currentTick),
                derivedAtTick: _world.currentTick
            });
            clansmen[i] = ClansmanFullView({clansman: dcs, activeMission: m});
        }

        uint32 thisClanDefendingBaseId = 0;
        for (uint256 i = 0; i < sim.clansmen.length; i++) {
            if (
                sim.missions[i].active && sim.missions[i].action == ActionType.DefendBase
                    && sim.clansmen[i].state == ClansmanState.ACTING
            ) {
                thisClanDefendingBaseId = sim.missions[i].targetRegion;
                break;
            }
        }
        if (thisClanDefendingBaseId == 0) {
            uint32[] storage csIds = _clanClansmanIds[clanId];
            for (uint256 i = 0; i < csIds.length; i++) {
                uint8 region = _clansmanDefendingRegion[csIds[i]];
                if (region != 0) {
                    thisClanDefendingBaseId = region;
                    break;
                }
            }
        }

        return ClanFullView({
            clan: derivedClan,
            clansmen: clansmen,
            westPlot: sim.wheatPlots[0],
            eastPlot: sim.wheatPlots[1],
            incomingDefenderIds: _defendingClansByRegion[sim.clan.baseRegion],
            thisClanDefendingBaseId: thisClanDefendingBaseId
        });
    }

    function getMarketState() external view override returns (MarketState memory) {
        return MarketState({
            wood: _poolReserves(_treasury.woodToken, _treasury.woodGoldPool),
            wheat: _poolReserves(_treasury.wheatToken, _treasury.wheatGoldPool),
            fish: _poolReserves(_treasury.fishToken, _treasury.fishGoldPool),
            iron: _poolReserves(_treasury.ironToken, _treasury.ironGoldPool),
            currentTick: _world.currentTick,
            currentTickQueue: _scheduledMarketActions[_world.currentTick],
            nextTickQueue: _scheduledMarketActions[_world.currentTick + 1]
        });
    }

    function _poolReserves(address resourceToken, address poolAddr) internal view returns (PoolReserves memory pr) {
        pr.resourceToken = resourceToken;
        if (poolAddr == address(0) || resourceToken == address(0)) {
            return pr;
        }
        (uint256 rA, uint256 rB) = StubPool(poolAddr).getReserves();
        pr.resourceReserve = rA;
        pr.goldReserve = rB;
        pr.spotPriceGoldPerResource = rA > 0 ? (rB * 1e18) / rA : 0;
    }

    function getActiveBanditView() external view override returns (ActiveBanditView memory) {
        BanditTroop memory bandit = _bandits[_world.activeBanditId];
        uint64 nextActionTick = 0;
        uint8 maxAttemptsRemaining = 0;
        bool exists = bandit.id != ClanWorldConstants.BANDIT_ID_NULL && bandit.state != BanditState.None;
        if (exists) {
            if (bandit.state == BanditState.Spawned) {
                nextActionTick = bandit.tickEnteredState + 1;
            } else if (bandit.state == BanditState.Camped) {
                nextActionTick = bandit.tickEnteredState + ClanWorldConstants.BANDIT_CAMP_TICKS;
            } else if (bandit.state == BanditState.Resting) {
                nextActionTick = bandit.tickEnteredState + ClanWorldConstants.BANDIT_REST_TICKS;
            }
            if (bandit.attackAttemptsMade < ClanWorldConstants.BANDIT_MAX_ATTACK_ATTEMPTS) {
                maxAttemptsRemaining = ClanWorldConstants.BANDIT_MAX_ATTACK_ATTEMPTS - bandit.attackAttemptsMade;
            }
        }

        return ActiveBanditView({
            exists: exists,
            banditId: bandit.id,
            state: bandit.state,
            currentRegion: bandit.region,
            attackAttemptsMade: bandit.attackAttemptsMade,
            maxAttemptsRemaining: maxAttemptsRemaining,
            stateEnteredTick: bandit.tickEnteredState,
            nextActionTick: nextActionTick,
            tier: bandit.tier,
            attackPower: _banditStrengthForLegacyEvent(bandit.strength),
            carryWood: bandit.carryWood,
            carryIron: bandit.carryIron,
            carryWheat: bandit.carryWheat,
            carryFish: bandit.carryFish,
            projectedTargetClanId: bandit.targetClanId,
            projectedTargetLootValue: 0 // projected — loot estimation not implemented
        });
    }

    /// @dev View function — no gas cost for off-chain indexer/UI reads.
    ///      Iterates all clans. Canonical game cap: ≤12 clans, ≤4 clansmen each = ≤48 iterations.
    function getRegionPopulation(uint8 region) external view override returns (RegionOccupant[] memory) {
        // Count matching occupants first
        uint256 count = 0;
        for (uint256 i = 0; i < _allClanIds.length; i++) {
            uint32 cid = _allClanIds[i];
            uint32[] storage csIds = _clanClansmanIds[cid];
            for (uint256 j = 0; j < csIds.length; j++) {
                Clansman storage cs = _clansmen[csIds[j]];
                if (cs.state != ClansmanState.DEAD && cs.currentRegion == region) {
                    count++;
                }
            }
        }

        RegionOccupant[] memory occupants = new RegionOccupant[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < _allClanIds.length; i++) {
            uint32 cid = _allClanIds[i];
            uint32[] storage csIds = _clanClansmanIds[cid];
            for (uint256 j = 0; j < csIds.length; j++) {
                uint32 clansmanId = csIds[j];
                Clansman storage cs = _clansmen[clansmanId];
                if (cs.state != ClansmanState.DEAD && cs.currentRegion == region) {
                    Mission storage m = _missions[clansmanId];
                    occupants[idx++] = RegionOccupant({
                        clansmanId: clansmanId,
                        clanId: cid,
                        state: cs.state,
                        currentAction: m.active ? m.action : ActionType.None,
                        missionNonce: cs.lastMissionNonce
                    });
                }
            }
        }
        return occupants;
    }
}
