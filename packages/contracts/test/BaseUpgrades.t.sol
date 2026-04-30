// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {
    IClanWorldEvents,
    ClanWorldConstants,
    Clan,
    ClanOrder,
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
            maxGoldIn: 0
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
                maxGoldIn: 0
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
        emit IClanWorldEvents.BaseUpgraded(clanId, 2, 1);
        _advanceTick();

        assertEq(world.getClan(clanId).baseLevel, 2, "base level after settle");
        assertEq(world.getClan(clanId).vaultWood, 100e18 - woodCost, "wood deducted at settle");
        assertEq(world.getClan(clanId).vaultIron, 100e18 - ironCost, "iron deducted at settle");
        assertEq(world.getClan(clanId).vaultWheat, 100e18 - wheatCost - 8e18, "wheat upkeep and upgrade cost deducted");
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

    function test_upgradeBase_simHidesRefundedReservationFromLaterRetry() public {
        uint32 clanId = _mintClan(elder);
        uint32 firstCsId = _csAt(clanId, 0);
        uint32 secondCsId = _csAt(clanId, 1);
        world.setVault(clanId, 500e18, 500e18, 500e18, 100e18);

        OrderResult[] memory second = _submitOrder(elder, clanId, secondCsId, ActionType.UpgradeBase);
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "second clansman queues level 2");
        OrderResult[] memory first = _submitOrder(elder, clanId, firstCsId, ActionType.UpgradeBase);
        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first clansman queues level 3");

        world.setCurrentTick(world.getActionDuration(ActionType.UpgradeBase) + 2);
        uint256 simLoot = world.quoteLootValueSettled(clanId);
        (uint256 simScore,,) = world.getClanScore(clanId);

        (uint256 realScore, uint256 realLoot, uint8 baseLevel) = world.settleClanAndGetStoredScore(clanId);

        assertEq(baseLevel, 2, "real refunds stale level-3 reservation");
        assertEq(realLoot, simLoot, "sim and real loot match");
        assertEq(realScore, simScore, "sim and real score match");
    }
}
