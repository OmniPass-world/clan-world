// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IClanWorld.sol";

/// @title ClanWorld
/// @notice Phase 1 real engine implementation of IClanWorld v4.
///         Implements: world clock, clan lifecycle, lazy settlement, resource gathering,
///         deposit, wheat harvest, travel, NOOP bypass, order validation.
///         Phase 2 (market execution) and Phase 3 (bandits, winter damage) are stubbed.
contract ClanWorld is IClanWorld {

    // =========================================================================
    // STORAGE
    // =========================================================================

    WorldState private _world;
    TreasuryState private _treasury;

    mapping(uint32 => Clan) private _clans;
    mapping(uint32 => Clansman) private _clansmen;
    mapping(uint32 => Mission) private _missions;              // keyed by clansmanId
    mapping(uint32 => WheatPlot[2]) private _wheatPlots;       // [0]=west [1]=east
    mapping(uint64 => ScheduledMarketAction[]) private _scheduledMarketActions; // keyed by tick
    mapping(uint32 => uint32[]) private _incomingDefenders;    // targetClanId => clansmanIds
    mapping(uint32 => uint32) private _clanDefendingBase;      // clansmanId => targetClanId
    mapping(uint64 => bytes32) private _tickSeeds;              // tick => seed

    uint32 private _nextClanId;
    uint32 private _nextClansmanId;
    uint32[] private _allClanIds;

    // per-clan clansman list: clanId => clansmanId[]
    mapping(uint32 => uint32[]) private _clanClansmanIds;

    // =========================================================================
    // CONSTANTS — Wheat harvest rate (not in IClanWorld constants)
    // =========================================================================

    uint256 private constant WHEAT_HARVEST_RATE = 20e18;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor() {
        _world.currentTick = 0;
        _world.nextHeartbeatAtTs = uint64(block.timestamp);
        _world.seasonStartTick = 0;
        _world.seasonEndTick = ClanWorldConstants.SEASON_DURATION_TICKS;
        _treasury.treasuryOwner = msg.sender;
        _nextClanId = 1;
        _nextClansmanId = 1;
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
            0, 1, 2, 1, 3, 2, 4, 3,
            // src=2: to 1,2,3,4,5,6,7,8
            1, 0, 1, 2, 2, 3, 3, 4,
            // src=3: to 1,2,3,4,5,6,7,8
            2, 1, 0, 1, 1, 2, 2, 3,
            // src=4: to 1,2,3,4,5,6,7,8
            1, 2, 1, 0, 2, 1, 3, 2,
            // src=5: to 1,2,3,4,5,6,7,8
            3, 2, 1, 2, 0, 3, 1, 2,
            // src=6: to 1,2,3,4,5,6,7,8
            2, 3, 2, 1, 3, 0, 2, 1,
            // src=7: to 1,2,3,4,5,6,7,8
            4, 3, 2, 3, 1, 2, 0, 1,
            // src=8: to 1,2,3,4,5,6,7,8
            3, 4, 3, 2, 2, 1, 1, 0
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
            [0, 0, 0],       // 0: unused
            [2, 4, 0],       // 1: Forest
            [1, 3, 0],       // 2: Mountains
            [2, 4, 5],       // 3: UnicornTown
            [1, 3, 6],       // 4: WestFarms
            [3, 7, 0],       // 5: EastFarms
            [4, 8, 0],       // 6: WestDocks
            [5, 8, 0],       // 7: EastDocks
            [6, 7, 0]        // 8: DeepSea
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
        uint256 byteShift = 56;
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

    // =========================================================================
    // INTERNAL SETTLEMENT
    // =========================================================================

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

            // 3. Advance each clansman
            bytes32 tickSeed = _tickSeeds[tick];
            for (uint256 i = 0; i < clansmanIds.length; i++) {
                uint32 csId = clansmanIds[i];
                Clansman storage cs = _clansmen[csId];
                if (cs.state == ClansmanState.DEAD) continue;

                Mission storage m = _missions[csId];
                if (!m.active) continue;

                // Travel advancement: if still traveling and this tick >= arrivalTick, arrive
                if (cs.state == ClansmanState.TRAVELING && tick >= m.arrivalTick) {
                    cs.state = ClansmanState.ACTING;
                    cs.currentRegion = m.targetRegion;
                    emit WorkerArrived(clanId, csId, m.targetRegion, tick);
                }

                // Action resolution: if acting and this tick >= actionStartTick
                if (cs.state == ClansmanState.ACTING && tick >= m.actionStartTick) {
                    _resolveAction(clan, cs, m, clanId, tick, tickSeed);
                }
            }
        }

        clan.lastSettledTick = curTick;
        emit ClanSettled(clanId, curTick);
    }

    /// @dev Apply one tick of upkeep. Marks starvation if insufficient food.
    function _applyUpkeep(Clan storage clan, uint64 tick) internal {
        if (clan.livingClansmen == 0) return;

        uint256 wheatNeeded = uint256(clan.livingClansmen) * ClanWorldConstants.WHEAT_UPKEEP_PER_CLANSMAN;
        uint256 fishNeeded  = uint256(clan.livingClansmen) * ClanWorldConstants.FISH_UPKEEP_PER_CLANSMAN;

        bool hadEnoughWheat = clan.vaultWheat >= wheatNeeded;
        bool hadEnoughFish  = clan.vaultFish  >= fishNeeded;

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
            // Register defender at arrival (not at submission) per v4.3 — ensures only arrived clansmen counted.
            // Guard: only register once (this branch executes every ACTING tick; idempotent via _clanDefendingBase check).
            if (_clanDefendingBase[cs.clansmanId] != m.targetClanId) {
                _incomingDefenders[m.targetClanId].push(cs.clansmanId);
                _clanDefendingBase[cs.clansmanId] = m.targetClanId;
            }
        } else if (
            action == ActionType.BuildWall ||
            action == ActionType.UpgradeBase ||
            action == ActionType.UpgradeMonument
        ) {
            // Phase 1 stub: check homebase, check resources; if ok, stub success
            _doBuilding(clan, cs, m, clanId, tick, action);
        } else if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
            // Phase 2 stub: immediate market not eligible; scheduled would also land here
            emit MarketActionFailed(clanId, cs.clansmanId, action, StatusCode.ERR_IMMEDIATE_MARKET_NOT_ELIGIBLE);
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

    function _rollIronGoldBonus(
        Clan storage clan,
        uint32 clansmanId,
        uint64 nonce,
        uint64 tick,
        bytes32 tickSeed
    ) internal returns (uint256 goldBonus) {
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
        Clan storage clan,
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

    function _doDeposit(
        Clan storage clan,
        Clansman storage cs,
        Mission storage m,
        uint32 clanId,
        uint64 tick
    ) internal {
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

        clan.vaultWood  += w;
        clan.vaultIron  += ir;
        clan.vaultWheat += wh;
        clan.vaultFish  += fi;

        cs.carryWood  = 0;
        cs.carryIron  = 0;
        cs.carryWheat = 0;
        cs.carryFish  = 0;

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

        if (nextLevel == 1) { woodCost = 20e18; ironCost = 0; }
        else if (nextLevel == 2) { woodCost = 35e18; ironCost = 0; }
        else if (nextLevel == 3) { woodCost = 30e18; ironCost = 5e18; }
        else if (nextLevel == 4) { woodCost = 40e18; ironCost = 10e18; }
        else { woodCost = 50e18; ironCost = 15e18; }

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

        if (nextLevel == 2) { woodCost = 40e18; ironCost = 0; wheatCost = 20e18; }
        else if (nextLevel == 3) { woodCost = 60e18; ironCost = 5e18; wheatCost = 30e18; }
        else if (nextLevel == 4) { woodCost = 80e18; ironCost = 10e18; wheatCost = 40e18; }
        else { woodCost = 100e18; ironCost = 15e18; wheatCost = 50e18; }

        if (clan.vaultWood < woodCost || clan.vaultIron < ironCost || clan.vaultWheat < wheatCost) return false;

        clan.vaultWood  -= woodCost;
        clan.vaultIron  -= ironCost;
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

        if (nextLevel == 1)  { woodCost = 30e18;  wheatCost = 20e18; }
        else if (nextLevel == 2)  { woodCost = 50e18;  wheatCost = 30e18; }
        else if (nextLevel == 3)  { woodCost = 70e18;  wheatCost = 40e18; ironCost = 5e18; }
        else if (nextLevel == 4)  { woodCost = 90e18;  wheatCost = 50e18; ironCost = 10e18; }
        else if (nextLevel == 5)  { woodCost = 120e18; wheatCost = 60e18; ironCost = 15e18; }
        else if (nextLevel == 6)  { woodCost = 150e18; wheatCost = 80e18; ironCost = 20e18; }
        else if (nextLevel <= 10) { woodCost = 200e18; wheatCost = 100e18; ironCost = 25e18; blueprintCost = 1e18; }

        if (clan.vaultWood < woodCost || clan.vaultWheat < wheatCost ||
            clan.vaultIron < ironCost || clan.blueprintBalance < blueprintCost) return false;

        clan.vaultWood        -= woodCost;
        clan.vaultWheat       -= wheatCost;
        clan.vaultIron        -= ironCost;
        clan.blueprintBalance -= blueprintCost;

        uint8 old = clan.monumentLevel;
        clan.monumentLevel = nextLevel;
        emit MonumentLevelChanged(clanId, old, nextLevel, tick);
        return true;
    }

    /// @dev Complete a mission: set worker to WAITING, mark mission inactive, emit event.
    function _completeMission(Clansman storage cs, Mission storage m) internal {
        cs.state = ClansmanState.WAITING;
        m.active = false;
        emit MissionCompleted(_clans[cs.clanId].clanId, cs.clansmanId, m.nonce, m.action);
    }

    // =========================================================================
    // WORLD PROGRESSION
    // =========================================================================

    /// @notice Permissionless heartbeat. Closes the current tick, advances tick counter.
    function heartbeat() external override {
        require(block.timestamp >= _world.nextHeartbeatAtTs, "ClanWorld: heartbeat rate limited");

        uint64 closedTick = _world.currentTick;
        _world.currentTick = closedTick + 1;                                    // increment first

        // Derive tick seed: domain-separated from block randomness; stored under NEW tick
        bytes32 newSeed = keccak256(abi.encode(block.prevrandao, closedTick, block.timestamp));
        _tickSeeds[_world.currentTick] = newSeed;                               // store under new tick
        _world.currentTickSeed = newSeed;

        _world.nextHeartbeatAtTs = uint64(block.timestamp) + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS;

        // TODO Phase 2: execute scheduled market actions for closedTick
        // TODO Phase 3: bandit state transitions and attacks

        emit TickAdvanced(closedTick, _world.currentTick, _world.currentTickSeed);
    }

    /// @notice Public settlement trigger — lazily settle a clan.
    function settleClan(uint32 clanId) external override {
        _settleClan(clanId);
    }

    /// @notice Finalize season. Phase 1 stub.
    function finalizeSeason() external override {
        // TODO Phase 3
    }

    // =========================================================================
    // CLAN LIFECYCLE
    // =========================================================================

    /// @notice Mint a new clan and spawn its homebase.
    function mintClan(address to) external override returns (uint32 clanId, uint256 iftTokenId) {
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
        clan.goldBalance = 3e18;  // starter gold per v4 spec §12.5
        clan.blueprintBalance = 0;
        // Starting vault per v4 spec §12.4
        clan.vaultWood  = 20e18;
        clan.vaultIron  = 0;
        clan.vaultWheat = 20e18;
        clan.vaultFish  = 2e18;

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
            cs.carryWood  = 0;
            cs.carryIron  = 0;
            cs.carryWheat = 0;
            cs.carryFish  = 0;
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

        // NOOP bypass: treat 0 as "stay here"
        ctx.isNoop = (ctx.gotoRegion == ClanWorldConstants.REGION_NOOP || ctx.gotoRegion == ctx.fromRegion);
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

        // Compute travel
        ctx.travelTicks = _travelTicks(ctx.fromRegion, ctx.gotoRegion);
        ctx.arrivalTick = _world.currentTick + uint64(ctx.travelTicks);

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

        // DefendBase: deregister old assignment immediately (clansman is being re-tasked).
        // Registration at the target base happens at arrival in _resolveAction (v4.3 — arrived defenders only).
        {
            uint32 oldTarget = _clanDefendingBase[cs.clansmanId];
            if (oldTarget != 0) {
                _removeDefender(oldTarget, cs.clansmanId);
                _clanDefendingBase[cs.clansmanId] = 0;
            }
        }

        // DefendBase zero-travel: register synchronously so getActiveDefenders() has no drop window.
        // When travelTicks == 0 the clansman is already at the target base — no travel window to wait out.
        // The _resolveAction guard (clanDefendingBase != targetClanId) will be false next tick, preventing double-register.
        if (order.action == ActionType.DefendBase && ctx.travelTicks == 0) {
            _incomingDefenders[order.targetClanId].push(cs.clansmanId);
            _clanDefendingBase[cs.clansmanId] = order.targetClanId;
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

    function _installMission(
        Mission storage m,
        ClanOrder calldata order,
        Clansman storage cs,
        OrderCtx memory ctx
    ) internal {
        m.active = true;
        m.nonce = ctx.newNonce;
        m.clansmanId = cs.clansmanId;
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
        m.targetClanId = order.targetClanId;
        m.marketToken = order.marketToken;
        m.marketAmount = order.marketAmount;
        m.maxGoldIn = order.maxGoldIn;
    }

    function _removeDefender(uint32 targetClanId, uint32 clansmanId) internal {
        uint32[] storage defenders = _incomingDefenders[targetClanId];
        for (uint256 i = 0; i < defenders.length; i++) {
            if (defenders[i] == clansmanId) {
                defenders[i] = defenders[defenders.length - 1];
                defenders.pop();
                break;
            }
        }
    }

    function _validateAction(
        Clan storage clan,
        Clansman storage cs,
        ClanOrder calldata order,
        uint8 gotoRegion
    ) internal view returns (StatusCode) {
        ActionType action = order.action;

        if (action == ActionType.None) return StatusCode.ERR_INVALID_ACTION;

        // DepositResources: must go to homebase
        if (action == ActionType.DepositResources) {
            if (gotoRegion != clan.baseRegion) return StatusCode.ERR_NOT_AT_HOMEBASE;
        }

        // BuildWall / UpgradeBase / UpgradeMonument: must go to homebase
        if (action == ActionType.BuildWall || action == ActionType.UpgradeBase || action == ActionType.UpgradeMonument) {
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
            if (gotoRegion != ClanWorldConstants.REGION_WEST_DOCKS && gotoRegion != ClanWorldConstants.REGION_EAST_DOCKS) {
                return StatusCode.ERR_INVALID_REGION;
            }
        }
        // FishDeepSea: must go to DeepSea
        if (action == ActionType.FishDeepSea) {
            if (gotoRegion != ClanWorldConstants.REGION_DEEP_SEA) return StatusCode.ERR_INVALID_REGION;
        }
        // HarvestWheat: must go to WestFarms or EastFarms
        if (action == ActionType.HarvestWheat) {
            if (gotoRegion != ClanWorldConstants.REGION_WEST_FARMS && gotoRegion != ClanWorldConstants.REGION_EAST_FARMS) {
                return StatusCode.ERR_INVALID_REGION;
            }
        }

        // DefendBase: targetClanId must be valid and gotoRegion must match target's baseRegion
        if (action == ActionType.DefendBase) {
            if (order.targetClanId == 0 || _clans[order.targetClanId].clanId == 0) {
                return StatusCode.ERR_INVALID_TARGET;
            }
            if (_clans[order.targetClanId].clanState == ClanState.DEAD) {
                return StatusCode.ERR_NOT_DEFENDABLE;
            }
            if (gotoRegion != _clans[order.targetClanId].baseRegion) {
                return StatusCode.ERR_NOT_AT_TARGET_BASE;
            }
        }

        // MarketBuy/MarketSell: Phase 2 — immediate market only eligible if already in town
        if (action == ActionType.MarketBuy || action == ActionType.MarketSell) {
            if (gotoRegion != ClanWorldConstants.REGION_UNICORN_TOWN) {
                return StatusCode.ERR_INVALID_REGION;
            }
            if (order.marketAmount == 0) return StatusCode.ERR_MARKET_ZERO_AMOUNT;
            // Immediate path: if already in UnicornTown and WAITING — Phase 2 execution
            // For Phase 1, return ERR_IMMEDIATE_MARKET_NOT_ELIGIBLE for immediate
            // Scheduled: allow order submission, stub execution in heartbeat
            // For now, allow scheduling (don't reject at order time)
        }

        cs; // suppress unused warning
        return StatusCode.OK;
    }

    // =========================================================================
    // TREASURY / POOL SEEDING
    // =========================================================================

    function seedPools(PoolSeedConfig calldata) external override {
        // Phase 1 stub — no token pools
    }

    // =========================================================================
    // OTC TRANSFERS — Phase 2 stubs
    // =========================================================================

    function transferGold(uint32, uint32, uint256) external override {
        revert("ClanWorld: OTC transfers available in Phase 2");
    }

    function transferVaultResource(uint32, uint32, ResourceType, uint256) external override {
        revert("ClanWorld: OTC transfers available in Phase 2");
    }

    function transferBlueprint(uint32, uint32, uint256) external override {
        revert("ClanWorld: OTC transfers available in Phase 2");
    }

    function transferBundle(uint32, uint32, uint256, uint256, uint256, uint256, uint256, uint256)
        external
        override
    {
        revert("ClanWorld: OTC transfers available in Phase 2");
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

    function getBanditTroop(uint32) external pure override returns (BanditTroop memory) {
        return BanditTroop({
            banditId: 0,
            state: BanditState.NONE,
            currentRegion: 0,
            attackAttemptsMade: 0,
            stateEnteredTick: 0,
            nextActionTick: 0,
            tier: 0,
            attackPower: 0,
            carryWood: 0,
            carryIron: 0,
            carryWheat: 0,
            carryFish: 0
        });
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

    function getActiveDefenders(uint32 targetClanId)
        external
        view
        override
        returns (uint32[] memory)
    {
        return _incomingDefenders[targetClanId];
    }

    // =========================================================================
    // DERIVED READ GETTERS (read-only, no storage mutation)
    // =========================================================================

    /// @dev Returns last-settled state; starvation check uses currentTick (live).
    ///      Carry amounts lag until next settleClan().
    function getDerivedClanState(uint32 clanId)
        external
        view
        override
        returns (DerivedClanState memory)
    {
        Clan memory clan = _clans[clanId];
        bool starving = clan.starvationStartsAtTick != 0 && clan.starvationStartsAtTick <= _world.currentTick;
        uint256 lootVal = _lootValueRaw(clan);
        return DerivedClanState({
            clan: clan,
            isStarving: starving,
            lootValue: lootVal,
            derivedAtTick: _world.currentTick
        });
    }

    function getDerivedClansmanState(uint32 clansmanId)
        external
        view
        override
        returns (DerivedClansmanState memory)
    {
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
            clansman: cs,
            activeMission: m,
            effectiveRegion: effectiveRegion,
            derivedAtTick: _world.currentTick
        });
    }

    function getBanditTargetPreview(uint32) external pure override returns (uint32) {
        return 0; // Phase 3
    }

    function quoteTravel(uint8 srcRegion, uint8 dstRegion)
        external
        view
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

        DerivedClanState memory derivedClan = DerivedClanState({
            clan: clan,
            isStarving: starving,
            lootValue: lootVal,
            derivedAtTick: _world.currentTick
        });

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
                clansman: cs,
                activeMission: m,
                effectiveRegion: effRegion,
                derivedAtTick: _world.currentTick
            });
            clansmen[i] = ClansmanFullView({ clansman: dcs, activeMission: m });
        }

        // Find if any of this clan's clansmen is defending a base
        uint32 thisClanDefendingBaseId = 0;
        for (uint256 i = 0; i < csIds.length; i++) {
            uint32 target = _clanDefendingBase[csIds[i]];
            if (target != 0) {
                thisClanDefendingBaseId = target;
                break;
            }
        }

        return ClanFullView({
            clan: derivedClan,
            clansmen: clansmen,
            westPlot: _wheatPlots[clanId][0],
            eastPlot: _wheatPlots[clanId][1],
            incomingDefenderIds: _incomingDefenders[clanId],
            thisClanDefendingBaseId: thisClanDefendingBaseId
        });
    }

    function getMarketState() external view override returns (MarketState memory) {
        return MarketState({
            wood:  PoolReserves({ resourceToken: _treasury.woodToken,  resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0 }),
            wheat: PoolReserves({ resourceToken: _treasury.wheatToken, resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0 }),
            fish:  PoolReserves({ resourceToken: _treasury.fishToken,  resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0 }),
            iron:  PoolReserves({ resourceToken: _treasury.ironToken,  resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0 }),
            currentTick: _world.currentTick,
            currentTickQueue: _scheduledMarketActions[_world.currentTick],
            nextTickQueue: _scheduledMarketActions[_world.currentTick + 1]
        });
    }

    function getActiveBanditView() external pure override returns (ActiveBanditView memory) {
        return ActiveBanditView({
            exists: false,
            banditId: 0,
            state: BanditState.NONE,
            currentRegion: 0,
            attackAttemptsMade: 0,
            maxAttemptsRemaining: 0,
            stateEnteredTick: 0,
            nextActionTick: 0,
            tier: 0,
            attackPower: 0,
            carryWood: 0,
            carryIron: 0,
            carryWheat: 0,
            carryFish: 0,
            projectedTargetClanId: 0,
            projectedTargetLootValue: 0
        });
    }

    /// @dev View function — no gas cost for off-chain indexer/UI reads.
    ///      Iterates all clans. Canonical game cap: ≤12 clans, ≤4 clansmen each = ≤48 iterations.
    function getRegionPopulation(uint8 region)
        external
        view
        override
        returns (RegionOccupant[] memory)
    {
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
