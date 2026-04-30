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

    function test_chopWoodAtForestYieldsBaseOrCritBonus() public {
        vm.prevrandao(bytes32(uint256(2)));
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        Clansman memory cs = _settleChopWood(clanId, csId);

        assertTrue(
            cs.carryWood == ClanWorldConstants.WOOD_BASE_YIELD
                || cs.carryWood == ClanWorldConstants.WOOD_BASE_YIELD + ClanWorldConstants.WOOD_CRIT_BONUS,
            "wood yield"
        );
    }

    function test_chopWoodCritDistributionAcrossSeeds() public {
        uint256 critCount = 0;
        world = new GatheringHarness();
        uint256 cleanState = vm.snapshotState();

        for (uint256 i = 0; i < 100; i++) {
            assertTrue(vm.revertToState(cleanState), "reset gathering world");
            vm.prevrandao(bytes32(uint256(i + 10_000)));
            uint32 clanId = _mintClan();
            uint32 csId = _firstCs(clanId);

            Clansman memory cs = _settleChopWood(clanId, csId);
            if (cs.carryWood == ClanWorldConstants.WOOD_BASE_YIELD + ClanWorldConstants.WOOD_CRIT_BONUS) {
                critCount++;
            } else {
                assertEq(cs.carryWood, ClanWorldConstants.WOOD_BASE_YIELD, "non-crit yield");
            }
        }

        assertGe(critCount, 10, "crit count too low");
        assertLe(critCount, 30, "crit count too high");
    }

    function test_chopWoodClampsToCarryCap() public {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);
        world.setCarryWood(csId, ClanWorldConstants.WOOD_CAP - 1e18);

        Clansman memory cs = _settleChopWood(clanId, csId);

        assertEq(cs.carryWood, ClanWorldConstants.WOOD_CAP, "wood carry cap");
    }

    function test_chopWoodReschedulesWhenCarryCapNotReached() public {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        OrderResult[] memory result = _submitChopWood(clanId, csId);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "chop wood accepted");

        Mission memory mission = world.getActiveMission(csId);
        _advanceUntilCurrentTick(mission.settlesAtTick + 1);
        world.settleClan(clanId);

        Clansman memory cs = world.getClansman(csId);
        assertEq(uint8(cs.state), uint8(ClansmanState.ACTING), "mission continues");
        assertTrue(world.getActiveMission(csId).active, "mission remains active");
        assertEq(
            world.getActiveMission(csId).settlesAtTick,
            mission.settlesAtTick + world.getActionDuration(ActionType.ChopWood),
            "next chop scheduled"
        );
    }

    function test_chopWoodAppliesCooldownWhenCarryCapReached() public {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);
        world.setCarryWood(csId, ClanWorldConstants.WOOD_CAP - 1e18);

        Clansman memory cs = _settleChopWood(clanId, csId);

        assertEq(uint8(cs.state), uint8(ClansmanState.WAITING), "mission completed");
        assertFalse(world.getActiveMission(csId).active, "mission inactive");
        assertGt(cs.cooldownEndsAtTs, block.timestamp, "cooldown starts on settlement");
    }
}
