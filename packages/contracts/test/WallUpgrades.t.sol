// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {
    IClanWorldEvents,
    ClanWorldConstants,
    Clan,
    ClanOrder,
    ClansmanState,
    OrderResult,
    StatusCode,
    ActionType
} from "../src/IClanWorld.sol";

contract WallUpgradeHarness is ClanWorld {
    function setVault(uint32 clanId, uint256 wood, uint256 iron, uint256 wheat, uint256 fish) external {
        _clans[clanId].vaultWood = wood;
        _clans[clanId].vaultIron = iron;
        _clans[clanId].vaultWheat = wheat;
        _clans[clanId].vaultFish = fish;
    }

    function killClansman(uint32 clansmanId) external {
        _clansmen[clansmanId].state = ClansmanState.DEAD;
    }
}

contract WallUpgradesTest is Test {
    WallUpgradeHarness world;
    address elder = address(0xA1);
    address elder2 = address(0xA2);

    function setUp() public {
        world = new WallUpgradeHarness();
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
                action: ActionType.UpgradeWall,
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

    function test_getWallUpgradeCost_matchesSpecTable() public view {
        (uint256 wood, uint256 iron) = world.getWallUpgradeCost(0);
        assertEq(wood, 20e18, "level 1 wood");
        assertEq(iron, 0, "level 1 iron");

        (wood, iron) = world.getWallUpgradeCost(2);
        assertEq(wood, 30e18, "level 3 wood");
        assertEq(iron, 5e18, "level 3 iron");

        (wood, iron) = world.getWallUpgradeCost(4);
        assertEq(wood, 50e18, "level 5 wood");
        assertEq(iron, 15e18, "level 5 iron");
    }

    function test_upgradeWall_holdsAtQueueAndDebitsAtSettle() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 100e18, 100e18, 100e18, 100e18);

        (uint256 woodCost, uint256 ironCost) = world.getWallUpgradeCost(0);
        OrderResult[] memory result = _submitOrder(elder, clanId, csId, ActionType.UpgradeWall);

        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "queue status");
        assertEq(world.getClan(clanId).vaultWood, 100e18, "wood not deducted at queue");
        assertEq(world.getClan(clanId).vaultIron, 100e18, "iron not deducted at queue");
        assertEq(world.getClan(clanId).wallLevel, 0, "wall level waits for settle");

        _advanceTicks(world.getActionDuration(ActionType.UpgradeWall));
        vm.expectEmit(true, false, false, true, address(world));
        emit IClanWorldEvents.WallUpgraded(clanId, 1, 1);
        _advanceTick();

        assertEq(world.getClan(clanId).wallLevel, 1, "wall level after settle");
        assertEq(world.getClan(clanId).vaultWood, 100e18 - woodCost, "wood deducted at settle");
        assertEq(world.getClan(clanId).vaultIron, 100e18 - ironCost, "iron deducted at settle");
    }

    function test_buildWall_isDeprecatedAndRejected() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 100e18, 100e18, 100e18, 100e18);

        OrderResult[] memory result = _submitOrder(elder, clanId, csId, ActionType.BuildWall);

        assertEq(uint8(result[0].status), uint8(StatusCode.ERR_INVALID_ACTION), "build wall rejected");
        assertFalse(world.getActiveMission(csId).active, "no mission queued");
        assertEq(world.getClan(clanId).wallLevel, 0, "wall unchanged");
    }

    function test_upgradeWall_deadClansmanReleasesReservationAndAllowsRequeue() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 100e18, 100e18, 100e18, 100e18);

        OrderResult[] memory first = _submitOrder(elder, clanId, csId, ActionType.UpgradeWall);
        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first queue status");

        world.killClansman(csId);
        _advanceTick();
        world.settleClan(clanId);

        assertEq(world.getClan(clanId).vaultWood, 100e18, "wood still in vault");
        assertEq(world.getClan(clanId).vaultIron, 100e18, "iron still in vault");
        assertFalse(world.getActiveMission(csId).active, "dead mission invalidated");

        uint32 replacementCsId = _csAt(clanId, 1);
        _advanceTicks(2);
        OrderResult[] memory second = _submitOrder(elder, clanId, replacementCsId, ActionType.UpgradeWall);
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "reservation released for requeue");
    }

    function test_upgradeWall_repricesLowerLevelAfterEarlierReservationCancelled() public {
        uint32 clanId = _mintClan(elder);
        uint32 firstCsId = _csAt(clanId, 0);
        world.setVault(clanId, 100e18, 100e18, 100e18, 100e18);

        OrderResult[] memory batch = _submitUpgradeBatch(elder, clanId, 2);
        assertEq(uint8(batch[0].status), uint8(StatusCode.OK), "first queue");
        assertEq(uint8(batch[1].status), uint8(StatusCode.OK), "second queue");

        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS);
        OrderResult[] memory cancelFirst = _submitOrder(elder, clanId, firstCsId, ActionType.Wait);
        assertEq(uint8(cancelFirst[0].status), uint8(StatusCode.OK), "cancel first");

        _advanceTicks(world.getActionDuration(ActionType.UpgradeWall) + 1);

        assertEq(world.getClan(clanId).wallLevel, 1, "second settles one level");
        assertEq(world.getClan(clanId).vaultWood, 80e18, "only level-1 cost debited");
        assertEq(world.getClan(clanId).vaultIron, 100e18, "no level-2 iron debit");

        _advanceTicks(2);
        OrderResult[] memory next = _submitOrder(elder, clanId, firstCsId, ActionType.UpgradeWall);
        assertEq(uint8(next[0].status), uint8(StatusCode.OK), "pending count released");
    }

    function test_upgradeWall_rejectsInsufficientVaultAtQueueTime() public {
        uint32 clanId = _mintClan(elder);
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, 0, 0, 100e18, 100e18);

        OrderResult[] memory result = _submitOrder(elder, clanId, csId, ActionType.UpgradeWall);

        assertEq(uint8(result[0].status), uint8(StatusCode.ERR_MISSING_RESOURCES), "missing resources");
        assertFalse(world.getActiveMission(csId).active, "no mission queued");
        assertEq(world.getClan(clanId).wallLevel, 0, "wall unchanged");
    }

    function test_upgradeWall_rejectsAboveMaxLevel() public {
        uint32 clanId = _mintClan(elder);
        world.setVault(clanId, 300e18, 100e18, 100e18, 100e18);

        OrderResult[] memory firstFour = _submitUpgradeBatch(elder, clanId, 4);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(uint8(firstFour[i].status), uint8(StatusCode.OK), "first batch status");
        }
        _advanceTicks(world.getActionDuration(ActionType.UpgradeWall) + 1);
        assertEq(world.getClan(clanId).wallLevel, 4, "first four upgrades settled");

        _advanceTicks(3);
        uint32 csId = _firstCs(clanId);
        OrderResult[] memory fifth = _submitOrder(elder, clanId, csId, ActionType.UpgradeWall);
        assertEq(uint8(fifth[0].status), uint8(StatusCode.OK), "fifth status");
        _advanceTicks(world.getActionDuration(ActionType.UpgradeWall) + 1);
        assertEq(world.getClan(clanId).wallLevel, 5, "max wall level");

        _advanceTicks(3);
        OrderResult[] memory sixth = _submitOrder(elder, clanId, csId, ActionType.UpgradeWall);
        assertEq(uint8(sixth[0].status), uint8(StatusCode.ERR_INVALID_ACTION), "max level rejects");
        assertEq(world.getClan(clanId).wallLevel, 5, "wall remains max");
    }

    function test_upgradeWall_twoClansDoNotInterfere() public {
        uint32 clanA = _mintClan(elder);
        vm.prank(elder2);
        (uint32 clanB,) = world.mintClan(elder2);
        world.setVault(clanA, 100e18, 100e18, 100e18, 100e18);
        world.setVault(clanB, 100e18, 100e18, 100e18, 100e18);

        OrderResult[] memory result = _submitOrder(elder, clanA, _firstCs(clanA), ActionType.UpgradeWall);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "queue status");
        _advanceTicks(world.getActionDuration(ActionType.UpgradeWall) + 1);

        assertEq(world.getClan(clanA).wallLevel, 1, "clan A wall");
        assertEq(world.getClan(clanB).wallLevel, 0, "clan B wall");
    }
}
