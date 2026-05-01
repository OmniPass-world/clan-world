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

contract MonumentUpgradeHarness is ClanWorld {
    function setVault(uint32 clanId, uint256 wood, uint256 iron, uint256 wheat, uint256 fish) external {
        _clans[clanId].vaultWood = wood;
        _clans[clanId].vaultIron = iron;
        _clans[clanId].vaultWheat = wheat;
        _clans[clanId].vaultFish = fish;
    }

    function setBlueprint(uint32 clanId, uint256 blueprint) external {
        _clans[clanId].blueprintBalance = blueprint;
    }

    function setMonumentLevel(uint32 clanId, uint8 level) external {
        _clans[clanId].monumentLevel = level;
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
        returns (uint256 score, uint256 lootValue, uint8 monumentLevel)
    {
        _settleClan(clanId);
        Clan memory clan = _clans[clanId];
        (score,,) = _getClanScoreFromClan(clanId, clan);
        lootValue = _lootValueRaw(clan);
        monumentLevel = clan.monumentLevel;
    }
}

contract MonumentUpgradesTest is Test {
    MonumentUpgradeHarness world;
    address elder = address(0xA1);
    address elder2 = address(0xA2);

    function setUp() public {
        world = new MonumentUpgradeHarness();
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
                action: ActionType.UpgradeMonument,
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

    function test_getMonumentUpgradeCost_matchesPhaseTable() public view {
        (uint256 wood, uint256 iron, uint256 wheat, uint256 blueprint) = world.getMonumentUpgradeCost(0);
        assertEq(wood, 30e18, "level 1 wood");
        assertEq(iron, 0, "level 1 iron");
        assertEq(wheat, 20e18, "level 1 wheat");
        assertEq(blueprint, 0, "level 1 blueprint");

        (wood, iron, wheat, blueprint) = world.getMonumentUpgradeCost(5);
        assertEq(wood, 150e18, "level 6 wood");
        assertEq(iron, 20e18, "level 6 iron");
        assertEq(wheat, 80e18, "level 6 wheat");
        assertEq(blueprint, 0, "level 6 blueprint");

        (wood, iron, wheat, blueprint) = world.getMonumentUpgradeCost(6);
        assertEq(wood, 200e18, "level 7 wood");
        assertEq(iron, 25e18, "level 7 iron");
        assertEq(wheat, 100e18, "level 7 wheat");
        assertEq(blueprint, 1e18, "level 7 blueprint");
    }

    function test_upgradeMonument_holdsAtQueueAndDebitsAtSettle() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 100e18, 100e18, 100e18, 100e18);
        world.setBlueprint(clanId, 5e18);

        (uint256 woodCost, uint256 ironCost, uint256 wheatCost, uint256 blueprintCost) = world.getMonumentUpgradeCost(0);
        OrderResult[] memory result = _submitOrder(elder, clanId, csId, ActionType.UpgradeMonument);

        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "queue status");
        assertEq(world.getClan(clanId).vaultWood, 100e18, "wood not deducted at queue");
        assertEq(world.getClan(clanId).vaultIron, 100e18, "iron not deducted at queue");
        assertEq(world.getClan(clanId).vaultWheat, 100e18, "wheat not deducted at queue");
        assertEq(world.getClan(clanId).blueprintBalance, 5e18, "blueprint not deducted at queue");
        assertEq(world.getClan(clanId).monumentLevel, 0, "monument level waits for settle");

        _advanceTicks(world.getActionDuration(ActionType.UpgradeMonument));
        vm.expectEmit(true, false, false, true, address(world));
        emit IClanWorldEvents.MonumentLevelChanged(clanId, 0, 1, 1);
        _advanceTick();

        assertEq(world.getClanFullView(clanId).clan.clan.monumentLevel, 1, "monument level after settle");
        assertEq(world.getClan(clanId).vaultWood, 100e18 - woodCost, "wood deducted at settle");
        assertEq(world.getClan(clanId).vaultIron, 100e18 - ironCost, "iron deducted at settle");
        assertEq(world.getClan(clanId).vaultWheat, 100e18 - wheatCost, "reserved wheat is protected from upkeep");
        assertEq(world.getClan(clanId).blueprintBalance, 5e18 - blueprintCost, "blueprint deducted at settle");
    }

    function test_upgradeMonument_rejectsInsufficientVaultAtQueueTime() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 0, 100e18, 0, 100e18);

        OrderResult[] memory result = _submitOrder(elder, clanId, csId, ActionType.UpgradeMonument);

        assertEq(uint8(result[0].status), uint8(StatusCode.ERR_MISSING_RESOURCES), "missing resources");
        assertFalse(world.getActiveMission(csId).active, "no mission queued");
        assertEq(world.getClan(clanId).monumentLevel, 0, "monument unchanged");
    }

    function test_upgradeMonument_requiresBlueprintForLateLevel() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setMonumentLevel(clanId, 6);
        world.setVault(clanId, 300e18, 100e18, 200e18, 100e18);

        OrderResult[] memory result = _submitOrder(elder, clanId, csId, ActionType.UpgradeMonument);

        assertEq(uint8(result[0].status), uint8(StatusCode.ERR_MISSING_RESOURCES), "missing blueprint");
        assertFalse(world.getActiveMission(csId).active, "no mission queued");
        assertEq(world.getClan(clanId).monumentLevel, 6, "monument unchanged");
    }

    function test_upgradeMonument_rejectsAboveMaxLevel() public {
        uint32 clanId = _mintClan(elder);
        world.setVault(clanId, 2_000e18, 500e18, 1_000e18, 100e18);
        world.setBlueprint(clanId, 4e18);

        uint256 remaining = 10;
        while (remaining > 0) {
            uint256 batchSize = remaining > 4 ? 4 : remaining;
            OrderResult[] memory batch = _submitUpgradeBatch(elder, clanId, batchSize);
            for (uint256 i = 0; i < batchSize; i++) {
                assertEq(uint8(batch[i].status), uint8(StatusCode.OK), "batch status");
            }
            _advanceTicks(world.getActionDuration(ActionType.UpgradeMonument) + 1);
            _advanceTicks(3);
            remaining -= batchSize;
        }
        assertEq(world.getClan(clanId).monumentLevel, 10, "max monument level");

        uint32 csId = _firstCs(clanId);
        OrderResult[] memory eleventh = _submitOrder(elder, clanId, csId, ActionType.UpgradeMonument);
        assertEq(uint8(eleventh[0].status), uint8(StatusCode.ERR_INVALID_ACTION), "max level rejects");
        assertEq(world.getClan(clanId).monumentLevel, 10, "monument remains max");
    }

    function test_upgradeMonument_twoClansDoNotInterfere() public {
        uint32 clanA = _mintClan(elder);
        vm.prank(elder2);
        (uint32 clanB,) = world.mintClan(elder2);
        world.setVault(clanA, 100e18, 100e18, 100e18, 100e18);
        world.setVault(clanB, 100e18, 100e18, 100e18, 100e18);

        OrderResult[] memory result = _submitOrder(elder, clanA, _firstCs(clanA), ActionType.UpgradeMonument);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "queue status");
        _advanceTicks(world.getActionDuration(ActionType.UpgradeMonument) + 1);

        assertEq(world.getClan(clanA).monumentLevel, 1, "clan A monument");
        assertEq(world.getClan(clanB).monumentLevel, 0, "clan B monument");
    }

    function test_upgradeMonument_simAndRealBothApplySequentially() public {
        // SHOULD FIX 5: higher-level reservation is retained for retry after lower-level settles.
        // Both reservations apply and sim agrees with real.
        uint32 clanId = _mintClan(elder);
        uint32 firstCsId = _csAt(clanId, 0);
        uint32 secondCsId = _csAt(clanId, 1);
        world.setVault(clanId, 500e18, 500e18, 500e18, 100e18);
        world.setBlueprint(clanId, 5e18);

        // secondCsId queues level 0→1 (fromLevel=0, matches current=0, settles first)
        OrderResult[] memory second = _submitOrder(elder, clanId, secondCsId, ActionType.UpgradeMonument);
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "second clansman queues level 1");
        // firstCsId queues level 1→2 (fromLevel=1, retained until monument reaches 1, then retries)
        OrderResult[] memory first = _submitOrder(elder, clanId, firstCsId, ActionType.UpgradeMonument);
        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first clansman queues level 2");

        world.setCurrentTick(world.getActionDuration(ActionType.UpgradeMonument) + 2);
        uint256 simLoot = world.quoteLootValueSettled(clanId);
        (uint256 simScore,,) = world.getClanScore(clanId);

        (uint256 realScore, uint256 realLoot, uint8 monumentLevel) = world.settleClanAndGetStoredScore(clanId);

        assertEq(monumentLevel, 2, "both reservations apply sequentially");
        assertEq(realLoot, simLoot, "sim and real loot match");
        assertEq(realScore, simScore, "sim and real score match");
    }

    function test_upgradeMonument_deadClansmanReleasesReservationAndAllowsRequeue() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 100e18, 0, 100e18, 0);

        OrderResult[] memory first = _submitOrder(elder, clanId, csId, ActionType.UpgradeMonument);
        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first queue status");

        world.killClansman(csId);
        _advanceTick();
        world.settleClan(clanId);

        assertEq(world.getClan(clanId).vaultWood, 100e18, "wood still in vault");
        assertFalse(world.getActiveMission(csId).active, "dead mission invalidated");

        uint32 replacementCsId = _csAt(clanId, 1);
        _advanceTicks(2);
        OrderResult[] memory second = _submitOrder(elder, clanId, replacementCsId, ActionType.UpgradeMonument);
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "reservation released for requeue");
    }

    function test_upgradeMonument_invalidatesFutureReservationAfterEarlierReservationCancelled() public {
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

        _advanceTicks(world.getActionDuration(ActionType.UpgradeMonument) + 1);

        assertEq(world.getClan(clanId).monumentLevel, 0, "future-level reservation does not reprice");
        assertTrue(world.getActiveMission(secondCsId).active, "stale mission stays pending for retry pass");

        _advanceTicks(2);
        OrderResult[] memory next = _submitOrder(elder, clanId, firstCsId, ActionType.UpgradeMonument);
        assertEq(uint8(next[0].status), uint8(StatusCode.OK), "pending count released");
    }

    function test_upgradeMonument_reversedClansmanSettlementAppliesSequentialReservations() public {
        uint32 clanId = _mintClan(elder);
        uint32 firstCsId = _csAt(clanId, 0);
        uint32 secondCsId = _csAt(clanId, 1);
        world.setVault(clanId, 500e18, 500e18, 500e18, 100e18);

        OrderResult[] memory second = _submitOrder(elder, clanId, secondCsId, ActionType.UpgradeMonument);
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "second clansman queues level 1");
        OrderResult[] memory first = _submitOrder(elder, clanId, firstCsId, ActionType.UpgradeMonument);
        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first clansman queues level 2");

        _advanceTicks(world.getActionDuration(ActionType.UpgradeMonument) + 2);

        assertEq(world.getClan(clanId).monumentLevel, 2, "future-level reservation retries after prerequisite lands");
    }

    function test_upgradeMonument_simAndRealScoresMatchAfterOutOfOrderCancellation() public {
        uint32 clanId = _mintClan(elder);
        uint32 firstCsId = _csAt(clanId, 0);
        uint32 secondCsId = _csAt(clanId, 1);
        world.setVault(clanId, 500e18, 500e18, 500e18, 100e18);

        OrderResult[] memory second = _submitOrder(elder, clanId, secondCsId, ActionType.UpgradeMonument);
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "second clansman queues level 1");
        OrderResult[] memory first = _submitOrder(elder, clanId, firstCsId, ActionType.UpgradeMonument);
        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first clansman queues level 2");

        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS);
        OrderResult[] memory cancelSecond = _submitOrder(elder, clanId, secondCsId, ActionType.Wait);
        assertEq(uint8(cancelSecond[0].status), uint8(StatusCode.OK), "cancel current-level reservation");

        world.setCurrentTick(2);
        uint256 simLoot = world.quoteLootValueSettled(clanId);
        (uint256 simScore,,) = world.getClanScore(clanId);

        (uint256 realScore, uint256 realLoot, uint8 monumentLevel) = world.settleClanAndGetStoredScore(clanId);

        assertEq(realLoot, simLoot, "sim and real loot match");
        assertEq(realScore, simScore, "sim and real score match");
        assertEq(monumentLevel, 0, "stale future reservation did not apply");
        assertTrue(world.getActiveMission(firstCsId).active, "failed upgrade remains pending for retry pass");
    }
}
