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
                action: ActionType.UpgradeMonument,
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

    function test_upgradeMonument_deductsAtQueueAndSettlesLevel() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 100e18, 100e18, 100e18, 100e18);
        world.setBlueprint(clanId, 5e18);

        (uint256 woodCost, uint256 ironCost, uint256 wheatCost, uint256 blueprintCost) = world.getMonumentUpgradeCost(0);
        OrderResult[] memory result = _submitOrder(elder, clanId, csId, ActionType.UpgradeMonument);

        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "queue status");
        assertEq(world.getClan(clanId).vaultWood, 100e18 - woodCost, "wood deducted at queue");
        assertEq(world.getClan(clanId).vaultIron, 100e18 - ironCost, "iron deducted at queue");
        assertEq(world.getClan(clanId).vaultWheat, 100e18 - wheatCost, "wheat deducted at queue");
        assertEq(world.getClan(clanId).blueprintBalance, 5e18 - blueprintCost, "blueprint deducted at queue");
        assertEq(world.getClan(clanId).monumentLevel, 0, "monument level waits for settle");

        _advanceTicks(world.getActionDuration(ActionType.UpgradeMonument));
        vm.expectEmit(true, false, false, true, address(world));
        emit IClanWorldEvents.MonumentUpgraded(clanId, 1, 4);
        _advanceTick();

        assertEq(world.getClanFullView(clanId).clan.clan.monumentLevel, 1, "monument level after settle");
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
}
