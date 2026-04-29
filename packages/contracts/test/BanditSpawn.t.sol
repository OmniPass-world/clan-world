// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {
    ActionType,
    BanditState,
    BanditTroop,
    Clan,
    ClanOrder,
    ClanWorldConstants,
    ClansmanState,
    Mission,
    OrderResult,
    StatusCode,
    WorldState
} from "../src/IClanWorld.sol";

contract BanditSpawnHarness is ClanWorld {
    function spawnBandit(uint8 region, uint32 strength) external returns (uint32) {
        return _spawnBandit(region, strength);
    }

    function evaluateBanditSpawns(bytes32 tickSeed) external {
        _evaluateBanditSpawns(tickSeed);
    }

    function setBanditSpawnState(uint8 region, uint64 lastSpawnTick, uint16 probabilityAccum) external {
        _banditSpawnByRegion[region].lastSpawnTick = lastSpawnTick;
        _banditSpawnByRegion[region].probabilityAccum = probabilityAccum;
    }

    function getBanditSpawnState(uint8 region) external view returns (uint64 lastSpawnTick, uint16 probabilityAccum) {
        lastSpawnTick = _banditSpawnByRegion[region].lastSpawnTick;
        probabilityAccum = _banditSpawnByRegion[region].probabilityAccum;
    }

    function activeBanditCount() external view returns (uint32) {
        return _activeBanditCount;
    }

    function minSpawnCooldownTicks() external pure returns (uint64) {
        return MIN_SPAWN_COOLDOWN_TICKS;
    }

    function spawnProbabilityIncrementBps() external pure returns (uint16) {
        return BANDIT_SPAWN_PROBABILITY_INCREMENT_BPS;
    }

    function maxBanditsPerRegion() external pure returns (uint8) {
        return MAX_BANDITS_PER_REGION;
    }

    function maxTotalBandits() external pure returns (uint8) {
        return MAX_TOTAL_BANDITS;
    }

    function maxBanditSpawnScanPerRegion() external pure returns (uint256) {
        return MAX_BANDIT_SPAWN_SCAN_PER_REGION;
    }

    function maxBanditEagerSettleBaseScanPerRegion() external pure returns (uint256) {
        return MAX_BANDIT_EAGER_SETTLE_BASE_SCAN_PER_REGION;
    }

    function banditSpawnRoll(bytes32 tickSeed, uint8 region) external pure returns (uint256) {
        return _banditSpawnRoll(tickSeed, region);
    }
}

contract BanditSpawnTest is Test {
    event ClanSettled(uint32 indexed clanId, uint64 settledToTick);
    event BanditSpawned(uint32 indexed banditId, uint8 region, uint8 tier, uint16 attackPower);

    BanditSpawnHarness world;

    function setUp() public {
        world = new BanditSpawnHarness();
    }

    function _advanceTick(BanditSpawnHarness target) internal {
        vm.warp(target.getWorldState().nextHeartbeatAtTs);
        target.heartbeat();
    }

    function _advanceTicks(BanditSpawnHarness target, uint64 ticks) internal {
        for (uint64 i = 0; i < ticks; i++) {
            _advanceTick(target);
        }
    }

    function _advancePastInitialCooldown(BanditSpawnHarness target) internal {
        _advanceTicks(target, target.minSpawnCooldownTicks());
    }

    function _mintForestClan(BanditSpawnHarness target) internal {
        target.mintClan(address(this));
    }

    function _mintUntilTwoForestClans(BanditSpawnHarness target) internal returns (uint32 first, uint32 second) {
        for (uint256 i = 0; i < target.maxBanditEagerSettleBaseScanPerRegion(); i++) {
            (uint32 clanId,) = target.mintClan(address(this));
            if (target.getClan(clanId).baseRegion == ClanWorldConstants.REGION_FOREST) {
                if (first == 0) {
                    first = clanId;
                } else {
                    second = clanId;
                    return (first, second);
                }
            }
        }
        revert("missing second forest clan");
    }

    function _csId(BanditSpawnHarness target, uint32 clanId, uint256 index) internal view returns (uint32) {
        return target.getClanFullView(clanId).clansmen[index].clansman.clansman.clansmanId;
    }

    function _ordersForPendingWorkerAndDefender(uint32 workerId, uint32 defenderId, uint8 baseRegion)
        internal
        pure
        returns (ClanOrder[] memory orders)
    {
        orders = new ClanOrder[](2);
        orders[0] = ClanOrder({
            clansmanId: workerId,
            gotoRegion: ClanWorldConstants.REGION_FOREST,
            action: ActionType.ChopWood,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
        orders[1] = ClanOrder({
            clansmanId: defenderId,
            gotoRegion: baseRegion,
            action: ActionType.DefendBase,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
    }

    function _submitPendingWorkerAndDefender(BanditSpawnHarness target, uint32 clanId)
        internal
        returns (uint32 workerId, uint32 defenderId)
    {
        Clan memory clan = target.getClan(clanId);
        workerId = _csId(target, clanId, 0);
        defenderId = _csId(target, clanId, 1);

        OrderResult[] memory results =
            target.submitClanOrders(clanId, _ordersForPendingWorkerAndDefender(workerId, defenderId, clan.baseRegion));
        assertEq(uint8(results[0].status), uint8(StatusCode.OK), "worker order accepted");
        assertEq(uint8(results[1].status), uint8(StatusCode.OK), "defender order accepted");
    }

    function _blockNonForestSpawnRegions(BanditSpawnHarness target) internal {
        uint64 currentTick = target.getWorldState().currentTick;
        for (uint8 region = ClanWorldConstants.REGION_FOREST; region <= ClanWorldConstants.REGION_DEEP_SEA; region++) {
            if (region != ClanWorldConstants.REGION_FOREST) {
                target.setBanditSpawnState(region, currentTick, 0);
            }
        }
    }

    function _prevrandaoForNextForestSpawn(BanditSpawnHarness target) internal view returns (bytes32) {
        WorldState memory state = target.getWorldState();
        for (uint256 i = 1; i < 256; i++) {
            bytes32 nextRandao = keccak256(abi.encodePacked("forest-spawn-randao", i));
            bytes32 nextSeed = keccak256(abi.encode(nextRandao, state.currentTickSeed, state.currentTick));
            if (target.banditSpawnRoll(nextSeed, ClanWorldConstants.REGION_FOREST) < 8000) {
                return nextRandao;
            }
        }
        revert("missing forest spawn randao");
    }

    function _missSeed(uint8 region, uint16 probability) internal view returns (bytes32) {
        for (uint256 i = 0; i < 256; i++) {
            bytes32 seed = keccak256(abi.encodePacked("miss", i));
            if (world.banditSpawnRoll(seed, region) >= probability) {
                return seed;
            }
        }
        revert("missing miss seed");
    }

    function _hitBothSeed(uint8 firstRegion, uint8 secondRegion, uint16 probability) internal view returns (bytes32) {
        for (uint256 i = 0; i < 256; i++) {
            bytes32 seed = keccak256(abi.encodePacked("hit-both", i));
            if (
                world.banditSpawnRoll(seed, firstRegion) < probability
                    && world.banditSpawnRoll(seed, secondRegion) < probability
            ) {
                return seed;
            }
        }
        revert("missing hit seed");
    }

    function test_cooldownEnforcedAfterSpawn() public {
        _mintForestClan(world);
        world.spawnBandit(ClanWorldConstants.REGION_FOREST, 100);

        _advanceTicks(world, world.minSpawnCooldownTicks() - 1);

        assertEq(world.getBanditsInRegion(ClanWorldConstants.REGION_FOREST).length, 1, "cooldown blocks second spawn");
        (, uint16 probabilityAccum) = world.getBanditSpawnState(ClanWorldConstants.REGION_FOREST);
        assertEq(probabilityAccum, 0, "cooldown does not accumulate chance");
    }

    function test_probabilityRisesAfterCooldown() public {
        _advancePastInitialCooldown(world);
        _mintForestClan(world);

        uint16 increment = world.spawnProbabilityIncrementBps();
        world.evaluateBanditSpawns(_missSeed(ClanWorldConstants.REGION_FOREST, increment));

        (, uint16 probabilityAccum) = world.getBanditSpawnState(ClanWorldConstants.REGION_FOREST);
        assertEq(probabilityAccum, increment, "first eligible tick increments accumulator");
    }

    function test_spawnResetsOnlySelectedRegionAccumulator() public {
        _advancePastInitialCooldown(world);
        world.mintClan(address(0xF0));
        world.mintClan(address(0xB0));

        uint16 oneStepBelowCap = 7000;
        world.setBanditSpawnState(ClanWorldConstants.REGION_FOREST, 0, oneStepBelowCap);
        world.setBanditSpawnState(ClanWorldConstants.REGION_MOUNTAINS, 0, oneStepBelowCap);

        world.evaluateBanditSpawns(
            _hitBothSeed(ClanWorldConstants.REGION_FOREST, ClanWorldConstants.REGION_MOUNTAINS, 8000)
        );

        uint8 selectedRegion = world.getBandit(1).region;
        uint8 otherRegion = selectedRegion == ClanWorldConstants.REGION_FOREST
            ? ClanWorldConstants.REGION_MOUNTAINS
            : ClanWorldConstants.REGION_FOREST;
        (, uint16 selectedAccum) = world.getBanditSpawnState(selectedRegion);
        (, uint16 otherAccum) = world.getBanditSpawnState(otherRegion);

        assertEq(selectedAccum, 0, "selected region reset");
        assertEq(otherAccum, 8000, "unselected candidate retained accum");
    }

    function test_perRegionCapEnforced() public {
        _advancePastInitialCooldown(world);
        _mintForestClan(world);

        uint8 maxPerRegion = world.maxBanditsPerRegion();
        for (uint8 i = 0; i < maxPerRegion; i++) {
            world.spawnBandit(ClanWorldConstants.REGION_FOREST, 100 + i);
        }
        world.setBanditSpawnState(ClanWorldConstants.REGION_FOREST, 0, 10000);

        world.evaluateBanditSpawns(keccak256("per-region-cap"));

        assertEq(world.getBanditsInRegion(ClanWorldConstants.REGION_FOREST).length, maxPerRegion, "region cap");
    }

    function test_globalCapEnforced() public {
        _advancePastInitialCooldown(world);
        _mintForestClan(world);

        uint8 maxTotal = world.maxTotalBandits();
        for (uint8 i = 0; i < maxTotal; i++) {
            world.spawnBandit(ClanWorldConstants.REGION_FOREST, 100 + i);
        }
        world.setBanditSpawnState(ClanWorldConstants.REGION_FOREST, 0, 10000);

        world.evaluateBanditSpawns(keccak256("global-cap"));

        assertEq(world.activeBanditCount(), maxTotal, "global cap");
    }

    function test_globalCapRefreshesPreviewOnHeartbeat() public {
        _mintForestClan(world);

        uint8 maxTotal = world.maxTotalBandits();
        for (uint8 i = 0; i < maxTotal; i++) {
            world.spawnBandit(uint8(ClanWorldConstants.REGION_FOREST + (i % 8)), 100 + i);
        }
        world.setBanditSpawnState(ClanWorldConstants.REGION_FOREST, 0, 4321);

        _advanceTick(world);

        WorldState memory state = world.getWorldState();
        assertEq(world.activeBanditCount(), maxTotal, "still at cap");
        assertEq(state.nextBanditSpawnEligibleTick, 0, "no eligible tick while capped");
        assertEq(state.currentBanditSpawnChanceBps, 4321, "preview chance refreshed");
    }

    function test_heartbeatCompletesWhenClanCountExceedsBanditSpawnScanCap() public {
        uint256 clanCount = world.maxBanditSpawnScanPerRegion() + 1;
        uint160 ownerId = 1;
        for (uint256 i = 0; i < clanCount; i++) {
            world.mintClan(address(ownerId));
            ownerId += 1;
        }

        _advanceTick(world);

        assertEq(world.getWorldState().currentTick, 1, "heartbeat advanced");
    }

    function test_heartbeatEagerSettlesCandidateRegionBasesAndDefendersBeforeBanditSpawn() public {
        _advancePastInitialCooldown(world);
        (uint32 clanId1, uint32 clanId2) = _mintUntilTwoForestClans(world);

        (uint32 workerId1, uint32 defenderId1) = _submitPendingWorkerAndDefender(world, clanId1);
        (uint32 workerId2, uint32 defenderId2) = _submitPendingWorkerAndDefender(world, clanId2);

        _blockNonForestSpawnRegions(world);
        world.setBanditSpawnState(ClanWorldConstants.REGION_FOREST, world.getWorldState().currentTick, 0);
        vm.prevrandao(_prevrandaoForNextForestSpawn(world));
        _advanceTick(world);

        uint64 closedTick = world.getWorldState().currentTick;
        assertEq(world.getClan(clanId1).lastSettledTick, closedTick - 1, "clan 1 setup: unsettled");
        assertEq(world.getClan(clanId2).lastSettledTick, closedTick - 1, "clan 2 setup: unsettled");
        assertTrue(world.getActiveMission(workerId1).active, "clan 1 worker has pending mission");
        assertTrue(world.getActiveMission(workerId2).active, "clan 2 worker has pending mission");
        assertEq(world.getActiveDefenders(clanId1)[0], defenderId1, "clan 1 defender registered");
        assertEq(world.getActiveDefenders(clanId2)[0], defenderId2, "clan 2 defender registered");

        _blockNonForestSpawnRegions(world);
        world.setBanditSpawnState(ClanWorldConstants.REGION_FOREST, 0, 10000);

        vm.expectEmit(true, false, false, true);
        emit ClanSettled(clanId1, closedTick);
        vm.expectEmit(true, false, false, true);
        emit ClanSettled(clanId2, closedTick);
        vm.expectEmit(true, false, false, false);
        emit BanditSpawned(1, 0, 0, 0);

        _advanceTick(world);

        assertEq(world.getClan(clanId1).lastSettledTick, closedTick, "clan 1 eager-settled");
        assertEq(world.getClan(clanId2).lastSettledTick, closedTick, "clan 2 eager-settled");

        Mission memory defenderMission1 = world.getActiveMission(defenderId1);
        Mission memory defenderMission2 = world.getActiveMission(defenderId2);
        assertTrue(defenderMission1.active, "clan 1 defender remains active");
        assertTrue(defenderMission2.active, "clan 2 defender remains active");
        assertEq(uint8(defenderMission1.action), uint8(ActionType.DefendBase), "clan 1 defender action");
        assertEq(uint8(defenderMission2.action), uint8(ActionType.DefendBase), "clan 2 defender action");
        assertEq(uint8(world.getClansman(defenderId1).state), uint8(ClansmanState.ACTING), "clan 1 defender settled");
        assertEq(uint8(world.getClansman(defenderId2).state), uint8(ClansmanState.ACTING), "clan 2 defender settled");

        BanditTroop memory bandit = world.getBandit(1);
        assertEq(uint8(bandit.state), uint8(BanditState.Spawned), "bandit spawned");
        assertEq(bandit.region, ClanWorldConstants.REGION_FOREST, "forest selected after eager settle");
        assertEq(bandit.tickEnteredState, closedTick, "spawn used closed tick");
    }

    function test_regionSelectionDeterministicForSameSeed() public {
        BanditSpawnHarness a = new BanditSpawnHarness();
        BanditSpawnHarness b = new BanditSpawnHarness();
        _advancePastInitialCooldown(a);
        _advancePastInitialCooldown(b);
        a.mintClan(address(0xA11CE));
        a.mintClan(address(0xB0B));
        b.mintClan(address(0xA11CE));
        b.mintClan(address(0xB0B));
        a.setBanditSpawnState(ClanWorldConstants.REGION_FOREST, 0, 10000);
        a.setBanditSpawnState(ClanWorldConstants.REGION_MOUNTAINS, 0, 10000);
        b.setBanditSpawnState(ClanWorldConstants.REGION_FOREST, 0, 10000);
        b.setBanditSpawnState(ClanWorldConstants.REGION_MOUNTAINS, 0, 10000);

        bytes32 seed = keccak256("deterministic-region");
        a.evaluateBanditSpawns(seed);
        b.evaluateBanditSpawns(seed);

        assertEq(a.getBandit(1).region, b.getBandit(1).region, "same seed selects same region");
    }

    function test_rngNoncePerRegionIsIndependent() public view {
        bytes32 seed = keccak256("region-nonce");

        uint256 forestRoll = world.banditSpawnRoll(seed, ClanWorldConstants.REGION_FOREST);
        uint256 mountainRoll = world.banditSpawnRoll(seed, ClanWorldConstants.REGION_MOUNTAINS);

        assertTrue(forestRoll != mountainRoll, "region nonce changes roll");
    }

    function test_spawnedBanditEntersStateMachine() public {
        _advancePastInitialCooldown(world);
        _mintForestClan(world);
        world.setBanditSpawnState(ClanWorldConstants.REGION_FOREST, 0, 10000);

        world.evaluateBanditSpawns(keccak256("spawn-state-machine"));

        BanditTroop memory bandit = world.getBandit(1);
        WorldState memory state = world.getWorldState();
        assertEq(uint8(bandit.state), uint8(BanditState.Spawned), "spawned state");
        assertEq(bandit.tickEnteredState, state.currentTick, "entered current tick");
        assertEq(state.activeBanditId, bandit.id, "active bandit set");
    }
}
