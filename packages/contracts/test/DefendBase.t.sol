// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {
    ClanWorldConstants,
    ClansmanState,
    ActionType,
    StatusCode,
    Clan,
    Clansman,
    Mission,
    ClanOrder,
    OrderResult
} from "../src/IClanWorld.sol";

contract DefendBaseTest is Test {
    ClanWorld world;
    address elder = address(0xA1);

    function setUp() public {
        world = new ClanWorld();
    }

    function _mintClan() internal returns (uint32 clanId) {
        vm.prank(elder);
        (clanId,) = world.mintClan(elder);
    }

    function _firstCs(uint32 clanId) internal view returns (uint32) {
        return world.getClanFullView(clanId).clansmen[0].clansman.clansman.clansmanId;
    }

    function _defendOrder(uint32 csId, uint8 region, uint32 targetClanId) internal pure returns (ClanOrder[] memory) {
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: region,
            action: ActionType.DefendBase,
            targetClanId: targetClanId,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
        return orders;
    }

    function _waitOrder(uint32 csId, uint8 region) internal pure returns (ClanOrder[] memory) {
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: region,
            action: ActionType.Wait,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
        return orders;
    }

    function _submit(uint32 clanId, ClanOrder[] memory orders) internal returns (OrderResult[] memory) {
        vm.prank(elder);
        return world.submitClanOrders(clanId, orders);
    }

    function _warpCooldown() internal {
        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS);
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

    function _otherRegion(uint8 homeRegion) internal pure returns (uint8) {
        return homeRegion == ClanWorldConstants.REGION_FOREST
            ? ClanWorldConstants.REGION_MOUNTAINS
            : ClanWorldConstants.REGION_FOREST;
    }

    function _assertContains(uint32[] memory values, uint32 needle) internal pure {
        for (uint256 i = 0; i < values.length; i++) {
            if (values[i] == needle) return;
        }
        revert("missing expected clanId");
    }

    function test_submitDefendBaseAtHome_succeedsImmediatePersistent() public {
        uint32 clanId = _mintClan();
        Clan memory clan = world.getClan(clanId);
        uint32 csId = _firstCs(clanId);
        uint64 submittedAtTick = world.getWorldState().currentTick;

        OrderResult[] memory results = _submit(clanId, _defendOrder(csId, clan.baseRegion, 0));

        assertEq(uint8(results[0].status), uint8(StatusCode.OK), "defend_base status");
        assertEq(results[0].missionNonce, 1, "first nonce");

        Clansman memory cs = world.getClansman(csId);
        assertEq(uint8(cs.state), uint8(ClansmanState.ACTING), "defender acts immediately");
        assertEq(cs.currentRegion, clan.baseRegion, "defender is at home");

        Mission memory mission = world.getActiveMission(csId);
        assertTrue(mission.active, "mission stays active");
        assertEq(uint8(mission.action), uint8(ActionType.DefendBase), "mission action");
        assertEq(mission.targetClanId, clanId, "zero target normalizes to self");
        assertEq(mission.startTick, submittedAtTick, "start tick");
        assertEq(mission.arrivalTick, submittedAtTick, "arrival tick");
        assertEq(mission.actionStartTick, submittedAtTick, "action tick");

        uint32[] memory defenders = world.getDefendingClans(clan.baseRegion);
        assertEq(defenders.length, 1, "one defending clan");
        assertEq(defenders[0], clanId, "defending clan id");

        _warpCooldown();
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
        world.settleClan(clanId);

        assertTrue(world.getActiveMission(csId).active, "defend_base does not settle complete");
        assertEq(uint8(world.getClansman(csId).state), uint8(ClansmanState.ACTING), "still acting");
    }

    function test_submitDefendBaseFromNonHome_travelsBeforeRegisteringDefender() public {
        uint32 clanId = _mintClan();
        Clan memory clan = world.getClan(clanId);
        uint32 csId = _firstCs(clanId);
        uint8 awayRegion = _otherRegion(clan.baseRegion);

        OrderResult[] memory move = _submit(clanId, _waitOrder(csId, awayRegion));
        assertEq(uint8(move[0].status), uint8(StatusCode.OK), "move away accepted");

        Mission memory moveMission = world.getActiveMission(csId);
        _advanceUntilCurrentTick(moveMission.executesAtTick + 1);
        world.settleClan(clanId);
        assertEq(world.getClansman(csId).currentRegion, awayRegion, "test setup: clansman is away");

        _warpCooldown();
        OrderResult[] memory defend = _submit(clanId, _defendOrder(csId, clan.baseRegion, 0));

        assertEq(uint8(defend[0].status), uint8(StatusCode.OK), "defend accepted");

        Mission memory defendMission = world.getActiveMission(csId);
        uint64 expectedTravel = world.getTravelTicks(awayRegion, clan.baseRegion);
        assertEq(defendMission.executesAtTick, defendMission.submittedAtTick + expectedTravel, "normal travel");
        assertEq(uint8(world.getClansman(csId).state), uint8(ClansmanState.TRAVELING), "travels home first");
        assertEq(world.getDefendingClans(clan.baseRegion).length, 0, "not registered before arrival");
        assertEq(world.getActiveDefenders(clanId).length, 0, "no active defender before arrival");

        _advanceUntilCurrentTick(defendMission.executesAtTick + 1);
        world.settleClan(clanId);

        Clansman memory cs = world.getClansman(csId);
        assertEq(uint8(cs.state), uint8(ClansmanState.ACTING), "defender acts after arrival");
        assertEq(cs.currentRegion, clan.baseRegion, "defender arrived home");

        uint32[] memory defendingClans = world.getDefendingClans(clan.baseRegion);
        assertEq(defendingClans.length, 1, "registered after arrival");
        assertEq(defendingClans[0], clanId, "defending clan id");
        uint32[] memory activeDefenders = world.getActiveDefenders(clanId);
        assertEq(activeDefenders.length, 1, "active defender after arrival");
        assertEq(activeDefenders[0], csId, "active defender id");
    }

    function test_submitDefendBaseAtNonHome_failsInvalidRegion() public {
        uint32 clanId = _mintClan();
        Clan memory clan = world.getClan(clanId);
        uint32 csId = _firstCs(clanId);

        OrderResult[] memory results = _submit(clanId, _defendOrder(csId, _otherRegion(clan.baseRegion), 0));

        assertEq(uint8(results[0].status), uint8(StatusCode.ERR_INVALID_REGION), "non-home defend rejected");
        assertEq(world.getDefendingClans(clan.baseRegion).length, 0, "no defender registered");
    }

    function test_resubmitSameDefendBase_isNoopNonceUnchanged() public {
        uint32 clanId = _mintClan();
        Clan memory clan = world.getClan(clanId);
        uint32 csId = _firstCs(clanId);

        OrderResult[] memory first = _submit(clanId, _defendOrder(csId, clan.baseRegion, 0));
        uint64 cooldown = world.getClansman(csId).cooldownEndsAtTs;

        OrderResult[] memory second = _submit(clanId, _defendOrder(csId, clan.baseRegion, 0));

        assertEq(uint8(first[0].status), uint8(StatusCode.OK), "first status");
        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "same-target no-op status");
        assertEq(second[0].missionNonce, first[0].missionNonce, "nonce unchanged");
        assertEq(world.getClansman(csId).lastMissionNonce, first[0].missionNonce, "stored nonce unchanged");
        assertEq(world.getClansman(csId).cooldownEndsAtTs, cooldown, "cooldown unchanged");
        assertEq(world.getDefendingClans(clan.baseRegion).length, 1, "no duplicate defender");
    }

    function test_resubmitExplicitSelfAfterDefaultDefendBase_isNoopNonceUnchanged() public {
        uint32 clanId = _mintClan();
        Clan memory clan = world.getClan(clanId);
        uint32 csId = _firstCs(clanId);

        OrderResult[] memory first = _submit(clanId, _defendOrder(csId, clan.baseRegion, 0));
        OrderResult[] memory second = _submit(clanId, _defendOrder(csId, clan.baseRegion, clanId));

        assertEq(uint8(second[0].status), uint8(StatusCode.OK), "explicit self is same target");
        assertEq(second[0].missionNonce, first[0].missionNonce, "nonce unchanged");
        assertEq(world.getActiveMission(csId).targetClanId, clanId, "target normalized");
        uint32[] memory defenders = world.getDefendingClans(clan.baseRegion);
        assertEq(defenders.length, 1, "no duplicate defender");
        assertEq(defenders[0], clanId, "defender remains registered once");
    }

    function test_defendBaseZeroTargetAppearsInActiveDefenders() public {
        uint32 clanId = _mintClan();
        Clan memory clan = world.getClan(clanId);
        uint32 csId = _firstCs(clanId);

        OrderResult[] memory results = _submit(clanId, _defendOrder(csId, clan.baseRegion, 0));

        assertEq(uint8(results[0].status), uint8(StatusCode.OK), "defend accepted");
        assertEq(world.getActiveMission(csId).targetClanId, clanId, "stored target is self");

        uint32[] memory activeDefenders = world.getActiveDefenders(clanId);
        assertEq(activeDefenders.length, 1, "default self-defense is target visible");
        assertEq(activeDefenders[0], csId, "active defender id");
    }

    function test_getDefendingClans_returnsAllCurrentlyDefendingClans() public {
        uint32 firstClanId = _mintClan();
        uint8 sharedHome = world.getClan(firstClanId).baseRegion;
        uint32 seventhClanId;
        for (uint256 i = 0; i < 6; i++) {
            seventhClanId = _mintClan();
        }
        assertEq(world.getClan(seventhClanId).baseRegion, sharedHome, "test setup shared home");

        _submit(firstClanId, _defendOrder(_firstCs(firstClanId), sharedHome, 0));
        _submit(seventhClanId, _defendOrder(_firstCs(seventhClanId), sharedHome, 0));

        uint32[] memory defenders = world.getDefendingClans(sharedHome);
        assertEq(defenders.length, 2, "two defending clans");
        _assertContains(defenders, firstClanId);
        _assertContains(defenders, seventhClanId);
    }

    function test_getActiveDefenders_keepsTargetSpecificClansmanSemantics() public {
        uint32 firstClanId = _mintClan();
        uint8 sharedHome = world.getClan(firstClanId).baseRegion;
        uint32 seventhClanId;
        for (uint256 i = 0; i < 6; i++) {
            seventhClanId = _mintClan();
        }
        assertEq(world.getClan(seventhClanId).baseRegion, sharedHome, "test setup shared home");

        uint32 firstCsId = _firstCs(firstClanId);
        uint32 seventhCsId = _firstCs(seventhClanId);
        _submit(firstClanId, _defendOrder(firstCsId, sharedHome, firstClanId));
        _submit(seventhClanId, _defendOrder(seventhCsId, sharedHome, seventhClanId));

        uint32[] memory regionDefenders = world.getDefendingClans(sharedHome);
        assertEq(regionDefenders.length, 2, "region index includes both defending clans");

        uint32[] memory targetDefenders = world.getActiveDefenders(firstClanId);
        assertEq(targetDefenders.length, 1, "target-specific getter excludes same-region defenders");
        assertEq(targetDefenders[0], firstCsId, "returns target-specific clansman id");
    }

    function test_nonDefendBaseMissionOverwritesDefendBase_dropsDefenderIndex() public {
        uint32 clanId = _mintClan();
        Clan memory clan = world.getClan(clanId);
        uint32 csId = _firstCs(clanId);

        _submit(clanId, _defendOrder(csId, clan.baseRegion, 0));
        assertEq(world.getDefendingClans(clan.baseRegion).length, 1, "defender registered");

        _warpCooldown();
        OrderResult[] memory results = _submit(clanId, _waitOrder(csId, clan.baseRegion));

        assertEq(uint8(results[0].status), uint8(StatusCode.OK), "wait retask accepted");
        assertEq(world.getDefendingClans(clan.baseRegion).length, 0, "defender dropped");
        assertEq(uint8(world.getActiveMission(csId).action), uint8(ActionType.Wait), "mission overwritten");
    }
}
