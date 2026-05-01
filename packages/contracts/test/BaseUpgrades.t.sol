// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {
    IClanWorldEvents,
    ClanWorldConstants,
    Clan,
    ClanOrder,
    WithdrawResourcesData,
    ClansmanState,
    OrderResult,
    StatusCode,
    ActionType
} from "../src/IClanWorld.sol";

contract BaseUpgradeHarness is ClanWorld {
    function setVault(uint32 clanId, uint256 wood, uint256 iron, uint256 wheat, uint256 fish) external {
        _clans[clanId].vaultWood = wood;
        _clans[clanId].vaultIron = iron;
        _clans[clanId].vaultWheat = wheat;
        _clans[clanId].vaultFish = fish;
    }

    function killClansman(uint32 clansmanId) external {
        _clansmen[clansmanId].state = ClansmanState.DEAD;
    }

    function setCurrentTick(uint64 tick) external {
        _world.currentTick = tick;
        _world.nextHeartbeatAtTick = tick + 1;
    }

    function settleClanAndGetStoredScore(uint32 clanId)
        external
        returns (uint256 score, uint256 lootValue, uint8 baseLevel)
    {
        _settleClan(clanId);
        Clan memory clan = _clans[clanId];
        (score,,) = _getClanScoreFromClan(clanId, clan);
        lootValue = _lootValueRaw(clan);
        baseLevel = clan.baseLevel;
    }
}

contract BaseUpgradesTest is Test {
    BaseUpgradeHarness world;
    address elder = address(0xA1);
    address elder2 = address(0xA2);

    function setUp() public {
        world = new BaseUpgradeHarness();
    }

    function _mintClan(address owner) internal returns (uint32 clanId) {
        vm.prank(owner);
        (clanId,) = world.mintClan(owner);
    }

    function _firstCs(uint32 clanId) internal view returns (uint32) {
        return world.getClanFullView(clanId).clansmen[0].clansman.clansman.clansmanId;
    }

    function _csAt(uint32 clanId, uint256 index) internal view returns (uint32) {
        return world.getClanFullView(clanId).clansmen[index].clansman.clansman.clansmanId;
    }

    function _submitOrder(address owner, uint32 clanId, uint32 csId, ActionType action)
        internal
        returns (OrderResult[] memory)
    {
        Clan memory clan = world.getClan(clanId);
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: clan.baseRegion,
            action: action,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0,
            withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
        });
        vm.prank(owner);
        return world.submitClanOrders(clanId, orders);
    }

    function _submitUpgradeBatch(address owner, uint32 clanId, uint256 count) internal returns (OrderResult[] memory) {
        Clan memory clan = world.getClan(clanId);
        ClanOrder[] memory orders = new ClanOrder[](count);
        for (uint256 i = 0; i < count; i++) {
            orders[i] = ClanOrder({
                clansmanId: _csAt(clanId, i),
                gotoRegion: clan.baseRegion,
                action: ActionType.UpgradeBase,
                targetClanId: 0,
                marketToken: address(0),
                marketAmount: 0,
                maxGoldIn: 0,
                withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
            });
        }
        vm.prank(owner);
        return world.submitClanOrders(clanId, orders);
    }

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }

    function _advanceTicks(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            _advanceTick();
        }
    }

    function test_getBaseUpgradeCost_matchesSpecTable() public view {
        (uint256 wood, uint256 iron, uint256 wheat) = world.getBaseUpgradeCost(1);
        assertEq(wood, 40e18, "level 2 wood");
        assertEq(iron, 0, "level 2 iron");
        assertEq(wheat, 20e18, "level 2 wheat");

        (wood, iron, wheat) = world.getBaseUpgradeCost(3);
        assertEq(wood, 80e18, "level 4 wood");
        assertEq(iron, 10e18, "level 4 iron");
        assertEq(wheat, 40e18, "level 4 wheat");

        (wood, iron, wheat) = world.getBaseUpgradeCost(4);
        assertEq(wood, 100e18, "level 5 wood");
        assertEq(iron, 15e18, "level 5 iron");
        assertEq(wheat, 50e18, "level 5 wheat");
    }

    function test_upgradeBase_holdsAtQueueAndDebitsAtSettle() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 100e18, 100e18, 100e18, 100e18);

        (uint256 woodCost, uint256 ironCost, uint256 wheatCost) = world.getBaseUpgradeCost(1);
        OrderResult[] memory result = _submitOrder(elder, clanId, csId, ActionType.UpgradeBase);

        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "queue status");
        assertEq(world.getClan(clanId).vaultWood, 100e18, "wood not deducted at queue");
        assertEq(world.getClan(clanId).vaultIron, 100e18, "iron not deducted at queue");
        assertEq(world.getClan(clanId).vaultWheat, 100e18, "wheat not deducted at queue");
        assertEq(world.getClan(clanId).baseLevel, 1, "base level waits for settle");

        _advanceTicks(world.getActionDuration(ActionType.UpgradeBase));
        vm.expectEmit(true, false, false, true, address(world));
        emit IClanWorldEvents.BaseLevelChanged(clanId, 1, 2, 1);
        _advanceTick();

        assertEq(world.getClan(clanId).baseLevel, 2, "base level after settle");
        assertEq(world.getClan(clanId).vaultWood, 100e18 - woodCost, "wood deducted at settle");
        assertEq(world.getClan(clanId).vaultIron, 100e18 - ironCost, "iron deducted at settle");
        assertEq(world.getClan(clanId).vaultWheat, 100e18 - wheatCost, "reserved wheat is protected from upkeep");
    }

    function test_upgradeBase_rejectsInsufficientVaultAtQueueTime() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 0, 100e18, 0, 100e18);

        OrderResult[] memory result = _submitOrder(elder, clanId, csId, ActionType.UpgradeBase);

        assertEq(uint8(result[0].status), uint8(StatusCode.ERR_MISSING_RESOURCES), "missing resources");
        assertFalse(world.getActiveMission(csId).active, "no mission queued");
        assertEq(world.getClan(clanId).baseLevel, 1, "base unchanged");
    }

    function test_upgradeBase_rejectsAboveMaxLevel() public {
        uint32 clanId = _mintClan(elder);
        world.setVault(clanId, 300e18, 100e18, 200e18, 100e18);

        OrderResult[] memory firstFour = _submitUpgradeBatch(elder, clanId, 4);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(uint8(firstFour[i].status), uint8(StatusCode.OK), "first batch status");
        }
        _advanceTicks(world.getActionDuration(ActionType.UpgradeBase) + 1);
        assertEq(world.getClan(clanId).baseLevel, 5, "max base level");

        _advanceTicks(3);
        uint32 csId = _firstCs(clanId);
        OrderResult[] memory fifth = _submitOrder(elder, clanId, csId, ActionType.UpgradeBase);
        assertEq(uint8(fifth[0].status), uint8(StatusCode.ERR_INVALID_ACTION), "max level rejects");
        assertEq(world.getClan(clanId).baseLevel, 5, "base remains max");
    }

    function test_upgradeBase_twoClansDoNotInterfere() public {
        uint32 clanA = _mintClan(elder);
        vm.prank(elder2);
        (uint32 clanB,) = world.mintClan(elder2);
        world.setVault(clanA, 100e18, 100e18, 100e18, 100e18);
        world.setVault(clanB, 100e18, 100e18, 100e18, 100e18);

        OrderResult[] memory result = _submitOrder(elder, clanA, _firstCs(clanA), ActionType.UpgradeBase);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "queue status");
        _advanceTicks(world.getActionDuration(ActionType.UpgradeBase) + 1);

        assertEq(world.getClan(clanA).baseLevel, 2, "clan A base");
        assertEq(world.getClan(clanB).baseLevel, 1, "clan B base");
    }

    function test_upgradeBase_simAndRealBothApplySequentially() public {
        // SHOULD FIX 5: higher-level reservation is retained for retry after lower-level settles.
        // Both reservations apply and sim agrees with real.
        uint32 clanId = _mintClan(elder);
        uint32 firstCsId = _csAt(clanId, 0);
        uint32 secondCsId = _csAt(clanId, 1);
        world.setVault(clanId, 500e18, 500e18, 500e18, 100e18);

        // secondCsId queues level 1→2 (fromLevel=1, matches current, settles first)
        OrderResult[] memory second = _submitOrder(elder, clanId, secondCsId, ActionType.UpgradeBase);
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "second clansman queues level 2");
        // firstCsId queues level 2→3 (fromLevel=2, retained until base reaches 2, then retries)
        OrderResult[] memory first = _submitOrder(elder, clanId, firstCsId, ActionType.UpgradeBase);
        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first clansman queues level 3");

        world.setCurrentTick(world.getActionDuration(ActionType.UpgradeBase) + 2);
        uint256 simLoot = world.quoteLootValueSettled(clanId);
        (uint256 simScore,,) = world.getClanScore(clanId);

        (uint256 realScore, uint256 realLoot, uint8 baseLevel) = world.settleClanAndGetStoredScore(clanId);

        assertEq(baseLevel, 3, "both reservations apply sequentially");
        assertEq(realLoot, simLoot, "sim and real loot match");
        assertEq(realScore, simScore, "sim and real score match");
    }

    /// @dev MUST FIX 1: sim upkeep must respect wheat reservations.
    ///      quoteLootValueSettled and getClanScore must agree with real settle when a wheat
    ///      reservation is active, because _simulateApplyUpkeep now mirrors _applyUpkeep's
    ///      _spendableAfterReleasing logic.
    function test_quoteLootValueMatchesRealAfterUpkeepWithReservedWheat() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);

        // Give enough wheat to cover the reservation but not upkeep (tight budget).
        // Base level 1 → 2 reservation costs 20e18 wheat. Clan has 1 living clansman,
        // upkeep = 1e18 wheat/tick. Set vault so reserved wheat covers most of vault.
        (,, uint256 wheatReserved) = world.getBaseUpgradeCost(1);
        // Give exactly reservation + 0 surplus (spendable = 0 if vault == reserved)
        world.setVault(clanId, 100e18, 100e18, wheatReserved, 100e18);

        // Queue the upgrade — this creates the wheat reservation.
        OrderResult[] memory result = _submitOrder(elder, clanId, csId, ActionType.UpgradeBase);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        // Advance to settlement tick.
        world.setCurrentTick(world.getActionDuration(ActionType.UpgradeBase) + 1);

        // Sim and real must agree: no wheat available for upkeep (all reserved), so clan starves.
        uint256 simLoot = world.quoteLootValueSettled(clanId);
        (uint256 simScore,,) = world.getClanScore(clanId);

        (uint256 realScore, uint256 realLoot,) = world.settleClanAndGetStoredScore(clanId);

        assertEq(realLoot, simLoot, "sim and real loot agree with wheat reservation");
        assertEq(realScore, simScore, "sim and real score agree with wheat reservation");
        // Clan is starving: starvation started (wheat spendable = 0)
        assertGt(world.getClan(clanId).starvationStartsAtTick, 0, "clan starves when all wheat reserved");
    }

    /// @dev SHOULD FIX 8: ERR_NOT_AT_HOMEBASE when gotoRegion != clan.baseRegion for UpgradeBase.
    function test_upgradeBase_rejectsWrongRegion() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 100e18, 100e18, 100e18, 100e18);

        Clan memory clan = world.getClan(clanId);
        // Use a region that is NOT the base region
        uint8 nonBase = clan.baseRegion == ClanWorldConstants.REGION_FOREST
            ? ClanWorldConstants.REGION_MOUNTAINS
            : ClanWorldConstants.REGION_FOREST;

        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: nonBase,
            action: ActionType.UpgradeBase,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0,
            withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
        });
        vm.prank(elder);
        OrderResult[] memory result = world.submitClanOrders(clanId, orders);

        assertEq(uint8(result[0].status), uint8(StatusCode.ERR_NOT_AT_HOMEBASE), "wrong region rejects");
        assertFalse(world.getActiveMission(csId).active, "no mission queued");
        assertEq(world.getClan(clanId).baseLevel, 1, "base level unchanged");
    }

    /// @dev SHOULD FIX 8: vault drained between submission and settlement triggers insolvency handling.
    ///      After draining vault below wheat cost, the upgrade should be retried (return false)
    ///      rather than incorrectly completing.
    function test_upgradeBase_drainedVaultBetweenSubmitAndSettleIsRetried() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 100e18, 100e18, 100e18, 100e18);

        OrderResult[] memory result = _submitOrder(elder, clanId, csId, ActionType.UpgradeBase);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        // Drain the vault below upgrade cost before settlement.
        world.setVault(clanId, 0, 0, 0, 100e18);

        world.setCurrentTick(world.getActionDuration(ActionType.UpgradeBase) + 1);
        world.settleClan(clanId);

        // Upgrade must NOT have applied — clansman still pending retry.
        assertEq(world.getClan(clanId).baseLevel, 1, "base not upgraded with drained vault");
        assertTrue(world.getActiveMission(csId).active, "mission stays active for retry");
    }

    function test_upgradeBase_deadClansmanReleasesReservationAndAllowsRequeue() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 100e18, 100e18, 100e18, 100e18);

        OrderResult[] memory first = _submitOrder(elder, clanId, csId, ActionType.UpgradeBase);
        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first queue status");

        world.killClansman(csId);
        _advanceTick();
        world.settleClan(clanId);

        assertEq(world.getClan(clanId).vaultWood, 100e18, "wood still in vault");
        assertFalse(world.getActiveMission(csId).active, "dead mission invalidated");

        uint32 replacementCsId = _csAt(clanId, 1);
        _advanceTicks(2);
        OrderResult[] memory second = _submitOrder(elder, clanId, replacementCsId, ActionType.UpgradeBase);
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "reservation released for requeue");
    }

    function test_upgradeBase_invalidatesFutureReservationAfterEarlierReservationCancelled() public {
        uint32 clanId = _mintClan(elder);
        uint32 firstCsId = _csAt(clanId, 0);
        uint32 secondCsId = _csAt(clanId, 1);
        world.setVault(clanId, 500e18, 500e18, 500e18, 100e18);

        OrderResult[] memory batch = _submitUpgradeBatch(elder, clanId, 2);
        assertEq(uint8(batch[0].status), uint8(StatusCode.OK), "first queue");
        assertEq(uint8(batch[1].status), uint8(StatusCode.OK), "second queue");

        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS);
        OrderResult[] memory cancelFirst = _submitOrder(elder, clanId, firstCsId, ActionType.Wait);
        assertEq(uint8(cancelFirst[0].status), uint8(StatusCode.OK), "cancel first");

        _advanceTicks(world.getActionDuration(ActionType.UpgradeBase) + 1);

        assertEq(world.getClan(clanId).baseLevel, 1, "future-level reservation does not reprice");
        assertTrue(world.getActiveMission(secondCsId).active, "stale mission stays pending for retry pass");

        _advanceTicks(2);
        OrderResult[] memory next = _submitOrder(elder, clanId, firstCsId, ActionType.UpgradeBase);
        assertEq(uint8(next[0].status), uint8(StatusCode.OK), "pending count released");
    }

    function test_upgradeBase_reversedClansmanSettlementAppliesSequentialReservations() public {
        uint32 clanId = _mintClan(elder);
        uint32 firstCsId = _csAt(clanId, 0);
        uint32 secondCsId = _csAt(clanId, 1);
        world.setVault(clanId, 500e18, 500e18, 500e18, 100e18);

        OrderResult[] memory second = _submitOrder(elder, clanId, secondCsId, ActionType.UpgradeBase);
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "second clansman queues level 1");
        OrderResult[] memory first = _submitOrder(elder, clanId, firstCsId, ActionType.UpgradeBase);
        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first clansman queues level 2");

        _advanceTicks(world.getActionDuration(ActionType.UpgradeBase) + 2);

        assertEq(world.getClan(clanId).baseLevel, 3, "future-level reservation retries after prerequisite lands");
    }

    function test_upgradeBase_simAndRealScoresMatchAfterOutOfOrderCancellation() public {
        uint32 clanId = _mintClan(elder);
        uint32 firstCsId = _csAt(clanId, 0);
        uint32 secondCsId = _csAt(clanId, 1);
        world.setVault(clanId, 500e18, 500e18, 500e18, 100e18);

        OrderResult[] memory second = _submitOrder(elder, clanId, secondCsId, ActionType.UpgradeBase);
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "second clansman queues level 1");
        OrderResult[] memory first = _submitOrder(elder, clanId, firstCsId, ActionType.UpgradeBase);
        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first clansman queues level 2");

        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS);
        OrderResult[] memory cancelSecond = _submitOrder(elder, clanId, secondCsId, ActionType.Wait);
        assertEq(uint8(cancelSecond[0].status), uint8(StatusCode.OK), "cancel current-level reservation");

        world.setCurrentTick(2);
        uint256 simLoot = world.quoteLootValueSettled(clanId);
        (uint256 simScore,,) = world.getClanScore(clanId);

        (uint256 realScore, uint256 realLoot, uint8 baseLevel) = world.settleClanAndGetStoredScore(clanId);

        assertEq(realLoot, simLoot, "sim and real loot match");
        assertEq(realScore, simScore, "sim and real score match");
        assertEq(baseLevel, 1, "stale future reservation did not apply");
        assertTrue(world.getActiveMission(firstCsId).active, "failed upgrade remains pending for retry pass");
    }
}
