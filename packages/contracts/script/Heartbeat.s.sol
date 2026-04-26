// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IClanWorld} from "../src/IClanWorld.sol";

contract Heartbeat is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address stub = vm.envAddress("CLAN_WORLD_STUB_ADDRESS");

        vm.startBroadcast(pk);
        IClanWorld(stub).heartbeat();
        vm.stopBroadcast();

        console.log("heartbeat() fired on", stub);
    }
}
