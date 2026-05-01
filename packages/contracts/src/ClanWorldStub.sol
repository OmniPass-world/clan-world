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

/// @notice Stub implementation of IClanWorld for Base Sepolia deployment.
///         Stores tick state and token/pool addresses. All game logic is no-op.
contract ClanWorldStub is IClanWorld {
    WorldState private _world;
    TreasuryState private _treasury;
    uint32 private _nextClanId = 1;
    mapping(uint32 => Clan) private _clans;

    constructor(address[6] memory tokens, address[4] memory pools) {
        _world.currentTick = 0;
        _world.nextHeartbeatAtTs = uint64(block.timestamp);
        _world.seasonStartTick = 0;
        _world.seasonEndTick = ClanWorldConstants.SEASON_DURATION_TICKS;
        _world.currentSeasonNumber = 1;
        _world.nextHeartbeatAtTick = _world.currentTick + 1;
        _world.winterStartsAtTick = ClanWorldConstants.WINTER_START_TICK;
        _world.winterEndsAtTick = ClanWorldConstants.WINTER_START_TICK + ClanWorldConstants.WINTER_DURATION_TICKS;
        _world.winterActive = false;

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

        _treasury.treasuryOwner = msg.sender;
    }

    // -------------------------------------------------------------------------
    // World progression
    // -------------------------------------------------------------------------

    function heartbeat() external override {
        require(block.timestamp >= _world.nextHeartbeatAtTs, "ClanWorld: heartbeat rate limited");

        uint64 closed = _world.currentTick;
        _world.currentTick += 1;
        _world.nextHeartbeatAtTick = _world.currentTick + 1;
        _world.nextHeartbeatAtTs = uint64(block.timestamp) + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS;
        bool wasWinter = _isWinterActiveAt(closed);
        bool nowWinter = _isWinterActiveAt(_world.currentTick);
        if (!wasWinter && nowWinter) {
            emit WinterStarted(_winterEventTick(_world.currentTick));
        }
        if (wasWinter && !nowWinter) {
            emit WinterEnded(_winterEventTick(_world.currentTick));
        }
        emit TickAdvanced(closed, _world.currentTick, bytes32(0));
    }

    function settleClan(uint32) external override {}

    function settleClansman(uint32) external override {}

    function finalizeSeason() external override {}

    // -------------------------------------------------------------------------
    // Clan lifecycle
    // -------------------------------------------------------------------------

    function mintClan(address to) external override returns (uint32 clanId, uint256 iftTokenId) {
        require(to != address(0), "ClanWorldStub: zero address");

        clanId = _nextClanId++;
        iftTokenId = uint256(clanId);

        Clan storage clan = _clans[clanId];
        clan.clanId = clanId;
        clan.iftTokenId = iftTokenId;
        clan.owner = to;
        clan.clanState = ClanState.ACTIVE;
        clan.lastSettledTick = _world.currentTick;
        clan.livingClansmen = 4;
        clan.goldBalance = 3e18;
        clan.vaultWood = 20e18;
        clan.vaultWheat = 20e18;
        clan.vaultFish = 2e18;

        emit ClanSpawned(clanId, to, iftTokenId, 0, _world.currentTick);
    }

    function submitClanOrders(uint32, ClanOrder[] calldata orders)
        external
        override
        returns (OrderResult[] memory results)
    {
        results = new OrderResult[](orders.length);
    }

    // -------------------------------------------------------------------------
    // Treasury
    // -------------------------------------------------------------------------

    function initTreasury(address[6] calldata, address[4] calldata) external override {}

    function seedPools(PoolSeedConfig calldata) external override {}

    // -------------------------------------------------------------------------
    // Clan ownership transfer
    // -------------------------------------------------------------------------

    function transferClanOwnership(uint32 clanId, address newOwner) external override {
        Clan storage clan = _clans[clanId];
        require(clan.clanId != 0, "ClanWorldStub: clan not found");
        require(clan.owner == msg.sender, "ClanWorldStub: not clan owner");
        require(newOwner != address(0), "ClanWorldStub: zero address");
        require(newOwner != clan.owner, "ClanWorldStub: same owner");

        address oldOwner = clan.owner;
        clan.owner = newOwner;
        clan.ownerNonce++;
        emit ClanOwnershipTransferred(clanId, oldOwner, newOwner, clan.ownerNonce);
    }

    // -------------------------------------------------------------------------
    // OTC transfers
    // -------------------------------------------------------------------------

    function transferGold(uint32 fromClanId, uint32 toClanId, uint256 amount) external override {
        Clan storage fromClan = _clans[fromClanId];
        Clan storage toClan = _clans[toClanId];
        require(fromClan.owner == msg.sender, "ClanWorldStub: not clan owner");
        require(toClan.clanId != 0, "ClanWorldStub: to clan not found");
        require(fromClan.goldBalance >= amount, "ClanWorldStub: insufficient gold");

        fromClan.goldBalance -= amount;
        toClan.goldBalance += amount;
        emit GoldTransferred(fromClanId, toClanId, amount, _world.currentTick);
    }

    function transferVaultResource(uint32 fromClanId, uint32 toClanId, ResourceType resource, uint256 amount)
        external
        override
    {
        Clan storage fromClan = _clans[fromClanId];
        Clan storage toClan = _clans[toClanId];
        require(fromClan.owner == msg.sender, "ClanWorldStub: not clan owner");
        require(toClan.clanId != 0, "ClanWorldStub: to clan not found");

        if (resource == ResourceType.Wood) {
            require(fromClan.vaultWood >= amount, "ClanWorldStub: insufficient wood");
            fromClan.vaultWood -= amount;
            toClan.vaultWood += amount;
        } else if (resource == ResourceType.Iron) {
            require(fromClan.vaultIron >= amount, "ClanWorldStub: insufficient iron");
            fromClan.vaultIron -= amount;
            toClan.vaultIron += amount;
        } else if (resource == ResourceType.Wheat) {
            require(fromClan.vaultWheat >= amount, "ClanWorldStub: insufficient wheat");
            fromClan.vaultWheat -= amount;
            toClan.vaultWheat += amount;
        } else if (resource == ResourceType.Fish) {
            require(fromClan.vaultFish >= amount, "ClanWorldStub: insufficient fish");
            fromClan.vaultFish -= amount;
            toClan.vaultFish += amount;
        } else {
            revert("ClanWorldStub: invalid resource");
        }

        emit VaultResourceTransferred(fromClanId, toClanId, resource, amount, _world.currentTick);
    }

    function transferBlueprint(uint32 fromClanId, uint32 toClanId, uint256 amount) external override {
        Clan storage fromClan = _clans[fromClanId];
        Clan storage toClan = _clans[toClanId];
        require(fromClan.owner == msg.sender, "ClanWorldStub: not clan owner");
        require(toClan.clanId != 0, "ClanWorldStub: to clan not found");
        require(fromClan.blueprintBalance >= amount, "ClanWorldStub: insufficient blueprints");

        fromClan.blueprintBalance -= amount;
        toClan.blueprintBalance += amount;
        emit BlueprintTransferred(fromClanId, toClanId, amount, _world.currentTick);
    }

    function transferBundle(
        uint32 fromClanId,
        uint32 toClanId,
        uint256 gold,
        uint256 blueprint,
        uint256 wood,
        uint256 iron,
        uint256 wheat,
        uint256 fish
    ) external override {
        Clan storage fromClan = _clans[fromClanId];
        Clan storage toClan = _clans[toClanId];
        require(fromClan.owner == msg.sender, "ClanWorldStub: not clan owner");
        require(toClan.clanId != 0, "ClanWorldStub: to clan not found");
        require(fromClan.goldBalance >= gold, "ClanWorldStub: insufficient gold");
        require(fromClan.blueprintBalance >= blueprint, "ClanWorldStub: insufficient blueprints");
        require(fromClan.vaultWood >= wood, "ClanWorldStub: insufficient wood");
        require(fromClan.vaultIron >= iron, "ClanWorldStub: insufficient iron");
        require(fromClan.vaultWheat >= wheat, "ClanWorldStub: insufficient wheat");
        require(fromClan.vaultFish >= fish, "ClanWorldStub: insufficient fish");

        fromClan.goldBalance -= gold;
        fromClan.blueprintBalance -= blueprint;
        fromClan.vaultWood -= wood;
        fromClan.vaultIron -= iron;
        fromClan.vaultWheat -= wheat;
        fromClan.vaultFish -= fish;
        toClan.goldBalance += gold;
        toClan.blueprintBalance += blueprint;
        toClan.vaultWood += wood;
        toClan.vaultIron += iron;
        toClan.vaultWheat += wheat;
        toClan.vaultFish += fish;

        if (gold > 0) emit GoldTransferred(fromClanId, toClanId, gold, _world.currentTick);
        if (blueprint > 0) emit BlueprintTransferred(fromClanId, toClanId, blueprint, _world.currentTick);
        if (wood > 0) {
            emit VaultResourceTransferred(fromClanId, toClanId, ResourceType.Wood, wood, _world.currentTick);
        }
        if (iron > 0) {
            emit VaultResourceTransferred(fromClanId, toClanId, ResourceType.Iron, iron, _world.currentTick);
        }
        if (wheat > 0) {
            emit VaultResourceTransferred(fromClanId, toClanId, ResourceType.Wheat, wheat, _world.currentTick);
        }
        if (fish > 0) {
            emit VaultResourceTransferred(fromClanId, toClanId, ResourceType.Fish, fish, _world.currentTick);
        }
    }

    // -------------------------------------------------------------------------
    // Raw read getters
    // -------------------------------------------------------------------------

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
        revert("ClanWorldStub: invalid resource");
    }

    function getPool(uint8 resourceType) external view override returns (address) {
        if (resourceType == uint8(ResourceType.Wood)) return _treasury.woodGoldPool;
        if (resourceType == uint8(ResourceType.Iron)) return _treasury.ironGoldPool;
        if (resourceType == uint8(ResourceType.Wheat)) return _treasury.wheatGoldPool;
        if (resourceType == uint8(ResourceType.Fish)) return _treasury.fishGoldPool;
        revert("ClanWorldStub: invalid resource");
    }

    function getPrice(uint8, uint256) external pure override returns (uint256) {
        return 0;
    }

    function getClan(uint32 clanId) external view override returns (Clan memory) {
        return _clans[clanId];
    }

    function getClansman(uint32) external pure override returns (Clansman memory) {
        return Clansman({
            clansmanId: 0,
            clanId: 0,
            state: ClansmanState.WAITING,
            currentRegion: 0,
            cooldownEndsAtTs: 0,
            lastMissionNonce: 0,
            carryWood: 0,
            carryIron: 0,
            carryWheat: 0,
            carryFish: 0
        });
    }

    function getActiveMission(uint32) external pure override returns (Mission memory) {
        return Mission({
            active: false,
            nonce: 0,
            submittedAtTick: 0,
            executesAtTick: 0,
            settlesAtTick: 0,
            clansmanId: 0,
            startRegion: 0,
            targetRegion: 0,
            action: ActionType.None,
            startTick: 0,
            arrivalTick: 0,
            actionStartTick: 0,
            missionSeed: bytes32(0),
            marketMode: MarketExecutionMode.None,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0,
            withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
        });
    }

    function getMissionTiming(uint32, uint32)
        external
        pure
        override
        returns (uint64 submitted, uint64 executes, uint64 settles)
    {
        return (0, 0, 0);
    }

    function getWallUpgradeCost(uint8 currentLevel) external pure override returns (uint256 wood, uint256 iron) {
        if (currentLevel == 0) return (20e18, 0);
        if (currentLevel == 1) return (35e18, 0);
        if (currentLevel == 2) return (30e18, 5e18);
        if (currentLevel == 3) return (40e18, 10e18);
        if (currentLevel == 4) return (50e18, 15e18);
        return (0, 0);
    }

    function getBaseUpgradeCost(uint8 currentLevel)
        external
        pure
        override
        returns (uint256 wood, uint256 iron, uint256 wheat)
    {
        if (currentLevel == 1) return (40e18, 0, 20e18);
        if (currentLevel == 2) return (60e18, 5e18, 30e18);
        if (currentLevel == 3) return (80e18, 10e18, 40e18);
        if (currentLevel == 4) return (100e18, 15e18, 50e18);
        return (0, 0, 0);
    }

    function getMonumentUpgradeCost(uint8 currentLevel)
        external
        pure
        override
        returns (uint256 wood, uint256 iron, uint256 wheat, uint256 blueprint)
    {
        if (currentLevel == 0) return (30e18, 0, 20e18, 0);
        if (currentLevel == 1) return (50e18, 0, 30e18, 0);
        if (currentLevel == 2) return (70e18, 5e18, 40e18, 0);
        if (currentLevel == 3) return (90e18, 10e18, 50e18, 0);
        if (currentLevel == 4) return (120e18, 15e18, 60e18, 0);
        if (currentLevel == 5) return (150e18, 20e18, 80e18, 0);
        if (currentLevel >= 6 && currentLevel < 10) return (200e18, 25e18, 100e18, 1e18);
        return (0, 0, 0, 0);
    }

    function isWinter() external view override returns (bool) {
        return _isWinterActiveAt(_world.currentTick);
    }

    function getActionDuration(ActionType) external pure override returns (uint64) {
        return 0;
    }

    function getTravelTicks(uint8, uint8) external pure override returns (uint64) {
        return 0;
    }

    function getBandit(uint32) public pure override returns (BanditTroop memory) {
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

    function getBanditTroop(uint32 banditId) external pure override returns (BanditTroop memory) {
        return getBandit(banditId);
    }

    function getBanditsInRegion(uint8) external pure override returns (uint32[] memory) {
        return new uint32[](0);
    }

    function getWheatPlots(uint32) external pure override returns (WheatPlot memory west, WheatPlot memory east) {
        west = WheatPlot({state: WheatPlotState.Harvestable, region: 0, remainingWheat: 0, regrowUntilTick: 0});
        east = WheatPlot({state: WheatPlotState.Harvestable, region: 0, remainingWheat: 0, regrowUntilTick: 0});
    }

    function getScheduledMarketActionsForTick(uint64) external pure override returns (ScheduledMarketAction[] memory) {
        return new ScheduledMarketAction[](0);
    }

    function getActiveDefenders(uint32) external pure override returns (uint32[] memory) {
        return new uint32[](0);
    }

    function getDefendingClans(uint8) external pure override returns (uint32[] memory) {
        return new uint32[](0);
    }

    // -------------------------------------------------------------------------
    // Derived read getters
    // -------------------------------------------------------------------------

    function getDerivedClanState(uint32 clanId) external view override returns (DerivedClanState memory) {
        Clan memory c = this.getClan(clanId);
        return DerivedClanState({clan: c, isStarving: false, lootValue: 0, derivedAtTick: _world.currentTick});
    }

    function getDerivedClansmanState(uint32) external view override returns (DerivedClansmanState memory) {
        Clansman memory cm = this.getClansman(0);
        Mission memory m = this.getActiveMission(0);
        return
            DerivedClansmanState({
                clansman: cm, activeMission: m, effectiveRegion: 0, derivedAtTick: _world.currentTick
            });
    }

    function getBanditTargetPreview(uint32) external pure override returns (uint32) {
        return 0;
    }

    function quoteTravel(uint8, uint8) external pure override returns (uint8, bytes8) {
        return (0, bytes8(0));
    }

    function quoteLootValueRaw(uint32) external pure override returns (uint256) {
        return 0;
    }

    function quoteLootValueSettled(uint32) external pure override returns (uint256) {
        return 0;
    }

    function getClanScore(uint32) external pure override returns (uint256, uint64, uint8) {
        return (0, 0, 0);
    }

    function getRankings() external pure override returns (uint32[] memory, uint256[] memory) {
        return (new uint32[](0), new uint256[](0));
    }

    // -------------------------------------------------------------------------
    // UI indexer aggregator getters
    // -------------------------------------------------------------------------

    function getWorldSnapshot() external view override returns (WorldSnapshot memory) {
        WorldState memory ws = _worldStateView();
        return WorldSnapshot({
            currentTick: ws.currentTick,
            seasonStartTick: ws.seasonStartTick,
            seasonEndTick: ws.seasonEndTick,
            seasonFinalized: false,
            currentSeasonNumber: ws.currentSeasonNumber,
            nextHeartbeatAtTick: ws.nextHeartbeatAtTick,
            winterActive: ws.winterActive,
            winterStartsAtTick: ws.winterStartsAtTick,
            winterEndsAtTick: ws.winterEndsAtTick,
            activeBanditId: 0,
            currentTickSeed: bytes32(0),
            leaderboard: new LeaderboardEntry[](0)
        });
    }

    function getClanFullView(uint32 clanId) external view override returns (ClanFullView memory) {
        return ClanFullView({
            clan: DerivedClanState({
                clan: this.getClan(clanId), isStarving: false, lootValue: 0, derivedAtTick: _world.currentTick
            }),
            clansmen: new ClansmanFullView[](0),
            westPlot: WheatPlot({state: WheatPlotState.Harvestable, region: 0, remainingWheat: 0, regrowUntilTick: 0}),
            eastPlot: WheatPlot({state: WheatPlotState.Harvestable, region: 0, remainingWheat: 0, regrowUntilTick: 0}),
            incomingDefenderIds: new uint32[](0),
            thisClanDefendingBaseId: 0
        });
    }

    function getMarketState() external view override returns (MarketState memory) {
        return MarketState({
            wood: PoolReserves({
                resourceToken: _treasury.woodToken, resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0
            }),
            wheat: PoolReserves({
                resourceToken: _treasury.wheatToken, resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0
            }),
            fish: PoolReserves({
                resourceToken: _treasury.fishToken, resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0
            }),
            iron: PoolReserves({
                resourceToken: _treasury.ironToken, resourceReserve: 0, goldReserve: 0, spotPriceGoldPerResource: 0
            }),
            currentTick: _world.currentTick,
            currentTickQueue: new ScheduledMarketAction[](0),
            nextTickQueue: new ScheduledMarketAction[](0)
        });
    }

    function getActiveBanditView() external pure override returns (ActiveBanditView memory) {
        return ActiveBanditView({
            exists: false,
            banditId: 0,
            state: BanditState.None,
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

    function getRegionPopulation(uint8) external pure override returns (RegionOccupant[] memory) {
        return new RegionOccupant[](0);
    }

    function _isWinterActiveAt(uint64 tick) internal pure returns (bool) {
        if (tick < ClanWorldConstants.WINTER_START_TICK) {
            return false;
        }
        uint64 elapsed = tick - ClanWorldConstants.WINTER_START_TICK;
        return elapsed % ClanWorldConstants.WINTER_PERIOD_TICKS < ClanWorldConstants.WINTER_DURATION_TICKS;
    }

    function _winterEventTick(uint64 tick) internal pure returns (uint64) {
        return tick;
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
        ws = _world;
        (ws.winterActive, ws.winterStartsAtTick, ws.winterEndsAtTick) = _winterWindowForTick(_world.currentTick);
    }
}
