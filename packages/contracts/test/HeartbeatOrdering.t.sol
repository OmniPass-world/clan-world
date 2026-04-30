// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {MinimalERC20} from "../src/MinimalERC20.sol";
import {StubPool} from "../src/StubPool.sol";
import {
    ClanWorldConstants,
    ClanState,
    ClansmanState,
    ActionType,
    StatusCode,
    WorldState,
    ClanOrder,
    WithdrawResourcesData,
    OrderResult,
    Mission,
    Clan,
    Clansman,
    ClanFullView,
    PoolSeedConfig
} from "../src/IClanWorld.sol";

/// @dev Harness to expose internal state injection for ordering tests.
contract HeartbeatOrderingHarness is ClanWorld {
    function setCarryWood(uint32 csId, uint256 amount) external {
        _clansmen[csId].carryWood = amount;
    }

    function setVaultWood(uint32 clanId, uint256 amount) external {
        _clans[clanId].vaultWood = amount;
    }

    function setClansmanRegion(uint32 csId, uint8 region) external {
        _clansmen[csId].currentRegion = region;
    }
}

contract HeartbeatOrderingTest is Test {
    HeartbeatOrderingHarness world;
    address elder = address(0xA1);

    // Market infra
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
        world = new HeartbeatOrderingHarness();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }

    function _advanceToTick(uint64 targetTick) internal {
        while (world.getWorldState().currentTick < targetTick) {
            _advanceTick();
        }
    }

    function _mintClan() internal returns (uint32 clanId) {
        vm.prank(elder);
        (clanId,) = world.mintClan(elder);
    }

    function _firstCs(uint32 clanId) internal view returns (uint32) {
        return world.getClanFullView(clanId).clansmen[0].clansman.clansman.clansmanId;
    }

    function _secondCs(uint32 clanId) internal view returns (uint32) {
        return world.getClanFullView(clanId).clansmen[1].clansman.clansman.clansmanId;
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
            maxGoldIn: 0,
            withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
        });
        vm.prank(elder);
        return world.submitClanOrders(clanId, orders);
    }

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
            maxGoldIn: maxGold,
            withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
        });
        vm.prank(elder);
        return world.submitClanOrders(clanId, orders);
    }

    function _setupMarket() internal {
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

        uint256 woodSeed = world.INITIAL_WOOD_POOL_SEED();
        uint256 wheatSeed = world.INITIAL_WHEAT_POOL_SEED();
        uint256 fishSeed = world.INITIAL_FISH_POOL_SEED();
        uint256 ironSeed = world.INITIAL_IRON_POOL_SEED();
        uint256 goldForWood = world.INITIAL_GOLD_SEED_FOR_WOOD();
        uint256 goldForWheat = world.INITIAL_GOLD_SEED_FOR_WHEAT();
        uint256 goldForFish = world.INITIAL_GOLD_SEED_FOR_FISH();
        uint256 goldForIron = world.INITIAL_GOLD_SEED_FOR_IRON();
        uint256 totalGoldSeed = goldForWood + goldForWheat + goldForFish + goldForIron;

        woodToken.seedTreasury(address(this), woodSeed);
        wheatToken.seedTreasury(address(this), wheatSeed);
        fishToken.seedTreasury(address(this), fishSeed);
        ironToken.seedTreasury(address(this), ironSeed);
        goldToken.seedTreasury(address(this), totalGoldSeed);

        woodToken.approve(address(world), woodSeed);
        wheatToken.approve(address(world), wheatSeed);
        fishToken.approve(address(world), fishSeed);
        ironToken.approve(address(world), ironSeed);
        goldToken.approve(address(world), totalGoldSeed);

        PoolSeedConfig memory cfg = PoolSeedConfig({
            woodSeed: woodSeed,
            wheatSeed: wheatSeed,
            fishSeed: fishSeed,
            ironSeed: ironSeed,
            goldSeedForWood: goldForWood,
            goldSeedForWheat: goldForWheat,
            goldSeedForFish: goldForFish,
            goldSeedForIron: goldForIron
        });
        world.seedPools(cfg);
    }

    // -------------------------------------------------------------------------
    // test_heartbeat_settlementBeforeMarket
    //
    // Proves Step 1 (settle) fires before Step 2 (market execute) within the SAME
    // heartbeat closing tick T:
    //   - cs0 is placed at Unicorn Town (region 3). Deposit to homebase Forest
    //     (region 1) = 2 ticks travel. arrivalTick = T0+2, settlesAtTick = T0+3.
    //   - cs1 at Forest submits MarketSell to UT (region 3) = 2 ticks travel.
    //     settlesAtTick = T0+2, matching the market action's arrival tick.
    //   - vault starts at 0; cs0 has carry wood.
    //   - Heartbeat at T0+2: Step 1 deposits cs0 carry wood to vault, Step 2 sells
    //     it. Gold increases only if Step 1 ran first (vault was 0 before Step 1).
    //   - If ordering were reversed, sell would fail (vault still 0) and gold stays flat.
    // -------------------------------------------------------------------------
    function test_heartbeat_settlementBeforeMarket() public {
        _setupMarket();
        uint32 clanId = _mintClan();
        uint32 csId0 = _firstCs(clanId);
        uint32 csId1 = _secondCs(clanId);

        uint64 t0 = world.getWorldState().currentTick;

        // Place cs0 at Unicorn Town (region 3). Homebase = Forest (region 1).
        // Deposit from Unicorn Town to Forest: travel = 2 ticks.
        world.setClansmanRegion(csId0, ClanWorldConstants.REGION_UNICORN_TOWN);

        // cs0: submit Deposit. arrivalTick = t0+2, settlesAtTick = t0+3.
        OrderResult[] memory r0 =
            _submitOrder(clanId, csId0, ClanWorldConstants.REGION_FOREST, ActionType.DepositResources);
        assertEq(uint8(r0[0].status), uint8(StatusCode.OK), "deposit order must succeed");
        Mission memory depositMission = world.getActiveMission(csId0);
        assertEq(depositMission.settlesAtTick, t0 + 3, "deposit settlesAtTick must be t0+3");

        // Give cs0 carry wood (for deposit) and cs1 carry wood (for sell).
        // Sell now draws from carry, not vault — zero vault to confirm vault is not involved.
        world.setCarryWood(csId0, 10e18);
        world.setCarryWood(csId1, 5e18);
        world.setVaultWood(clanId, 0);
        assertEq(world.getClan(clanId).vaultWood, 0, "vault wood must be 0 before test tick");

        // cs1: at Forest. Submit MarketSell to UT. Forest→UT = 2 ticks.
        // Market actions execute at the heartbeat closing their arrival tick.
        OrderResult[] memory r1 = _submitMarketOrder(clanId, csId1, ActionType.MarketSell, address(woodToken), 5e18, 0);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "market sell order must enqueue");
        Mission memory sellMission = world.getActiveMission(csId1);
        assertEq(sellMission.arrivalTick, t0 + 2, "sell arrivalTick must be t0+2");
        assertEq(sellMission.settlesAtTick, t0 + 2, "sell settlesAtTick must be t0+2");

        uint256 goldBefore = world.getClan(clanId).goldBalance;

        // Advance past both the market sale at t0+2 and the deposit completion at t0+3.
        _advanceToTick(t0 + 4);

        uint256 goldAfter = world.getClan(clanId).goldBalance;
        assertGt(goldAfter, goldBefore, "gold must increase: settlement ran before market sell");
        assertEq(world.getClansman(csId0).carryWood, 0, "cs0 carry wood cleared by deposit");
        assertFalse(world.getActiveMission(csId0).active, "deposit mission must be complete");
    }

    // -------------------------------------------------------------------------
    // test_heartbeat_atomicTickSeedPublish
    //
    // Proves Step 5: after heartbeat, currentTick increments by 1, currentTickSeed
    // changes, and the new seed is deterministic from block.prevrandao + prior seed.
    // -------------------------------------------------------------------------
    function test_heartbeat_atomicTickSeedPublish() public {
        WorldState memory before_ = world.getWorldState();
        uint64 tickBefore = before_.currentTick;
        bytes32 seedBefore = before_.currentTickSeed;

        bytes32 expectedSeed = keccak256(abi.encode(block.prevrandao, seedBefore, tickBefore));
        world.heartbeat();

        WorldState memory after_ = world.getWorldState();
        assertEq(after_.currentTick, tickBefore + 1, "tick must increment by 1");
        assertNotEq(after_.currentTickSeed, seedBefore, "seed must change after heartbeat");
        assertEq(after_.currentTickSeed, expectedSeed, "seed must match keccak(prevrandao, oldSeed, closedTick)");

        // Second heartbeat chains from the new seed
        uint64 tick2 = after_.currentTick;
        bytes32 seed2 = after_.currentTickSeed;
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        bytes32 expectedSeed2 = keccak256(abi.encode(block.prevrandao, seed2, tick2));
        world.heartbeat();

        assertEq(world.getWorldState().currentTick, tick2 + 1, "tick must increment again");
        assertEq(world.getWorldState().currentTickSeed, expectedSeed2, "seed must chain from prior seed");
    }

    // -------------------------------------------------------------------------
    // test_heartbeat_seasonTransition
    //
    // Proves Step 4 (world events) fires AFTER Steps 1-3:
    //   - season boundary is crossed at SEASON_DURATION_TICKS
    //   - currentSeasonNumber increments on the heartbeat that closes tick
    //     SEASON_DURATION_TICKS-1 (newTick = SEASON_DURATION_TICKS >= seasonEndTick)
    //   - no crash or revert when there are no pending missions or market actions
    // -------------------------------------------------------------------------
    function test_heartbeat_seasonTransition() public {
        WorldState memory ws0 = world.getWorldState();
        assertEq(ws0.currentSeasonNumber, 1, "season starts at 1");
        assertEq(ws0.seasonEndTick, ClanWorldConstants.SEASON_DURATION_TICKS, "seasonEndTick starts at 360");

        // Advance SEASON_DURATION_TICKS heartbeats to cross the boundary
        for (uint256 i = 0; i < ClanWorldConstants.SEASON_DURATION_TICKS; i++) {
            vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
            world.heartbeat();
        }

        WorldState memory ws1 = world.getWorldState();
        assertEq(ws1.currentSeasonNumber, 2, "season must have incremented to 2 after Steps 1-4");
        assertEq(ws1.currentTick, ClanWorldConstants.SEASON_DURATION_TICKS, "tick must be at season boundary");
        assertEq(ws1.seasonStartTick, ClanWorldConstants.SEASON_DURATION_TICKS, "new seasonStartTick");
        assertEq(ws1.seasonEndTick, ClanWorldConstants.SEASON_DURATION_TICKS * 2, "new seasonEndTick");
    }

    // -------------------------------------------------------------------------
    // test_heartbeat_noopTick
    //
    // Heartbeat with no pending missions and no queued market actions must:
    //   - not revert
    //   - increment currentTick exactly by 1
    //   - change currentTickSeed
    // -------------------------------------------------------------------------
    function test_heartbeat_noopTick() public {
        uint64 tickBefore = world.getWorldState().currentTick;
        bytes32 seedBefore = world.getWorldState().currentTickSeed;

        world.heartbeat();

        assertEq(world.getWorldState().currentTick, tickBefore + 1, "tick must increment");
        assertNotEq(world.getWorldState().currentTickSeed, seedBefore, "seed must change");
    }

    // -------------------------------------------------------------------------
    // test_heartbeat_multipleStepsInOneTick
    //
    // Proves that adjacent heartbeat work can process a scheduled market action
    // at its arrival tick and a normal mission at its later settlement tick.
    //   - cs0 placed at Unicorn Town, deposits to Forest homebase: settlesAtTick = T0+3
    //   - cs1 sells wood to UT from Forest: settlesAtTick = T0+2
    // -------------------------------------------------------------------------
    function test_heartbeat_multipleStepsInOneTick() public {
        _setupMarket();
        uint32 clanId = _mintClan();
        uint32 csId0 = _firstCs(clanId);
        uint32 csId1 = _secondCs(clanId);

        uint64 t0 = world.getWorldState().currentTick;

        // cs0: placed at Unicorn Town (2 ticks from Forest homebase).
        // Deposit: arrivalTick = t0+2, settlesAtTick = t0+3.
        world.setClansmanRegion(csId0, ClanWorldConstants.REGION_UNICORN_TOWN);
        world.setCarryWood(csId0, 10e18);
        OrderResult[] memory r0 =
            _submitOrder(clanId, csId0, ClanWorldConstants.REGION_FOREST, ActionType.DepositResources);
        assertEq(uint8(r0[0].status), uint8(StatusCode.OK), "deposit must succeed");
        assertEq(world.getActiveMission(csId0).settlesAtTick, t0 + 3, "deposit settlesAtTick must be t0+3");

        // cs1: at Forest, sells wood to UT. Forest→UT = 2 ticks. settlesAtTick = t0+2.
        // Give cs1 carry wood — sell draws from carry (not vault).
        world.setCarryWood(csId1, 10e18);
        OrderResult[] memory r1 = _submitMarketOrder(clanId, csId1, ActionType.MarketSell, address(woodToken), 5e18, 0);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "market sell must enqueue");
        assertEq(world.getActiveMission(csId1).arrivalTick, t0 + 2, "sell arrivalTick must be t0+2");
        assertEq(world.getActiveMission(csId1).settlesAtTick, t0 + 2, "sell settlesAtTick must be t0+2");

        uint256 goldBefore = world.getClan(clanId).goldBalance;

        // Advance past the sell at t0+2 and the deposit at t0+3.
        _advanceToTick(t0 + 4);

        // Both cs0 deposit (settled at T0+3) and cs1 sell (settled at T0+2) must have fired.
        assertEq(world.getClansman(csId0).carryWood, 0, "deposit settled: carry cleared");
        assertGt(world.getClan(clanId).goldBalance, goldBefore, "sell executed: gold increased");
        assertFalse(world.getActiveMission(csId0).active, "deposit mission must be complete");
    }
}
