// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {
    WorldState,
    TreasuryState,
    Clan,
    Clansman,
    Mission,
    WheatPlot,
    ScheduledMarketAction
} from "../IClanWorld.sol";

/// @title LibStorage
/// @notice Single AppStorage struct for the ClanWorld Diamond.
///         All facets access state through `LibStorage.appStorage()`.
///
///         Pattern: Diamond-3 / Aavegotchi-style single shared struct at a
///         deterministic storage slot. Avoids slot-0 collision with any
///         inherited contracts or future additions.
///
///         DO NOT add fields between existing fields — Solidity packs structs
///         sequentially. Always append new fields at the END of AppStorage.
library LibStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("clan.world.app.storage.v1");

    struct AppStorage {
        // -------------------------------------------------------------------------
        // Reentrancy guard (must be in AppStorage so all facets share one guard)
        // ReentrancyGuard.sol status flag: 1 = not entered, 2 = entered
        // -------------------------------------------------------------------------
        uint256 reentrancyStatus;

        // -------------------------------------------------------------------------
        // World state (was: WorldState private _world in ClanWorld.sol)
        // -------------------------------------------------------------------------
        WorldState world;

        // -------------------------------------------------------------------------
        // Treasury (was: TreasuryState private _treasury in ClanWorld.sol)
        // -------------------------------------------------------------------------
        TreasuryState treasury;

        // -------------------------------------------------------------------------
        // Clan registry
        // (was: mapping(uint32 => Clan) internal _clans)
        // (was: uint32 private _nextClanId)
        // (was: uint32[] private _allClanIds)
        // -------------------------------------------------------------------------
        mapping(uint32 => Clan) clans;
        uint32 nextClanId;
        uint32[] allClanIds;

        // -------------------------------------------------------------------------
        // Clansman registry
        // (was: mapping(uint32 => Clansman) internal _clansmen)
        // (was: uint32 private _nextClansmanId)
        // (was: mapping(uint32 => uint32[]) private _clanClansmanIds)
        // -------------------------------------------------------------------------
        mapping(uint32 => Clansman) clansmen;
        uint32 nextClansmanId;
        mapping(uint32 => uint32[]) clanClansmanIds; // clanId => clansmanId[]

        // -------------------------------------------------------------------------
        // Mission state (keyed by clansmanId)
        // (was: mapping(uint32 => Mission) private _missions)
        // -------------------------------------------------------------------------
        mapping(uint32 => Mission) missions;

        // -------------------------------------------------------------------------
        // Wheat plots: clanId => [west=0, east=1]
        // (was: mapping(uint32 => WheatPlot[2]) private _wheatPlots)
        // -------------------------------------------------------------------------
        mapping(uint32 => WheatPlot[2]) wheatPlots;

        // -------------------------------------------------------------------------
        // Scheduled market actions: tick => actions[]
        // (was: mapping(uint64 => ScheduledMarketAction[]) private _scheduledMarketActions)
        // -------------------------------------------------------------------------
        mapping(uint64 => ScheduledMarketAction[]) scheduledMarketActions;

        // -------------------------------------------------------------------------
        // Defense registries
        // (was: mapping(uint8 => uint32[]) private _defendingClansByRegion)
        // (was: mapping(uint8 => mapping(uint32 => uint256)) private _defenderCountByRegionClan)
        // (was: mapping(uint32 => uint8) private _clansmanDefendingRegion)
        // -------------------------------------------------------------------------
        mapping(uint8 => uint32[]) defendingClansByRegion;
        mapping(uint8 => mapping(uint32 => uint256)) defenderCountByRegionClan;
        mapping(uint32 => uint8) clansmanDefendingRegion;

        // -------------------------------------------------------------------------
        // RNG tick seeds (was: mapping(uint64 => bytes32) private _tickSeeds)
        // -------------------------------------------------------------------------
        mapping(uint64 => bytes32) tickSeeds;

        // -------------------------------------------------------------------------
        // Phase 9 / 10 future fields — append here when needed
        // (BanditsFacet, WintersFacet landing zones)
        // -------------------------------------------------------------------------
        // mapping(uint32 => BanditTroop) bandits;   // Phase 9 — uncomment when adding
        // uint256[] activeBanditIds;                  // Phase 9
    }

    /// @notice Returns a storage pointer to the AppStorage struct.
    ///         Uses inline assembly to load at the deterministic STORAGE_SLOT.
    ///         All facets call this to get mutable access to game state.
    function appStorage() internal pure returns (AppStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := slot
        }
    }
}
