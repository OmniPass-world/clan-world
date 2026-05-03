// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script} from "forge-std/Script.sol";
import {ClanAgentNFT} from "../src/ClanAgentNFT.sol";
import {Mock7857Verifier} from "../src/Mock7857Verifier.sol";

contract DeployClanAgentNFT is Script {
    function run() external returns (Mock7857Verifier verifier, ClanAgentNFT nft) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        verifier = new Mock7857Verifier();
        nft = new ClanAgentNFT("ClanWorld Elder iNFT", "ELDER", address(verifier));
        vm.stopBroadcast();
    }
}
