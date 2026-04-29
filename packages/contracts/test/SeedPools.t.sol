// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {MinimalERC20} from "../src/MinimalERC20.sol";
import {StubPool} from "../src/StubPool.sol";
import {PoolSeedConfig, ResourceType} from "../src/IClanWorld.sol";

contract SeedPoolsTest is Test {
    ClanWorld world;
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

        woodToken = new MinimalERC20("Wood", "WOOD");
        ironToken = new MinimalERC20("Iron", "IRON");
        wheatToken = new MinimalERC20("Wheat", "WHEAT");
        fishToken = new MinimalERC20("Fish", "FISH");
        goldToken = new MinimalERC20("Gold", "GOLD");
        blueprintToken = new MinimalERC20("BPRT", "BPRT");

        address engine = address(world);
        woodPool = new StubPool(address(woodToken), address(goldToken), engine);
        wheatPool = new StubPool(address(wheatToken), address(goldToken), engine);
        fishPool = new StubPool(address(fishToken), address(goldToken), engine);
        ironPool = new StubPool(address(ironToken), address(goldToken), engine);

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

        _seedTreasuryAndApprove();
        world.seedPools(_seedConfig());
    }

    function test_deploysFourPoolsAndGetterReturnsExpectedPools() public {
        assertEq(world.getPool(uint8(ResourceType.Wood)), address(woodPool), "wood pool");
        assertEq(world.getPool(uint8(ResourceType.Wheat)), address(wheatPool), "wheat pool");
        assertEq(world.getPool(uint8(ResourceType.Fish)), address(fishPool), "fish pool");
        assertEq(world.getPool(uint8(ResourceType.Iron)), address(ironPool), "iron pool");
    }

    function test_treasurySeedingTransfersExpectedPoolBalances() public {
        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();

        _assertPoolSeeded(woodToken, woodPool, resSeed, goldSeed, "wood");
        _assertPoolSeeded(wheatToken, wheatPool, resSeed, goldSeed, "wheat");
        _assertPoolSeeded(fishToken, fishPool, resSeed, goldSeed, "fish");
        _assertPoolSeeded(ironToken, ironPool, resSeed, goldSeed, "iron");
        assertEq(goldToken.balanceOf(address(this)), 0, "treasury gold fully seeded");
    }

    function test_kInvariantHoldsAfterEachSwap() public {
        uint256 kBefore = _k(woodPool);

        vm.prank(address(world));
        woodPool.swapExactInForOut(10e18, 1);
        uint256 kAfterSell = _k(woodPool);
        assertGe(kAfterSell, kBefore, "k after exact-in sell");

        vm.prank(address(world));
        woodPool.swapExactOutForInWithMaxIn(3e18, 10e18);
        uint256 kAfterBuy = _k(woodPool);
        assertGe(kAfterBuy, kAfterSell, "k after exact-out buy");
    }

    function test_pricePreviewMatchesActualSwap() public {
        uint256 amountIn = 25e18;
        uint256 preview = world.getPrice(uint8(ResourceType.Wood), amountIn);

        vm.prank(address(world));
        uint256 actual = woodPool.swapExactInForOut(amountIn, 0);

        assertEq(actual, preview, "preview should match exact-in swap");
    }

    function _seedTreasuryAndApprove() internal {
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
    }

    function _seedConfig() internal view returns (PoolSeedConfig memory) {
        uint256 resSeed = world.INITIAL_RESOURCE_POOL_SEED();
        uint256 goldSeed = world.INITIAL_GOLD_POOL_SEED();
        return PoolSeedConfig({
            woodSeed: resSeed,
            wheatSeed: resSeed,
            fishSeed: resSeed,
            ironSeed: resSeed,
            goldSeedForWood: goldSeed,
            goldSeedForWheat: goldSeed,
            goldSeedForFish: goldSeed,
            goldSeedForIron: goldSeed
        });
    }

    function _assertPoolSeeded(
        MinimalERC20 resourceToken,
        StubPool pool,
        uint256 expectedResource,
        uint256 expectedGold,
        string memory label
    ) internal view {
        (uint256 resourceReserve, uint256 goldReserve) = pool.getReserves();

        assertEq(resourceReserve, expectedResource, string.concat(label, " resource reserve"));
        assertEq(goldReserve, expectedGold, string.concat(label, " gold reserve"));
        assertEq(resourceToken.balanceOf(address(pool)), expectedResource, string.concat(label, " resource balance"));
        assertEq(goldToken.balanceOf(address(pool)), expectedGold, string.concat(label, " gold balance"));
    }

    function _k(StubPool pool) internal view returns (uint256) {
        (uint256 resourceReserve, uint256 goldReserve) = pool.getReserves();
        return resourceReserve * goldReserve;
    }
}
