// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {MinimalERC20} from "../src/MinimalERC20.sol";
import {StubPool} from "../src/StubPool.sol";
import {
    IClanWorld,
    IClanWorldEvents,
    ClanWorldConstants,
    ClanState,
    ClansmanState,
    BanditState,
    WheatPlotState,
    ResourceType,
    ActionType,
    MarketExecutionMode,
    StatusCode,
    WorldState,
    TreasuryState,
    Clan,
    WheatPlot,
    Clansman,
    Mission,
    BanditTroop,
    ScheduledMarketAction,
    DefenseContribution,
    PackedRoute,
    DerivedClanState,
    DerivedClansmanState,
    ClanOrder,
    OrderResult,
    PoolSeedConfig,
    LeaderboardEntry,
    WorldSnapshot,
    ClansmanFullView,
    ClanFullView,
    PoolReserves,
    MarketState,
    ActiveBanditView,
    RegionOccupant
} from "../src/IClanWorld.sol";

/// @dev Test harness that exposes internal state manipulation for unit tests.
contract ClanWorldTestHarness is ClanWorld {
    function killClansman(uint32 csId) external {
        _clansmen[csId].state = ClansmanState.DEAD;
    }

    function setCarry(uint32 csId, uint256 wood, uint256 iron, uint256 wheat, uint256 fish) external {
        _clansmen[csId].carryWood = wood;
        _clansmen[csId].carryIron = iron;
        _clansmen[csId].carryWheat = wheat;
        _clansmen[csId].carryFish = fish;
    }
}

contract ClanWorldTest is Test {
    ClanWorld world;
    address elder = address(0xA1);
    address elder2 = address(0xA2);

    // Phase 2 market infrastructure
    MinimalERC20 woodToken;
    MinimalERC20 ironToken;
    MinimalERC20 wheatToken;
    MinimalERC20 fishToken;
    MinimalERC20 goldToken;
    MinimalERC20 blueprintToken;
    StubPool woodPool;
    StubPool ironPool;
    StubPool wheatPool;
    StubPool fishPool;

    function setUp() public {
        world = new ClanWorld();
    }

    /// @dev Deploy tokens + pools, call initTreasury + seedPools. Returns wood token address.
    function _setupMarket() internal returns (address woodAddr) {
        woodToken = new MinimalERC20("Wood", "WOOD");
        ironToken = new MinimalERC20("Iron", "IRON");
        wheatToken = new MinimalERC20("Wheat", "WHEAT");
        fishToken = new MinimalERC20("Fish", "FISH");
        goldToken = new MinimalERC20("Gold", "GOLD");
        blueprintToken = new MinimalERC20("BPRT", "BPRT");

        address wAddr = address(world);
        woodPool = new StubPool(address(woodToken), address(goldToken), wAddr);
        ironPool = new StubPool(address(ironToken), address(goldToken), wAddr);
        wheatPool = new StubPool(address(wheatToken), address(goldToken), wAddr);
        fishPool = new StubPool(address(fishToken), address(goldToken), wAddr);

        address[6] memory tokens = [
            address(woodToken),
            address(ironToken),
            address(wheatToken),
            address(fishToken),
            address(goldToken),
            address(blueprintToken)
        ];
        address[4] memory pools = [address(woodPool), address(wheatPool), address(fishPool), address(ironPool)];

        world.initTreasury(tokens, pools);

        // Seed: 1000 wood + 1000 gold per pool (spot price 1 gold / 1 wood)
        uint256 resSeed = 1000e18;
        uint256 goldSeed = 1000e18;
        PoolSeedConfig memory cfg = PoolSeedConfig({
            woodSeed: resSeed,
            wheatSeed: resSeed,
            fishSeed: resSeed,
            ironSeed: resSeed,
            goldSeedForWood: goldSeed,
            goldSeedForWheat: goldSeed,
            goldSeedForFish: goldSeed,
            goldSeedForIron: goldSeed
        });
        world.seedPools(cfg);

        return address(woodToken);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }

    function _mintClan() internal returns (uint32 clanId) {
        vm.prank(elder);
        (clanId,) = world.mintClan(elder);
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

    // -------------------------------------------------------------------------
    // Test 1: heartbeat rate limit
    // -------------------------------------------------------------------------

    function test_heartbeat_rateLimit() public {
        // First heartbeat should succeed (nextHeartbeatAtTs == block.timestamp)
        world.heartbeat();
        // Second heartbeat immediately after should revert
        vm.expectRevert("ClanWorld: heartbeat rate limited");
        world.heartbeat();
    }

    function test_heartbeat_tickIncrementsExactlyOne() public {
        uint64 tickBefore = world.getWorldState().currentTick;

        world.heartbeat();

        uint64 tickAfter = world.getWorldState().currentTick;
        assertEq(tickAfter - tickBefore, 1, "heartbeat should advance exactly one tick");
    }

    // -------------------------------------------------------------------------
    // Test 2: tick seed changes after heartbeat
    // -------------------------------------------------------------------------

    function test_heartbeat_seedChanges() public {
        WorldState memory beforeFirst = world.getWorldState();
        assertEq(beforeFirst.currentTickSeed, bytes32(0));

        bytes32 expectedFirstSeed =
            keccak256(abi.encode(block.prevrandao, beforeFirst.currentTickSeed, beforeFirst.currentTick));
        world.heartbeat();

        WorldState memory afterFirst = world.getWorldState();
        assertEq(afterFirst.currentTickSeed, expectedFirstSeed, "first seed should use closed tick and prior seed");
        assertTrue(afterFirst.currentTickSeed != beforeFirst.currentTickSeed, "seed should change after heartbeat");

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        bytes32 expectedSecondSeed =
            keccak256(abi.encode(block.prevrandao, afterFirst.currentTickSeed, afterFirst.currentTick));
        world.heartbeat();

        WorldState memory afterSecond = world.getWorldState();
        assertEq(afterSecond.currentTickSeed, expectedSecondSeed, "second seed should chain from prior seed");
        assertTrue(afterSecond.currentTickSeed != afterFirst.currentTickSeed, "next seed should differ");
        assertTrue(
            afterSecond.currentTickSeed != beforeFirst.currentTickSeed, "next seed should not repeat initial seed"
        );
    }

    function test_heartbeat_permissionless() public {
        address rando = makeAddr("rando");
        uint64 tickBefore = world.getWorldState().currentTick;

        vm.prank(rando);
        world.heartbeat();

        assertEq(world.getWorldState().currentTick, tickBefore + 1, "non-owner caller should advance heartbeat");
    }

    function test_heartbeat_sequenceFiveTicks() public {
        bytes32[5] memory seeds;
        uint64 previousTick = world.getWorldState().currentTick;

        for (uint256 i = 0; i < 5; i++) {
            if (i != 0) {
                vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
            }

            world.heartbeat();

            WorldState memory state = world.getWorldState();
            assertEq(state.currentTick, previousTick + 1, "each heartbeat should advance exactly one tick");
            assertTrue(state.currentTickSeed != bytes32(0), "seed should be non-zero");

            for (uint256 j = 0; j < i; j++) {
                assertTrue(state.currentTickSeed != seeds[j], "seed sequence should not repeat");
            }

            seeds[i] = state.currentTickSeed;
            previousTick = state.currentTick;
        }
    }

    // -------------------------------------------------------------------------
    // Test 3: mintClan — ID starts at 1
    // -------------------------------------------------------------------------

    function test_mintClan_idStartsAtOne() public {
        (uint32 clanId, uint256 iftTokenId) = world.mintClan(elder);
        assertGe(clanId, 1, "First clan ID must be >= 1");
        assertEq(clanId, 1, "First clan ID must be exactly 1");
        assertTrue(iftTokenId != 0, "iftTokenId should be non-zero");
    }

    // -------------------------------------------------------------------------
    // Test 4: mintClan — creates correct state
    // -------------------------------------------------------------------------

    function test_mintClan_createsState() public {
        uint32 clanId = _mintClan();

        Clan memory clan = world.getClan(clanId);
        assertEq(clan.clanId, clanId, "clanId should match");
        assertEq(clan.owner, elder, "owner should be elder");
        assertGt(clan.baseRegion, 0, "baseRegion should be non-zero");
        assertLe(clan.baseRegion, 8, "baseRegion should be <= 8");
        assertEq(clan.baseLevel, 1, "baseLevel should start at 1");
        assertEq(clan.livingClansmen, 4, "should have 4 living clansmen");
        assertGt(clan.vaultWood, 0, "should have starting wood");
        assertGt(clan.vaultWheat, 0, "should have starting wheat");
        assertGt(clan.vaultFish, 0, "should have starting fish");
        assertGt(clan.goldBalance, 0, "should have starting gold");
    }

    // -------------------------------------------------------------------------
    // Test 5: mintClan — getClanFullView shows 4 WAITING clansmen at homebase
    // -------------------------------------------------------------------------

    function test_mintClan_clansmen() public {
        uint32 clanId = _mintClan();
        ClanFullView memory view_ = world.getClanFullView(clanId);

        assertEq(view_.clansmen.length, 4, "should have 4 clansmen");
        uint8 baseRegion = view_.clan.clan.baseRegion;

        for (uint256 i = 0; i < 4; i++) {
            Clansman memory cs = view_.clansmen[i].clansman.clansman;
            assertEq(uint8(cs.state), uint8(ClansmanState.WAITING), "clansman should be WAITING");
            assertEq(cs.currentRegion, baseRegion, "clansman should be at homebase");
            assertEq(cs.clanId, clanId, "clansman.clanId should match clan");
        }
    }

    // -------------------------------------------------------------------------
    // Test 6: submitOrders — per-order failure (bad clansmanId) doesn't revert
    // -------------------------------------------------------------------------

    function test_submitOrders_perOrderFailure() public {
        uint32 clanId = _mintClan();
        ClanFullView memory view_ = world.getClanFullView(clanId);
        uint32 validCs = view_.clansmen[0].clansman.clansman.clansmanId;
        uint8 homeRegion = view_.clan.clan.baseRegion;

        ClanOrder[] memory orders = new ClanOrder[](2);
        // Valid order: send to forest to chop wood
        orders[0] = ClanOrder({
            clansmanId: validCs,
            gotoRegion: ClanWorldConstants.REGION_FOREST,
            action: ActionType.ChopWood,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
        // Invalid order: non-existent clansmanId
        orders[1] = ClanOrder({
            clansmanId: 9999,
            gotoRegion: homeRegion,
            action: ActionType.Wait,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });

        vm.prank(elder);
        OrderResult[] memory results = world.submitClanOrders(clanId, orders);

        assertEq(results.length, 2);
        assertEq(uint8(results[0].status), uint8(StatusCode.OK), "valid order should succeed");
        assertEq(uint8(results[1].status), uint8(StatusCode.ERR_INVALID_CLANSMAN), "bad csId should fail");
    }

    // -------------------------------------------------------------------------
    // Test 7: submitOrders — second immediate order hits cooldown
    // -------------------------------------------------------------------------

    function test_submitOrders_cooldown() public {
        uint32 clanId = _mintClan();
        ClanFullView memory view_ = world.getClanFullView(clanId);
        uint32 csId = view_.clansmen[0].clansman.clansman.clansmanId;

        // First order
        OrderResult[] memory r1 = _submitOrder(clanId, csId, ClanWorldConstants.REGION_FOREST, ActionType.ChopWood);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "first order should succeed");

        // Second order immediately — should hit cooldown
        OrderResult[] memory r2 = _submitOrder(clanId, csId, ClanWorldConstants.REGION_FOREST, ActionType.ChopWood);
        assertEq(uint8(r2[0].status), uint8(StatusCode.ERR_COOLDOWN_ACTIVE), "second order should hit cooldown");
    }

    // -------------------------------------------------------------------------
    // Test 8: NOOP bypass — same-region order has travelTicks == 0, clansman stays / goes ACTING
    // -------------------------------------------------------------------------

    function test_submitOrders_noopBypass() public {
        uint32 clanId = _mintClan();
        ClanFullView memory view_ = world.getClanFullView(clanId);
        uint32 csId = view_.clansmen[0].clansman.clansman.clansmanId;
        uint8 homeRegion = view_.clan.clan.baseRegion;

        // Issue a NOOP order: gotoRegion == 0 (NOOP), action = Wait
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: ClanWorldConstants.REGION_NOOP, // 0 = NOOP
            action: ActionType.Wait,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });

        vm.prank(elder);
        OrderResult[] memory results = world.submitClanOrders(clanId, orders);
        assertEq(uint8(results[0].status), uint8(StatusCode.OK), "NOOP order should succeed");

        // Mission should show travelTicks = 0 (arrivalTick == startTick)
        Mission memory m = world.getActiveMission(csId);
        assertTrue(m.active, "mission should be active");
        assertEq(m.arrivalTick, m.startTick, "NOOP: arrivalTick == startTick (0 travel)");
        assertEq(m.targetRegion, homeRegion, "NOOP: targetRegion == homeRegion");

        // Clansman should be ACTING (same-region → no traveling state)
        Clansman memory cs = world.getClansman(csId);
        assertEq(uint8(cs.state), uint8(ClansmanState.ACTING), "same-region: no TRAVELING state");
    }

    // -------------------------------------------------------------------------
    // Test 9: settlement — travel + gather
    // -------------------------------------------------------------------------

    function test_settlement_travelAndGather() public {
        uint32 clanId = _mintClan();
        ClanFullView memory view_ = world.getClanFullView(clanId);
        uint32 csId = view_.clansmen[0].clansman.clansman.clansmanId;
        uint8 homeRegion = view_.clan.clan.baseRegion;

        // Submit MineIron mission to Mountains (region 2) — requires at least 1 travel tick from Forest(1)
        uint8 targetRegion = ClanWorldConstants.REGION_MOUNTAINS;
        (uint8 travelTicks,) = world.quoteTravel(homeRegion, targetRegion);

        OrderResult[] memory r = _submitOrder(clanId, csId, targetRegion, ActionType.MineIron);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK));

        // If travel > 0, clansman should be TRAVELING immediately after submission
        if (travelTicks > 0) {
            Clansman memory csTraveling = world.getClansman(csId);
            assertEq(uint8(csTraveling.state), uint8(ClansmanState.TRAVELING), "should be TRAVELING before arrival");
        }

        // Advance until the arrival tick and four-tick action duration have both closed.
        uint256 ticksToAdvance = uint256(travelTicks) + world.getActionDuration(ActionType.MineIron) + 1;
        for (uint256 i = 0; i < ticksToAdvance; i++) {
            _advanceTick();
        }

        // Trigger settlement by calling settleClan
        world.settleClan(clanId);

        // Verify clansman has carry iron (traveled to Mountains and mined)
        Clansman memory cs = world.getClansman(csId);
        assertGt(cs.carryIron, 0, "clansman should have gathered iron after travel to Mountains");
    }

    // -------------------------------------------------------------------------
    // Test 10: settlement — deposit adds to vault and clears carry
    // -------------------------------------------------------------------------

    function test_settlement_depositAddsToVault() public {
        uint32 clanId = _mintClan();
        ClanFullView memory view_ = world.getClanFullView(clanId);
        uint8 homeRegion = view_.clan.clan.baseRegion;

        // Use two clansmen: one mines iron, one stays home to deposit
        uint32 cs0 = view_.clansmen[0].clansman.clansman.clansmanId;
        uint32 cs1 = view_.clansmen[1].clansman.clansman.clansmanId;

        // Send cs0 to Mountains to mine iron (requires travel from non-Mountains home)
        uint8 targetRegion = ClanWorldConstants.REGION_MOUNTAINS;
        (uint8 travelToMountains,) = world.quoteTravel(homeRegion, targetRegion);
        _submitOrder(clanId, cs0, targetRegion, ActionType.MineIron);

        // Advance through travel and the four-tick mining duration.
        for (uint256 i = 0; i < uint256(travelToMountains) + world.getActionDuration(ActionType.MineIron) + 1; i++) {
            _advanceTick();
        }
        world.settleClan(clanId);

        uint256 carryBefore = world.getClansman(cs0).carryIron;
        assertGt(carryBefore, 0, "cs0 should have carry iron after mining at Mountains");

        uint256 vaultBefore = world.getClan(clanId).vaultIron;

        // Wait for cs0 cooldown to expire, then send back to deposit
        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS + 1);
        _submitOrder(clanId, cs0, homeRegion, ActionType.DepositResources);

        // Advance through travel back to homebase and the deposit's 1-tick transfer.
        (uint8 travelBack,) = world.quoteTravel(targetRegion, homeRegion);
        for (uint256 i = 0; i < uint256(travelBack) + world.getActionDuration(ActionType.DepositResources) + 1; i++) {
            _advanceTick();
        }
        world.settleClan(clanId);

        // cs0 carry iron should be cleared and vault iron should have increased
        Clansman memory cs0After = world.getClansman(cs0);
        assertEq(cs0After.carryIron, 0, "carry iron should be cleared after deposit");

        uint256 vaultAfter = world.getClan(clanId).vaultIron;
        assertGt(vaultAfter, vaultBefore, "vault iron should increase after deposit");

        // cs1 unused — suppress warning
        cs1;
    }

    function test_depositResources_woodCarryMovesToVaultAndClears() public {
        (ClanWorldTestHarness harness, uint32 clanId, uint32 csId) = _setupHarness();
        uint8 homeRegion = harness.getClan(clanId).baseRegion;
        uint256 woodDelta = 5e18;

        harness.setCarry(csId, woodDelta, 0, 0, 0);
        uint256 vaultBefore = harness.getClan(clanId).vaultWood;

        OrderResult[] memory r = _submitOrderHarness(harness, clanId, csId, homeRegion, ActionType.DepositResources);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "deposit order should be accepted");

        Mission memory mission = harness.getActiveMission(csId);
        assertEq(
            mission.settlesAtTick,
            mission.executesAtTick + harness.getActionDuration(ActionType.DepositResources),
            "deposit settles after transfer duration"
        );

        _advanceTickHarness(harness);
        _advanceTickHarness(harness);

        assertEq(harness.getClan(clanId).vaultWood, vaultBefore + woodDelta, "vault wood receives carried wood");
        assertEq(harness.getClansman(csId).carryWood, 0, "carry wood is cleared");
    }

    function test_depositResources_emptyCarryNoopsWithoutEvent() public {
        (ClanWorldTestHarness harness, uint32 clanId, uint32 csId) = _setupHarness();
        uint8 homeRegion = harness.getClan(clanId).baseRegion;

        OrderResult[] memory r = _submitOrderHarness(harness, clanId, csId, homeRegion, ActionType.DepositResources);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "empty deposit order should be accepted");

        vm.recordLogs();
        _advanceTickHarness(harness);
        _advanceTickHarness(harness);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 depositedTopic = keccak256("ResourcesDeposited(uint32,uint32,uint256,uint256,uint256,uint256,uint32)");

        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != depositedTopic, "empty deposit emits no ResourcesDeposited event");
        }

        assertFalse(harness.getActiveMission(csId).active, "empty deposit still completes");
    }

    function test_depositResources_multipleTypesMoveTogether() public {
        (ClanWorldTestHarness harness, uint32 clanId, uint32 csId) = _setupHarness();
        uint8 homeRegion = harness.getClan(clanId).baseRegion;
        uint256 woodDelta = 4e18;
        uint256 ironDelta = 2e18;
        uint256 fishDelta = 3e18;

        harness.setCarry(csId, woodDelta, ironDelta, 0, fishDelta);
        Clan memory beforeClan = harness.getClan(clanId);

        OrderResult[] memory r = _submitOrderHarness(harness, clanId, csId, homeRegion, ActionType.DepositResources);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "deposit order should be accepted");

        _advanceTickHarness(harness);
        _advanceTickHarness(harness);

        Clan memory afterClan = harness.getClan(clanId);
        Clansman memory afterCs = harness.getClansman(csId);

        assertEq(afterClan.vaultWood, beforeClan.vaultWood + woodDelta, "wood transferred");
        assertEq(afterClan.vaultIron, beforeClan.vaultIron + ironDelta, "iron transferred");
        assertEq(afterClan.vaultFish, beforeClan.vaultFish + fishDelta - 8e17, "fish transferred after upkeep");
        assertEq(afterCs.carryWood, 0, "wood carry cleared");
        assertEq(afterCs.carryIron, 0, "iron carry cleared");
        assertEq(afterCs.carryFish, 0, "fish carry cleared");
    }

    function test_depositResources_requiresHomeRegion() public {
        (ClanWorldTestHarness harness, uint32 clanId, uint32 csId) = _setupHarness();
        uint8 homeRegion = harness.getClan(clanId).baseRegion;
        uint8 nonHomeRegion = homeRegion == ClanWorldConstants.REGION_FOREST
            ? ClanWorldConstants.REGION_MOUNTAINS
            : ClanWorldConstants.REGION_FOREST;

        OrderResult[] memory r = _submitOrderHarness(harness, clanId, csId, nonHomeRegion, ActionType.DepositResources);

        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_INVALID_REGION), "deposit must target home region");
    }

    function test_depositResources_eventHasCorrectDeltas() public {
        (ClanWorldTestHarness harness, uint32 clanId, uint32 csId) = _setupHarness();
        uint8 homeRegion = harness.getClan(clanId).baseRegion;

        harness.setCarry(csId, 5e18, 2e18, 1e18, 3e18);

        OrderResult[] memory r = _submitOrderHarness(harness, clanId, csId, homeRegion, ActionType.DepositResources);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "deposit order should be accepted");

        _advanceTickHarness(harness);
        vm.expectEmit(true, true, false, true);
        emit IClanWorldEvents.ResourcesDeposited(clanId, csId, 5e18, 2e18, 1e18, 3e18, 1);
        _advanceTickHarness(harness);
    }

    function test_quoteTravel_outOfBounds_returnsZero() public {
        (uint8 ticks, bytes8 path) = world.quoteTravel(9, 1);
        assertEq(ticks, 0, "out-of-range src should return 0 ticks");
        assertEq(path, bytes8(0), "out-of-range src should return empty path");

        (ticks, path) = world.quoteTravel(1, 9);
        assertEq(ticks, 0, "out-of-range dst should return 0 ticks");
        assertEq(path, bytes8(0), "out-of-range dst should return empty path");
    }

    // -------------------------------------------------------------------------
    // Test A: quoteTravel(9,9) — both out-of-bounds same-region, must return (0, bytes8(0))
    // -------------------------------------------------------------------------

    function test_quoteTravel_outOfBounds_sameRegion() public {
        // Previously (9,9) escaped the > 8 guard (same-region early return fired first),
        // returning (0, bytes8(uint64(9) << 56)) instead of (0, bytes8(0)).
        (uint8 ticks, bytes8 path) = world.quoteTravel(9, 9);
        assertEq(ticks, 0, "quoteTravel(9,9): travelTicks must be 0");
        assertEq(path, bytes8(0), "quoteTravel(9,9): path must be bytes8(0), not a packed 9-region sentinel");
    }

    // -------------------------------------------------------------------------
    // Test B: heartbeat eager settlement keeps clans from drifting >200 ticks behind
    // -------------------------------------------------------------------------

    function test_submitClanOrders_reverts_when_clan_too_far_behind() public {
        uint32 clanId = _mintClan();
        ClanFullView memory view_ = world.getClanFullView(clanId);
        uint32 csId = view_.clansmen[0].clansman.clansman.clansmanId;

        // Advance 201 ticks — clan is now 201 ticks behind its lastSettledTick
        for (uint256 i = 0; i < 201; i++) {
            _advanceTick();
        }

        // Heartbeat now advances the clan checkpoint, so submission can proceed normally.
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
        OrderResult[] memory results = world.submitClanOrders(clanId, orders);

        assertEq(results.length, 1, "should return one result");
        assertEq(
            uint8(results[0].status),
            uint8(StatusCode.OK),
            "heartbeat eager settlement keeps order submission unblocked"
        );
    }

    // -------------------------------------------------------------------------
    // Test C: cooldown resets on mission interrupt
    // -------------------------------------------------------------------------

    function test_cooldown_resets_on_mission_interrupt() public {
        uint32 clanId = _mintClan();
        ClanFullView memory view_ = world.getClanFullView(clanId);
        uint32 csId = view_.clansmen[0].clansman.clansman.clansmanId;

        // Submit first mission — sends clansman to Forest to chop wood
        OrderResult[] memory r1 = _submitOrder(clanId, csId, ClanWorldConstants.REGION_FOREST, ActionType.ChopWood);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "first order should succeed");
        uint64 firstCooldown = r1[0].cooldownEndsAtTs;
        assertGt(firstCooldown, 0, "cooldown should be set after first order");

        // Wait for cooldown to expire
        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS + 1);

        // Advance tick so heartbeat is valid, then submit interrupt mission
        _advanceTick();

        // Submit a new mission to interrupt the first (still en-route to Forest)
        // Use MineIron in Mountains — different target, forces interrupt
        OrderResult[] memory r2 = _submitOrder(clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);
        assertEq(uint8(r2[0].status), uint8(StatusCode.OK), "interrupt order should succeed");

        uint64 newCooldown = r2[0].cooldownEndsAtTs;
        assertGt(newCooldown, firstCooldown, "new cooldown must be later than first cooldown");
        assertGt(newCooldown, block.timestamp, "new cooldown must be in the future");
    }

    // =========================================================================
    // Phase 2 Market Tests
    // =========================================================================

    // Helper: submit a market order for a specific clansman
    function _submitMarketOrder(
        uint32 clanId,
        uint32 csId,
        ActionType action,
        address token,
        uint256 amount,
        uint256 maxGold
    ) internal returns (OrderResult[] memory) {
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: ClanWorldConstants.REGION_UNICORN_TOWN,
            action: action,
            targetClanId: 0,
            marketToken: token,
            marketAmount: amount,
            maxGoldIn: maxGold
        });
        vm.prank(elder);
        return world.submitClanOrders(clanId, orders);
    }

    function _submitAllClanMarketSells(uint32 clanId, address token) internal returns (uint256 count) {
        ClanFullView memory view_ = world.getClanFullView(clanId);
        count = view_.clansmen.length;
        return _submitFirstClanMarketSells(clanId, token, count);
    }

    function _submitFirstClanMarketSells(uint32 clanId, address token, uint256 count) internal returns (uint256) {
        ClanFullView memory view_ = world.getClanFullView(clanId);
        require(count <= view_.clansmen.length, "too many clansmen");
        ClanOrder[] memory orders = new ClanOrder[](count);
        for (uint256 i = 0; i < count; i++) {
            orders[i] = ClanOrder({
                clansmanId: view_.clansmen[i].clansman.clansman.clansmanId,
                gotoRegion: ClanWorldConstants.REGION_UNICORN_TOWN,
                action: ActionType.MarketSell,
                targetClanId: 0,
                marketToken: token,
                marketAmount: 1e18,
                maxGoldIn: 0
            });
        }
        vm.prank(elder);
        OrderResult[] memory results = world.submitClanOrders(clanId, orders);
        for (uint256 i = 0; i < results.length; i++) {
            assertEq(uint8(results[i].status), uint8(StatusCode.OK), "market sell should enqueue");
        }
        return count;
    }

    // Helper: get the first clansman id for a clan
    function _firstCs(uint32 clanId) internal view returns (uint32) {
        return world.getClanFullView(clanId).clansmen[0].clansman.clansman.clansmanId;
    }

    // -------------------------------------------------------------------------
    // Test 11: sell_creditsGold — after scheduled sell, clan.goldBalance > starter gold
    // -------------------------------------------------------------------------

    function test_sell_creditsGold() public {
        address woodAddr = _setupMarket();
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        // Clan starts with 20 wood in vault (starter pack)
        uint256 goldBefore = world.getClan(clanId).goldBalance;

        // Submit sell order — clansman travels to Unicorn Town then executes at actionStartTick
        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 5e18, 0);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "sell order should be accepted");

        // Find out which tick the action fires
        Mission memory m = world.getActiveMission(csId);
        uint64 executeAtTick = m.actionStartTick;

        // Advance ticks until heartbeat closes executeAtTick
        uint64 curTick = world.getWorldState().currentTick;
        uint256 ticksNeeded = uint256(executeAtTick - curTick) + 1;
        for (uint256 i = 0; i < ticksNeeded; i++) {
            _advanceTick();
        }

        // Settle clan to apply any mission resolution
        world.settleClan(clanId);

        uint256 goldAfter = world.getClan(clanId).goldBalance;
        assertGt(goldAfter, goldBefore, "gold should increase after sell");
    }

    // -------------------------------------------------------------------------
    // Test 12: buy_debitsGold — after scheduled buy, gold decreases, vault resource increases
    // -------------------------------------------------------------------------

    function test_buy_debitsGold() public {
        address woodAddr = _setupMarket();
        uint32 clanId = _mintClan();

        // Give clan ample gold for the buy
        // We need a second clansman to do the buy while first does something else
        ClanFullView memory view_ = world.getClanFullView(clanId);
        uint32 csId = view_.clansmen[0].clansman.clansman.clansmanId;

        uint256 goldBefore = world.getClan(clanId).goldBalance;
        uint256 vaultWoodBefore = world.getClan(clanId).vaultWood;

        // Submit buy order for 1e18 wood, maxGoldIn = generous 500e18
        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 500e18);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "buy order should be accepted");

        Mission memory m = world.getActiveMission(csId);
        uint64 executeAtTick = m.actionStartTick;

        uint64 curTick = world.getWorldState().currentTick;
        uint256 ticksNeeded = uint256(executeAtTick - curTick) + 1;
        for (uint256 i = 0; i < ticksNeeded; i++) {
            _advanceTick();
        }

        world.settleClan(clanId);

        uint256 goldAfter = world.getClan(clanId).goldBalance;
        uint256 vaultWoodAfter = world.getClan(clanId).vaultWood;
        assertLt(goldAfter, goldBefore, "gold should decrease after buy");
        assertGt(vaultWoodAfter, vaultWoodBefore, "vault wood should increase after buy");
    }

    // -------------------------------------------------------------------------
    // Test 13: buy_maxGoldIn — buy fails with ERR_MARKET_BUY_MAX_GOLD_EXCEEDED
    // -------------------------------------------------------------------------

    function test_buy_maxGoldIn() public {
        address woodAddr = _setupMarket();
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        // maxGoldIn = 0 (will always be exceeded for any nonzero buy)
        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketBuy, woodAddr, 1e18, 0);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "order submission should succeed");

        Mission memory m = world.getActiveMission(csId);
        uint64 executeAtTick = m.actionStartTick;
        uint64 curTick = world.getWorldState().currentTick;

        // Advance all ticks UP TO (but not including) the execute tick
        if (executeAtTick > curTick) {
            for (uint256 i = 0; i < uint256(executeAtTick - curTick); i++) {
                _advanceTick();
            }
        }

        // Now the next heartbeat will close executeAtTick — that's when MarketActionFailed fires
        // Place expectEmit right before the final heartbeat
        vm.expectEmit(true, true, false, true);
        emit IClanWorldEvents.MarketActionFailed(
            clanId, csId, ActionType.MarketBuy, StatusCode.ERR_MARKET_BUY_MAX_GOLD_EXCEEDED
        );
        _advanceTick();

        // Verify gold balance unchanged (buy failed)
        assertEq(world.getClan(clanId).goldBalance, 3e18, "gold should be unchanged after failed buy");
    }

    // -------------------------------------------------------------------------
    // Test 14: scheduledMarket_deletedAfterHeartbeat
    // -------------------------------------------------------------------------

    function test_scheduledMarket_deletedAfterHeartbeat() public {
        address woodAddr = _setupMarket();
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK));

        Mission memory m = world.getActiveMission(csId);
        uint64 executeAtTick = m.actionStartTick;

        // Verify queue has entry before heartbeat
        assertGt(world.getScheduledMarketActionsForTick(executeAtTick).length, 0, "queue should have entry");

        uint64 curTick = world.getWorldState().currentTick;
        uint256 ticksNeeded = uint256(executeAtTick - curTick) + 1;
        for (uint256 i = 0; i < ticksNeeded; i++) {
            _advanceTick();
        }

        // Queue should be empty after heartbeat processes it
        assertEq(
            world.getScheduledMarketActionsForTick(executeAtTick).length, 0, "queue should be empty after heartbeat"
        );
    }

    function test_scheduledMarket_sameTypeRetask_skipsStaleNonce() public {
        address woodAddr = _setupMarket();
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        OrderResult[] memory r1 = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 1e18, 0);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "first sell order should be accepted");
        Mission memory oldMission = world.getActiveMission(csId);
        uint64 oldExecuteAtTick = oldMission.actionStartTick;

        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS + 1);
        _advanceTick();

        OrderResult[] memory r2 = _submitMarketOrder(clanId, csId, ActionType.MarketSell, woodAddr, 2e18, 0);
        assertEq(uint8(r2[0].status), uint8(StatusCode.OK), "replacement sell order should be accepted");
        Mission memory newMission = world.getActiveMission(csId);
        uint64 newExecuteAtTick = newMission.actionStartTick;
        assertGt(newMission.nonce, oldMission.nonce, "replacement should bump nonce");

        ScheduledMarketAction[] memory oldQueue = world.getScheduledMarketActionsForTick(oldExecuteAtTick);
        ScheduledMarketAction[] memory newQueue = world.getScheduledMarketActionsForTick(newExecuteAtTick);
        assertEq(oldQueue[0].missionNonce, oldMission.nonce, "old queue captures old nonce");
        assertEq(newQueue[0].missionNonce, newMission.nonce, "new queue captures new nonce");

        uint256 goldBefore = world.getClan(clanId).goldBalance;

        _advanceTick(); // close tick before the stale entry

        vm.expectEmit(true, true, false, true);
        emit IClanWorldEvents.MarketActionFailed(clanId, csId, ActionType.MarketSell, StatusCode.ERR_INVALID_ACTION);
        _advanceTick(); // close stale entry tick
        assertEq(world.getClan(clanId).goldBalance, goldBefore, "stale sell must not execute");

        _advanceTick(); // close replacement entry tick
        assertGt(world.getClan(clanId).goldBalance, goldBefore, "replacement sell should execute");
    }

    function test_scheduledMarket_defersActionsAbovePerTickCap() public {
        address woodAddr = _setupMarket();
        uint32[] memory distOneClans = new uint32[](12);
        uint32[] memory distTwoClans = new uint32[](12);
        uint256 distOneCount;
        uint256 distTwoCount;

        for (uint256 i = 0; i < 12; i++) {
            uint32 clanId = _mintClan();
            ClanFullView memory view_ = world.getClanFullView(clanId);
            (uint8 travelTicks,) = world.quoteTravel(view_.clan.clan.baseRegion, ClanWorldConstants.REGION_UNICORN_TOWN);
            if (travelTicks == 1) {
                distOneClans[distOneCount++] = clanId;
            } else if (travelTicks == 2) {
                distTwoClans[distTwoCount++] = clanId;
            }
        }

        uint256 totalQueued;
        for (uint256 i = 0; i < distTwoCount; i++) {
            totalQueued += _submitAllClanMarketSells(distTwoClans[i], woodAddr);
        }

        _advanceTick();

        for (uint256 i = 0; i < distOneCount; i++) {
            totalQueued += _submitAllClanMarketSells(distOneClans[i], woodAddr);
        }

        uint64 executeAtTick = 2;
        uint256 cap = world.MAX_MARKET_ACTIONS_PER_TICK();
        assertGt(totalQueued, cap, "test setup must exceed cap");
        assertEq(
            world.getScheduledMarketActionsForTick(executeAtTick).length,
            totalQueued,
            "all aligned actions should share tick 2"
        );

        _advanceTick(); // close tick 1
        _advanceTick(); // close tick 2, process cap and defer remainder

        assertEq(world.getScheduledMarketActionsForTick(executeAtTick).length, 0, "original tick queue cleared");
        assertEq(
            world.getScheduledMarketActionsForTick(executeAtTick + 1).length,
            totalQueued - cap,
            "overflow actions deferred to next tick"
        );

        _advanceTick(); // close tick 3, process deferred actions
        assertEq(world.getScheduledMarketActionsForTick(executeAtTick + 1).length, 0, "deferred queue cleared");
    }

    function test_scheduledMarket_overflowExecutesBeforeNativeNextTickActions() public {
        address woodAddr = _setupMarket();
        uint32[] memory distOneClans = new uint32[](12);
        uint32[] memory distTwoClans = new uint32[](12);
        uint256 distOneCount;
        uint256 distTwoCount;

        for (uint256 i = 0; i < 12; i++) {
            uint32 clanId = _mintClan();
            ClanFullView memory view_ = world.getClanFullView(clanId);
            (uint8 travelTicks,) = world.quoteTravel(view_.clan.clan.baseRegion, ClanWorldConstants.REGION_UNICORN_TOWN);
            if (travelTicks == 1) {
                distOneClans[distOneCount++] = clanId;
            } else if (travelTicks == 2) {
                distTwoClans[distTwoCount++] = clanId;
            }
        }
        assertGt(distTwoCount, 0, "test setup needs a distance-two clan");

        uint32 nativeClanId = distTwoClans[0];
        ClanFullView memory nativeView = world.getClanFullView(nativeClanId);
        uint32 nativeCsId = nativeView.clansmen[3].clansman.clansman.clansmanId;

        uint256 totalQueuedForTickTwo = _submitFirstClanMarketSells(nativeClanId, woodAddr, 3);
        for (uint256 i = 1; i < distTwoCount; i++) {
            totalQueuedForTickTwo += _submitAllClanMarketSells(distTwoClans[i], woodAddr);
        }

        _advanceTick();

        for (uint256 i = 0; i < distOneCount; i++) {
            totalQueuedForTickTwo += _submitAllClanMarketSells(distOneClans[i], woodAddr);
        }

        OrderResult[] memory nativeResult =
            _submitMarketOrder(nativeClanId, nativeCsId, ActionType.MarketSell, woodAddr, 1e18, 0);
        assertEq(uint8(nativeResult[0].status), uint8(StatusCode.OK), "native next-tick action should enqueue");

        uint64 overflowTick = 2;
        uint64 nextTick = overflowTick + 1;
        uint256 cap = world.MAX_MARKET_ACTIONS_PER_TICK();
        assertGt(totalQueuedForTickTwo, cap, "test setup must exceed cap");

        ScheduledMarketAction[] memory nativeQueueBefore = world.getScheduledMarketActionsForTick(nextTick);
        assertEq(nativeQueueBefore.length, 1, "native next-tick queue should exist before overflow merge");
        uint64 nativeSeq = nativeQueueBefore[0].commitSequence;

        _advanceTick(); // close tick 1
        _advanceTick(); // close tick 2, process cap and defer overflow into tick 3

        uint256 overflowCount = totalQueuedForTickTwo - cap;
        ScheduledMarketAction[] memory mergedQueue = world.getScheduledMarketActionsForTick(nextTick);
        assertEq(mergedQueue.length, overflowCount + 1, "overflow should merge with native next-tick action");
        assertEq(
            mergedQueue[mergedQueue.length - 1].commitSequence,
            nativeSeq,
            "native action must stay after older overflow"
        );
        for (uint256 i = 1; i < mergedQueue.length; i++) {
            assertGt(mergedQueue[i].commitSequence, mergedQueue[i - 1].commitSequence, "merged queue must be FIFO");
        }

        bytes32 executedSig =
            keccak256("ScheduledMarketActionExecuted(uint64,uint64,uint32,uint32,address,address,uint256,uint256)");
        vm.recordLogs();
        _advanceTick(); // close tick 3 and execute the sorted merged queue
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool sawExecution;
        uint64 previousSeq;
        uint256 executedCount;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(world) || logs[i].topics.length == 0 || logs[i].topics[0] != executedSig) {
                continue;
            }
            uint64 executedTick = uint64(uint256(logs[i].topics[1]));
            if (executedTick != nextTick) continue;

            uint64 seq = uint64(uint256(logs[i].topics[2]));
            if (sawExecution) assertGt(seq, previousSeq, "execution events must be FIFO");
            sawExecution = true;
            previousSeq = seq;
            executedCount++;
        }

        assertEq(executedCount, overflowCount + 1, "all merged actions should execute");
        assertEq(previousSeq, nativeSeq, "native action should execute after older overflow actions");
    }

    // -------------------------------------------------------------------------
    // Test 15: scheduledMarket_fifo — two clans queue sells; commitSequence is FIFO
    // -------------------------------------------------------------------------

    function test_scheduledMarket_fifo() public {
        address woodAddr = _setupMarket();

        // Mint two clans — they get region 1 and region 2 respectively
        uint32 clanId1 = _mintClan();
        vm.prank(elder2);
        (uint32 clanId2,) = world.mintClan(elder2);

        uint32 csId1 = _firstCs(clanId1);
        uint32 csId2 = world.getClanFullView(clanId2).clansmen[0].clansman.clansman.clansmanId;

        // Submit clan1's sell order first (commitSequence = 0)
        ClanOrder[] memory orders1 = new ClanOrder[](1);
        orders1[0] = ClanOrder({
            clansmanId: csId1,
            gotoRegion: ClanWorldConstants.REGION_UNICORN_TOWN,
            action: ActionType.MarketSell,
            targetClanId: 0,
            marketToken: woodAddr,
            marketAmount: 2e18,
            maxGoldIn: 0
        });
        vm.prank(elder);
        OrderResult[] memory r1 = world.submitClanOrders(clanId1, orders1);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "clan1 sell order ok");

        // Submit clan2's sell order second (commitSequence = 1)
        ClanOrder[] memory orders2 = new ClanOrder[](1);
        orders2[0] = ClanOrder({
            clansmanId: csId2,
            gotoRegion: ClanWorldConstants.REGION_UNICORN_TOWN,
            action: ActionType.MarketSell,
            targetClanId: 0,
            marketToken: woodAddr,
            marketAmount: 2e18,
            maxGoldIn: 0
        });
        vm.prank(elder2);
        OrderResult[] memory r2 = world.submitClanOrders(clanId2, orders2);
        assertEq(uint8(r2[0].status), uint8(StatusCode.OK), "clan2 sell order ok");

        // Verify FIFO: clan1 committed before clan2 so has lower commitSequence
        Mission memory m1 = world.getActiveMission(csId1);
        Mission memory m2 = world.getActiveMission(csId2);

        // Check commitSequence in the queues for each clan's respective tick
        ScheduledMarketAction[] memory q1 = world.getScheduledMarketActionsForTick(m1.actionStartTick);
        ScheduledMarketAction[] memory q2 = world.getScheduledMarketActionsForTick(m2.actionStartTick);

        uint64 seq1;
        uint64 seq2;
        for (uint256 i = 0; i < q1.length; i++) {
            if (q1[i].clanId == clanId1) seq1 = q1[i].commitSequence;
        }
        for (uint256 i = 0; i < q2.length; i++) {
            if (q2[i].clanId == clanId2) seq2 = q2[i].commitSequence;
        }
        assertLt(seq1, seq2, "clan1 submitted first: lower commitSequence");

        // Advance ticks to cover both actions
        uint64 curTick = world.getWorldState().currentTick;
        uint64 maxTick = m1.actionStartTick > m2.actionStartTick ? m1.actionStartTick : m2.actionStartTick;
        uint256 ticksNeeded = uint256(maxTick - curTick) + 1;
        for (uint256 i = 0; i < ticksNeeded; i++) {
            _advanceTick();
        }

        // Both clans should have gained gold (starter 3e18 + sell proceeds)
        assertGt(world.getClan(clanId1).goldBalance, 3e18, "clan1 should have gained gold from sell");
        assertGt(world.getClan(clanId2).goldBalance, 3e18, "clan2 should have gained gold from sell");
    }

    // -------------------------------------------------------------------------
    // Test 16: twoClan_sellBuyCycle — clan A sells wood, clan B buys wood; both succeed
    // -------------------------------------------------------------------------

    function test_twoClan_sellBuyCycle() public {
        address woodAddr = _setupMarket();

        uint32 clanId1 = _mintClan();
        vm.prank(elder2);
        (uint32 clanId2,) = world.mintClan(elder2);

        uint32 csId1 = _firstCs(clanId1);
        uint32 csId2 = world.getClanFullView(clanId2).clansmen[0].clansman.clansman.clansmanId;

        // Clan 1: sell 5e18 wood
        ClanOrder[] memory sellOrders = new ClanOrder[](1);
        sellOrders[0] = ClanOrder({
            clansmanId: csId1,
            gotoRegion: ClanWorldConstants.REGION_UNICORN_TOWN,
            action: ActionType.MarketSell,
            targetClanId: 0,
            marketToken: woodAddr,
            marketAmount: 5e18,
            maxGoldIn: 0
        });
        vm.prank(elder);
        world.submitClanOrders(clanId1, sellOrders);

        // Clan 2: buy 1e18 wood with maxGoldIn = 100e18
        ClanOrder[] memory buyOrders = new ClanOrder[](1);
        buyOrders[0] = ClanOrder({
            clansmanId: csId2,
            gotoRegion: ClanWorldConstants.REGION_UNICORN_TOWN,
            action: ActionType.MarketBuy,
            targetClanId: 0,
            marketToken: woodAddr,
            marketAmount: 1e18,
            maxGoldIn: 100e18
        });
        vm.prank(elder2);
        world.submitClanOrders(clanId2, buyOrders);

        Mission memory m1 = world.getActiveMission(csId1);
        Mission memory m2 = world.getActiveMission(csId2);

        uint64 maxTick = m1.actionStartTick > m2.actionStartTick ? m1.actionStartTick : m2.actionStartTick;
        uint64 curTick = world.getWorldState().currentTick;
        uint256 ticksNeeded = uint256(maxTick - curTick) + 1;
        for (uint256 i = 0; i < ticksNeeded; i++) {
            _advanceTick();
        }

        world.settleClan(clanId1);
        world.settleClan(clanId2);

        // Clan1 sold wood → gold should increase
        assertGt(world.getClan(clanId1).goldBalance, 3e18, "clan1 should have more gold after sell");
        // Clan2 bought wood → vault wood should increase beyond starter 20e18
        assertGt(world.getClan(clanId2).vaultWood, 20e18, "clan2 should have more vault wood after buy");
        // Clan2 spent gold
        assertLt(world.getClan(clanId2).goldBalance, 3e18, "clan2 should have less gold after buy");
    }

    // -------------------------------------------------------------------------
    // Test 17: marketOrder_rejectsInvalidRegion — non-UT market order rejected
    // -------------------------------------------------------------------------

    function test_marketOrder_rejectsInvalidRegion() public {
        address woodAddr = _setupMarket();
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        // Try to submit market sell to Forest (wrong region)
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: ClanWorldConstants.REGION_FOREST,
            action: ActionType.MarketSell,
            targetClanId: 0,
            marketToken: woodAddr,
            marketAmount: 1e18,
            maxGoldIn: 0
        });
        vm.prank(elder);
        OrderResult[] memory results = world.submitClanOrders(clanId, orders);
        assertEq(uint8(results[0].status), uint8(StatusCode.ERR_INVALID_REGION), "market sell to Forest should fail");
    }

    function test_marketOrder_returnsErrorWhenTreasuryUninitialized() public {
        uint32 clanId = _mintClan();
        ClanFullView memory view_ = world.getClanFullView(clanId);
        uint32 marketCsId = view_.clansmen[0].clansman.clansman.clansmanId;
        uint32 noopCsId = view_.clansmen[1].clansman.clansman.clansmanId;
        uint8 baseRegion = view_.clan.clan.baseRegion;

        ClanOrder[] memory orders = new ClanOrder[](2);
        orders[0] = ClanOrder({
            clansmanId: marketCsId,
            gotoRegion: ClanWorldConstants.REGION_UNICORN_TOWN,
            action: ActionType.MarketSell,
            targetClanId: 0,
            marketToken: address(0xBEEF),
            marketAmount: 1e18,
            maxGoldIn: 0
        });
        orders[1] = ClanOrder({
            clansmanId: noopCsId,
            gotoRegion: baseRegion,
            action: ActionType.Wait,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });

        vm.prank(elder);
        OrderResult[] memory results = world.submitClanOrders(clanId, orders);

        assertEq(
            uint8(results[0].status),
            uint8(StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN),
            "uninitialized treasury should be a per-order market error"
        );
        assertEq(uint8(results[1].status), uint8(StatusCode.OK), "other batch orders should proceed");
    }

    // -------------------------------------------------------------------------
    // Issue #95: DefendBase re-tasking — zero-travel same-target retask must not drop defender
    // -------------------------------------------------------------------------

    function test_defendBase_zeroTravel_retask_noDropWindow() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;
        uint8 baseRegion = v.clan.clan.baseRegion;

        // First DefendBase: clansman defends its own clan (same region → zero travel).
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: baseRegion,
            action: ActionType.DefendBase,
            targetClanId: clanId,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
        vm.prank(elder);
        OrderResult[] memory r1 = world.submitClanOrders(clanId, orders);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "first DefendBase OK");

        // Advance past cooldown and settle so defender is registered.
        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS + 1);
        _advanceTick();

        uint32[] memory defs = world.getDefendingClans(baseRegion);
        assertEq(defs.length, 1, "one defender registered");
        assertEq(defs[0], clanId, "clanId is the defender");

        // Second DefendBase to same target: zero-travel re-task — the regression case.
        vm.prank(elder);
        OrderResult[] memory r2 = world.submitClanOrders(clanId, orders);
        assertEq(uint8(r2[0].status), uint8(StatusCode.OK), "re-task DefendBase OK");

        // Defender must NOT be dropped — fix must register synchronously.
        defs = world.getDefendingClans(baseRegion);
        assertEq(defs.length, 1, "defender count must not drop after re-task");
        assertEq(defs[0], clanId, "clanId must still be defending after re-task");
    }

    // =========================================================================
    // Phase 3.1 Order Submission Tests (3.E1–3.E8)
    // =========================================================================

    // -------------------------------------------------------------------------
    // 3.E1: Valid order returns OK with correct nonce and cooldown set
    // -------------------------------------------------------------------------

    function test_phase3E1_validOrder_returnsOkNonceCooldown() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;

        OrderResult[] memory r = _submitOrder(clanId, csId, ClanWorldConstants.REGION_FOREST, ActionType.ChopWood);

        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "3.E1: status must be OK");
        assertEq(r[0].missionNonce, 1, "3.E1: first nonce must be 1");
        assertEq(
            r[0].cooldownEndsAtTs,
            block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS,
            "3.E1: cooldownEndsAtTs must equal block.timestamp + COOLDOWN"
        );
    }

    // -------------------------------------------------------------------------
    // 3.E2: ERR_INVALID_CLANSMAN — clansmanId belongs to a different clan
    // -------------------------------------------------------------------------

    function test_phase3E2_invalidClansman_wrongClan() public {
        // Clan 1 (elder)
        uint32 clanId1 = _mintClan();
        // Clan 2 (elder2)
        vm.prank(elder2);
        (uint32 clanId2,) = world.mintClan(elder2);

        // Get a clansmanId from clan2
        uint32 cs2Id = world.getClanFullView(clanId2).clansmen[0].clansman.clansman.clansmanId;

        // Submit an order for clan1 using clan2's clansmanId
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: cs2Id,
            gotoRegion: ClanWorldConstants.REGION_FOREST,
            action: ActionType.ChopWood,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
        vm.prank(elder);
        OrderResult[] memory r = world.submitClanOrders(clanId1, orders);

        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_INVALID_CLANSMAN), "3.E2: cross-clan csId must be invalid");
    }

    // -------------------------------------------------------------------------
    // 3.E3: ERR_CLANSMAN_DEAD — dead clansman is rejected
    // -------------------------------------------------------------------------

    function test_phase3E3_deadClansman_rejectsOrder() public {
        ClanWorldTestHarness harness = new ClanWorldTestHarness();

        vm.prank(elder);
        (uint32 clanId,) = harness.mintClan(elder);

        uint32 csId = harness.getClanFullView(clanId).clansmen[0].clansman.clansman.clansmanId;

        harness.killClansman(csId);

        assertEq(uint8(harness.getClansman(csId).state), uint8(ClansmanState.DEAD), "3.E3: clansman must be DEAD");

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
        OrderResult[] memory r = harness.submitClanOrders(clanId, orders);

        assertEq(uint8(r[0].status), uint8(StatusCode.ERR_CLANSMAN_DEAD), "3.E3: dead clansman must be rejected");
    }

    // -------------------------------------------------------------------------
    // 3.E4: ERR_COOLDOWN_ACTIVE — submit-time cooldown enforced
    // -------------------------------------------------------------------------

    function test_phase3E4_cooldownActive_blocksImmediateReorder() public {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        // First order succeeds
        OrderResult[] memory r1 = _submitOrder(clanId, csId, ClanWorldConstants.REGION_FOREST, ActionType.ChopWood);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "3.E4: first order must succeed");
        uint64 expectedCooldown = r1[0].cooldownEndsAtTs;

        // Immediate re-order hits cooldown
        OrderResult[] memory r2 = _submitOrder(clanId, csId, ClanWorldConstants.REGION_FOREST, ActionType.ChopWood);
        assertEq(uint8(r2[0].status), uint8(StatusCode.ERR_COOLDOWN_ACTIVE), "3.E4: must return ERR_COOLDOWN_ACTIVE");
        assertEq(r2[0].cooldownEndsAtTs, expectedCooldown, "3.E4: cooldownEndsAtTs must match first order cooldown");
    }

    // -------------------------------------------------------------------------
    // 3.E5: Cooldown from heartbeat-resolved mission — can't re-order immediately after natural completion
    // -------------------------------------------------------------------------

    function test_phase3E5_heartbeatResolvedMission_setsCooldown() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;
        uint8 homeRegion = v.clan.clan.baseRegion;

        // Send clansman to homebase to DepositResources (empty carry -> completes when the arrival tick closes).
        // _doDeposit with empty carry calls _completeMission immediately during settlement.
        OrderResult[] memory r = _submitOrder(clanId, csId, homeRegion, ActionType.DepositResources);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "3.E5: order must succeed");

        // Wait for submit-time cooldown to expire (warp only; no ticks yet)
        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS + 1);

        _advanceTick();
        _advanceTick();

        // Settle the clan — mission completes, clansman back to WAITING with new cooldown
        world.settleClan(clanId);

        // Verify clansman is now WAITING
        Clansman memory cs = world.getClansman(csId);
        assertEq(uint8(cs.state), uint8(ClansmanState.WAITING), "3.E5: clansman must be WAITING after completion");
        assertGt(cs.cooldownEndsAtTs, block.timestamp, "3.E5: heartbeat-resolved completion must set future cooldown");

        // Attempt to re-order without advancing time — must hit cooldown
        OrderResult[] memory r2 = _submitOrder(clanId, csId, homeRegion, ActionType.Wait);
        assertEq(
            uint8(r2[0].status),
            uint8(StatusCode.ERR_COOLDOWN_ACTIVE),
            "3.E5: must be ERR_COOLDOWN_ACTIVE after heartbeat resolution"
        );

        // Warp past cooldown and try again — should succeed
        // Note: the cooldown check uses strict less-than (`block.timestamp < cs.cooldownEndsAtTs`),
        // so `timestamp == cooldownEndsAtTs` is already expired (boundary is inclusive).
        // The +1 warp here is conservative; test_phase3E5b_cooldown_exactBoundary verifies the exact boundary.
        vm.warp(cs.cooldownEndsAtTs + 1);
        OrderResult[] memory r3 = _submitOrder(clanId, csId, homeRegion, ActionType.Wait);
        assertEq(uint8(r3[0].status), uint8(StatusCode.OK), "3.E5: after cooldown expires must succeed");
    }

    // -------------------------------------------------------------------------
    // 3.E5b: Cooldown exact boundary — at exactly cooldownEndsAtTs, order is accepted
    // (contract uses strict `<`, so `timestamp == cooldownEndsAtTs` passes)
    // -------------------------------------------------------------------------

    function test_phase3E5b_cooldown_exactBoundary() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;
        uint8 homeRegion = v.clan.clan.baseRegion;

        // Submit first order — sets cooldown
        OrderResult[] memory r1 = _submitOrder(clanId, csId, homeRegion, ActionType.Wait);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "3.E5b: first order must succeed");
        uint64 cooldownEndsAt = r1[0].cooldownEndsAtTs;
        assertGt(cooldownEndsAt, 0, "3.E5b: cooldown must be set");

        // Warp to exactly cooldownEndsAtTs (not +1) — the strict-less-than guard means
        // `block.timestamp < cooldownEndsAtTs` is false, so cooldown is considered expired.
        vm.warp(cooldownEndsAt);

        // Order must be accepted at the exact boundary
        OrderResult[] memory r2 = _submitOrder(clanId, csId, homeRegion, ActionType.Wait);
        assertEq(
            uint8(r2[0].status),
            uint8(StatusCode.OK),
            "3.E5b: order at exact cooldownEndsAtTs must succeed (boundary inclusive)"
        );
    }

    // -------------------------------------------------------------------------
    // 3.phase3: DefendBase does not call _completeMission — cooldown must not slide
    // -------------------------------------------------------------------------

    function test_phase3_defendBase_noCompletionCooldownSlide() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;
        uint8 baseRegion = v.clan.clan.baseRegion;

        // Submit DefendBase to own clan — same region → zero travel → instant ACTING
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: baseRegion,
            action: ActionType.DefendBase,
            targetClanId: clanId,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
        vm.prank(elder);
        OrderResult[] memory r = world.submitClanOrders(clanId, orders);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "DefendBase order must succeed");

        // Wait for submit-time cooldown to expire before settling
        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS + 1);
        _advanceTick();
        world.settleClan(clanId);

        // Record cooldown after initial settlement
        uint64 cooldownAfterSubmit = world.getClansman(csId).cooldownEndsAtTs;

        // Run 3 more settle ticks — each calls _resolveAction for DefendBase
        // DefendBase does NOT call _completeMission, so cooldown must stay flat
        for (uint256 i = 0; i < 3; i++) {
            _advanceTick();
            world.settleClan(clanId);
            uint64 cooldownNow = world.getClansman(csId).cooldownEndsAtTs;
            assertEq(
                cooldownNow,
                cooldownAfterSubmit,
                "DefendBase must not slide cooldown: _completeMission must not be called per tick"
            );
        }

        // Clansman must still be ACTING (continuous defender, not returned to WAITING)
        Clansman memory cs = world.getClansman(csId);
        assertEq(
            uint8(cs.state),
            uint8(ClansmanState.ACTING),
            "DefendBase clansman must remain ACTING after 3 settlement ticks"
        );
    }

    // -------------------------------------------------------------------------
    // 3.E6: ERR_INVALID_REGION — wrong region for action type
    // -------------------------------------------------------------------------

    function test_phase3E6_invalidRegion_wrongActionForRegion() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);

        uint32 cs0 = v.clansmen[0].clansman.clansman.clansmanId;
        uint32 cs1 = v.clansmen[1].clansman.clansman.clansmanId;
        uint32 cs2 = v.clansmen[2].clansman.clansman.clansmanId;

        // ChopWood to Mountains (not Forest) → ERR_INVALID_REGION
        OrderResult[] memory r0 = _submitOrder(clanId, cs0, ClanWorldConstants.REGION_MOUNTAINS, ActionType.ChopWood);
        assertEq(
            uint8(r0[0].status), uint8(StatusCode.ERR_INVALID_REGION), "3.E6: ChopWood to Mountains must be invalid"
        );

        // MineIron to Forest (not Mountains) → ERR_INVALID_REGION
        OrderResult[] memory r1 = _submitOrder(clanId, cs1, ClanWorldConstants.REGION_FOREST, ActionType.MineIron);
        assertEq(uint8(r1[0].status), uint8(StatusCode.ERR_INVALID_REGION), "3.E6: MineIron to Forest must be invalid");

        // FishDocks to Forest (not WestDocks or EastDocks) → ERR_INVALID_REGION
        OrderResult[] memory r2 = _submitOrder(clanId, cs2, ClanWorldConstants.REGION_FOREST, ActionType.FishDocks);
        assertEq(uint8(r2[0].status), uint8(StatusCode.ERR_INVALID_REGION), "3.E6: FishDocks to Forest must be invalid");
    }

    // -------------------------------------------------------------------------
    // 3.E7: Mission overwrite — nonce increments, MissionInterrupted emitted
    // -------------------------------------------------------------------------

    function test_phase3E7_missionOverwrite_nonceIncrements_interruptedEmitted() public {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        // Submit first mission → nonce 1
        OrderResult[] memory r1 = _submitOrder(clanId, csId, ClanWorldConstants.REGION_FOREST, ActionType.ChopWood);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "3.E7: first order must succeed");
        assertEq(r1[0].missionNonce, 1, "3.E7: first mission nonce must be 1");

        // Wait for cooldown
        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS + 1);

        // Expect MissionInterrupted(clanId, csId, oldNonce=1, newNonce=2) before second submit
        vm.expectEmit(true, true, false, true);
        emit IClanWorldEvents.MissionInterrupted(clanId, csId, 1, 2);

        // Submit second mission → interrupts first, nonce 2
        OrderResult[] memory r2 = _submitOrder(clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);
        assertEq(uint8(r2[0].status), uint8(StatusCode.OK), "3.E7: interrupt order must succeed");
        assertEq(r2[0].missionNonce, 2, "3.E7: second mission nonce must be 2");

        // Active mission must have nonce 2
        Mission memory m = world.getActiveMission(csId);
        assertTrue(m.active, "3.E7: mission must be active");
        assertEq(m.nonce, 2, "3.E7: active mission nonce must be 2");
    }

    // =========================================================================
    // Phase 3.2 Lazy Settlement Engine Tests
    // =========================================================================

    // Helper: harness-based setup for Path 6 and other tests needing killClansman
    function _setupHarness() internal returns (ClanWorldTestHarness harness, uint32 clanId, uint32 csId) {
        harness = new ClanWorldTestHarness();
        vm.prank(elder);
        (clanId,) = harness.mintClan(elder);
        csId = harness.getClanFullView(clanId).clansmen[0].clansman.clansman.clansmanId;
    }

    // Helper: submit an order on a harness-based world
    function _submitOrderHarness(
        ClanWorldTestHarness harness,
        uint32 clanId,
        uint32 csId,
        uint8 gotoRegion,
        ActionType action
    ) internal returns (OrderResult[] memory) {
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
        return harness.submitClanOrders(clanId, orders);
    }

    // Helper: advance tick on a harness-based world
    function _advanceTickHarness(ClanWorldTestHarness harness) internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        harness.heartbeat();
    }

    // -------------------------------------------------------------------------
    // test_lazySettle_path1_noopBeforeArrival
    // Path 1: TRAVELING, currentTick < arrivalTick → no-op
    // -------------------------------------------------------------------------

    function test_lazySettle_path1_noopBeforeArrival() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;
        uint8 homeRegion = v.clan.clan.baseRegion; // Forest (region 1) for first clan

        // Travel from Forest(1) to Mountains(2) is 1 tick — clansman starts TRAVELING
        (uint8 travelTicks,) = world.quoteTravel(homeRegion, ClanWorldConstants.REGION_MOUNTAINS);
        assertGt(travelTicks, 0, "path1: need travel > 0 ticks");

        OrderResult[] memory r = _submitOrder(clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK));

        // Clansman should be TRAVELING before arrival
        Clansman memory csNow = world.getClansman(csId);
        assertEq(uint8(csNow.state), uint8(ClansmanState.TRAVELING), "path1: should be TRAVELING after submission");
        assertTrue(world.getActiveMission(csId).active, "path1: mission should be active");

        // Call settleClansman without advancing any ticks (same tick as submission)
        world.settleClansman(csId);

        // State must be unchanged — still TRAVELING, no iron
        Clansman memory csAfter = world.getClansman(csId);
        assertEq(
            uint8(csAfter.state), uint8(ClansmanState.TRAVELING), "path1: must still be TRAVELING (no ticks passed)"
        );
        assertEq(csAfter.carryIron, 0, "path1: no iron gathered (haven't arrived)");
    }

    // -------------------------------------------------------------------------
    // test_lazySettle_path2_arrivalTransition
    // Path 2: TRAVELING → ACTING at arrivalTick
    // -------------------------------------------------------------------------

    function test_lazySettle_path2_arrivalTransition() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;
        uint8 homeRegion = v.clan.clan.baseRegion;

        // Travel Forest(1) → Mountains(2) = 1 tick
        (uint8 travelTicks,) = world.quoteTravel(homeRegion, ClanWorldConstants.REGION_MOUNTAINS);
        assertGt(travelTicks, 0, "path2: need travel > 0 ticks");

        _submitOrder(clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);

        // arrivalTick = currentTick + travelTicks. Settlement processes [lastSettledTick, currentTick).
        // To include arrivalTick in the settled range we need currentTick > arrivalTick,
        // i.e. currentTick >= arrivalTick + 1, so advance travelTicks + 1 ticks.
        for (uint256 i = 0; i < uint256(travelTicks) + 1; i++) {
            _advanceTick();
        }

        // Call settleClansman on-demand
        world.settleClansman(csId);

        // Clansman should have transitioned to ACTING at the target region
        Clansman memory csAfter = world.getClansman(csId);
        assertEq(uint8(csAfter.state), uint8(ClansmanState.ACTING), "path2: must be ACTING after arrival");
        assertEq(csAfter.currentRegion, ClanWorldConstants.REGION_MOUNTAINS, "path2: currentRegion must be Mountains");
    }

    // -------------------------------------------------------------------------
    // test_lazySettle_path3_settleOnCompletion
    // Path 3: ACTING + tick >= settlesAtTick → resolves action
    // -------------------------------------------------------------------------

    function test_lazySettle_path3_settleOnCompletion() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;
        uint8 homeRegion = v.clan.clan.baseRegion;

        (uint8 travelTicks,) = world.quoteTravel(homeRegion, ClanWorldConstants.REGION_MOUNTAINS);
        _submitOrder(clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);

        // Advance through travel and the four-tick mining duration.
        for (uint256 i = 0; i < uint256(travelTicks) + world.getActionDuration(ActionType.MineIron) + 1; i++) {
            _advanceTick();
        }

        // settleClan triggers the full settlement path
        world.settleClan(clanId);

        // Clansman should have mined some iron
        Clansman memory csAfter = world.getClansman(csId);
        assertGt(csAfter.carryIron, 0, "path3: clansman should have gathered iron after action resolved");
    }

    // -------------------------------------------------------------------------
    // test_lazySettle_path4_missionOverwrite
    // Path 4: mission overwrite mid-flight — old mission gone, new mission executes
    // -------------------------------------------------------------------------

    function test_lazySettle_path4_missionOverwrite() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;
        uint8 homeRegion = v.clan.clan.baseRegion;

        // Submit mission 1: FishDocks to EastDocks (region 7) — from Forest homebase, that's
        // 4 ticks of travel (Forest→Mountains→UnicornTown→EastFarms→EastDocks), ensuring the
        // clansman is still TRAVELING when interrupted after just 1 tick.
        (uint8 travelTicks1,) = world.quoteTravel(homeRegion, ClanWorldConstants.REGION_EAST_DOCKS);
        assertGt(travelTicks1, 1, "path4: first mission needs > 1 tick travel so it stays TRAVELING after 1 tick");

        OrderResult[] memory r1 = _submitOrder(clanId, csId, ClanWorldConstants.REGION_EAST_DOCKS, ActionType.FishDocks);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "path4: first order must succeed");
        uint64 nonce1 = r1[0].missionNonce;
        assertEq(nonce1, 1, "path4: first nonce must be 1");

        // Advance only 1 tick — first mission still TRAVELING (arrivalTick is 4 ticks away)
        // Wait for cooldown and advance 1 tick, then interrupt
        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS + 1);
        _advanceTick();

        // Confirm clansman is still TRAVELING (hasn't reached EastDocks yet)
        assertEq(
            uint8(world.getClansman(csId).state),
            uint8(ClansmanState.TRAVELING),
            "path4: must still be TRAVELING before interrupt"
        );

        // Overwrite with MineIron to Mountains
        OrderResult[] memory r2 = _submitOrder(clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);
        assertEq(uint8(r2[0].status), uint8(StatusCode.OK), "path4: interrupt order must succeed");
        uint64 nonce2 = r2[0].missionNonce;
        assertEq(nonce2, 2, "path4: second nonce must be 2");

        // Active mission must now be MineIron (nonce 2)
        Mission memory m = world.getActiveMission(csId);
        assertTrue(m.active, "path4: mission must be active");
        assertEq(m.nonce, 2, "path4: active mission nonce must be 2");
        assertEq(uint8(m.action), uint8(ActionType.MineIron), "path4: active mission action must be MineIron");

        // Advance until new mission resolves (from current position after 1 tick)
        // clansman was re-tasked from its current region; compute remaining travel
        uint8 csRegionNow = world.getClansman(csId).currentRegion;
        (uint8 travelToMountains,) = world.quoteTravel(csRegionNow, ClanWorldConstants.REGION_MOUNTAINS);
        for (uint256 i = 0; i < uint256(travelToMountains) + world.getActionDuration(ActionType.MineIron) + 1; i++) {
            _advanceTick();
        }
        world.settleClan(clanId);

        // Must have iron (new mission executed), must have NO fish (old mission never arrived)
        Clansman memory csAfter = world.getClansman(csId);
        assertGt(csAfter.carryIron, 0, "path4: new mission (MineIron) should have executed");
        assertEq(csAfter.carryFish, 0, "path4: old mission (FishDocks) must not have executed (clansman never arrived)");
    }

    // -------------------------------------------------------------------------
    // test_lazySettle_path5_defendBaseNeverSettles
    // Path 5: DefendBase → clansman stays ACTING indefinitely, mission stays active
    // -------------------------------------------------------------------------

    function test_lazySettle_path5_defendBaseNeverSettles() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;
        uint8 baseRegion = v.clan.clan.baseRegion;

        // Submit DefendBase to own clan's base (zero travel)
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: baseRegion,
            action: ActionType.DefendBase,
            targetClanId: clanId,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
        vm.prank(elder);
        OrderResult[] memory r = world.submitClanOrders(clanId, orders);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "path5: DefendBase order must succeed");

        // Advance 5 ticks and settle
        for (uint256 i = 0; i < 5; i++) {
            _advanceTick();
        }
        world.settleClan(clanId);

        // Clansman must still be ACTING (DefendBase never completes the mission)
        Clansman memory csAfter = world.getClansman(csId);
        assertEq(uint8(csAfter.state), uint8(ClansmanState.ACTING), "path5: DefendBase clansman must stay ACTING");
        assertTrue(world.getActiveMission(csId).active, "path5: DefendBase mission must stay active");
    }

    // -------------------------------------------------------------------------
    // test_lazySettle_path6_deadClansmanMidMission
    // Path 6: dead clansman mid-mission → mission invalidated
    // -------------------------------------------------------------------------

    function test_lazySettle_path6_deadClansmanMidMission() public {
        (ClanWorldTestHarness harness, uint32 clanId, uint32 csId) = _setupHarness();
        uint8 homeRegion = harness.getClanFullView(clanId).clan.clan.baseRegion;

        // Submit ChopWood to a region that requires travel (so clansman is TRAVELING)
        // From Forest homebase, go to Mountains (1 tick travel)
        (uint8 travelTicks,) = harness.quoteTravel(homeRegion, ClanWorldConstants.REGION_MOUNTAINS);
        assertGt(travelTicks, 0, "path6: need travel > 0 so clansman is TRAVELING when killed");

        OrderResult[] memory r =
            _submitOrderHarness(harness, clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "path6: order must succeed");
        assertTrue(harness.getActiveMission(csId).active, "path6: mission must be active before kill");

        // Kill clansman while it's mid-mission (TRAVELING)
        harness.killClansman(csId);
        assertEq(uint8(harness.getClansman(csId).state), uint8(ClansmanState.DEAD), "path6: clansman must be DEAD");

        // Settle the clan — should trigger path 6 handling
        _advanceTickHarness(harness);
        harness.settleClan(clanId);

        // Mission must be invalidated (active = false)
        Mission memory m = harness.getActiveMission(csId);
        assertFalse(m.active, "path6: mission must be inactive after clansman died");

        // Clansman must still be DEAD (no resurrection)
        assertEq(uint8(harness.getClansman(csId).state), uint8(ClansmanState.DEAD), "path6: clansman must remain DEAD");
    }

    // -------------------------------------------------------------------------
    // test_lazySettle_path6_deadDefender_cleanedFromRegistry
    // Path 6 + DefendBase: dead defending clansman must be removed from registry
    // -------------------------------------------------------------------------

    function test_lazySettle_path6_deadDefender_cleanedFromRegistry() public {
        (ClanWorldTestHarness harness, uint32 clanId, uint32 csId) = _setupHarness();
        uint8 baseRegion = harness.getClanFullView(clanId).clan.clan.baseRegion;

        // Submit DefendBase to own base (zero travel → immediately registered)
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: baseRegion,
            action: ActionType.DefendBase,
            targetClanId: clanId,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });
        vm.prank(elder);
        OrderResult[] memory r = harness.submitClanOrders(clanId, orders);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "path6-defender: DefendBase order must succeed");

        // Confirm clansman is registered as a defender
        uint32[] memory defs = harness.getActiveDefenders(clanId);
        assertEq(defs.length, 1, "path6-defender: should have 1 defender before kill");

        // Kill the clansman
        harness.killClansman(csId);
        assertEq(
            uint8(harness.getClansman(csId).state), uint8(ClansmanState.DEAD), "path6-defender: clansman must be DEAD"
        );

        // Settle the clan — triggers Path 6, should remove from registry
        _advanceTickHarness(harness);
        harness.settleClan(clanId);

        // Defender must be removed from registry
        uint32[] memory defsAfter = harness.getActiveDefenders(clanId);
        assertEq(defsAfter.length, 0, "path6-defender: dead defender must be removed from registry");

        // Mission must be inactive
        assertFalse(harness.getActiveMission(csId).active, "path6-defender: mission must be inactive");
    }

    // -------------------------------------------------------------------------
    // test_lazySettle_settleClansman_onDemand
    // settleClansman settles a single clansman without settleClan
    // -------------------------------------------------------------------------

    function test_lazySettle_settleClansman_onDemand() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;
        uint8 homeRegion = v.clan.clan.baseRegion;

        // Submit MineIron — requires travel to Mountains
        (uint8 travelTicks,) = world.quoteTravel(homeRegion, ClanWorldConstants.REGION_MOUNTAINS);
        _submitOrder(clanId, csId, ClanWorldConstants.REGION_MOUNTAINS, ActionType.MineIron);

        // Advance through travel and the four-tick mining duration WITHOUT calling settleClan.
        for (uint256 i = 0; i < uint256(travelTicks) + world.getActionDuration(ActionType.MineIron) + 1; i++) {
            _advanceTick();
        }

        // Phase 4.2: heartbeat eagerly settles missions at settlesAtTick (step 1 of heartbeat).
        // carryIron is already > 0 after tick advancement — no manual settleClansman required.
        assertGt(world.getClansman(csId).carryIron, 0, "onDemand: heartbeat settled mission at settlesAtTick");

        // Call settleClansman on-demand — must be idempotent (no crash, no double-credit).
        uint256 ironBefore = world.getClansman(csId).carryIron;
        world.settleClansman(csId);
        assertEq(
            world.getClansman(csId).carryIron,
            ironBefore,
            "onDemand: settleClansman is idempotent after heartbeat settle"
        );
    }

    // -------------------------------------------------------------------------
    // test_lazySettle_settleClansman_noopIfUpToDate
    // settleClansman is a no-op when clan is already settled
    // -------------------------------------------------------------------------

    function test_lazySettle_settleClansman_noopIfUpToDate() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);
        uint32 csId = v.clansmen[0].clansman.clansman.clansmanId;

        // No ticks advanced — clan is already up to date
        // settleClansman must not revert and must leave state unchanged
        world.settleClansman(csId);

        Clansman memory csAfter = world.getClansman(csId);
        assertEq(uint8(csAfter.state), uint8(ClansmanState.WAITING), "noop: state must be unchanged");
        assertEq(csAfter.carryIron, 0, "noop: carryIron must be 0");
        assertEq(csAfter.carryWood, 0, "noop: carryWood must be 0");
    }

    // -------------------------------------------------------------------------
    // 3.E8: Partial batch — mixed results across 4 orders
    // -------------------------------------------------------------------------

    function test_phase3E8_partialBatch_mixedResults() public {
        uint32 clanId = _mintClan();
        ClanFullView memory v = world.getClanFullView(clanId);

        uint32 cs0 = v.clansmen[0].clansman.clansman.clansmanId;
        uint32 cs1 = v.clansmen[1].clansman.clansman.clansmanId;
        uint32 cs2 = v.clansmen[2].clansman.clansman.clansmanId;

        ClanOrder[] memory orders = new ClanOrder[](4);

        // Order 0: valid — cs0 ChopWood to Forest
        orders[0] = ClanOrder({
            clansmanId: cs0,
            gotoRegion: ClanWorldConstants.REGION_FOREST,
            action: ActionType.ChopWood,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });

        // Order 1: invalid clansmanId 9999
        orders[1] = ClanOrder({
            clansmanId: 9999,
            gotoRegion: ClanWorldConstants.REGION_FOREST,
            action: ActionType.ChopWood,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });

        // Order 2: valid — cs1 Wait at homebase (NOOP)
        orders[2] = ClanOrder({
            clansmanId: cs1,
            gotoRegion: ClanWorldConstants.REGION_NOOP,
            action: ActionType.Wait,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });

        // Order 3: invalid — cs2 ChopWood to Mountains (wrong region for ChopWood)
        orders[3] = ClanOrder({
            clansmanId: cs2,
            gotoRegion: ClanWorldConstants.REGION_MOUNTAINS,
            action: ActionType.ChopWood,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });

        vm.prank(elder);
        OrderResult[] memory results = world.submitClanOrders(clanId, orders);

        assertEq(results.length, 4, "3.E8: must return 4 results");
        assertEq(uint8(results[0].status), uint8(StatusCode.OK), "3.E8: order[0] must be OK");
        assertEq(
            uint8(results[1].status),
            uint8(StatusCode.ERR_INVALID_CLANSMAN),
            "3.E8: order[1] must be ERR_INVALID_CLANSMAN"
        );
        assertEq(uint8(results[2].status), uint8(StatusCode.OK), "3.E8: order[2] must be OK");
        assertEq(
            uint8(results[3].status), uint8(StatusCode.ERR_INVALID_REGION), "3.E8: order[3] must be ERR_INVALID_REGION"
        );
    }

    // =====================================================================
    // Phase 4.4 — season + winter timer tests
    // =====================================================================

    function test_season_initialState() public {
        WorldState memory ws = world.getWorldState();
        assertEq(ws.currentSeasonNumber, 1, "season starts at 1");
        assertEq(ws.seasonStartTick, 0);
        assertEq(ws.seasonEndTick, ClanWorldConstants.SEASON_DURATION_TICKS);
        assertEq(
            ws.winterStartsAtTick, ClanWorldConstants.TICKS_PER_WINTER_CYCLE - ClanWorldConstants.WINTER_DURATION_TICKS
        );
        assertFalse(ws.winterActive);
    }

    function test_winter_onset() public {
        // winterStartsAtTick = 100; WinterStarted fires on the heartbeat that opens tick 100
        // i.e. when closedTick=99, newTick=100 >= winterStartsAtTick=100.
        // Advance 99 heartbeats so currentTick=99, then one more heartbeat fires WinterStarted at tick 100.
        uint64 winterStart = ClanWorldConstants.TICKS_PER_WINTER_CYCLE - ClanWorldConstants.WINTER_DURATION_TICKS; // = 100
        for (uint64 i = 0; i < winterStart - 1; i++) {
            vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
            world.heartbeat();
        }
        // currentTick == 99; next heartbeat opens tick 100 and should emit WinterStarted(100)
        vm.recordLogs();
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 winterSig = keccak256("WinterStarted(uint64)");
        bool foundWinterStarted = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == winterSig) {
                foundWinterStarted = true;
                break;
            }
        }
        assertTrue(foundWinterStarted, "WinterStarted event should have been emitted at tick 100");
        assertTrue(world.getWorldState().winterActive, "winter should be active");
        assertEq(world.getWorldState().currentTick, winterStart, "currentTick should be 100");
    }

    function test_winter_end_and_next_cycle() public {
        // Advance past first winter end tick (= 110)
        uint64 winterEnd = ClanWorldConstants.TICKS_PER_WINTER_CYCLE; // = 110
        for (uint64 i = 0; i <= winterEnd; i++) {
            vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
            world.heartbeat();
        }
        WorldState memory ws = world.getWorldState();
        assertFalse(ws.winterActive, "winter should be over");
        // next winter at [210, 220)
        assertEq(
            ws.winterStartsAtTick,
            ClanWorldConstants.TICKS_PER_WINTER_CYCLE * 2 - ClanWorldConstants.WINTER_DURATION_TICKS
        );
    }

    function test_season_transition() public {
        // Advance SEASON_DURATION_TICKS heartbeats to cross season boundary
        for (uint256 i = 0; i < ClanWorldConstants.SEASON_DURATION_TICKS; i++) {
            vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
            world.heartbeat();
        }
        WorldState memory ws = world.getWorldState();
        assertEq(ws.currentSeasonNumber, 2, "season number should increment");
        assertEq(ws.seasonStartTick, ClanWorldConstants.SEASON_DURATION_TICKS);
        assertEq(ws.seasonEndTick, ClanWorldConstants.SEASON_DURATION_TICKS * 2);
        // winter reset for new season
        uint64 expectedWinterStart = ClanWorldConstants.SEASON_DURATION_TICKS
            + ClanWorldConstants.TICKS_PER_WINTER_CYCLE - ClanWorldConstants.WINTER_DURATION_TICKS;
        assertEq(ws.winterStartsAtTick, expectedWinterStart);
    }

    function test_nextHeartbeatAtTick_tracks_tick() public {
        WorldState memory ws0 = world.getWorldState();
        assertEq(ws0.nextHeartbeatAtTick, 1, "before first heartbeat, next = tick 1");
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
        WorldState memory ws1 = world.getWorldState();
        assertEq(ws1.currentTick, 1);
        assertEq(ws1.nextHeartbeatAtTick, 2, "after tick 1, next = tick 2");
    }
}
