// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {BanditState, BanditTroop, ClanWorldConstants, WorldState} from "../src/IClanWorld.sol";

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

    function banditSpawnRoll(bytes32 tickSeed, uint8 region) external pure returns (uint256) {
        return _banditSpawnRoll(tickSeed, region);
    }
}

contract BanditSpawnTest is Test {
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

    function _missSeed(uint8 region, uint16 probability) internal view returns (bytes32) {
        for (uint256 i = 0; i < 256; i++) {
            bytes32 seed = keccak256(abi.encodePacked("miss", i));
            if (world.banditSpawnRoll(seed, region) >= probability) {
                return seed;
            }
        }
        revert("missing miss seed");
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
