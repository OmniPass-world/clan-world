// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {LibStorage} from "../LibStorage.sol";
import {
    ActionType,
    StatusCode,
    ScheduledMarketAction,
    PoolSeedConfig,
    ResourceType
} from "../../IClanWorld.sol";

/// @title MarketFacet
/// @notice Market execution, treasury initialization, pool seeding, OTC stubs.
///
///         Functions to migrate from ClanWorld.sol:
///         - _executeScheduledMarketActions(uint64 tick)  — called by CoreFacet.heartbeat
///         - _executeMarketSellExternal(uint64, uint32, uint32, address, uint256, uint64)
///         - _executeMarketSell(uint64, uint32, uint32, address, uint256, uint64)
///         - _executeMarketBuyExternal(uint64, uint32, uint32, address, uint256, uint256, uint64)
///         - _executeMarketBuy(uint64, uint32, uint32, address, uint256, uint256, uint64)
///         - _sortScheduledMarketActionsByCommitSequence(ScheduledMarketAction[] storage)
///         - _poolFor(address token)
///         - _addToVault(Clan storage, address, uint256)
///         - _deductFromVault(Clan storage, address, uint256)
///         - initTreasury(address[6] calldata, address[4] calldata)
///         - seedPools(PoolSeedConfig calldata)
///         - transferGold(uint32, uint32, uint256)       — pure revert stub
///         - transferVaultResource(uint32, uint32, ResourceType, uint256) — pure revert stub
///         - transferBlueprint(uint32, uint32, uint256)  — pure revert stub
///         - transferBundle(uint32, uint32, uint256, uint256, uint256, uint256, uint256, uint256) — pure revert stub
///
///         Note on try/catch pattern:
///         In ClanWorld.sol, heartbeat calls `this._executeMarketSellExternal(...)` (self-call)
///         to create a try/catch boundary. In the Diamond, `address(this)` is the proxy.
///         CoreFacet calls `IClanWorld(address(this))._executeMarketSellExternal(...)` —
///         the proxy routes back to MarketFacet via delegatecall.
///         The `require(msg.sender == address(this))` guard in the external wrapper
///         still works because under delegatecall, address(this) = Diamond proxy.
///
/// TODO: migrate from ClanWorld.sol
contract MarketFacet {
    // Access shared state via AppStorage
    // LibStorage.AppStorage storage s = LibStorage.appStorage();

    // =========================================================================
    // MARKET EXECUTION (called by CoreFacet.heartbeat)
    // =========================================================================

    function _executeMarketSellExternal(
        uint64, /*closedTick*/
        uint32, /*clanId*/
        uint32, /*clansmanId*/
        address, /*token*/
        uint256, /*amount*/
        uint64 /*commitSequence*/
    ) external {
        // TODO: migrate from ClanWorld.sol
        // Guard: require(msg.sender == address(this), "ClanWorld: internal only");
    }

    function _executeMarketBuyExternal(
        uint64, /*closedTick*/
        uint32, /*clanId*/
        uint32, /*clansmanId*/
        address, /*token*/
        uint256, /*amountOut*/
        uint256, /*maxGoldIn*/
        uint64 /*commitSequence*/
    ) external {
        // TODO: migrate from ClanWorld.sol
        // Guard: require(msg.sender == address(this), "ClanWorld: internal only");
    }

    // =========================================================================
    // TREASURY
    // =========================================================================

    function initTreasury(address[6] calldata /*tokens*/, address[4] calldata /*pools*/) external {
        // TODO: migrate from ClanWorld.sol
    }

    function seedPools(PoolSeedConfig calldata /*cfg*/) external {
        // TODO: migrate from ClanWorld.sol
    }

    // =========================================================================
    // OTC STUBS (pure revert — Phase 8+)
    // =========================================================================

    function transferGold(uint32, uint32, uint256) external pure {
        revert("OTC transfers not implemented");
    }

    function transferVaultResource(uint32, uint32, ResourceType, uint256) external pure {
        revert("OTC transfers not implemented");
    }

    function transferBlueprint(uint32, uint32, uint256) external pure {
        revert("OTC transfers not implemented");
    }

    function transferBundle(uint32, uint32, uint256, uint256, uint256, uint256, uint256, uint256) external pure {
        revert("OTC transfers not implemented");
    }
}
