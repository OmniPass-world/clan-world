// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MinimalERC20} from "../src/MinimalERC20.sol";
import {StubPool} from "../src/StubPool.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {PoolSeedConfig} from "../src/IClanWorld.sol";

contract Deploy is Script {
    // v4 section 5.11 default pool ratios for the hackathon deployment.
    uint256 private constant WOOD_POOL_SEED = 1_000e18;
    uint256 private constant WHEAT_POOL_SEED = 1_000e18;
    uint256 private constant FISH_POOL_SEED = 500e18;
    uint256 private constant IRON_POOL_SEED = 250e18;
    uint256 private constant GOLD_SEED_FOR_WOOD = 500e18;
    uint256 private constant GOLD_SEED_FOR_WHEAT = 700e18;
    uint256 private constant GOLD_SEED_FOR_FISH = 600e18;
    uint256 private constant GOLD_SEED_FOR_IRON = 800e18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address treasury = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy boundary tokens (gold existed in Phase 2 and is reused here).
        MinimalERC20 wood = new MinimalERC20("Wood", "WOOD");
        MinimalERC20 iron = new MinimalERC20("Iron", "IRON");
        MinimalERC20 wheat = new MinimalERC20("Wheat", "WHEAT");
        MinimalERC20 fish = new MinimalERC20("Fish", "FISH");
        MinimalERC20 gold = new MinimalERC20("Gold", "GOLD");
        MinimalERC20 blueprint = new MinimalERC20("ClanWorld Blueprint", "BPRT");

        console.log("wood:     ", address(wood));
        console.log("iron:     ", address(iron));
        console.log("wheat:    ", address(wheat));
        console.log("fish:     ", address(fish));
        console.log("gold:     ", address(gold));
        console.log("blueprint:", address(blueprint));

        // 2. Deploy ClanWorld first (needed as engine arg for pools).
        ClanWorld game = new ClanWorld();
        console.log("CLAN_WORLD_CONTRACT_ADDRESS:", address(game));

        // 3. Deploy 4 AMM pools (Phase 6.2: constant-product pools).
        StubPool woodGold = new StubPool(address(wood), address(gold), address(game));
        StubPool wheatGold = new StubPool(address(wheat), address(gold), address(game));
        StubPool fishGold = new StubPool(address(fish), address(gold), address(game));
        StubPool ironGold = new StubPool(address(iron), address(gold), address(game));

        console.log("woodGoldPool: ", address(woodGold));
        console.log("wheatGoldPool:", address(wheatGold));
        console.log("fishGoldPool: ", address(fishGold));
        console.log("ironGoldPool: ", address(ironGold));

        address[6] memory tokens =
            [address(wood), address(iron), address(wheat), address(fish), address(gold), address(blueprint)];
        address[4] memory pools = [address(woodGold), address(wheatGold), address(fishGold), address(ironGold)];

        game.initTreasury(tokens, pools);

        uint256 totalGoldSeed = GOLD_SEED_FOR_WOOD + GOLD_SEED_FOR_WHEAT + GOLD_SEED_FOR_FISH + GOLD_SEED_FOR_IRON;

        wood.seedTreasury(treasury, WOOD_POOL_SEED);
        wheat.seedTreasury(treasury, WHEAT_POOL_SEED);
        fish.seedTreasury(treasury, FISH_POOL_SEED);
        iron.seedTreasury(treasury, IRON_POOL_SEED);
        gold.seedTreasury(treasury, totalGoldSeed);

        wood.approve(address(game), WOOD_POOL_SEED);
        wheat.approve(address(game), WHEAT_POOL_SEED);
        fish.approve(address(game), FISH_POOL_SEED);
        iron.approve(address(game), IRON_POOL_SEED);
        gold.approve(address(game), totalGoldSeed);

        game.seedPools(
            PoolSeedConfig({
                woodSeed: WOOD_POOL_SEED,
                wheatSeed: WHEAT_POOL_SEED,
                fishSeed: FISH_POOL_SEED,
                ironSeed: IRON_POOL_SEED,
                goldSeedForWood: GOLD_SEED_FOR_WOOD,
                goldSeedForWheat: GOLD_SEED_FOR_WHEAT,
                goldSeedForFish: GOLD_SEED_FOR_FISH,
                goldSeedForIron: GOLD_SEED_FOR_IRON
            })
        );

        vm.stopBroadcast();
    }
}
