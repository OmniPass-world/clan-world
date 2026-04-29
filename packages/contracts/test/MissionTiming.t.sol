// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {
    ClanWorldConstants,
    ActionType,
    ClansmanState,
    StatusCode,
    ClanFullView,
    Clansman,
    ClanOrder,
    OrderResult,
    Mission
} from "../src/IClanWorld.sol";

contract MissionTimingTest is Test {
    ClanWorld world;
    address elder = address(0xA1);

    function setUp() public {
        world = new ClanWorld();
    }

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }

    function _advanceUntilCurrentTick(uint64 targetTick) internal {
        while (world.getWorldState().currentTick < targetTick) {
            _advanceTick();
        }
    }

    function _mintClan() internal returns (uint32 clanId) {
        vm.prank(elder);
        (clanId,) = world.mintClan(elder);
    }

    function _firstCs(uint32 clanId) internal view returns (uint32) {
        ClanFullView memory view_ = world.getClanFullView(clanId);
        return view_.clansmen[0].clansman.clansman.clansmanId;
    }

    function _submitOrder(uint32 clanId, uint32 csId, uint8 gotoRegion, ActionType action)
        internal
        returns (OrderResult[] memory)
    {
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: gotoRegion,
            action: action,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
        vm.prank(elder);
        return world.submitClanOrders(clanId, orders);
    }

    function test_submitStoresSubmittedExecutesAndSettlesTicks() public {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);
        uint64 submittedAt = world.getWorldState().currentTick;
        uint64 travel = world.getTravelTicks(ClanWorldConstants.REGION_FOREST, ClanWorldConstants.REGION_MOUNTAINS);
        uint64 duration = world.getActionDuration(ActionType.MineIron);

        OrderResult[] memory results =
            _submitOrder(clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);

        assertEq(uint8(results[0].status), uint8(StatusCode.OK), "order should be accepted");

        Mission memory mission = world.getActiveMission(csId);
        assertEq(mission.submittedAtTick, submittedAt, "submitted tick");
        assertEq(mission.executesAtTick, submittedAt + travel, "executes tick");
        assertEq(mission.settlesAtTick, submittedAt + travel + duration, "settles tick");

        assertEq(mission.startTick, mission.submittedAtTick, "legacy start tick mirrors submitted");
        assertEq(mission.actionStartTick, mission.executesAtTick, "legacy action start mirrors executes");

        (uint64 submitted, uint64 executes, uint64 settles) = world.getMissionTiming(clanId, csId);
        assertEq(submitted, mission.submittedAtTick, "getter submitted");
        assertEq(executes, mission.executesAtTick, "getter executes");
        assertEq(settles, mission.settlesAtTick, "getter settles");
    }

    function test_settlementWaitsUntilSettlesAtTickForGatherMission() public {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        OrderResult[] memory results =
            _submitOrder(clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);
        assertEq(uint8(results[0].status), uint8(StatusCode.OK), "order should be accepted");

        Mission memory mission = world.getActiveMission(csId);
        assertEq(mission.settlesAtTick, mission.executesAtTick + 4, "four tick action duration");

        _advanceUntilCurrentTick(mission.executesAtTick + 1);
        world.settleClan(clanId);

        Clansman memory arrived = world.getClansman(csId);
        assertEq(uint8(arrived.state), uint8(ClansmanState.ACTING), "arrived and action started");
        assertEq(arrived.currentRegion, ClanWorldConstants.REGION_MOUNTAINS, "arrived at target");
        assertEq(arrived.carryIron, 0, "no iron before settlesAtTick");
        assertTrue(world.getActiveMission(csId).active, "mission remains active before settlesAtTick");

        _advanceUntilCurrentTick(mission.settlesAtTick + 1);
        world.settleClan(clanId);

        Clansman memory settled = world.getClansman(csId);
        assertGt(settled.carryIron, 0, "iron granted at settlesAtTick");
        assertEq(uint8(settled.state), uint8(ClansmanState.WAITING), "mission completed");
        assertFalse(world.getActiveMission(csId).active, "mission inactive after settlement");
        assertGt(settled.cooldownEndsAtTs, block.timestamp, "cooldown starts on settlement");
    }

    function test_getActionDuration_eachActionType() public view {
        assertEq(world.getActionDuration(ActionType.None), 0, "none");
        assertEq(world.getActionDuration(ActionType.ChopWood), 4, "chop wood");
        assertEq(world.getActionDuration(ActionType.MineIron), 4, "mine iron");
        assertEq(world.getActionDuration(ActionType.FishDocks), 4, "fish docks");
        assertEq(world.getActionDuration(ActionType.FishDeepSea), 4, "fish deep sea");
        assertEq(world.getActionDuration(ActionType.HarvestWheat), 4, "harvest wheat");
        assertEq(world.getActionDuration(ActionType.DepositResources), 1, "deposit");
        assertEq(world.getActionDuration(ActionType.BuildWall), 1, "build wall");
        assertEq(world.getActionDuration(ActionType.UpgradeBase), 1, "upgrade base");
        assertEq(world.getActionDuration(ActionType.UpgradeMonument), 1, "upgrade monument");
        assertEq(world.getActionDuration(ActionType.DefendBase), 0, "defend base");
        assertEq(world.getActionDuration(ActionType.MarketBuy), 1, "market buy");
        assertEq(world.getActionDuration(ActionType.MarketSell), 1, "market sell");
        assertEq(world.getActionDuration(ActionType.Wait), 0, "wait");
    }

    function test_getTravelTicks_adjacentAndDistantMatchTable() public view {
        assertEq(
            world.getTravelTicks(ClanWorldConstants.REGION_FOREST, ClanWorldConstants.REGION_MOUNTAINS), 1, "adjacent"
        );
        assertEq(
            world.getTravelTicks(ClanWorldConstants.REGION_FOREST, ClanWorldConstants.REGION_EAST_DOCKS), 4, "distant"
        );
        assertEq(
            world.getTravelTicks(ClanWorldConstants.REGION_FOREST, ClanWorldConstants.REGION_FOREST), 0, "same region"
        );
    }

    function test_missionOverwriteResetsSubmittedAtTick() public {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        OrderResult[] memory first = _submitOrder(clanId, csId, ClanWorldConstants.REGION_NOOP, ActionType.Wait);
        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first wait");
        uint64 firstSubmitted = world.getActiveMission(csId).submittedAtTick;

        _advanceTick();

        OrderResult[] memory second = _submitOrder(clanId, csId, ClanWorldConstants.REGION_NOOP, ActionType.Wait);
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "second wait");
        uint64 secondSubmitted = world.getActiveMission(csId).submittedAtTick;

        assertEq(firstSubmitted, 0, "first submit starts at tick 0");
        assertEq(secondSubmitted, world.getWorldState().currentTick, "second submit uses current tick");
        assertGt(secondSubmitted, firstSubmitted, "countdown restarts");
    }

    function test_getMissionTimingReturnsZerosForNonExistentMission() public view {
        (uint64 submitted, uint64 executes, uint64 settles) = world.getMissionTiming(123, 456);

        assertEq(submitted, 0, "submitted");
        assertEq(executes, 0, "executes");
        assertEq(settles, 0, "settles");
    }
}
