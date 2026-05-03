// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DiamondSelectors} from "../../script/DiamondSelectors.sol";
import {ClanWorld} from "../../src/ClanWorld.sol";
import {Diamond} from "../../src/diamond/Diamond.sol";
import {ClanWorldDiamondInit} from "../../src/diamond/ClanWorldDiamondInit.sol";
import {IDiamondCut} from "../../src/diamond/IDiamondCut.sol";
import {ClanLifecycleFacet} from "../../src/diamond/facets/ClanLifecycleFacet.sol";
import {DiamondCutFacet} from "../../src/diamond/facets/DiamondCutFacet.sol";
import {HeartbeatFacet} from "../../src/diamond/facets/HeartbeatFacet.sol";
import {RawClanViewsFacet} from "../../src/diamond/facets/RawClanViewsFacet.sol";
import {RawWorldViewsFacet} from "../../src/diamond/facets/RawWorldViewsFacet.sol";
import {LibStorage} from "../../src/diamond/lib/LibStorage.sol";
import {IClanWorld, ClanWorldConstants, WheatPlot, WheatPlotState, WorldState} from "../../src/IClanWorld.sol";

contract CoreWinterBoundaryHarness is ClanWorld {
    function disableBanditsForTest() external {
        _activeBanditCount = MAX_TOTAL_BANDITS;
    }

    function setCurrentTickForTest(uint64 tick) external {
        bytes32 tickSeed = bytes32(uint256(tick));
        _world.currentTick = tick;
        _world.nextHeartbeatAtTick = tick + 1;
        _world.nextHeartbeatAtTs = 0;
        _world.currentTickSeed = tickSeed;
    }

    function setClanLastSettledTickForTest(uint32 clanId, uint64 tick) external {
        _clans[clanId].lastSettledTick = tick;
    }
}

interface IWinterBoundaryHarness {
    function disableBanditsForTest() external;
    function setCurrentTickForTest(uint64 tick) external;
    function setClanLastSettledTickForTest(uint32 clanId, uint64 tick) external;
}

contract DiamondWinterBoundaryHarnessFacet {
    function disableBanditsForTest() external {
        LibStorage.appStorage().activeBanditCount = 1;
    }

    function setCurrentTickForTest(uint64 tick) external {
        LibStorage.AppStorage storage s = LibStorage.appStorage();
        bytes32 tickSeed = bytes32(uint256(tick));
        s.world.currentTick = tick;
        s.world.nextHeartbeatAtTick = tick + 1;
        s.world.nextHeartbeatAtTs = 0;
        s.world.currentTickSeed = tickSeed;
        s.tickSeeds[tick] = tickSeed;
    }

    function setClanLastSettledTickForTest(uint32 clanId, uint64 tick) external {
        LibStorage.appStorage().clans[clanId].lastSettledTick = tick;
    }
}

contract DiamondWinterBoundaryTest is Test {
    bytes32 private constant WINTER_STARTED_TOPIC = keccak256("WinterStarted(uint64)");
    bytes32 private constant WINTER_ENDED_TOPIC = keccak256("WinterEnded(uint64)");

    function testWinterStartLocksPlotsLikeCore() public {
        CoreWinterBoundaryHarness core = new CoreWinterBoundaryHarness();
        IClanWorld diamondWorld = _deployDiamondWorld();
        core.disableBanditsForTest();
        IWinterBoundaryHarness(address(diamondWorld)).disableBanditsForTest();

        address elder = address(0xA11CE);
        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = diamondWorld.mintClan(elder);
        assertEq(diamondClanId, coreClanId, "clan id");

        _advancePairToTick(core, diamondWorld, ClanWorldConstants.WINTER_START_TICK - 1);
        assertFalse(core.isWinter(), "core pre-winter");
        assertFalse(diamondWorld.isWinter(), "diamond pre-winter");

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);

        vm.recordLogs();
        core.heartbeat();
        assertEq(_countRecorded(WINTER_STARTED_TOPIC), 1, "core WinterStarted");

        vm.recordLogs();
        diamondWorld.heartbeat();
        assertEq(_countRecorded(WINTER_STARTED_TOPIC), 1, "diamond WinterStarted");

        assertTrue(core.isWinter(), "core winter");
        assertTrue(diamondWorld.isWinter(), "diamond winter");
        _assertWorldStateEq(diamondWorld.getWorldState(), core.getWorldState());

        (WheatPlot memory coreWest, WheatPlot memory coreEast) = core.getWheatPlots(coreClanId);
        (WheatPlot memory diamondWest, WheatPlot memory diamondEast) = diamondWorld.getWheatPlots(diamondClanId);
        _assertLockedPlotEq(diamondWest, coreWest, "west");
        _assertLockedPlotEq(diamondEast, coreEast, "east");
    }

    function testWinterEndRestartsPlotsLikeCore() public {
        CoreWinterBoundaryHarness core = new CoreWinterBoundaryHarness();
        IClanWorld diamondWorld = _deployDiamondWorld();
        core.disableBanditsForTest();
        IWinterBoundaryHarness(address(diamondWorld)).disableBanditsForTest();

        address elder = address(0xB0B);
        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = diamondWorld.mintClan(elder);

        uint64 winterEndTick = ClanWorldConstants.WINTER_START_TICK + ClanWorldConstants.WINTER_DURATION_TICKS;
        _advancePairToTick(core, diamondWorld, winterEndTick - 1);
        assertTrue(core.isWinter(), "core pre-exit winter");
        assertTrue(diamondWorld.isWinter(), "diamond pre-exit winter");

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);

        vm.recordLogs();
        core.heartbeat();
        assertEq(_countRecorded(WINTER_ENDED_TOPIC), 1, "core WinterEnded");

        vm.recordLogs();
        diamondWorld.heartbeat();
        assertEq(_countRecorded(WINTER_ENDED_TOPIC), 1, "diamond WinterEnded");

        assertFalse(core.isWinter(), "core after winter");
        assertFalse(diamondWorld.isWinter(), "diamond after winter");
        _assertWorldStateEq(diamondWorld.getWorldState(), core.getWorldState());

        (WheatPlot memory coreWest, WheatPlot memory coreEast) = core.getWheatPlots(coreClanId);
        (WheatPlot memory diamondWest, WheatPlot memory diamondEast) = diamondWorld.getWheatPlots(diamondClanId);
        _assertRegrowingPlotEq(diamondWest, coreWest, winterEndTick, "west");
        _assertRegrowingPlotEq(diamondEast, coreEast, winterEndTick, "east");
    }

    function testWinterStartHandlesMaxLiveClanCropTransitionsLikeCore() public {
        CoreWinterBoundaryHarness core = new CoreWinterBoundaryHarness();
        IClanWorld diamondWorld = _deployDiamondWorld();
        IWinterBoundaryHarness diamondHarness = IWinterBoundaryHarness(address(diamondWorld));
        uint32 clanCount = 12;
        uint64 preWinterTick = ClanWorldConstants.WINTER_START_TICK - 1;

        core.disableBanditsForTest();
        diamondHarness.disableBanditsForTest();
        for (uint32 clanId = 1; clanId <= clanCount; clanId++) {
            address elder = address(uint160(0xC000 + clanId));
            vm.prank(elder);
            (uint32 coreClanId,) = core.mintClan(elder);
            vm.prank(elder);
            (uint32 diamondClanId,) = diamondWorld.mintClan(elder);
            assertEq(coreClanId, clanId, "core clan id");
            assertEq(diamondClanId, clanId, "diamond clan id");
        }
        core.setCurrentTickForTest(preWinterTick);
        diamondHarness.setCurrentTickForTest(preWinterTick);
        for (uint32 clanId = 1; clanId <= clanCount; clanId++) {
            core.setClanLastSettledTickForTest(clanId, preWinterTick);
            diamondHarness.setClanLastSettledTickForTest(clanId, preWinterTick);
        }

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        diamondWorld.heartbeat();

        assertTrue(core.isWinter(), "core winter");
        assertTrue(diamondWorld.isWinter(), "diamond winter");
        _assertWorldStateEq(diamondWorld.getWorldState(), core.getWorldState());
        assertEq(diamondWorld.getClanIds().length, clanCount, "synthetic clan count");

        for (uint32 clanId = 1; clanId <= clanCount; clanId++) {
            (WheatPlot memory coreWest, WheatPlot memory coreEast) = core.getWheatPlots(clanId);
            (WheatPlot memory diamondWest, WheatPlot memory diamondEast) = diamondWorld.getWheatPlots(clanId);
            _assertLockedPlotEq(diamondWest, coreWest, "west");
            _assertLockedPlotEq(diamondEast, coreEast, "east");
        }
    }

    function _deployDiamondWorld() internal returns (IClanWorld diamondWorld) {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        Diamond diamond = new Diamond(address(this), address(cutFacet));
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](5);
        cut[0] = _facetCut(address(new RawWorldViewsFacet()), DiamondSelectors.rawWorldViewsSelectors());
        cut[1] = _facetCut(address(new RawClanViewsFacet()), DiamondSelectors.rawClanViewsSelectors());
        cut[2] = _facetCut(address(new ClanLifecycleFacet()), DiamondSelectors.lifecycleSelectors());
        cut[3] = _facetCut(address(new HeartbeatFacet()), DiamondSelectors.heartbeatSelectors());
        cut[4] = _facetCut(address(new DiamondWinterBoundaryHarnessFacet()), _harnessSelectors());

        IDiamondCut(address(diamond)).diamondCut(cut, address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        diamondWorld = IClanWorld(address(diamond));
    }

    function _facetCut(address facet, bytes4[] memory selectors) internal pure returns (IDiamondCut.FacetCut memory) {
        return IDiamondCut.FacetCut({
            facetAddress: facet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });
    }

    function _harnessSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = DiamondWinterBoundaryHarnessFacet.disableBanditsForTest.selector;
        selectors[1] = DiamondWinterBoundaryHarnessFacet.setCurrentTickForTest.selector;
        selectors[2] = DiamondWinterBoundaryHarnessFacet.setClanLastSettledTickForTest.selector;
    }

    function _advancePairToTick(CoreWinterBoundaryHarness core, IClanWorld diamondWorld, uint64 targetTick) internal {
        while (core.getWorldState().currentTick < targetTick) {
            vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
            core.heartbeat();
            diamondWorld.heartbeat();
        }
        assertEq(diamondWorld.getWorldState().currentTick, targetTick, "diamond target tick");
    }

    function _countRecorded(bytes32 topic) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) count++;
        }
    }

    function _assertLockedPlotEq(WheatPlot memory actual, WheatPlot memory expected, string memory label) internal pure {
        assertEq(uint8(actual.state), uint8(WheatPlotState.WinterLocked), string.concat(label, " locked"));
        assertEq(uint8(actual.state), uint8(expected.state), string.concat(label, " state"));
        assertEq(actual.region, expected.region, string.concat(label, " region"));
        assertEq(actual.remainingWheat, 0, string.concat(label, " wheat"));
        assertEq(actual.remainingWheat, expected.remainingWheat, string.concat(label, " wheat parity"));
        assertEq(actual.regrowUntilTick, 0, string.concat(label, " regrow"));
        assertEq(actual.regrowUntilTick, expected.regrowUntilTick, string.concat(label, " regrow parity"));
    }

    function _assertRegrowingPlotEq(
        WheatPlot memory actual,
        WheatPlot memory expected,
        uint64 winterEndTick,
        string memory label
    ) internal pure {
        assertEq(uint8(actual.state), uint8(WheatPlotState.Regrowing), string.concat(label, " regrowing"));
        assertEq(uint8(actual.state), uint8(expected.state), string.concat(label, " state"));
        assertEq(actual.region, expected.region, string.concat(label, " region"));
        assertEq(actual.remainingWheat, 0, string.concat(label, " wheat"));
        assertEq(actual.remainingWheat, expected.remainingWheat, string.concat(label, " wheat parity"));
        assertEq(
            actual.regrowUntilTick,
            winterEndTick + ClanWorldConstants.WHEAT_PLOT_REGROW_TICKS,
            string.concat(label, " regrow tick")
        );
        assertEq(actual.regrowUntilTick, expected.regrowUntilTick, string.concat(label, " regrow parity"));
    }

    function _assertWorldStateEq(WorldState memory actual, WorldState memory expected) internal pure {
        assertEq(actual.currentTick, expected.currentTick, "currentTick");
        assertEq(actual.seasonStartTick, expected.seasonStartTick, "seasonStartTick");
        assertEq(actual.seasonEndTick, expected.seasonEndTick, "seasonEndTick");
        assertEq(actual.seasonFinalized, expected.seasonFinalized, "seasonFinalized");
        assertEq(actual.currentSeasonNumber, expected.currentSeasonNumber, "currentSeasonNumber");
        assertEq(actual.nextHeartbeatAtTick, expected.nextHeartbeatAtTick, "nextHeartbeatAtTick");
        assertEq(actual.nextHeartbeatAtTs, expected.nextHeartbeatAtTs, "nextHeartbeatAtTs");
        assertEq(actual.nextBanditSpawnEligibleTick, expected.nextBanditSpawnEligibleTick, "banditEligible");
        assertEq(actual.currentBanditSpawnChanceBps, expected.currentBanditSpawnChanceBps, "banditChance");
        assertEq(actual.currentTickSeed, expected.currentTickSeed, "currentTickSeed");
        assertEq(actual.activeBanditId, expected.activeBanditId, "activeBanditId");
        assertEq(actual.winterActive, expected.winterActive, "winterActive");
        assertEq(actual.winterStartsAtTick, expected.winterStartsAtTick, "winterStartsAtTick");
        assertEq(actual.winterEndsAtTick, expected.winterEndsAtTick, "winterEndsAtTick");
        assertEq(actual.nextCommitSequence, expected.nextCommitSequence, "nextCommitSequence");
    }
}
