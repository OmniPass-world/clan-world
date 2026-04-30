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
        _assertPoolSeeded(
            woodToken, woodPool, world.INITIAL_WOOD_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WOOD(), "wood"
        );
        _assertPoolSeeded(
            wheatToken, wheatPool, world.INITIAL_WHEAT_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_WHEAT(), "wheat"
        );
        _assertPoolSeeded(
            fishToken, fishPool, world.INITIAL_FISH_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_FISH(), "fish"
        );
        _assertPoolSeeded(
            ironToken, ironPool, world.INITIAL_IRON_POOL_SEED(), world.INITIAL_GOLD_SEED_FOR_IRON(), "iron"
        );
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
    }

    function _seedConfig() internal view returns (PoolSeedConfig memory) {
        return PoolSeedConfig({
            woodSeed: world.INITIAL_WOOD_POOL_SEED(),
            wheatSeed: world.INITIAL_WHEAT_POOL_SEED(),
            fishSeed: world.INITIAL_FISH_POOL_SEED(),
            ironSeed: world.INITIAL_IRON_POOL_SEED(),
            goldSeedForWood: world.INITIAL_GOLD_SEED_FOR_WOOD(),
            goldSeedForWheat: world.INITIAL_GOLD_SEED_FOR_WHEAT(),
            goldSeedForFish: world.INITIAL_GOLD_SEED_FOR_FISH(),
            goldSeedForIron: world.INITIAL_GOLD_SEED_FOR_IRON()
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
