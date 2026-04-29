// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MinimalERC20} from "../src/MinimalERC20.sol";
import {StubPool} from "../src/StubPool.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {PoolSeedConfig, ResourceType} from "../src/IClanWorld.sol";

contract Deploy is Script {
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

        wood.configureBoundary(uint8(ResourceType.Wood), address(game));
        iron.configureBoundary(uint8(ResourceType.Iron), address(game));
        wheat.configureBoundary(uint8(ResourceType.Wheat), address(game));
        fish.configureBoundary(uint8(ResourceType.Fish), address(game));

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

        uint256 resSeed = game.INITIAL_RESOURCE_POOL_SEED();
        uint256 goldSeed = game.INITIAL_GOLD_POOL_SEED();
        uint256 totalGoldSeed = goldSeed * 4;

        wood.seedTreasury(treasury, resSeed);
        wheat.seedTreasury(treasury, resSeed);
        fish.seedTreasury(treasury, resSeed);
        iron.seedTreasury(treasury, resSeed);
        gold.seedTreasury(treasury, totalGoldSeed);

        wood.approve(address(game), resSeed);
        wheat.approve(address(game), resSeed);
        fish.approve(address(game), resSeed);
        iron.approve(address(game), resSeed);
        gold.approve(address(game), totalGoldSeed);

        game.seedPools(
            PoolSeedConfig({
                woodSeed: resSeed,
                wheatSeed: resSeed,
                fishSeed: resSeed,
                ironSeed: resSeed,
                goldSeedForWood: goldSeed,
                goldSeedForWheat: goldSeed,
                goldSeedForFish: goldSeed,
                goldSeedForIron: goldSeed
            })
        );

        vm.stopBroadcast();
    }
}
