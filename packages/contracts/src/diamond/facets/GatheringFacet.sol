// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {LibStorage} from "../LibStorage.sol";
import {
    ActionType,
    ClanState,
    ClansmanState,
    Clan,
    Clansman,
    Mission,
    WheatPlot,
    WheatPlotState
} from "../../IClanWorld.sol";

/// @title GatheringFacet
/// @notice Settlement engine, all gathering actions, deposit, building upgrades.
///
///         Functions to migrate from ClanWorld.sol:
///         - _settleClan(uint32 clanId)                           — core settlement loop
///         - _settleMissionForClansman(Clan storage, Clansman storage, uint32, uint64, uint64)
///         - _settleCompletingMissions(uint64 tick)               — called by CoreFacet.heartbeat
///         - _applyUpkeep(Clan storage, uint64)
///         - _isStarving(Clan storage)
///         - _resolveAction(Clan storage, Clansman storage, Mission storage, uint32, uint64, bytes32)
///         - _gatherWood(Clan storage, Clansman storage, Mission storage, uint32, uint64, bool, bytes32)
///         - _gatherIron(Clan storage, Clansman storage, Mission storage, uint32, uint64, bool, bytes32)
///         - _rollIronGoldBonus(Clan storage, uint32, uint64, uint64, bytes32)
///         - _gatherFishDocks(Clan storage, Clansman storage, Mission storage, uint32, uint64, bool, bytes32)
///         - _gatherFishDeepSea(Clan storage, Clansman storage, Mission storage, uint32, uint64, bool, bytes32)
///         - _gatherWheat(Clan storage, Clansman storage, Mission storage, uint32, uint64, bool)
///         - _doDeposit(Clan storage, Clansman storage, Mission storage, uint32, uint64)
///         - _doBuilding(Clan storage, Clansman storage, Mission storage, uint32, uint64, ActionType)
///         - _tryBuildWall(Clan storage, uint32, uint64)
///         - _tryUpgradeBase(Clan storage, uint32, uint64)
///         - _tryUpgradeMonument(Clan storage, uint32, uint64)
///         - _completeMission(Clansman storage, Mission storage)
///
///         Cross-facet calls:
///         - CoreFacet.heartbeat calls _settleCompletingMissions via IClanWorld(address(this))
///         - CoreFacet.settleClan / settleClansman call _settleClan via IClanWorld(address(this))
///
/// TODO: migrate from ClanWorld.sol
contract GatheringFacet {
    // Access shared state via AppStorage
    // LibStorage.AppStorage storage s = LibStorage.appStorage();

    // Constants (same as ClanWorld.sol — not in AppStorage, just Solidity constants)
    uint256 private constant WHEAT_HARVEST_RATE = 20e18;
    uint256 public constant MAX_MARKET_ACTIONS_PER_TICK = 32;

    // =========================================================================
    // PUBLIC SETTLEMENT ENTRY POINTS (called via Diamond proxy)
    // =========================================================================

    // Note: settleClan and settleClansman are registered on CoreFacet as the
    // public-facing functions. GatheringFacet exposes _settleClan as an internal
    // helper. In the Diamond these are all in the same delegatecall context.

    // =========================================================================
    // SETTLEMENT ENGINE
    // =========================================================================

    // _settleClan, _settleMissionForClansman, _settleCompletingMissions
    // _applyUpkeep, _isStarving, _resolveAction
    // TODO: migrate from ClanWorld.sol

    // =========================================================================
    // GATHERING HELPERS
    // =========================================================================

    // _gatherWood, _gatherIron, _rollIronGoldBonus
    // _gatherFishDocks, _gatherFishDeepSea, _gatherWheat
    // _doDeposit, _doBuilding
    // _tryBuildWall, _tryUpgradeBase, _tryUpgradeMonument
    // _completeMission
    // TODO: migrate from ClanWorld.sol
}
