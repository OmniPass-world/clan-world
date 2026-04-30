// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {LibStorage} from "../LibStorage.sol";
import {
    IClanWorld,
    IClanWorldEvents,
    ClanWorldConstants,
    ClanState,
    ClansmanState,
    ActionType,
    MarketExecutionMode,
    StatusCode,
    WorldState,
    Clan,
    Clansman,
    Mission,
    WheatPlot,
    WheatPlotState,
    ScheduledMarketAction,
    ClanOrder,
    OrderResult,
    BanditTroop,
    BanditState
} from "../../IClanWorld.sol";

/// @title CoreFacet
/// @notice World clock, heartbeat dispatch shell, clan lifecycle, order submission, travel.
///
///         Functions to migrate from ClanWorld.sol (Phase 2 / PR):
///         - heartbeat()
///         - _resolveWorldEvents(uint64 closedTick)
///         - settleClan(uint32 clanId)          — delegates to GatheringFacet._settleClan
///         - settleClansman(uint32 csId)        — delegates to GatheringFacet._settleClan
///         - finalizeSeason()                   — stub; moves to WintersFacet at Phase 10
///         - mintClan(address to)
///         - submitClanOrders(uint32, ClanOrder[] calldata)
///         - _processOrder(uint32, Clan storage, ClanOrder calldata)
///         - _installMission(Mission storage, ClanOrder calldata, Clansman storage, OrderCtx memory)
///         - _enqueueScheduledMarketAction(...)
///         - _registerDefender(uint8, uint32, uint32)
///         - _clearDefender(uint32)
///         - _validateAction(Clan storage, Clansman storage, ClanOrder calldata, uint8)
///         - _validateDefendBaseOrder(Clan storage, ClanOrder calldata, uint8)
///         - _distMatrix(uint8, uint8)  — pure travel helper
///         - _buildPath(uint8, uint8)   — pure travel helper
///         - _travelTicks(uint8, uint8) — pure travel helper
///         - _addTicksClamped(uint64, uint64) — pure helper
///         - getActionDuration(ActionType)  — pure, from IClanWorld
///         - getTravelTicks(uint8, uint8)   — pure, from IClanWorld
///
///         Note: heartbeat calls into GatheringFacet for _settleCompletingMissions
///         and into MarketFacet for _executeScheduledMarketActions.
///         Cross-facet calls within a Diamond use the proxy address (address(this)).
///
/// TODO: migrate from ClanWorld.sol
contract CoreFacet {
    // Access shared state via AppStorage
    // LibStorage.AppStorage storage s = LibStorage.appStorage();

    // =========================================================================
    // WORLD PROGRESSION
    // =========================================================================

    function heartbeat() external {
        // TODO: migrate from ClanWorld.sol
    }

    function settleClan(uint32 /*clanId*/) external {
        // TODO: migrate from ClanWorld.sol
        // Delegates to GatheringFacet._settleClan via internal call pattern
    }

    function settleClansman(uint32 /*csId*/) external {
        // TODO: migrate from ClanWorld.sol
    }

    function finalizeSeason() external {
        // TODO: stub — Phase 10 implementation moves to WintersFacet
    }

    // =========================================================================
    // CLAN LIFECYCLE
    // =========================================================================

    function mintClan(address /*to*/) external returns (uint32 clanId, uint256 iftTokenId) {
        // TODO: migrate from ClanWorld.sol
    }

    function submitClanOrders(uint32 /*clanId*/, ClanOrder[] calldata /*orders*/)
        external
        returns (OrderResult[] memory results)
    {
        // TODO: migrate from ClanWorld.sol
    }

    // =========================================================================
    // PURE VIEWS (no storage)
    // =========================================================================

    function getActionDuration(ActionType /*action*/) public pure returns (uint64) {
        // TODO: migrate from ClanWorld.sol
    }

    function getTravelTicks(uint8 /*fromRegion*/, uint8 /*toRegion*/) external pure returns (uint64) {
        // TODO: migrate from ClanWorld.sol
    }
}
