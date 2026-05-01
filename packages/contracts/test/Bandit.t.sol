// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {ActiveBanditView, ClanWorldConstants, BanditState, BanditTroop, WorldState} from "../src/IClanWorld.sol";

contract BanditHarness is ClanWorld {
    function spawnBandit(uint8 region, uint32 strength) external returns (uint32) {
        return _spawnBandit(region, strength);
    }

    function transitionBandit(uint32 id, BanditState newState) external {
        _transitionBanditState(id, newState);
    }

    function transitionBanditToAttacking(uint32 id, uint32 targetClanId) external {
        _transitionBanditToAttacking(id, targetClanId);
    }
}

contract BanditTest is Test {
    BanditHarness world;

    function setUp() public {
        world = new BanditHarness();
    }

    function _advanceTick() internal {
        vm.warp(world.getWorldState().nextHeartbeatAtTs);
        world.heartbeat();
    }

    function _advanceTicks(uint64 ticks) internal {
        for (uint64 i = 0; i < ticks; i++) {
            _advanceTick();
        }
    }

    function _spawnAndCamp() internal returns (uint32 id) {
        id = world.spawnBandit(ClanWorldConstants.REGION_FOREST, 100);
        _advanceTicks(2);
    }

    function _spawnCampAndAttack(uint32 targetClanId) internal returns (uint32 id) {
        id = _spawnAndCamp();
        _advanceTicks(ClanWorldConstants.BANDIT_CAMP_TICKS - 1);
        world.transitionBanditToAttacking(id, targetClanId);
    }

    function test_spawnBandit_recordsSpawnedTroopAndRegionIndex() public {
        uint32 id = world.spawnBandit(ClanWorldConstants.REGION_MOUNTAINS, 250);

        assertEq(id, 1, "first bandit id");
        BanditTroop memory bandit = world.getBandit(id);
        assertEq(bandit.id, id, "bandit id");
        assertEq(bandit.region, ClanWorldConstants.REGION_MOUNTAINS, "region");
        assertEq(uint8(bandit.state), uint8(BanditState.Spawned), "state");
        assertEq(bandit.targetClanId, 0, "no target while spawned");
        assertEq(bandit.tickEnteredState, world.getWorldState().currentTick, "entered tick");
        assertEq(bandit.strength, 250, "strength");
        assertEq(bandit.tier, 0, "custom strength has no v4 tier");
        assertEq(bandit.attackAttemptsMade, 0, "no attacks yet");

        uint32[] memory regionBandits = world.getBanditsInRegion(ClanWorldConstants.REGION_MOUNTAINS);
        assertEq(regionBandits.length, 1, "region index length");
        assertEq(regionBandits[0], id, "region index id");

        WorldState memory state = world.getWorldState();
        assertEq(state.activeBanditId, id, "active bandit");
    }

    function test_getBanditAbiDecodeIncludesTierAndAttackAttempts() public {
        uint32 id = world.spawnBandit(ClanWorldConstants.REGION_MOUNTAINS, 45);

        (bool getBanditOk, bytes memory getBanditData) =
            address(world).staticcall(abi.encodeWithSelector(world.getBandit.selector, id));
        assertTrue(getBanditOk, "getBandit call");
        BanditTroop memory bandit = abi.decode(getBanditData, (BanditTroop));
        assertEq(bandit.id, id, "getBandit id");
        assertEq(bandit.tier, 2, "getBandit tier");
        assertEq(bandit.attackAttemptsMade, 0, "getBandit attempts");

        (bool getTroopOk, bytes memory getTroopData) =
            address(world).staticcall(abi.encodeWithSignature("getBanditTroop(uint32)", id));
        assertTrue(getTroopOk, "getBanditTroop call");
        BanditTroop memory troop = abi.decode(getTroopData, (BanditTroop));
        assertEq(troop.id, id, "getBanditTroop id");
        assertEq(troop.tier, 2, "getBanditTroop tier");
        assertEq(troop.attackAttemptsMade, 0, "getBanditTroop attempts");
    }

    function test_getBanditMissingIdReturnsNoneState() public view {
        BanditTroop memory bandit = world.getBandit(999);

        assertEq(bandit.id, 0, "missing id");
        assertEq(uint8(bandit.state), uint8(BanditState.None), "missing state");
    }

    function test_defaultBanditTroopStateIsNone() public pure {
        BanditTroop memory bandit;

        assertEq(uint8(bandit.state), uint8(BanditState.None), "default state");
    }

    function test_spawnedToCampedTransitionAdvancesAfterSpawnDelay() public {
        uint32 id = world.spawnBandit(ClanWorldConstants.REGION_FOREST, 100);

        _advanceTicks(2);

        BanditTroop memory bandit = world.getBandit(id);
        assertEq(uint8(bandit.state), uint8(BanditState.Camped), "state");
        assertEq(bandit.tickEnteredState, world.getWorldState().currentTick - 1, "entered camp tick");
    }

    function test_spawnedActiveBanditViewReportsNextActionTick() public {
        uint32 id = world.spawnBandit(ClanWorldConstants.REGION_FOREST, 100);

        ActiveBanditView memory view_ = world.getActiveBanditView();

        assertEq(view_.banditId, id, "active bandit");
        assertEq(uint8(view_.state), uint8(BanditState.Spawned), "state");
        assertEq(view_.nextActionTick, world.getWorldState().currentTick + 1, "spawn delay tick");
    }

    function test_campedToAttackingTransitionSucceedsWithTargetAfterCampDuration() public {
        uint32 id = _spawnAndCamp();
        _advanceTicks(ClanWorldConstants.BANDIT_CAMP_TICKS - 1);

        world.transitionBanditToAttacking(id, 77);

        BanditTroop memory bandit = world.getBandit(id);
        assertEq(uint8(bandit.state), uint8(BanditState.Attacking), "state");
        assertEq(bandit.targetClanId, 77, "target");
        assertEq(bandit.tickEnteredState, world.getWorldState().currentTick, "entered attack tick");
    }

    function test_attackingToDefeatedDeletesBanditAndRegionIndex() public {
        uint32 id = _spawnCampAndAttack(77);

        world.transitionBandit(id, BanditState.Defeated);

        BanditTroop memory deletedBandit = world.getBandit(id);
        assertEq(deletedBandit.id, 0, "deleted id");
        assertEq(deletedBandit.region, 0, "deleted region");
        assertEq(uint8(deletedBandit.state), uint8(BanditState.None), "deleted state");
        assertEq(world.getBanditsInRegion(ClanWorldConstants.REGION_FOREST).length, 0, "removed from region");
        assertEq(world.getWorldState().activeBanditId, 0, "active bandit cleared");
    }

    function test_defeatingActiveBanditPromotesOldestRemainingBandit() public {
        uint32 id1 = world.spawnBandit(ClanWorldConstants.REGION_FOREST, 100);
        uint32 id2 = world.spawnBandit(ClanWorldConstants.REGION_MOUNTAINS, 200);
        uint32 id3 = world.spawnBandit(ClanWorldConstants.REGION_WEST_FARMS, 300);

        _advanceTicks(2);
        _advanceTicks(ClanWorldConstants.BANDIT_CAMP_TICKS - 1);
        world.transitionBanditToAttacking(id1, 77);
        world.transitionBandit(id1, BanditState.Defeated);

        assertEq(world.getWorldState().activeBanditId, id2, "oldest remaining promoted");
        assertEq(world.getBandit(id3).id, id3, "newer bandit remains live");
    }

    function test_attackingToEscapedRestingCampedCycleWorks() public {
        uint32 id = _spawnCampAndAttack(77);

        world.transitionBandit(id, BanditState.Escaped);
        BanditTroop memory escaped = world.getBandit(id);
        assertEq(uint8(escaped.state), uint8(BanditState.Escaped), "escaped");
        assertEq(escaped.targetClanId, 0, "target cleared on escape");

        world.transitionBandit(id, BanditState.Resting);
        BanditTroop memory resting = world.getBandit(id);
        assertEq(uint8(resting.state), uint8(BanditState.Resting), "resting");
        assertEq(resting.tickEnteredState, world.getWorldState().currentTick, "resting tick");

        _advanceTicks(ClanWorldConstants.BANDIT_REST_TICKS + 1);

        BanditTroop memory camped = world.getBandit(id);
        assertEq(uint8(camped.state), uint8(BanditState.Camped), "camped again");
        assertEq(camped.targetClanId, 0, "target remains clear");
        assertEq(camped.region, ClanWorldConstants.REGION_MOUNTAINS, "rampaged to next region");
        assertEq(world.getBanditsInRegion(ClanWorldConstants.REGION_FOREST).length, 0, "left forest index");
        assertEq(world.getBanditsInRegion(ClanWorldConstants.REGION_MOUNTAINS)[0], id, "entered mountain index");
    }

    function test_restingToCampedFollowsRampagePath() public {
        uint32 id = _spawnCampAndAttack(77);
        world.transitionBandit(id, BanditState.Escaped);
        world.transitionBandit(id, BanditState.Resting);

        _advanceTicks(ClanWorldConstants.BANDIT_REST_TICKS + 1);
        assertEq(world.getBandit(id).region, ClanWorldConstants.REGION_MOUNTAINS, "forest to mountains");

        world.transitionBandit(id, BanditState.Resting);
        _advanceTicks(ClanWorldConstants.BANDIT_REST_TICKS + 1);
        assertEq(world.getBandit(id).region, ClanWorldConstants.REGION_EAST_FARMS, "mountains to east farms");
    }

    function test_invalidTransitionsRevert() public {
        uint32 id = world.spawnBandit(ClanWorldConstants.REGION_FOREST, 100);

        vm.expectRevert("ClanWorld: invalid bandit transition");
        world.transitionBandit(id, BanditState.Defeated);

        _advanceTicks(2);
        _advanceTicks(ClanWorldConstants.BANDIT_CAMP_TICKS - 1);

        vm.expectRevert("ClanWorld: invalid bandit transition");
        world.transitionBandit(id, BanditState.Attacking);

        vm.expectRevert("ClanWorld: invalid bandit transition");
        world.transitionBandit(id, BanditState.None);
    }

    function test_getBanditsInRegionReturnsListAndUpdatesAfterDelete() public {
        uint32 id1 = world.spawnBandit(ClanWorldConstants.REGION_FOREST, 100);
        uint32 id2 = world.spawnBandit(ClanWorldConstants.REGION_FOREST, 200);
        uint32 id3 = world.spawnBandit(ClanWorldConstants.REGION_MOUNTAINS, 300);

        uint32[] memory forestBandits = world.getBanditsInRegion(ClanWorldConstants.REGION_FOREST);
        assertEq(forestBandits.length, 2, "forest count");
        assertEq(forestBandits[0], id1, "first forest bandit");
        assertEq(forestBandits[1], id2, "second forest bandit");

        uint32[] memory mountainBandits = world.getBanditsInRegion(ClanWorldConstants.REGION_MOUNTAINS);
        assertEq(mountainBandits.length, 1, "mountain count");
        assertEq(mountainBandits[0], id3, "mountain bandit");

        _advanceTicks(2);
        _advanceTicks(ClanWorldConstants.BANDIT_CAMP_TICKS - 1);
        world.transitionBanditToAttacking(id1, 77);
        world.transitionBandit(id1, BanditState.Defeated);

        forestBandits = world.getBanditsInRegion(ClanWorldConstants.REGION_FOREST);
        assertEq(forestBandits.length, 1, "forest count after delete");
        assertEq(forestBandits[0], id2, "remaining forest bandit");
    }
}
