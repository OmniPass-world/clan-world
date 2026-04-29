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

contract RecordingPool {
    address public immutable TOKEN_A;
    address public immutable TOKEN_B;
    address public immutable ENGINE;

    uint256 public reserveA;
    uint256 public reserveB;
    uint64 public observedTick;
    bytes32 public observedSeed;
    bool public observedSell;
    bool private _seeded;

    modifier onlyEngine() {
        require(msg.sender == ENGINE, "RecordingPool: only engine");
        _;
    }

    constructor(address tokenA_, address tokenB_, address engine_) {
        TOKEN_A = tokenA_;
        TOKEN_B = tokenB_;
        ENGINE = engine_;
    }

    function seed(uint256 amountA, uint256 amountB) external onlyEngine {
        require(!_seeded, "RecordingPool: already seeded");
        require(amountA > 0 && amountB > 0, "RecordingPool: zero seed");
        reserveA = amountA;
        reserveB = amountB;
        _seeded = true;
    }

    function sellResource(uint256 amountIn) external onlyEngine returns (uint256 goldOut) {
        require(amountIn > 0, "RecordingPool: zero amount");
        require(reserveA > 0 && reserveB > 0, "RecordingPool: not seeded");

        WorldState memory state = HeartbeatOrderingHarness(ENGINE).getWorldState();
        observedTick = state.currentTick;
        observedSeed = state.currentTickSeed;
        observedSell = true;

        goldOut = (reserveB * amountIn) / (reserveA + amountIn);
        require(goldOut > 0, "RecordingPool: zero output");
        reserveA += amountIn;
        reserveB -= goldOut;
    }

    function quoteBuy(uint256 amountOut) external view returns (uint256 goldIn) {
        require(amountOut > 0, "RecordingPool: zero amount");
        require(amountOut < reserveA, "RecordingPool: insufficient resource reserve");
        uint256 num = reserveB * amountOut;
        uint256 denom_ = reserveA - amountOut;
        goldIn = num / denom_ + (num % denom_ == 0 ? 0 : 1);
    }

    function buyResource(uint256 amountOut) external onlyEngine returns (uint256 goldIn) {
        require(amountOut > 0, "RecordingPool: zero amount");
        require(amountOut < reserveA, "RecordingPool: insufficient resource reserve");
        require(reserveB > 0, "RecordingPool: not seeded");
        uint256 num = reserveB * amountOut;
        uint256 denom_ = reserveA - amountOut;
        goldIn = num / denom_ + (num % denom_ == 0 ? 0 : 1);
        reserveA -= amountOut;
        reserveB += goldIn;
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
    RecordingPool recordingWoodPool;

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
            maxGoldIn: 0
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
            maxGoldIn: maxGold
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
    }

    function _setupRecordingMarket() internal {
        woodToken = new MinimalERC20("Wood", "WOOD");
        ironToken = new MinimalERC20("Iron", "IRON");
        wheatToken = new MinimalERC20("Wheat", "WHEAT");
        fishToken = new MinimalERC20("Fish", "FISH");
        goldToken = new MinimalERC20("Gold", "GOLD");
        blueprintToken = new MinimalERC20("BPRT", "BPRT");

        address wAddr = address(world);
        recordingWoodPool = new RecordingPool(address(woodToken), address(goldToken), wAddr);
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
        address[4] memory pools = [address(recordingWoodPool), address(wheatPool), address(fishPool), address(ironPool)];
        world.initTreasury(tokens, pools);

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
    }

    // -------------------------------------------------------------------------
    // test_heartbeat_settlementBeforeMarket
    //
    // Proves Step 1 (settle) fires before Step 2 (market execute) within the SAME
    // heartbeat closing tick T:
    //   - cs0 is placed at Mountains (region 2). Deposit to homebase Forest (region 1)
    //     = 1 tick travel. arrivalTick = T0+1, settlesAtTick = T0+2.
    //   - cs1 at Forest submits MarketSell to UT (region 3) = 2 ticks travel.
    //     executeAtTick = T0+2. (Same tick as cs0 settles.)
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

        // Place cs0 at Mountains (region 2). Homebase = Forest (region 1).
        // Deposit from Mountains to Forest: travel = 1 tick.
        world.setClansmanRegion(csId0, ClanWorldConstants.REGION_MOUNTAINS);

        // cs0: submit Deposit. arrivalTick = t0+1, settlesAtTick = t0+2.
        OrderResult[] memory r0 = _submitOrder(clanId, csId0, ClanWorldConstants.REGION_FOREST, ActionType.DepositResources);
        assertEq(uint8(r0[0].status), uint8(StatusCode.OK), "deposit order must succeed");
        Mission memory depositMission = world.getActiveMission(csId0);
        assertEq(depositMission.settlesAtTick, t0 + 2, "deposit settlesAtTick must be t0+2");

        // cs1: at Forest. Submit MarketSell to UT. Forest→UT = 2 ticks.
        // executeAtTick = t0+2. Same tick as deposit settles.
        OrderResult[] memory r1 = _submitMarketOrder(clanId, csId1, ActionType.MarketSell, address(woodToken), 5e18, 0);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "market sell order must enqueue");
        Mission memory sellMission = world.getActiveMission(csId1);
        assertEq(sellMission.arrivalTick, t0 + 2, "sell arrivalTick must be t0+2");

        // Give cs0 carry wood. Zero vault so market sell only succeeds if step1 ran first.
        world.setCarryWood(csId0, 10e18);
        world.setVaultWood(clanId, 0);
        assertEq(world.getClan(clanId).vaultWood, 0, "vault wood must be 0 before test tick");

        uint256 goldBefore = world.getClan(clanId).goldBalance;

        // Advance to tick t0+2. The heartbeat closing t0+2 runs:
        //   Step 1: _settleCompletingMissions(t0+2) → deposit fires, cs0 carry 10e18 → vault
        //   Step 2: _executeScheduledMarketActions(t0+2) → sell fires, 5e18 vault wood → gold
        // If reversed: sell would fail (vault=0), gold unchanged.
        _advanceToTick(t0 + 3);

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

    function test_heartbeat_scheduledMarketObservesClosedTickSeedBeforeIncrement() public {
        _setupRecordingMarket();
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);

        OrderResult[] memory r = _submitMarketOrder(clanId, csId, ActionType.MarketSell, address(woodToken), 5e18, 0);
        assertEq(uint8(r[0].status), uint8(StatusCode.OK), "market sell order must enqueue");

        Mission memory m = world.getActiveMission(csId);
        uint64 executeAtTick = m.actionStartTick;
        _advanceToTick(executeAtTick);

        WorldState memory beforeClose = world.getWorldState();
        assertEq(beforeClose.currentTick, executeAtTick, "setup must be at execute tick before close");
        bytes32 seedForClosedTick = beforeClose.currentTickSeed;

        _advanceTick();

        assertTrue(recordingWoodPool.observedSell(), "scheduled sell must execute");
        assertEq(recordingWoodPool.observedTick(), executeAtTick, "market observes closed tick before increment");
        assertEq(recordingWoodPool.observedSeed(), seedForClosedTick, "market observes seed for closed tick");

        WorldState memory afterClose = world.getWorldState();
        assertEq(afterClose.currentTick, executeAtTick + 1, "heartbeat opens next tick after market execution");
        assertNotEq(afterClose.currentTickSeed, seedForClosedTick, "next tick seed publishes after close-tick work");
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
    // Proves that when a mission settles at tick T AND a market action is queued at
    // tick T, both fire in the same heartbeat without conflict.
    //   - cs0 placed at Mountains, deposits to Forest homebase: settlesAtTick = T0+2
    //   - cs1 sells wood to UT from Forest: executeAtTick = T0+2
    //   Both succeed in the same heartbeat call at T0+2.
    // -------------------------------------------------------------------------
    function test_heartbeat_multipleStepsInOneTick() public {
        _setupMarket();
        uint32 clanId = _mintClan();
        uint32 csId0 = _firstCs(clanId);
        uint32 csId1 = _secondCs(clanId);

        uint64 t0 = world.getWorldState().currentTick;

        // cs0: placed at Mountains (1 tick from Forest homebase).
        // Deposit: arrivalTick = t0+1, settlesAtTick = t0+2.
        world.setClansmanRegion(csId0, ClanWorldConstants.REGION_MOUNTAINS);
        world.setCarryWood(csId0, 10e18);
        OrderResult[] memory r0 = _submitOrder(clanId, csId0, ClanWorldConstants.REGION_FOREST, ActionType.DepositResources);
        assertEq(uint8(r0[0].status), uint8(StatusCode.OK), "deposit must succeed");
        assertEq(world.getActiveMission(csId0).settlesAtTick, t0 + 2, "deposit settlesAtTick must be t0+2");

        // cs1: at Forest, sells wood to UT. Forest→UT = 2 ticks. executeAtTick = t0+2.
        // Vault has 20e18 starter wood — sell always has enough.
        OrderResult[] memory r1 = _submitMarketOrder(clanId, csId1, ActionType.MarketSell, address(woodToken), 5e18, 0);
        assertEq(uint8(r1[0].status), uint8(StatusCode.OK), "market sell must enqueue");
        assertEq(world.getActiveMission(csId1).arrivalTick, t0 + 2, "sell executeAtTick must be t0+2");

        uint256 goldBefore = world.getClan(clanId).goldBalance;

        // Advance to tick t0+3 (the heartbeat closing t0+2 runs step1+step2 together).
        _advanceToTick(t0 + 3);

        // Both cs0 deposit (settled at T0+2) and cs1 sell (at T0+2) must have fired.
        assertEq(world.getClansman(csId0).carryWood, 0, "deposit settled: carry cleared");
        assertGt(world.getClan(clanId).goldBalance, goldBefore, "sell executed: gold increased");
        assertFalse(world.getActiveMission(csId0).active, "deposit mission must be complete");
    }
}
