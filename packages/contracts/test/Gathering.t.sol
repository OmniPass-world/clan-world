// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {
    ClanWorldConstants,
    ActionType,
    ClansmanState,
    StatusCode,
    Clansman,
    Mission,
    ClanFullView,
    ClanOrder,
    OrderResult
} from "../src/IClanWorld.sol";

contract GatheringHarness is ClanWorld {
    function setCarryWood(uint32 csId, uint256 wood) external {
        _clansmen[csId].carryWood = wood;
    }

    function setVaultFood(uint32 clanId, uint256 wheat, uint256 fish) external {
        _clans[clanId].vaultWheat = wheat;
        _clans[clanId].vaultFish = fish;
    }
}

contract GatheringTest is Test {
    GatheringHarness world;
    address elder = address(0xA1);

    function setUp() public {
        world = new GatheringHarness();
    }

    function _advanceTick() internal {
        vm.warp(world.getWorldState().nextHeartbeatAtTs);
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

    function _submitChopWood(uint32 clanId, uint32 csId) internal returns (OrderResult[] memory) {
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: ClanWorldConstants.REGION_FOREST,
            action: ActionType.ChopWood,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });

        vm.prank(elder);
        return world.submitClanOrders(clanId, orders);
    }

    function _settleChopWood(uint32 clanId, uint32 csId) internal returns (Clansman memory) {
        OrderResult[] memory result = _submitChopWood(clanId, csId);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "chop wood accepted");

        Mission memory mission = world.getActiveMission(csId);
        _advanceUntilCurrentTick(mission.settlesAtTick + 1);
        world.settleClan(clanId);
        return world.getClansman(csId);
    }

    function test_chopWoodAtForestYieldsBaseTimesActionDuration() public {
        vm.prevrandao(bytes32(uint256(2)));
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        Clansman memory cs = _settleChopWood(clanId, csId);

        uint256 expected = ClanWorldConstants.WOOD_YIELD_PER_TICK * world.getActionDuration(ActionType.ChopWood);
        assertEq(cs.carryWood, expected, "base wood yield");
    }

    function test_chopWoodCritDistributionAcrossSeeds() public {
        uint256 baseYield = ClanWorldConstants.WOOD_YIELD_PER_TICK * world.getActionDuration(ActionType.ChopWood);
        uint256 critCount = 0;
        world = new GatheringHarness();
        uint256 cleanState = vm.snapshotState();

        for (uint256 i = 0; i < 100; i++) {
            assertTrue(vm.revertToState(cleanState), "reset gathering world");
            vm.prevrandao(bytes32(uint256(i + 10_000)));
            uint32 clanId = _mintClan();
            uint32 csId = _firstCs(clanId);

            Clansman memory cs = _settleChopWood(clanId, csId);
            if (cs.carryWood == baseYield * 2) {
                critCount++;
            } else {
                assertEq(cs.carryWood, baseYield, "non-crit yield");
            }
        }

        assertGe(critCount, 3, "crit count too low");
        assertLe(critCount, 20, "crit count too high");
    }

    function test_chopWoodClampsToCarryCap() public {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);
        world.setCarryWood(csId, ClanWorldConstants.WOOD_CAP - 1e18);

        Clansman memory cs = _settleChopWood(clanId, csId);

        assertEq(cs.carryWood, ClanWorldConstants.WOOD_CAP, "wood carry cap");
    }

    function test_starvationBeginsOnNextTickAfterUpkeepFailure() public {
        uint32 clanId = _mintClan();
        uint64 failureTick = world.getWorldState().currentTick;
        world.setVaultFood(clanId, 0, 0);

        _advanceTick();
        world.settleClan(clanId);

        ClanFullView memory failed = world.getClanFullView(clanId);
        assertEq(failed.clan.clan.starvationStartsAtTick, failureTick + 1, "starvation starts next tick");
        assertTrue(failed.clan.isStarving, "starving once next tick is current");

        _advanceTick();

        ClanFullView memory nextTick = world.getClanFullView(clanId);
        assertTrue(nextTick.clan.isStarving, "starvation remains active without food");
    }

    function test_chopWoodAppliesCooldownPostSettle() public {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        Clansman memory cs = _settleChopWood(clanId, csId);

        assertEq(uint8(cs.state), uint8(ClansmanState.WAITING), "mission completed");
        assertFalse(world.getActiveMission(csId).active, "mission inactive");
        assertGt(cs.cooldownEndsAtTs, block.timestamp, "cooldown starts on settlement");
    }

    // -------------------------------------------------------------------------
    // Per-tick yield parity tests (H2): confirm per-tick constants × duration
    // produce the same per-call totals as the old flat yields.
    // -------------------------------------------------------------------------

    function _submitOrder(uint32 clanId, uint32 csId, uint8 region, ActionType action)
        internal
        returns (OrderResult[] memory)
    {
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: region,
            action: action,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
        vm.prank(elder);
        return world.submitClanOrders(clanId, orders);
    }

    function _settleOrder(uint32 clanId, uint32 csId, uint8 region, ActionType action)
        internal
        returns (Clansman memory)
    {
        OrderResult[] memory result = _submitOrder(clanId, csId, region, action);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "order accepted");
        Mission memory mission = world.getActiveMission(csId);
        _advanceUntilCurrentTick(mission.settlesAtTick + 1);
        world.settleClan(clanId);
        return world.getClansman(csId);
    }

    // Iron: IRON_YIELD_PER_TICK * duration = IRON_BASE_YIELD = 5e17
    function test_mineIronYieldsIronBaseYield() public {
        // Use prevrandao that avoids gold-bonus path (or just check carryIron)
        vm.prevrandao(bytes32(uint256(1)));
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        Clansman memory cs = _settleOrder(clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);

        uint256 expectedYield =
            ClanWorldConstants.IRON_YIELD_PER_TICK * uint256(world.getActionDuration(ActionType.MineIron));
        assertEq(expectedYield, ClanWorldConstants.IRON_BASE_YIELD, "constant parity: per-tick*duration == base");
        assertEq(cs.carryIron, expectedYield, "iron yield equals IRON_BASE_YIELD");
    }

    // Fish (docks): when roll succeeds, yield = FISH_YIELD_PER_TICK * duration = 1e18
    function test_fishDocksYieldsOneEther_onSuccessfulRoll() public {
        // prevrandao 1 → fishRoll = keccak256("fish_roll",...) % 10000 < 2500 (25%)
        // Try multiple seeds until we get a hit
        uint256 cleanState = vm.snapshotState();
        bool hit = false;
        for (uint256 seed = 1; seed < 100; seed++) {
            vm.revertToState(cleanState);
            vm.prevrandao(bytes32(seed));
            uint32 clanId = _mintClan();
            uint32 csId = _firstCs(clanId);
            Clansman memory cs =
                _settleOrder(clanId, csId, ClanWorldConstants.REGION_WEST_DOCKS, ActionType.FishDocks);
            if (cs.carryFish > 0) {
                uint256 expectedYield =
                    ClanWorldConstants.FISH_YIELD_PER_TICK * uint256(world.getActionDuration(ActionType.FishDocks));
                assertEq(expectedYield, 1e18, "constant parity: per-tick*duration == 1e18");
                assertEq(cs.carryFish, expectedYield, "fish docks yield equals 1e18 on success");
                hit = true;
                break;
            }
        }
        assertTrue(hit, "did not get a fish roll hit in 100 seeds");
    }
}
