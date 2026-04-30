// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {LibStorage} from "../LibStorage.sol";

/// @title BanditsFacet
/// @notice Phase 9 bandit attack/defense mechanics — STUB, no business logic yet.
///
///         This facet is a landing zone for Phase 9 implementation.
///         It registers the Phase 9 function selectors in the Diamond so
///         the ABI surface is reserved even before the logic is written.
///
///         Functions to implement in Phase 9:
///         - spawnBandit(uint8 region, uint8 tier)          — owner/keeper call
///         - resolveBanditAttack(uint32 banditId)           — permissionless
///         - _pickBanditTarget(uint32 banditId, bytes32 seed) — internal
///         - _executeBanditSteal(uint32 banditId, uint32 targetClanId, bytes32 seed) — internal
///         - _defeatBandit(uint32 banditId)                 — internal
///         - _escapeBandit(uint32 banditId)                 — internal
///
///         Phase 9 storage fields to add to AppStorage (LibStorage.sol):
///         - mapping(uint32 => BanditTroop) bandits
///         - uint32[] activeBanditIds
///         - (append to end of AppStorage struct — never insert in middle)
///
///         Relevant ClanWorldConstants (already in IClanWorld):
///         - BANDIT_COOLDOWN_TICKS = 10
///         - BANDIT_CAMP_TICKS = 3
///         - BANDIT_REST_TICKS = 2
///         - BANDIT_MAX_ATTACK_ATTEMPTS = 6
///         - BANDIT_BASE_STEAL_BPS = 2000 (20%)
///         - BANDIT_DROP_TO_DEFENDERS_BPS = 5000 (50%)
///
/// TODO: Phase 9 implementation — all functions are stubs
contract BanditsFacet {
    // Access shared state via AppStorage
    // LibStorage.AppStorage storage s = LibStorage.appStorage();

    // Phase 9 — placeholder; selectors registered in Diamond at deploy
    // so existing function signatures are reserved in the ABI.
}
