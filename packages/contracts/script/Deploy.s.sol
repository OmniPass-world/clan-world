// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MinimalERC20} from "../src/MinimalERC20.sol";
import {StubPool} from "../src/StubPool.sol";
import {ClanWorld} from "../src/ClanWorld.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy 6 resource tokens (still needed for treasury/pool references)
        MinimalERC20 wood      = new MinimalERC20("ClanWorld Wood",      "WOOD");
        MinimalERC20 iron      = new MinimalERC20("ClanWorld Iron",      "IRON");
        MinimalERC20 wheat     = new MinimalERC20("ClanWorld Wheat",     "WHEAT");
        MinimalERC20 fish      = new MinimalERC20("ClanWorld Fish",      "FISH");
        MinimalERC20 gold      = new MinimalERC20("ClanWorld Gold",      "GOLD");
        MinimalERC20 blueprint = new MinimalERC20("ClanWorld Blueprint", "BPRT");

        console.log("wood:     ", address(wood));
        console.log("iron:     ", address(iron));
        console.log("wheat:    ", address(wheat));
        console.log("fish:     ", address(fish));
        console.log("gold:     ", address(gold));
        console.log("blueprint:", address(blueprint));

        // 3. Deploy ClanWorld first (needed as engine arg for pools)
        ClanWorld game = new ClanWorld();
        console.log("CLAN_WORLD_CONTRACT_ADDRESS:", address(game));

        // 2. Deploy 4 AMM pools (Phase 2: real constant-product pools)
        StubPool woodGold  = new StubPool(address(wood),  address(gold), address(game));
        StubPool wheatGold = new StubPool(address(wheat), address(gold), address(game));
        StubPool fishGold  = new StubPool(address(fish),  address(gold), address(game));
        StubPool ironGold  = new StubPool(address(iron),  address(gold), address(game));

        console.log("woodGoldPool: ", address(woodGold));
        console.log("wheatGoldPool:", address(wheatGold));
        console.log("fishGoldPool: ", address(fishGold));
        console.log("ironGoldPool: ", address(ironGold));

        vm.stopBroadcast();
    }
}
