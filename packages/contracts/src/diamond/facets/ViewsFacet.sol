// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {LibStorage} from "../LibStorage.sol";
import {
    WorldState,
    TreasuryState,
    Clan,
    Clansman,
    Mission,
    BanditTroop,
    BanditState,
    WheatPlot,
    ScheduledMarketAction,
    DerivedClanState,
    DerivedClansmanState,
    ClansmanFullView,
    ClanFullView,
    WorldSnapshot,
    LeaderboardEntry,
    MarketState,
    PoolReserves,
    ActiveBanditView,
    RegionOccupant,
    ActionType,
    ClansmanState
} from "../../IClanWorld.sol";

/// @title ViewsFacet
/// @notice All pure/view aggregators — no storage writes.
///
///         Functions to migrate from ClanWorld.sol:
///         RAW READ GETTERS:
///         - getWorldState()
///         - getTreasuryState()
///         - getClan(uint32)
///         - getClansman(uint32)
///         - getActiveMission(uint32)
///         - getMissionTiming(uint32, uint32)
///         - getBanditTroop(uint32)               — stub (Phase 9)
///         - getWheatPlots(uint32)
///         - getScheduledMarketActionsForTick(uint64)
///         - getActiveDefenders(uint32)
///         - getDefendingClans(uint8)
///
///         DERIVED READ GETTERS:
///         - getDerivedClanState(uint32)
///         - getDerivedClansmanState(uint32)
///         - getBanditTargetPreview(uint32)       — stub (Phase 9)
///         - quoteTravel(uint8, uint8)
///         - quoteLootValueRaw(uint32)
///         - quoteLootValueSettled(uint32)
///         - _lootValueRaw(Clan memory)           — pure helper
///
///         UI INDEXER AGGREGATORS (v4.4):
///         - getWorldSnapshot()
///         - getClanFullView(uint32)
///         - getMarketState()
///         - _poolReserves(address, address)      — pure computation
///         - getActiveBanditView()                — stub (Phase 9)
///         - getRegionPopulation(uint8)
///
///         Note: quoteTravel also needs _distMatrix and _buildPath (pure helpers).
///         These will be duplicated here or extracted to a LibTravel pure library
///         shared between CoreFacet and ViewsFacet. Decision: use LibTravel to avoid
///         bytecode duplication.
///
/// TODO: migrate from ClanWorld.sol
contract ViewsFacet {
    // Access shared state (read-only) via AppStorage
    // LibStorage.AppStorage storage s = LibStorage.appStorage();

    // =========================================================================
    // RAW READ GETTERS
    // =========================================================================

    function getWorldState() external view returns (WorldState memory) {
        // TODO: migrate from ClanWorld.sol
    }

    function getTreasuryState() external view returns (TreasuryState memory) {
        // TODO: migrate from ClanWorld.sol
    }

    function getClan(uint32 /*clanId*/) external view returns (Clan memory) {
        // TODO: migrate from ClanWorld.sol
    }

    function getClansman(uint32 /*clansmanId*/) external view returns (Clansman memory) {
        // TODO: migrate from ClanWorld.sol
    }

    function getActiveMission(uint32 /*clansmanId*/) external view returns (Mission memory) {
        // TODO: migrate from ClanWorld.sol
    }

    function getMissionTiming(uint32 /*clanId*/, uint32 /*clansmanId*/)
        external
        view
        returns (uint64 submitted, uint64 executes, uint64 settles)
    {
        // TODO: migrate from ClanWorld.sol
    }

    function getBanditTroop(uint32 /*banditId*/) external pure returns (BanditTroop memory) {
        // TODO: stub — Phase 9 implementation in BanditsFacet
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

    function getWheatPlots(uint32 /*clanId*/)
        external
        view
        returns (WheatPlot memory west, WheatPlot memory east)
    {
        // TODO: migrate from ClanWorld.sol
    }

    function getScheduledMarketActionsForTick(uint64 /*tick*/)
        external
        view
        returns (ScheduledMarketAction[] memory)
    {
        // TODO: migrate from ClanWorld.sol
    }

    function getActiveDefenders(uint32 /*targetClanId*/) external view returns (uint32[] memory clansmanIds) {
        // TODO: migrate from ClanWorld.sol
    }

    function getDefendingClans(uint8 /*region*/) external view returns (uint32[] memory) {
        // TODO: migrate from ClanWorld.sol
    }

    // =========================================================================
    // DERIVED READ GETTERS
    // =========================================================================

    function getDerivedClanState(uint32 /*clanId*/) external view returns (DerivedClanState memory) {
        // TODO: migrate from ClanWorld.sol
    }

    function getDerivedClansmanState(uint32 /*clansmanId*/) external view returns (DerivedClansmanState memory) {
        // TODO: migrate from ClanWorld.sol
    }

    function getBanditTargetPreview(uint32 /*clansmanId*/) external pure returns (uint32) {
        return 0; // TODO: Phase 9 stub
    }

    function quoteTravel(uint8 /*srcRegion*/, uint8 /*dstRegion*/)
        external
        pure
        returns (uint8 travelTicks, bytes8 path)
    {
        // TODO: migrate from ClanWorld.sol — uses _distMatrix and _buildPath
        // These pure helpers will be extracted to LibTravel to avoid duplication
        // with CoreFacet (which also needs travel logic for order submission)
    }

    function quoteLootValueRaw(uint32 /*clanId*/) external view returns (uint256) {
        // TODO: migrate from ClanWorld.sol
    }

    function quoteLootValueSettled(uint32 /*clanId*/) external view returns (uint256) {
        // TODO: migrate from ClanWorld.sol
    }

    // =========================================================================
    // UI INDEXER AGGREGATORS
    // =========================================================================

    function getWorldSnapshot() external view returns (WorldSnapshot memory) {
        // TODO: migrate from ClanWorld.sol
    }

    function getClanFullView(uint32 /*clanId*/) external view returns (ClanFullView memory) {
        // TODO: migrate from ClanWorld.sol
    }

    function getMarketState() external view returns (MarketState memory) {
        // TODO: migrate from ClanWorld.sol
    }

    function getActiveBanditView() external pure returns (ActiveBanditView memory) {
        // TODO: stub — Phase 9 implementation in BanditsFacet
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

    function getRegionPopulation(uint8 /*region*/) external view returns (RegionOccupant[] memory) {
        // TODO: migrate from ClanWorld.sol
    }
}
