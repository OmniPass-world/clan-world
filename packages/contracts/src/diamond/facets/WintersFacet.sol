// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {LibStorage} from "../LibStorage.sol";

/// @title WintersFacet
/// @notice Phase 10 winter damage + clan elimination mechanics — STUB.
///
///         This facet is a landing zone for Phase 10 implementation.
///         It owns the winter-mechanics functions that are currently
///         timer-only stubs in CoreFacet._resolveWorldEvents.
///
///         Functions to implement in Phase 10:
///         - _applyWinterDamage(uint64 tick)        — called each tick winter is active
///         - _applyWinterUpkeepMultiplier(uint32 clanId, uint64 tick) — 2x upkeep
///         - _applyWinterWoodBurn(uint32 clanId, uint64 tick) — burns wood per base level
///         - _accumulateColdDamage(uint32 clanId)   — increments coldDamage on Clan
///         - _eliminateClan(uint32 clanId, uint64 tick) — marks ClanState.DEAD
///         - finalizeSeason()                       — full Phase 10 impl (CoreFacet has stub now)
///         - _distributeSeasonPrizes()              — treasury payout at season end
///
///         Relevant storage fields (already in AppStorage via WorldState):
///         - world.winterActive
///         - world.winterStartsAtTick
///         - world.winterEndsAtTick
///         - clan.coldDamage (uint16 on Clan struct)
///         - treasury.prizePotGold (on TreasuryState)
///
///         Relevant ClanWorldConstants (already in IClanWorld):
///         - WINTER_WOOD_BURN_PER_BASE = 1e18
///         - WINTER_UPKEEP_MULTIPLIER_BPS = 20000 (2x)
///         - TICKS_PER_WINTER_CYCLE = 110
///         - WINTER_DURATION_TICKS = 10
///
/// TODO: Phase 10 implementation — all functions are stubs
contract WintersFacet {
    // Access shared state via AppStorage
    // LibStorage.AppStorage storage s = LibStorage.appStorage();

    // Phase 10 — placeholder; finalizeSeason is currently stubbed in CoreFacet
    // When Phase 10 ships: remove finalizeSeason from CoreFacet, register it here.
}
