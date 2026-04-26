// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MinimalERC20} from "../src/MinimalERC20.sol";
import {StubPool} from "../src/StubPool.sol";
import {ClanWorldStub} from "../src/ClanWorldStub.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy 6 resource tokens
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

        // 2. Deploy 4 stub LP pools
        StubPool woodGold  = new StubPool(address(wood),  address(gold));
        StubPool wheatGold = new StubPool(address(wheat), address(gold));
        StubPool fishGold  = new StubPool(address(fish),  address(gold));
        StubPool ironGold  = new StubPool(address(iron),  address(gold));

        console.log("woodGoldPool: ", address(woodGold));
        console.log("wheatGoldPool:", address(wheatGold));
        console.log("fishGoldPool: ", address(fishGold));
        console.log("ironGoldPool: ", address(ironGold));

        // 3. Deploy ClanWorldStub
        address[6] memory tokens = [
            address(wood),
            address(iron),
            address(wheat),
            address(fish),
            address(gold),
            address(blueprint)
        ];
        address[4] memory pools = [
            address(woodGold),
            address(wheatGold),
            address(fishGold),
            address(ironGold)
        ];

        ClanWorldStub stub = new ClanWorldStub(tokens, pools);
        console.log("ClanWorldStub:", address(stub));

        vm.stopBroadcast();
    }
}
