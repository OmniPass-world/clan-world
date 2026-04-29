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

/// @notice Stub implementation of IClanWorld for Base Sepolia deployment.
///         Stores tick state and token/pool addresses. All game logic is no-op.
contract ClanWorldStub is IClanWorld {
    WorldState private _world;
    TreasuryState private _treasury;

    constructor(address[6] memory tokens, address[4] memory pools) {
        _world.currentTick = 1;
        _world.nextHeartbeatAtTs = uint64(block.timestamp);

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
        uint64 closed = _world.currentTick;
        _world.currentTick += 1;
        _world.nextHeartbeatAtTs = uint64(block.timestamp);
        emit TickAdvanced(closed, _world.currentTick, bytes32(0));
    }

    function settleClan(uint32) external override {}

    function settleClansman(uint32) external override {}

    function finalizeSeason() external override {}

    // -------------------------------------------------------------------------
    // Clan lifecycle
    // -------------------------------------------------------------------------

    function mintClan(address) external override returns (uint32, uint256) {
        return (1, 1);
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
    // OTC transfers
    // -------------------------------------------------------------------------

    function transferGold(uint32, uint32, uint256) external override {}

    function transferVaultResource(uint32, uint32, ResourceType, uint256) external override {}

    function transferBlueprint(uint32, uint32, uint256) external override {}

    function transferBundle(uint32, uint32, uint256, uint256, uint256, uint256, uint256, uint256) external override {}

    // -------------------------------------------------------------------------
    // Raw read getters
    // -------------------------------------------------------------------------

    function getWorldState() external view override returns (WorldState memory) {
        return _world;
    }

    function getTreasuryState() external view override returns (TreasuryState memory) {
        return _treasury;
    }

    function getClan(uint32) external pure override returns (Clan memory) {
        return Clan({
            clanId: 0,
            iftTokenId: 0,
            owner: address(0),
            clanState: ClanState.ACTIVE,
            baseRegion: 0,
            baseLevel: 0,
            wallLevel: 0,
            monumentLevel: 0,
            livingClansmen: 0,
            lastSettledTick: 0,
            starvationStartsAtTick: 0,
            coldDamage: 0,
            goldBalance: 0,
            blueprintBalance: 0,
            vaultWood: 0,
            vaultIron: 0,
            vaultWheat: 0,
            vaultFish: 0
        });
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
            maxGoldIn: 0
        });
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

    // -------------------------------------------------------------------------
    // Derived read getters
    // -------------------------------------------------------------------------

    function getDerivedClanState(uint32) external view override returns (DerivedClanState memory) {
        Clan memory c = this.getClan(0);
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

    // -------------------------------------------------------------------------
    // UI indexer aggregator getters
    // -------------------------------------------------------------------------

    function getWorldSnapshot() external view override returns (WorldSnapshot memory) {
        return WorldSnapshot({
            currentTick: _world.currentTick,
            seasonStartTick: _world.seasonStartTick,
            seasonEndTick: _world.seasonEndTick,
            seasonFinalized: false,
            winterActive: false,
            winterStartsAtTick: 0,
            winterEndsAtTick: 0,
            activeBanditId: 0,
            currentTickSeed: bytes32(0),
            leaderboard: new LeaderboardEntry[](0)
        });
    }

    function getClanFullView(uint32) external view override returns (ClanFullView memory) {
        return ClanFullView({
            clan: DerivedClanState({
                clan: this.getClan(0), isStarving: false, lootValue: 0, derivedAtTick: _world.currentTick
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

    function getRegionPopulation(uint8) external pure override returns (RegionOccupant[] memory) {
        return new RegionOccupant[](0);
    }
}
