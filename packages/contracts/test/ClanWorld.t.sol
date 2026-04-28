// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
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

contract ClanWorldTest is Test {
    ClanWorld world;
    address elder = address(0xA1);

    function setUp() public {
        world = new ClanWorld();
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

    // -------------------------------------------------------------------------
    // Test 2: tick seed changes after heartbeat
    // -------------------------------------------------------------------------

    function test_heartbeat_seedChanges() public {
        bytes32 seedBefore = world.getWorldState().currentTickSeed;
        assertEq(seedBefore, bytes32(0));

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();

        bytes32 seedAfter = world.getWorldState().currentTickSeed;
        assertTrue(seedAfter != bytes32(0), "Seed should be non-zero after heartbeat");
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

        // Advance past travel ticks + 1 action tick
        uint256 ticksToAdvance = uint256(travelTicks) + 1;
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

        // Advance past travel + 1 action tick to gather some iron
        for (uint256 i = 0; i < uint256(travelToMountains) + 1; i++) {
            _advanceTick();
        }
        world.settleClan(clanId);

        uint256 carryBefore = world.getClansman(cs0).carryIron;
        assertGt(carryBefore, 0, "cs0 should have carry iron after mining at Mountains");

        uint256 vaultBefore = world.getClan(clanId).vaultIron;

        // Wait for cs0 cooldown to expire, then send back to deposit
        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS + 1);
        _submitOrder(clanId, cs0, homeRegion, ActionType.DepositResources);

        // Advance travel back to homebase + 1 action tick
        (uint8 travelBack,) = world.quoteTravel(targetRegion, homeRegion);
        for (uint256 i = 0; i < uint256(travelBack) + 1; i++) {
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
    // Test B: submitClanOrders returns ERR_INVALID_ACTION when clan is >200 ticks behind
    // -------------------------------------------------------------------------

    function test_submitClanOrders_reverts_when_clan_too_far_behind() public {
        uint32 clanId = _mintClan();
        ClanFullView memory view_ = world.getClanFullView(clanId);
        uint32 csId = view_.clansmen[0].clansman.clansman.clansmanId;

        // Advance 201 ticks — clan is now 201 ticks behind its lastSettledTick
        for (uint256 i = 0; i < 201; i++) {
            _advanceTick();
        }

        // submitClanOrders should return ERR_INVALID_ACTION (ERR_MUST_SETTLE_FIRST proxy)
        // without reverting, for every order in the batch
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
            uint8(StatusCode.ERR_INVALID_ACTION),
            "clan >200 ticks behind must return ERR_INVALID_ACTION (settle-first guard)"
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

        uint32[] memory defs = world.getActiveDefenders(clanId);
        assertEq(defs.length, 1, "one defender registered");
        assertEq(defs[0], csId, "csId is the defender");

        // Second DefendBase to same target: zero-travel re-task — the regression case.
        vm.prank(elder);
        OrderResult[] memory r2 = world.submitClanOrders(clanId, orders);
        assertEq(uint8(r2[0].status), uint8(StatusCode.OK), "re-task DefendBase OK");

        // Defender must NOT be dropped — fix must register synchronously.
        defs = world.getActiveDefenders(clanId);
        assertEq(defs.length, 1, "defender count must not drop after re-task");
        assertEq(defs[0], csId, "csId must still be defending after re-task");
    }
}
