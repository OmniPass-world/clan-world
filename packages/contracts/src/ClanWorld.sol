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
import {StubPool} from "./StubPool.sol";
import {ReentrancyGuard} from "./util/ReentrancyGuard.sol";

/// @title ClanWorld
/// @notice Phase 1+2 real engine implementation of IClanWorld v4.
///         Implements: world clock, clan lifecycle, lazy settlement, resource gathering,
///         deposit, wheat harvest, travel, NOOP bypass, order validation, and market execution.
///         Phase 2 is implemented; Phase 3 (bandits, winter damage) remains stubbed.
contract ClanWorld is IClanWorld, ReentrancyGuard {
    // =========================================================================
    // STORAGE
    // =========================================================================

    WorldState private _world;
    TreasuryState private _treasury;

    mapping(uint32 => Clan) internal _clans;
    mapping(uint32 => Clansman) internal _clansmen;
    mapping(uint32 => Mission) private _missions; // keyed by clansmanId
    mapping(uint32 => WheatPlot[2]) private _wheatPlots; // [0]=west [1]=east
    mapping(uint64 => ScheduledMarketAction[]) private _scheduledMarketActions; // keyed by tick
    mapping(uint8 => uint32[]) private _defendingClansByRegion; // home region => unique defending clanIds
    mapping(uint8 => mapping(uint32 => uint256)) private _defenderCountByRegionClan; // region => clanId => clansmen count
    mapping(uint32 => uint8) private _clansmanDefendingRegion; // clansmanId => defended home region
    mapping(uint32 => BanditTroop) internal _bandits;
    mapping(uint8 => uint32[]) internal _banditsByRegion; // region => bandit IDs
    mapping(uint8 => BanditSpawnState) internal _banditSpawnByRegion;
    mapping(uint64 => bytes32) private _tickSeeds; // tick => seed

    uint32 private _nextClanId;
    uint32 private _nextClansmanId;
    uint32 internal _nextBanditId;
    uint32 internal _activeBanditCount;
    uint32[] private _allClanIds;

    // per-clan clansman list: clanId => clansmanId[]
    mapping(uint32 => uint32[]) private _clanClansmanIds;

    // =========================================================================
    // CONSTANTS — Wheat harvest rate (not in IClanWorld constants)
    // =========================================================================

    uint256 private constant WHEAT_HARVEST_RATE = 20e18;
    /// @dev Caps market queue work per heartbeat; overflow is deferred to the next tick.
    uint256 public constant MAX_MARKET_ACTIONS_PER_TICK = 32;
    uint256 internal constant DOMAIN_BANDIT_SPAWN = uint256(keccak256("clanworld.bandit.spawn.v1"));
    uint64 internal constant MIN_SPAWN_COOLDOWN_TICKS = ClanWorldConstants.BANDIT_COOLDOWN_TICKS;
    uint16 internal constant BANDIT_SPAWN_PROBABILITY_INCREMENT_BPS = 1000;
    uint16 internal constant BANDIT_SPAWN_MAX_PROBABILITY_BPS = 8000;
    uint8 internal constant MAX_BANDITS_PER_REGION = 3;
    uint8 internal constant MAX_TOTAL_BANDITS = 8;
    /// @dev Bandit spawn weights are a heartbeat-time heuristic. Bound the scan
    ///      and rotate the starting clan by tick so larger worlds do not turn
    ///      spawn preview/selection into an unbounded heartbeat cost.
    uint256 internal constant MAX_BANDIT_SPAWN_SCAN_PER_REGION = 8;
    uint256 internal constant MAX_BANDIT_SPAWN_CLANSMEN_SCAN_PER_REGION = MAX_BANDIT_SPAWN_SCAN_PER_REGION * 4;
    uint32 internal constant MIN_BANDIT_SPAWN_STRENGTH = 100;
    uint32 internal constant BANDIT_SPAWN_STRENGTH_SPREAD = 151;

    struct BanditSpawnState {
        uint64 lastSpawnTick;
        uint16 probabilityAccum;
    }

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
        // First winter: last WINTER_DURATION_TICKS of first TICKS_PER_WINTER_CYCLE cycle
        // i.e. ticks [100, 110)
        _world.winterStartsAtTick =
            ClanWorldConstants.TICKS_PER_WINTER_CYCLE - ClanWorldConstants.WINTER_DURATION_TICKS; // = 100
        _world.winterEndsAtTick = ClanWorldConstants.TICKS_PER_WINTER_CYCLE; // = 110
        _world.winterActive = false;
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
                    _completeMission(cs, m);
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
        uint64 maxSettleTicks = 200;
        if (curTick > fromTick + maxSettleTicks) {
            curTick = fromTick + maxSettleTicks;
        }

        uint32[] storage clansmanIds = _clanClansmanIds[clanId];

        // Settle tick by tick from fromTick to curTick - 1
        // (curTick is still open; we settle through the last closed tick)
        for (uint64 tick = fromTick; tick < curTick; tick++) {
            // 1. Apply upkeep for this tick
            _applyUpkeep(clan, tick);

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

        clan.lastSettledTick = curTick;
        emit ClanSettled(clanId, curTick);
    }

    /// @dev Apply one tick of upkeep. Marks starvation if insufficient food.
    function _applyUpkeep(Clan storage clan, uint64 tick) internal {
        if (clan.livingClansmen == 0) return;

        uint256 wheatNeeded = uint256(clan.livingClansmen) * ClanWorldConstants.WHEAT_UPKEEP_PER_CLANSMAN;
        uint256 fishNeeded = uint256(clan.livingClansmen) * ClanWorldConstants.FISH_UPKEEP_PER_CLANSMAN;

        bool hadEnoughWheat = clan.vaultWheat >= wheatNeeded;
        bool hadEnoughFish = clan.vaultFish >= fishNeeded;

        if (hadEnoughWheat) {
            clan.vaultWheat -= wheatNeeded;
        } else {
            clan.vaultWheat = 0;
        }
        if (hadEnoughFish) {
            clan.vaultFish -= fishNeeded;
        } else {
            clan.vaultFish = 0;
        }

        bool starving = !hadEnoughWheat || !hadEnoughFish;
        if (starving && clan.starvationStartsAtTick == 0) {
            clan.starvationStartsAtTick = tick;
            emit ClanStarvationChanged(clan.clanId, true, tick);
        } else if (!starving && clan.starvationStartsAtTick != 0) {
            clan.starvationStartsAtTick = 0;
            emit ClanStarvationChanged(clan.clanId, false, tick);
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
        } else if (action == ActionType.Wait) {
            // NOOP — worker stays ACTING (continuous), no transition needed
            // Wait mission is effectively persistent until interrupted
        } else if (action == ActionType.DefendBase) {
            // Persistent mission. Registration happens atomically at order submission.
        } else if (
            action == ActionType.BuildWall || action == ActionType.UpgradeBase || action == ActionType.UpgradeMonument
        ) {
            // Phase 1 stub: check homebase, check resources; if ok, stub success
            _doBuilding(clan, cs, m, clanId, tick, action);
        } else if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
            // Scheduled market actions: already enqueued at submitClanOrders time.
            // Settlement resolves this action slot — just complete the mission.
            // (Actual execution happened or will happen at heartbeat.)
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

        bool success = false;
        if (action == ActionType.BuildWall) {
            success = _tryBuildWall(clan, clanId, tick);
        } else if (action == ActionType.UpgradeBase) {
            success = _tryUpgradeBase(clan, clanId, tick);
        } else if (action == ActionType.UpgradeMonument) {
            success = _tryUpgradeMonument(clan, clanId, tick);
        }

        if (!success) {
            // Resources missing — worker transitions to WAITING
        }
        _completeMission(cs, m);
    }

    function _tryBuildWall(Clan storage clan, uint32 clanId, uint64 tick) internal returns (bool) {
        uint8 nextLevel = clan.wallLevel + 1;
        if (nextLevel > 5) return false;

        uint256 woodCost;
        uint256 ironCost;

        if (nextLevel == 1) {
            woodCost = 20e18;
            ironCost = 0;
        } else if (nextLevel == 2) {
            woodCost = 35e18;
            ironCost = 0;
        } else if (nextLevel == 3) {
            woodCost = 30e18;
            ironCost = 5e18;
        } else if (nextLevel == 4) {
            woodCost = 40e18;
            ironCost = 10e18;
        } else {
            woodCost = 50e18;
            ironCost = 15e18;
        }

        if (clan.vaultWood < woodCost || clan.vaultIron < ironCost) return false;

        clan.vaultWood -= woodCost;
        clan.vaultIron -= ironCost;
        uint8 old = clan.wallLevel;
        clan.wallLevel = nextLevel;
        emit WallLevelChanged(clanId, old, nextLevel, tick);
        return true;
    }

    function _tryUpgradeBase(Clan storage clan, uint32 clanId, uint64 tick) internal returns (bool) {
        uint8 nextLevel = clan.baseLevel + 1;
        if (nextLevel > 5) return false;

        uint256 woodCost;
        uint256 ironCost;
        uint256 wheatCost;

        if (nextLevel == 2) {
            woodCost = 40e18;
            ironCost = 0;
            wheatCost = 20e18;
        } else if (nextLevel == 3) {
            woodCost = 60e18;
            ironCost = 5e18;
            wheatCost = 30e18;
        } else if (nextLevel == 4) {
            woodCost = 80e18;
            ironCost = 10e18;
            wheatCost = 40e18;
        } else {
            woodCost = 100e18;
            ironCost = 15e18;
            wheatCost = 50e18;
        }

        if (clan.vaultWood < woodCost || clan.vaultIron < ironCost || clan.vaultWheat < wheatCost) return false;

        clan.vaultWood -= woodCost;
        clan.vaultIron -= ironCost;
        clan.vaultWheat -= wheatCost;
        uint8 old = clan.baseLevel;
        clan.baseLevel = nextLevel;
        emit BaseLevelChanged(clanId, old, nextLevel, tick);
        return true;
    }

    function _tryUpgradeMonument(Clan storage clan, uint32 clanId, uint64 tick) internal returns (bool) {
        uint8 nextLevel = clan.monumentLevel + 1;
        if (nextLevel > 10) return false;

        uint256 woodCost;
        uint256 wheatCost;
        uint256 ironCost;
        uint256 blueprintCost;

        if (nextLevel == 1) {
            woodCost = 30e18;
            wheatCost = 20e18;
        } else if (nextLevel == 2) {
            woodCost = 50e18;
            wheatCost = 30e18;
        } else if (nextLevel == 3) {
            woodCost = 70e18;
            wheatCost = 40e18;
            ironCost = 5e18;
        } else if (nextLevel == 4) {
            woodCost = 90e18;
            wheatCost = 50e18;
            ironCost = 10e18;
        } else if (nextLevel == 5) {
            woodCost = 120e18;
            wheatCost = 60e18;
            ironCost = 15e18;
        } else if (nextLevel == 6) {
            woodCost = 150e18;
            wheatCost = 80e18;
            ironCost = 20e18;
        } else if (nextLevel <= 10) {
            woodCost = 200e18;
            wheatCost = 100e18;
            ironCost = 25e18;
            blueprintCost = 1e18;
        }

        if (
            clan.vaultWood < woodCost || clan.vaultWheat < wheatCost || clan.vaultIron < ironCost
                || clan.blueprintBalance < blueprintCost
        ) return false;

        clan.vaultWood -= woodCost;
        clan.vaultWheat -= wheatCost;
        clan.vaultIron -= ironCost;
        clan.blueprintBalance -= blueprintCost;

        uint8 old = clan.monumentLevel;
        clan.monumentLevel = nextLevel;
        emit MonumentLevelChanged(clanId, old, nextLevel, tick);
        return true;
    }

    /// @dev Complete a mission: set worker to WAITING, set cooldown, mark mission inactive, emit event.
    function _completeMission(Clansman storage cs, Mission storage m) internal {
        cs.state = ClansmanState.WAITING;
        cs.cooldownEndsAtTs = uint64(block.timestamp) + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS;
        m.active = false;
        emit MissionCompleted(_clans[cs.clanId].clanId, cs.clansmanId, m.nonce, m.action);
    }

    // =========================================================================
    // BANDIT STATE MACHINE
    // =========================================================================

    function _spawnBandit(uint8 region, uint32 strength) internal returns (uint32 id) {
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
            strength: strength
        });
        _banditsByRegion[region].push(id);
        _activeBanditCount += 1;

        BanditSpawnState storage spawnState = _banditSpawnByRegion[region];
        spawnState.lastSpawnTick = _world.currentTick;
        spawnState.probabilityAccum = 0;

        if (_world.activeBanditId == ClanWorldConstants.BANDIT_ID_NULL) {
            _world.activeBanditId = id;
        }

        emit BanditSpawned(id, region, 0, _banditStrengthForLegacyEvent(strength));
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
        return newState == BanditState.Camped && _world.currentTick >= bandit.tickEnteredState + 1;
    }

    function _canBanditLeaveCamped(BanditTroop storage bandit, BanditState newState) internal view returns (bool) {
        return newState == BanditState.Attacking && bandit.targetClanId != ClanWorldConstants.CLAN_ID_NULL
            && _world.currentTick >= bandit.tickEnteredState + ClanWorldConstants.BANDIT_CAMP_TICKS;
    }

    function _canBanditLeaveAttacking(BanditState newState) internal pure returns (bool) {
        return newState == BanditState.Defeated || newState == BanditState.Escaped;
    }

    function _canBanditLeaveEscaped(BanditState newState) internal pure returns (bool) {
        return newState == BanditState.Resting;
    }

    function _canBanditLeaveResting(BanditTroop storage bandit, BanditState newState) internal view returns (bool) {
        return newState == BanditState.Camped
            && _world.currentTick >= bandit.tickEnteredState + ClanWorldConstants.BANDIT_REST_TICKS;
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

    function _banditStrengthForLegacyEvent(uint32 strength) internal pure returns (uint16) {
        if (strength > type(uint16).max) return type(uint16).max;
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(strength);
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
            _spawnBandit(selectedRegion, _banditSpawnStrength(tickSeed, selectedRegion));
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

    function _banditSpawnStrength(bytes32 tickSeed, uint8 region) internal pure returns (uint32) {
        uint256 nonce = uint256(keccak256(abi.encodePacked("bandit_spawn_strength", region)));
        uint256 roll = RNG.rngBounded(tickSeed, DOMAIN_BANDIT_SPAWN, nonce, BANDIT_SPAWN_STRENGTH_SPREAD);
        // forge-lint: disable-next-line(unsafe-typecast)
        return MIN_BANDIT_SPAWN_STRENGTH + uint32(roll);
    }

    function _banditSpawnRegionWeights() internal view returns (uint256[] memory weights) {
        weights = new uint256[](8);
        uint256 clanCount = _allClanIds.length;
        if (clanCount == 0) {
            return weights;
        }

        uint256 scanCount =
            clanCount < MAX_BANDIT_SPAWN_SCAN_PER_REGION ? clanCount : MAX_BANDIT_SPAWN_SCAN_PER_REGION;
        uint256 startIndex = uint256(_world.currentTick) % clanCount;
        uint256 clansmenScanned;
        for (uint256 i = 0; i < scanCount; i++) {
            Clan storage clan = _clans[_allClanIds[(startIndex + i) % clanCount]];
            if (clan.clanState == ClanState.DEAD) {
                continue;
            }

            if (clan.baseRegion >= ClanWorldConstants.REGION_FOREST && clan.baseRegion <= ClanWorldConstants.REGION_DEEP_SEA) {
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
                    && _banditsByRegion[region].length < MAX_BANDITS_PER_REGION
                    && eligibleTick < nextEligibleTick
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
    ///         3. Eager-settle clans touched by world events (Phase 9 stub).
    ///         4. Resolve closed-tick bandit/world events.
    ///         5. Increment tick and publish the next tick seed atomically.
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

        // Step 3: Eager-settle clans touched by world events (Phase 9 bandit — stub).
        // TODO Phase 9: _settleClansNearBandit(closedTick);

        // Step 4: Evaluate deterministic bandit spawns for the closed tick.
        _evaluateBanditSpawns(closedTickSeed);

        // Step 5: Resolve world events (season boundary, winter transitions).
        _resolveWorldEvents(closedTick);

        // Step 6: Increment tick and publish the opened tick seed as one visible state transition.
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
            // reset winter timers for new season
            _world.winterActive = false;
            _world.winterStartsAtTick = _world.seasonStartTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE
                - ClanWorldConstants.WINTER_DURATION_TICKS;
            _world.winterEndsAtTick = _world.seasonStartTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE;
        }

        // --- winter transitions (timer only; mechanics = Phase 10) ---
        if (
            !_world.winterActive && newTick >= _world.winterStartsAtTick
                && _world.winterStartsAtTick < _world.seasonEndTick
        ) {
            _world.winterActive = true;
            emit WinterStarted(newTick);
        }
        if (_world.winterActive && newTick >= _world.winterEndsAtTick) {
            _world.winterActive = false;
            emit WinterEnded(newTick);
            // schedule next winter cycle within this season
            uint64 nextWinterStart = _world.winterEndsAtTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE
                - ClanWorldConstants.WINTER_DURATION_TICKS;
            uint64 nextWinterEnd = _world.winterEndsAtTick + ClanWorldConstants.TICKS_PER_WINTER_CYCLE;
            if (nextWinterStart < _world.seasonEndTick) {
                _world.winterStartsAtTick = nextWinterStart;
                _world.winterEndsAtTick = nextWinterEnd;
            } else {
                // no more winters this season; sentinel = seasonEndTick so guard never fires
                _world.winterStartsAtTick = _world.seasonEndTick;
                _world.winterEndsAtTick = _world.seasonEndTick;
            }
        }
    }

    /// @notice Public settlement trigger — lazily settle a clan.
    function settleClan(uint32 clanId) external override nonReentrant {
        _settleClan(clanId);
    }

    /// @notice Lazily settle a single clansman's mission to current tick. Idempotent.
    ///         Internally settles the entire clan (including upkeep) to guarantee
    ///         correct ordering and prevent double-settlement. Callers may call this
    ///         or settleClan interchangeably; both are safe and idempotent.
    function settleClansman(uint32 csId) external override nonReentrant {
        Clansman storage cs = _clansmen[csId];
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
        require(_allClanIds.length < 12, "ClanWorld: max clans");
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

        // Wheat plots
        _wheatPlots[clanId][0] = WheatPlot({
            state: WheatPlotState.Harvestable,
            region: ClanWorldConstants.REGION_WEST_FARMS,
            remainingWheat: ClanWorldConstants.WHEAT_PLOT_STARTING_WHEAT,
            regrowUntilTick: 0
        });
        _wheatPlots[clanId][1] = WheatPlot({
            state: WheatPlotState.Harvestable,
            region: ClanWorldConstants.REGION_EAST_FARMS,
            remainingWheat: ClanWorldConstants.WHEAT_PLOT_STARTING_WHEAT,
            regrowUntilTick: 0
        });

        // Create 4 clansmen
        for (uint256 i = 0; i < 4; i++) {
            uint32 csId = _nextClansmanId++;
            Clansman storage cs = _clansmen[csId];
            cs.clansmanId = csId;
            cs.clanId = clanId;
            cs.state = ClansmanState.WAITING;
            cs.currentRegion = baseRegion;
            cs.cooldownEndsAtTs = 0;
            cs.lastMissionNonce = 0;
            cs.carryWood = 0;
            cs.carryIron = 0;
            cs.carryWheat = 0;
            cs.carryFish = 0;
            _clanClansmanIds[clanId].push(csId);
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
        // ERR_MUST_SETTLE_FIRST not in StatusCode enum — using ERR_INVALID_ACTION as the closest proxy
        {
            uint64 lastSettled = _clans[clanId].lastSettledTick;
            if (_world.currentTick > lastSettled + 200) {
                results = new OrderResult[](orders.length);
                for (uint256 i = 0; i < orders.length; i++) {
                    results[i] = OrderResult({
                        clansmanId: orders[i].clansmanId,
                        status: StatusCode.ERR_INVALID_ACTION,
                        cooldownEndsAtTs: 0,
                        missionNonce: 0
                    });
                }
                return results;
            }
        }

        // Lazy settle before processing orders
        _settleClan(clanId);

        results = new OrderResult[](orders.length);

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

        // Cooldown check
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

        // NOOP bypass: treat 0 as "stay here"; DefendBase requires explicit home region.
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

        // v4.2 §8 L758: "executes at heartbeat closing tick T" where T = arrivalTick.
        // executeAtTick = arrivalTick (not arrivalTick+1).
        if (order.action == ActionType.MarketBuy || order.action == ActionType.MarketSell) {
            _enqueueScheduledMarketAction(clanId, order, cs.clansmanId, ctx.arrivalTick, ctx.newNonce);
        }

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
    }

    function _enqueueScheduledMarketAction(
        uint32 clanId,
        ClanOrder calldata order,
        uint32 clansmanId,
        uint64 executeAtTick,
        uint64 missionNonce
    ) internal {
        ScheduledMarketAction memory sma = ScheduledMarketAction({
            executeAtTick: executeAtTick,
            commitSequence: _world.nextCommitSequence++,
            missionNonce: missionNonce,
            clanId: clanId,
            clansmanId: clansmanId,
            action: order.action,
            marketToken: order.marketToken,
            marketAmount: order.marketAmount,
            maxGoldIn: order.maxGoldIn
        });
        _scheduledMarketActions[executeAtTick].push(sma);
        emit ScheduledMarketActionCommitted(
            executeAtTick,
            sma.commitSequence,
            clanId,
            clansmanId,
            order.action,
            order.marketToken,
            order.marketAmount,
            order.maxGoldIn
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
    // MARKET EXECUTION (Phase 2)
    // =========================================================================

    /// @dev Execute up to MAX_MARKET_ACTIONS_PER_TICK scheduled market actions for the given tick.
    ///      Overflow is appended to the next tick to keep heartbeat gas bounded.
    function _executeScheduledMarketActions(uint64 tick) internal {
        ScheduledMarketAction[] storage actions = _scheduledMarketActions[tick];
        uint256 len = actions.length;
        if (len == 0) return;

        uint256 processCount = len > MAX_MARKET_ACTIONS_PER_TICK ? MAX_MARKET_ACTIONS_PER_TICK : len;

        for (uint256 i = 0; i < processCount; i++) {
            ScheduledMarketAction storage sma = actions[i];

            // Validate clansman still belongs to the clan
            Clansman storage cs = _clansmen[sma.clansmanId];
            if (cs.clanId != sma.clanId || cs.state == ClansmanState.DEAD) {
                emit MarketActionFailed(sma.clanId, sma.clansmanId, sma.action, StatusCode.ERR_INVALID_CLANSMAN);
                continue;
            }

            // Guard: clansman was re-tasked if mission action no longer matches the queued type.
            // Note: _completeMission sets m.active=false during settlement (by design), so we
            // cannot use m.active as a validity signal here — check action type and nonce.
            Mission storage m = _missions[sma.clansmanId];
            if (m.action != sma.action || m.nonce != sma.missionNonce) {
                emit MarketActionFailed(sma.clanId, sma.clansmanId, sma.action, StatusCode.ERR_INVALID_ACTION);
                continue;
            }

            if (sma.action == ActionType.MarketSell) {
                try this._executeMarketSellExternal(
                    tick, sma.clanId, sma.clansmanId, sma.marketToken, sma.marketAmount, sma.commitSequence
                ) {
                // success
                }
                catch {
                    emit MarketActionFailed(sma.clanId, sma.clansmanId, sma.action, StatusCode.ERR_INVALID_ACTION);
                }
            } else if (sma.action == ActionType.MarketBuy) {
                try this._executeMarketBuyExternal(
                    tick,
                    sma.clanId,
                    sma.clansmanId,
                    sma.marketToken,
                    sma.marketAmount,
                    sma.maxGoldIn,
                    sma.commitSequence
                ) {
                // success
                }
                catch {
                    emit MarketActionFailed(sma.clanId, sma.clansmanId, sma.action, StatusCode.ERR_INVALID_ACTION);
                }
            }
        }

        if (len > processCount) {
            ScheduledMarketAction[] storage nextActions = _scheduledMarketActions[tick + 1];
            for (uint256 i = processCount; i < len; i++) {
                nextActions.push(actions[i]);
            }
            // Invariant: each tick queue executes in global commitSequence order, including
            // older overflow actions merged into a tick that already has native actions.
            _sortScheduledMarketActionsByCommitSequence(nextActions);
        }

        delete _scheduledMarketActions[tick];
    }

    function _sortScheduledMarketActionsByCommitSequence(ScheduledMarketAction[] storage actions) internal {
        for (uint256 i = 1; i < actions.length; i++) {
            ScheduledMarketAction memory key = actions[i];
            uint256 j = i;
            while (j > 0 && actions[j - 1].commitSequence > key.commitSequence) {
                actions[j] = actions[j - 1];
                j--;
            }
            actions[j] = key;
        }
    }

    /// @dev External wrapper for _executeMarketSell — enables try/catch from heartbeat loop.
    function _executeMarketSellExternal(
        uint64 closedTick,
        uint32 clanId,
        uint32 clansmanId,
        address token,
        uint256 amount,
        uint64 commitSequence
    ) external {
        require(msg.sender == address(this), "ClanWorld: internal only");
        _executeMarketSell(closedTick, clanId, clansmanId, token, amount, commitSequence);
    }

    /// @dev External wrapper for _executeMarketBuy — enables try/catch from heartbeat loop.
    function _executeMarketBuyExternal(
        uint64 closedTick,
        uint32 clanId,
        uint32 clansmanId,
        address token,
        uint256 amountOut,
        uint256 maxGoldIn,
        uint64 commitSequence
    ) external {
        require(msg.sender == address(this), "ClanWorld: internal only");
        _executeMarketBuy(closedTick, clanId, clansmanId, token, amountOut, maxGoldIn, commitSequence);
    }

    /// @dev Map a resource token address to its pool address.
    function _poolFor(address token) internal view returns (address pool) {
        if (token == _treasury.woodToken) return _treasury.woodGoldPool;
        if (token == _treasury.ironToken) return _treasury.ironGoldPool;
        if (token == _treasury.wheatToken) return _treasury.wheatGoldPool;
        if (token == _treasury.fishToken) return _treasury.fishGoldPool;
        return address(0);
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

    /// @dev Deduct an amount of a resource token from the clan vault. Returns false if insufficient.
    function _deductFromVault(Clan storage clan, address token, uint256 amount) internal returns (bool) {
        if (token == _treasury.woodToken) {
            if (clan.vaultWood < amount) return false;
            clan.vaultWood -= amount;
            return true;
        }
        if (token == _treasury.ironToken) {
            if (clan.vaultIron < amount) return false;
            clan.vaultIron -= amount;
            return true;
        }
        if (token == _treasury.wheatToken) {
            if (clan.vaultWheat < amount) return false;
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

    /// @dev Execute a scheduled market sell: deduct resource from vault, credit gold.
    function _executeMarketSell(
        uint64 closedTick,
        uint32 clanId,
        uint32 clansmanId,
        address token,
        uint256 amount,
        uint64 commitSequence
    ) internal {
        if (!_treasury.poolsSeeded) {
            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketSell, StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN);
            return;
        }
        address poolAddr = _poolFor(token);
        if (poolAddr == address(0)) {
            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketSell, StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN);
            return;
        }

        Clan storage clan = _clans[clanId];
        if (!_deductFromVault(clan, token, amount)) {
            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketSell, StatusCode.ERR_MISSING_RESOURCES);
            return;
        }

        uint256 goldOut = StubPool(poolAddr).sellResource(amount);
        clan.goldBalance += goldOut;

        emit ScheduledMarketActionExecuted(
            closedTick, commitSequence, clanId, clansmanId, token, _treasury.goldToken, amount, goldOut
        );
    }

    /// @dev Execute a scheduled market buy: deduct gold from purse, credit resource to vault.
    function _executeMarketBuy(
        uint64 closedTick,
        uint32 clanId,
        uint32 clansmanId,
        address token,
        uint256 amountOut,
        uint256 maxGoldIn,
        uint64 commitSequence
    ) internal {
        if (!_treasury.poolsSeeded) {
            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketBuy, StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN);
            return;
        }
        address poolAddr = _poolFor(token);
        if (poolAddr == address(0)) {
            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketBuy, StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN);
            return;
        }

        // Quote gold cost without updating reserves
        uint256 goldIn = StubPool(poolAddr).quoteBuy(amountOut);

        Clan storage clan = _clans[clanId];

        if (goldIn > maxGoldIn) {
            emit MarketActionFailed(
                clanId, clansmanId, ActionType.MarketBuy, StatusCode.ERR_MARKET_BUY_MAX_GOLD_EXCEEDED
            );
            return;
        }
        if (clan.goldBalance < goldIn) {
            emit MarketActionFailed(clanId, clansmanId, ActionType.MarketBuy, StatusCode.ERR_NOT_ENOUGH_GOLD);
            return;
        }

        // Execute — use return value to guard against any future pool divergence
        uint256 actualGoldIn = StubPool(poolAddr).buyResource(amountOut);
        clan.goldBalance -= actualGoldIn;
        _addToVault(clan, token, amountOut);

        emit ScheduledMarketActionExecuted(
            closedTick, commitSequence, clanId, clansmanId, _treasury.goldToken, token, actualGoldIn, amountOut
        );
    }

    function _validateAction(Clan storage clan, Clansman storage cs, ClanOrder calldata order, uint8 gotoRegion)
        internal
        view
        returns (StatusCode)
    {
        ActionType action = order.action;

        if (action == ActionType.None) return StatusCode.ERR_INVALID_ACTION;

        // DepositResources: must go to homebase
        if (action == ActionType.DepositResources) {
            if (gotoRegion != clan.baseRegion) return StatusCode.ERR_NOT_AT_HOMEBASE;
        }

        // BuildWall / UpgradeBase / UpgradeMonument: must go to homebase
        if (action == ActionType.BuildWall || action == ActionType.UpgradeBase || action == ActionType.UpgradeMonument)
        {
            if (gotoRegion != clan.baseRegion) return StatusCode.ERR_NOT_AT_HOMEBASE;
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
            // Market orders are always enqueued for the arrivalTick FIFO queue.
            // _resolveAction records mission completion but does not execute any swap.
            if (cs.currentRegion == ClanWorldConstants.REGION_UNICORN_TOWN && cs.state == ClansmanState.WAITING) {
                // Already at Unicorn Town — arrivalTick == currentTick, queued for next heartbeat.
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
        if (gotoRegion != clan.baseRegion) return StatusCode.ERR_INVALID_REGION;
        if (order.targetClanId != 0 && order.targetClanId != clan.clanId) return StatusCode.ERR_INVALID_TARGET;
        return StatusCode.OK;
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

        StubPool(_treasury.woodGoldPool).seed(cfg.woodSeed, cfg.goldSeedForWood);
        StubPool(_treasury.wheatGoldPool).seed(cfg.wheatSeed, cfg.goldSeedForWheat);
        StubPool(_treasury.fishGoldPool).seed(cfg.fishSeed, cfg.goldSeedForFish);
        StubPool(_treasury.ironGoldPool).seed(cfg.ironSeed, cfg.goldSeedForIron);

        _treasury.poolsSeeded = true;

        emit PoolsSeeded(
            _treasury.woodGoldPool, _treasury.wheatGoldPool, _treasury.fishGoldPool, _treasury.ironGoldPool
        );
    }

    // =========================================================================
    // OTC TRANSFERS
    // =========================================================================

    function transferGold(uint32, uint32, uint256) external pure override {
        revert("OTC transfers not implemented");
    }

    function transferVaultResource(uint32, uint32, ResourceType, uint256) external pure override {
        revert("OTC transfers not implemented");
    }

    function transferBlueprint(uint32, uint32, uint256) external pure override {
        revert("OTC transfers not implemented");
    }

    function transferBundle(uint32, uint32, uint256, uint256, uint256, uint256, uint256, uint256)
        external
        pure
        override
    {
        revert("OTC transfers not implemented");
    }

    // =========================================================================
    // RAW READ GETTERS
    // =========================================================================

    function getWorldState() external view override returns (WorldState memory) {
        return _world;
    }

    function getTreasuryState() external view override returns (TreasuryState memory) {
        return _treasury;
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

    function getActionDuration(ActionType action) public pure override returns (uint64) {
        if (
            action == ActionType.ChopWood || action == ActionType.MineIron || action == ActionType.FishDocks
                || action == ActionType.FishDeepSea || action == ActionType.HarvestWheat
        ) {
            return 4;
        }

        if (
            action == ActionType.DepositResources || action == ActionType.BuildWall || action == ActionType.UpgradeBase
                || action == ActionType.UpgradeMonument || action == ActionType.MarketBuy
                || action == ActionType.MarketSell
        ) {
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
            return
                BanditTroop({
                    id: 0, region: 0, state: BanditState.None, targetClanId: 0, tickEnteredState: 0, strength: 0
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

    /// @dev Returns last-settled state; starvation check uses currentTick (live).
    ///      Carry amounts lag until next settleClan().
    function getDerivedClanState(uint32 clanId) external view override returns (DerivedClanState memory) {
        Clan memory clan = _clans[clanId];
        bool starving = clan.starvationStartsAtTick != 0 && clan.starvationStartsAtTick <= _world.currentTick;
        uint256 lootVal = _lootValueRaw(clan);
        return
            DerivedClanState({clan: clan, isStarving: starving, lootValue: lootVal, derivedAtTick: _world.currentTick});
    }

    function getDerivedClansmanState(uint32 clansmanId) external view override returns (DerivedClansmanState memory) {
        Clansman memory cs = _clansmen[clansmanId];
        Mission memory m = _missions[clansmanId];
        uint8 effectiveRegion = cs.currentRegion;
        if (cs.state == ClansmanState.TRAVELING && m.active) {
            // Simplified: if past arrivalTick, they're at target; else at start
            if (_world.currentTick >= m.arrivalTick) {
                effectiveRegion = m.targetRegion;
            } else {
                effectiveRegion = m.startRegion;
            }
        }
        return DerivedClansmanState({
            clansman: cs, activeMission: m, effectiveRegion: effectiveRegion, derivedAtTick: _world.currentTick
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
        // Phase 1: return raw value (no simulation)
        return _lootValueRaw(_clans[clanId]);
    }

    /// @dev Compute loot value per v4 spec §6.9: wood=1, wheat=1, fish=2, iron=4 points.
    function _lootValueRaw(Clan memory clan) internal pure returns (uint256) {
        return clan.vaultWood + clan.vaultWheat + clan.vaultFish * 2 + clan.vaultIron * 4;
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

        return WorldSnapshot({
            currentTick: _world.currentTick,
            seasonStartTick: _world.seasonStartTick,
            seasonEndTick: _world.seasonEndTick,
            seasonFinalized: _world.seasonFinalized,
            currentSeasonNumber: _world.currentSeasonNumber,
            nextHeartbeatAtTick: _world.nextHeartbeatAtTick,
            winterActive: _world.winterActive,
            winterStartsAtTick: _world.winterStartsAtTick,
            winterEndsAtTick: _world.winterEndsAtTick,
            activeBanditId: _world.activeBanditId,
            currentTickSeed: _world.currentTickSeed,
            leaderboard: lb
        });
    }

    /// @dev Returns last-settled storage state. Vault contents and starvation flag are
    ///      current; carry amounts and wheat progress lag until next settleClan() call.
    ///      Full view-only settlement simulation is deferred (tracked issue).
    function getClanFullView(uint32 clanId) external view override returns (ClanFullView memory) {
        Clan storage clan = _clans[clanId];
        bool starving = clan.starvationStartsAtTick != 0 && clan.starvationStartsAtTick <= _world.currentTick;
        uint256 lootVal = _lootValueRaw(clan);

        DerivedClanState memory derivedClan =
            DerivedClanState({clan: clan, isStarving: starving, lootValue: lootVal, derivedAtTick: _world.currentTick});

        uint32[] storage csIds = _clanClansmanIds[clanId];
        ClansmanFullView[] memory clansmen = new ClansmanFullView[](csIds.length);
        for (uint256 i = 0; i < csIds.length; i++) {
            uint32 csId = csIds[i];
            Clansman memory cs = _clansmen[csId];
            Mission memory m = _missions[csId];
            uint8 effRegion = cs.currentRegion;
            if (cs.state == ClansmanState.TRAVELING && m.active) {
                effRegion = _world.currentTick >= m.arrivalTick ? m.targetRegion : m.startRegion;
            }
            DerivedClansmanState memory dcs = DerivedClansmanState({
                clansman: cs, activeMission: m, effectiveRegion: effRegion, derivedAtTick: _world.currentTick
            });
            clansmen[i] = ClansmanFullView({clansman: dcs, activeMission: m});
        }

        // Find if any of this clan's clansmen is defending a home region.
        uint32 thisClanDefendingBaseId = 0;
        for (uint256 i = 0; i < csIds.length; i++) {
            uint8 region = _clansmanDefendingRegion[csIds[i]];
            if (region != 0) {
                thisClanDefendingBaseId = region;
                break;
            }
        }

        return ClanFullView({
            clan: derivedClan,
            clansmen: clansmen,
            westPlot: _wheatPlots[clanId][0],
            eastPlot: _wheatPlots[clanId][1],
            incomingDefenderIds: _defendingClansByRegion[clan.baseRegion],
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
        bool exists = bandit.id != ClanWorldConstants.BANDIT_ID_NULL && bandit.state != BanditState.None;
        if (exists) {
            if (bandit.state == BanditState.Camped) {
                nextActionTick = bandit.tickEnteredState + ClanWorldConstants.BANDIT_CAMP_TICKS;
            } else if (bandit.state == BanditState.Resting) {
                nextActionTick = bandit.tickEnteredState + ClanWorldConstants.BANDIT_REST_TICKS;
            }
        }

        return ActiveBanditView({
            exists: exists,
            banditId: bandit.id,
            state: bandit.state,
            currentRegion: bandit.region,
            attackAttemptsMade: 0,
            maxAttemptsRemaining: 0,
            stateEnteredTick: bandit.tickEnteredState,
            nextActionTick: nextActionTick,
            tier: 0,
            attackPower: _banditStrengthForLegacyEvent(bandit.strength),
            carryWood: 0,
            carryIron: 0,
            carryWheat: 0,
            carryFish: 0,
            projectedTargetClanId: bandit.targetClanId,
            projectedTargetLootValue: 0
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
                uint32 csId = csIds[j];
                Clansman storage cs = _clansmen[csId];
                if (cs.state != ClansmanState.DEAD && cs.currentRegion == region) {
                    Mission storage m = _missions[csId];
                    occupants[idx++] = RegionOccupant({
                        clansmanId: csId,
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
