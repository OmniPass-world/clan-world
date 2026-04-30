// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {MinimalERC20} from "../src/MinimalERC20.sol";
import {StubPool} from "../src/StubPool.sol";
import {
    IClanWorld,
    ClanWorldConstants,
    ActionType,
    StatusCode,
    ClanOrder,
    WithdrawResourcesData,
    OrderResult,
    Mission,
    PoolSeedConfig
} from "../src/IClanWorld.sol";

contract MockReentrantPool {
    address public immutable TOKEN_A;
    address public immutable TOKEN_B;
    address public immutable ENGINE;

    uint256 public reserveA;
    uint256 public reserveB;
    bool public sawReentrantGuard;
    bytes public lastRevertData;

    bool private _seeded;

    modifier onlyEngine() {
        require(msg.sender == ENGINE, "MockReentrantPool: only engine");
        _;
    }

    constructor(address tokenA_, address tokenB_, address engine_) {
        TOKEN_A = tokenA_;
        TOKEN_B = tokenB_;
        ENGINE = engine_;
    }

    function seed(uint256 amountA, uint256 amountB) external onlyEngine {
        require(!_seeded, "MockReentrantPool: already seeded");
        require(amountA > 0 && amountB > 0, "MockReentrantPool: zero seed");
        reserveA = amountA;
        reserveB = amountB;
        _seeded = true;
    }

    function sellResource(uint256 amountIn) external onlyEngine returns (uint256 goldOut) {
        _attemptHeartbeatReentry();

        require(amountIn > 0, "MockReentrantPool: zero amount");
        require(reserveA > 0 && reserveB > 0, "MockReentrantPool: not seeded");
        goldOut = (reserveB * amountIn) / (reserveA + amountIn);
        require(goldOut > 0, "MockReentrantPool: zero output");
        reserveA += amountIn;
        reserveB -= goldOut;
    }

    function quoteBuy(uint256 amountOut) external view returns (uint256 goldIn) {
        require(amountOut > 0, "MockReentrantPool: zero amount");
        require(amountOut < reserveA, "MockReentrantPool: insufficient resource reserve");
        uint256 num = reserveB * amountOut;
        uint256 denom = reserveA - amountOut;
        goldIn = num / denom + (num % denom == 0 ? 0 : 1);
    }

    function buyResource(uint256 amountOut) external onlyEngine returns (uint256 goldIn) {
        require(amountOut > 0, "MockReentrantPool: zero amount");
        require(amountOut < reserveA, "MockReentrantPool: insufficient resource reserve");
        require(reserveB > 0, "MockReentrantPool: not seeded");
        uint256 num = reserveB * amountOut;
        uint256 denom = reserveA - amountOut;
        goldIn = num / denom + (num % denom == 0 ? 0 : 1);
        reserveA -= amountOut;
        reserveB += goldIn;
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }

    function _attemptHeartbeatReentry() internal {
        try IClanWorld(ENGINE).heartbeat() {
            revert("MockReentrantPool: heartbeat reentry succeeded");
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == keccak256(bytes("ClanWorld: reentrant call"))) {
                sawReentrantGuard = true;
            }
        } catch (bytes memory data) {
            lastRevertData = data;
        }
    }
}

contract ClanWorldReentrantHarness is ClanWorld {
    function setCarryWood(uint32 csId, uint256 amount) external {
        _clansmen[csId].carryWood = amount;
    }
}

contract ReentrancyTest is Test {
    ClanWorldReentrantHarness world;
    address elder = address(0xA1);

    MinimalERC20 woodToken;
    MinimalERC20 ironToken;
    MinimalERC20 wheatToken;
    MinimalERC20 fishToken;
    MinimalERC20 goldToken;
    MinimalERC20 blueprintToken;
    MockReentrantPool woodPool;
    StubPool ironPool;
    StubPool wheatPool;
    StubPool fishPool;

    function setUp() public {
        world = new ClanWorldReentrantHarness();
    }

    function test_marketPoolHeartbeatCallback_revertsWithReentrancyGuard() public {
        _setupReentrantMarket();
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);
        // Give clansman carry wood so the scheduled sell has something to sell
        world.setCarryWood(csId, 10e18);

        uint256 goldBefore = world.getClan(clanId).goldBalance;

        OrderResult[] memory results = _submitMarketSell(clanId, csId, address(woodToken), 5e18);
        assertEq(uint8(results[0].status), uint8(StatusCode.OK), "market sell should enqueue");

        Mission memory mission = world.getActiveMission(csId);
        uint64 currentTick = world.getWorldState().currentTick;
        uint256 ticksNeeded = uint256(mission.settlesAtTick - currentTick) + 1;
        for (uint256 i = 0; i < ticksNeeded; i++) {
            _advanceTick();
        }

        assertTrue(woodPool.sawReentrantGuard(), "pool callback should receive reentrant guard revert");
        assertEq(woodPool.lastRevertData().length, 0, "callback should catch the string guard revert");
        assertGt(world.getClan(clanId).goldBalance, goldBefore, "heartbeat should finish original market action");
    }

    function _setupReentrantMarket() internal {
        woodToken = new MinimalERC20("Wood", "WOOD");
        ironToken = new MinimalERC20("Iron", "IRON");
        wheatToken = new MinimalERC20("Wheat", "WHEAT");
        fishToken = new MinimalERC20("Fish", "FISH");
        goldToken = new MinimalERC20("Gold", "GOLD");
        blueprintToken = new MinimalERC20("BPRT", "BPRT");

        address engine = address(world);
        woodPool = new MockReentrantPool(address(woodToken), address(goldToken), engine);
        ironPool = new StubPool(address(ironToken), address(goldToken), engine);
        wheatPool = new StubPool(address(wheatToken), address(goldToken), engine);
        fishPool = new StubPool(address(fishToken), address(goldToken), engine);

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

        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
        uint256 totalGoldSeed = goldSeed * 4;

        woodToken.seedTreasury(address(this), resSeed);
        wheatToken.seedTreasury(address(this), resSeed);
        fishToken.seedTreasury(address(this), resSeed);
        ironToken.seedTreasury(address(this), resSeed);
        goldToken.seedTreasury(address(this), totalGoldSeed);

        woodToken.approve(address(world), resSeed);
        wheatToken.approve(address(world), resSeed);
        fishToken.approve(address(world), resSeed);
        ironToken.approve(address(world), resSeed);
        goldToken.approve(address(world), totalGoldSeed);

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

    function _advanceTick() internal {
        vm.warp(world.getWorldState().nextHeartbeatAtTs);
        world.heartbeat();
    }

    function _mintClan() internal returns (uint32 clanId) {
        vm.prank(elder);
        (clanId,) = world.mintClan(elder);
    }

    function _firstCs(uint32 clanId) internal view returns (uint32) {
        return world.getClanFullView(clanId).clansmen[0].clansman.clansman.clansmanId;
    }

    function _submitMarketSell(uint32 clanId, uint32 csId, address token, uint256 amount)
        internal
        returns (OrderResult[] memory)
    {
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: ClanWorldConstants.REGION_UNICORN_TOWN,
            action: ActionType.MarketSell,
            targetClanId: 0,
            marketToken: token,
            marketAmount: amount,
            maxGoldIn: 0,
            withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
        });
        vm.prank(elder);
        return world.submitClanOrders(clanId, orders);
    }
}
